#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/tpu_runtime.h"

#ifndef BREATH_TPU_SOC_DEMO_USE_UART
#define BREATH_TPU_SOC_DEMO_USE_UART 1
#endif

#if BREATH_TPU_SOC_DEMO_USE_UART
#include "../../include/apb_uart.h"
#include "../../include/xprintf.h"
#define UART0_BASEADDE 0x40003000u
#define DEMO_LOG(...) xprintf(__VA_ARGS__)

static ApbUART uart0;

static void uart_putc(uint8_t c){
    while(apb_uart_send_byte(&uart0, c));
}

static void demo_log_init(void){
    apb_uart_init(&uart0, UART0_BASEADDE);
    xdev_out(uart_putc);
}
#else
#define DEMO_LOG(...) do {} while(0)
static void demo_log_init(void){}
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define TPU_WAIT_TIMEOUT 500000u

static void print_desc(const TPUDesc* desc){
    DEMO_LOG("desc.net_id      = %d\r\n", desc->net_id);
    DEMO_LOG("desc.input_addr  = 0x%08x\r\n", desc->input_addr);
    DEMO_LOG("desc.output_addr = 0x%08x\r\n", desc->output_addr);
    DEMO_LOG("desc.param_addr  = 0x%08x\r\n", desc->param_addr);
    DEMO_LOG("desc.scratch_addr= 0x%08x\r\n", desc->scratch_addr);
    DEMO_LOG("desc.input_words = %d\r\n", desc->input_words);
    DEMO_LOG("desc.output_words= %d\r\n", desc->output_words);
    DEMO_LOG("desc.flags       = 0x%08x\r\n", desc->flags);
}

static void run_demo_stage(uint32_t net_id, uint8_t buf_id, uint32_t flags, const char* stage_name){
    TPUDesc desc;
    uint32_t output_dump[TPU_DEMO_OUTPUT_DUMP_WORDS] = {0u};
    int wait_rc;

    tpu_select_desc_buffer(&g_tpu_runtime, buf_id);
    tpu_prepare_demo_input(&g_tpu_runtime, net_id);
    tpu_build_desc(&desc,
        net_id,
        g_tpu_runtime.active_input_addr,
        g_tpu_runtime.active_output_addr,
        g_tpu_runtime.active_scratch_addr,
        flags);

    DEMO_LOG("\r\n[%s]\r\n", stage_name);
    DEMO_LOG("active_buf_id    = %d\r\n", g_tpu_runtime.active_buf_id);
    DEMO_LOG("active_desc_addr = 0x%08x\r\n", g_tpu_runtime.active_desc_addr);
    print_desc(&desc);

    tpu_submit_desc(&g_tpu_runtime, &desc);

#if TPU_RUNTIME_USE_MMIO
    wait_rc = tpu_wait_done(&g_tpu_runtime, TPU_WAIT_TIMEOUT);
    DEMO_LOG("wait_done rc     = %d\r\n", wait_rc);
#else
    wait_rc = 0;
    DEMO_LOG("wait_done skipped (MMIO disabled)\r\n");
#endif

    tpu_read_output_words(&desc, output_dump, TPU_DEMO_OUTPUT_DUMP_WORDS);
    DEMO_LOG("out[0..3]        = %08x %08x %08x %08x\r\n",
        output_dump[0], output_dump[1], output_dump[2], output_dump[3]);

    (void)wait_rc;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
    demo_log_init();

    tpu_runtime_init(&g_tpu_runtime, TPU_CTRL_BASEADDR);
    tpu_load_param_pool();

    DEMO_LOG("breath_tpu_soc_demo start\r\n");
    DEMO_LOG("TPU runtime regs_base = 0x%08x\r\n", g_tpu_runtime.regs_baseaddr);
    DEMO_LOG("param_pool loaded: key=0x%08x other=0x%08x classifier=0x%08x\r\n",
        TPU_PARAM_POOL_MLP_KEY_BASE,
        TPU_PARAM_POOL_MLP_OTHER_BASE,
        TPU_PARAM_POOL_CLASSIFIER_BASE);

    run_demo_stage(NET_ID_MLP_KEY, 0u, TPU_DESC_F_RELU | TPU_DESC_F_TILE2X2_Q8_8, "MLP_KEY");
    run_demo_stage(NET_ID_MLP_OTHER, 1u, TPU_DESC_F_RELU | TPU_DESC_F_BUFSEL, "MLP_OTHER");
    run_demo_stage(NET_ID_CLASSIFIER, 0u, TPU_DESC_F_LAST_STAGE, "CLASSIFIER");

    DEMO_LOG("breath_tpu_soc_demo end\r\n");

    while(1){
    }
}
