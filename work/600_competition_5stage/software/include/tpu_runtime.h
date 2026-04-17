/************************************************************************************************************************
TPU runtime 骨架(接口头文件)
@brief  CPU 侧 TPU runtime API 和状态结构
@date   2026/04/17
************************************************************************************************************************/

#include <stdint.h>

#include "tpu_desc.h"
#include "tpu_regs.h"

#ifndef __TPU_RUNTIME_H
#define __TPU_RUNTIME_H

typedef struct{
    uint32_t regs_baseaddr;
    uint32_t active_desc_addr;
    uint32_t active_input_addr;
    uint32_t active_output_addr;
    uint32_t active_scratch_addr;
    uint8_t active_buf_id;
}TPURuntime;

extern TPURuntime g_tpu_runtime;

void tpu_runtime_init(TPURuntime* runtime, uint32_t regs_baseaddr);
const TPUNetMeta* tpu_get_net_meta(uint32_t net_id);
void tpu_select_desc_buffer(TPURuntime* runtime, uint8_t buf_id);
TPUBufferLayout tpu_get_buffer_layout(uint8_t buf_id);
void tpu_build_desc(TPUDesc* desc, uint32_t net_id, uint32_t input_addr, uint32_t output_addr, uint32_t scratch_addr, uint32_t flags);
int tpu_submit_desc(TPURuntime* runtime, const TPUDesc* desc);
int tpu_wait_done(TPURuntime* runtime, uint32_t timeout);
void tpu_load_param_pool(void);
void tpu_prepare_demo_input(TPURuntime* runtime, uint32_t net_id);
void tpu_clear_output_buffer(const TPUDesc* desc);
void tpu_read_output_words(const TPUDesc* desc, uint32_t* out_words, uint32_t max_words);

#endif
