/************************************************************************************************************************
TPU runtime 骨架(主源文件)
@brief  CPU 侧 TPU runtime 的最小软件骨架
@date   2026/04/17
************************************************************************************************************************/

#include "../include/tpu_runtime.h"
#include "../include/utils.h"

#ifndef TPU_RUNTIME_USE_MMIO
#define TPU_RUNTIME_USE_MMIO 0
#endif

TPURuntime g_tpu_runtime;

static const TPUNetMeta g_tpu_net_meta[] = {
    {NET_ID_MLP_KEY,        TPU_FAMILY_MLP,   0u,   1u,   16u, TPU_PARAM_POOL_MLP_KEY_WORDS,    1u},
    {NET_ID_MLP_OTHER,      TPU_FAMILY_MLP,   1u,   3u,   16u, TPU_PARAM_POOL_MLP_OTHER_WORDS,  1u},
    {NET_ID_CLASSIFIER,     TPU_FAMILY_HEAD,  2u, 161u,    2u, TPU_PARAM_POOL_CLASSIFIER_WORDS, 1u},
    {NET_ID_CNN1D_RESERVED, TPU_FAMILY_CNN1D, 3u,   0u,    0u, TPU_PARAM_POOL_CNN1D_RSVD_WORDS, 0u}
};

static const uint32_t g_param_blob_mlp_key[TPU_PARAM_POOL_MLP_KEY_WORDS] = {
    1u, 2u, 3u, 4u
};

static const uint32_t g_param_blob_mlp_other[TPU_PARAM_POOL_MLP_OTHER_WORDS] = {
    11u, 22u, 33u, 44u, 55u, 66u
};

static const uint32_t g_param_blob_classifier[TPU_PARAM_POOL_CLASSIFIER_WORDS] = {
    101u, 102u, 103u, 104u, 105u, 106u, 107u, 108u
};

static volatile uint32_t g_shared_mem_evict_sink;
static uint32_t g_shared_mem_evict_epoch;

#define TPU_SHARED_SYNC_SETTLE_LOOPS 2048u

static inline void cpu_mem_fence(void){
    __asm__ __volatile__("fence rw, rw" ::: "memory");
}

static volatile uint32_t* tpu_reg_ptr(TPURuntime* runtime, uint32_t reg_ofs){
    return (volatile uint32_t*)(uintptr_t)(runtime->regs_baseaddr + reg_ofs);
}

static volatile uint32_t* shared_word_ptr(uint32_t addr){
    return (volatile uint32_t*)(uintptr_t)addr;
}

static void tpu_reg_write(TPURuntime* runtime, uint32_t reg_ofs, uint32_t value){
    *tpu_reg_ptr(runtime, reg_ofs) = value;
}

static uint32_t tpu_reg_read(TPURuntime* runtime, uint32_t reg_ofs){
    return *tpu_reg_ptr(runtime, reg_ofs);
}

static void shared_mem_write_words(uint32_t dst_addr, const uint32_t* src_words, uint32_t word_count){
    for(uint32_t i = 0u;i < word_count;i++){
        shared_word_ptr(dst_addr)[i] = src_words[i];
    }
}

static void shared_mem_fill_ramp(uint32_t dst_addr, uint32_t word_count, uint32_t seed){
    for(uint32_t i = 0u;i < word_count;i++){
        shared_word_ptr(dst_addr)[i] = seed + i;
    }
}

static void shared_mem_zero_words(uint32_t dst_addr, uint32_t word_count){
    for(uint32_t i = 0u;i < word_count;i++){
        shared_word_ptr(dst_addr)[i] = 0u;
    }
}

static void shared_mem_cache_evict_all(void){
    uint32_t evict_base = (g_shared_mem_evict_epoch & 0x1u) ? TPU_CACHE_EVICT_REGION1_BASE:TPU_CACHE_EVICT_REGION0_BASE;

    for(uint32_t set_idx = 0u;set_idx < TPU_DCACHE_SET_COUNT;set_idx++){
        uint32_t line_ofs = set_idx * TPU_DCACHE_LINE_BYTES;

        for(uint32_t tag_idx = 0u;tag_idx < TPU_DCACHE_EVICT_TAGS;tag_idx++){
            uint32_t evict_addr = evict_base + (tag_idx * TPU_DCACHE_SET_STRIDE) + line_ofs;
            g_shared_mem_evict_sink ^= *shared_word_ptr(evict_addr);
        }
    }

    g_shared_mem_evict_epoch ^= 0x1u;
}

static void shared_mem_sync_settle(void){
    for(volatile uint32_t i = 0u;i < TPU_SHARED_SYNC_SETTLE_LOOPS;i++){
        __asm__ __volatile__("nop");
    }
}

static void shared_mem_sync_for_device(void){
    cpu_mem_fence();
    shared_mem_cache_evict_all();
    cpu_mem_fence();
    shared_mem_sync_settle();
}

static void shared_mem_sync_for_cpu(void){
    cpu_mem_fence();
    shared_mem_cache_evict_all();
    cpu_mem_fence();
    shared_mem_sync_settle();
}

static uint32_t tpu_param_pool_base(uint32_t net_id){
    switch(net_id){
        case NET_ID_MLP_KEY:
            return TPU_PARAM_POOL_MLP_KEY_BASE;
        case NET_ID_MLP_OTHER:
            return TPU_PARAM_POOL_MLP_OTHER_BASE;
        case NET_ID_CLASSIFIER:
            return TPU_PARAM_POOL_CLASSIFIER_BASE;
        default:
            return TPU_PARAM_POOL_CNN1D_RSVD_BASE;
    }
}

static const uint32_t* tpu_param_blob_ptr(uint32_t net_id){
    switch(net_id){
        case NET_ID_MLP_KEY:
            return g_param_blob_mlp_key;
        case NET_ID_MLP_OTHER:
            return g_param_blob_mlp_other;
        case NET_ID_CLASSIFIER:
            return g_param_blob_classifier;
        default:
            return (const uint32_t*)0;
    }
}

static void tpu_runtime_refresh_active_layout(TPURuntime* runtime){
    TPUBufferLayout layout = tpu_get_buffer_layout(runtime->active_buf_id);
    runtime->active_desc_addr = layout.desc_addr;
    runtime->active_input_addr = layout.input_addr;
    runtime->active_output_addr = layout.output_addr;
    runtime->active_scratch_addr = layout.scratch_addr;
}

void tpu_runtime_init(TPURuntime* runtime, uint32_t regs_baseaddr){
    runtime->regs_baseaddr = regs_baseaddr;
    runtime->active_buf_id = 0u;
    g_shared_mem_evict_sink = 0u;
    g_shared_mem_evict_epoch = 0u;
    tpu_runtime_refresh_active_layout(runtime);
}

const TPUNetMeta* tpu_get_net_meta(uint32_t net_id){
    for(uint32_t i = 0u;i < (sizeof(g_tpu_net_meta) / sizeof(g_tpu_net_meta[0]));i++){
        if(g_tpu_net_meta[i].net_id == net_id){
            return &g_tpu_net_meta[i];
        }
    }
    return (const TPUNetMeta*)0;
}

TPUBufferLayout tpu_get_buffer_layout(uint8_t buf_id){
    TPUBufferLayout layout;

    if((buf_id & 0x01u) != 0u){
        layout.desc_addr = TPU_DESC1_BASE;
        layout.input_addr = TPU_IN_BUF1_BASE;
        layout.output_addr = TPU_OUT_BUF1_BASE;
        layout.scratch_addr = TPU_SCRATCH1_BASE;
    }else{
        layout.desc_addr = TPU_DESC0_BASE;
        layout.input_addr = TPU_IN_BUF0_BASE;
        layout.output_addr = TPU_OUT_BUF0_BASE;
        layout.scratch_addr = TPU_SCRATCH0_BASE;
    }

    return layout;
}

void tpu_select_desc_buffer(TPURuntime* runtime, uint8_t buf_id){
    runtime->active_buf_id = (uint8_t)(buf_id & 0x01u);
    tpu_runtime_refresh_active_layout(runtime);
}

void tpu_build_desc(TPUDesc* desc, uint32_t net_id, uint32_t input_addr, uint32_t output_addr, uint32_t scratch_addr, uint32_t flags){
    const TPUNetMeta* meta = tpu_get_net_meta(net_id);

    desc->net_id = net_id;
    desc->input_addr = input_addr;
    desc->output_addr = output_addr;
    desc->param_addr = tpu_param_pool_base(net_id);
    desc->scratch_addr = scratch_addr;
    desc->flags = flags;

    if(meta == (const TPUNetMeta*)0){
        desc->param_addr = 0u;
        desc->input_words = 0u;
        desc->output_words = 0u;
        return;
    }

    desc->input_words = meta->input_words;
    desc->output_words = meta->output_words;
}

void tpu_clear_output_buffer(const TPUDesc* desc){
    shared_mem_zero_words(desc->output_addr, desc->output_words);
}

int tpu_submit_desc(TPURuntime* runtime, const TPUDesc* desc){
    volatile uint32_t* desc_slot = shared_word_ptr(runtime->active_desc_addr);

    desc_slot[0] = desc->net_id;
    desc_slot[1] = desc->input_addr;
    desc_slot[2] = desc->output_addr;
    desc_slot[3] = desc->param_addr;
    desc_slot[4] = desc->scratch_addr;
    desc_slot[5] = desc->input_words;
    desc_slot[6] = desc->output_words;
    desc_slot[7] = desc->flags;

    tpu_clear_output_buffer(desc);
    shared_mem_sync_for_device();

#if TPU_RUNTIME_USE_MMIO
    tpu_reg_write(runtime, TPU_REG_CTRL, TPU_CTRL_SOFT_RESET_MASK);
    tpu_reg_write(runtime, TPU_REG_MODE, TPU_MODE_INFER);
    tpu_reg_write(runtime, TPU_REG_NET_ID, desc->net_id);
    tpu_reg_write(runtime, TPU_REG_DESC_LO, runtime->active_desc_addr);
    tpu_reg_write(runtime, TPU_REG_DESC_HI, 0u);
    tpu_reg_write(runtime, TPU_REG_CTRL, TPU_CTRL_START_MASK);
#endif

    return 0;
}

int tpu_wait_done(TPURuntime* runtime, uint32_t timeout){
#if TPU_RUNTIME_USE_MMIO
    while(timeout--){
        uint32_t status = tpu_reg_read(runtime, TPU_REG_STATUS);
        if(status & TPU_STATUS_ERROR_MASK){
            return -1;
        }
        if(status & TPU_STATUS_DONE_MASK){
            return 0;
        }
    }
    return -2;
#else
    (void)runtime;
    (void)timeout;
    return 0;
#endif
}

void tpu_load_param_pool(void){
    shared_mem_write_words(TPU_PARAM_POOL_MLP_KEY_BASE, g_param_blob_mlp_key, TPU_PARAM_POOL_MLP_KEY_WORDS);
    shared_mem_write_words(TPU_PARAM_POOL_MLP_OTHER_BASE, g_param_blob_mlp_other, TPU_PARAM_POOL_MLP_OTHER_WORDS);
    shared_mem_write_words(TPU_PARAM_POOL_CLASSIFIER_BASE, g_param_blob_classifier, TPU_PARAM_POOL_CLASSIFIER_WORDS);
    shared_mem_sync_for_device();
}

void tpu_prepare_demo_input(TPURuntime* runtime, uint32_t net_id){
    const TPUNetMeta* meta = tpu_get_net_meta(net_id);

    if(meta == (const TPUNetMeta*)0){
        return;
    }

    switch(net_id){
        case NET_ID_MLP_KEY:
            shared_word_ptr(runtime->active_input_addr)[0] = 0x00100020u;
            break;
        case NET_ID_MLP_OTHER:
            shared_word_ptr(runtime->active_input_addr)[0] = 0x00010002u;
            shared_word_ptr(runtime->active_input_addr)[1] = 0x00030004u;
            shared_word_ptr(runtime->active_input_addr)[2] = 0x00050006u;
            break;
        case NET_ID_CLASSIFIER:
            shared_mem_fill_ramp(runtime->active_input_addr, meta->input_words, 0x0100u);
            break;
        default:
            shared_mem_zero_words(runtime->active_input_addr, meta->input_words);
            break;
    }
}

void tpu_read_output_words(const TPUDesc* desc, uint32_t* out_words, uint32_t max_words){
    uint32_t dump_words = desc->output_words;
    if(dump_words > max_words){
        dump_words = max_words;
    }

    shared_mem_sync_for_cpu();

    for(uint32_t i = 0u;i < dump_words;i++){
        out_words[i] = shared_word_ptr(desc->output_addr)[i];
    }
}
