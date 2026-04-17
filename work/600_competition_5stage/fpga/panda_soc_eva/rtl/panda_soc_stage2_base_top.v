`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
二阶段 SoC 基座顶层
@brief  当前版本提供：
        1. Panda CPU 子系统
        2. UART 最小外设通路
        3. TPU_CTRL 最小控制寄存器块
        4. shared SRAM 数据面
        5. shared SRAM 数据面 + TPU AXI master主路径
        6. 默认内建 descriptor/data fetch DMA stub
        7. 保留 task stub 作为更小的控制面后备占位

        注意：
        - 当前版本仍未集成真实 TPU core datapath。
        - 当前版本已把 CPU 控制面分成 UART/APB 与 TPU_CTRL 两路。
        - 当前版本默认启用 descriptor/data fetch DMA stub，用于闭合 CPU -> TPU_CTRL -> DMA -> shared SRAM -> status 主路径。
@date   2026/04/16
************************************************************************************************************************/
module panda_soc_stage2_base_top #(
    parameter EN_DCACHE = "true",
    parameter EN_DTCM = "false",
    parameter integer DCACHE_WAY_N = 2,
    parameter integer DCACHE_ENTRY_N = 128,
    parameter integer DCACHE_LINE_WORD_N = 4,
    parameter integer DCACHE_TAG_WIDTH = 20,
    parameter integer DCACHE_WBUF_ITEM_N = 8,
    parameter integer imem_depth = 8192,
    parameter integer dmem_depth = 8192,
    parameter real clk_frequency_MHz = 50.0,
    parameter en_mem_byte_write = "true",
    parameter imem_init_file = "no_init",
    parameter imem_init_file_b0 = "no_init",
    parameter imem_init_file_b1 = "no_init",
    parameter imem_init_file_b2 = "no_init",
    parameter imem_init_file_b3 = "no_init",
    parameter sgn_period_mul = "true",
    parameter integer USE_TPU_STATUS_STUB = 1,
    parameter integer USE_TPU_DESC_DMA_STUB = 1,
    parameter integer TPU_STUB_DONE_LATENCY = 64,
    parameter integer SIM_TPU_CTRL_AXIL_BYPASS = 0,
    parameter real simulation_delay = 1
)(
    input wire clk,
    input wire ext_resetn,

    input wire uart0_rx,
    output wire uart0_tx,

    // TPU 控制块状态输入，后续由真实 TPU wrapper / DMA engine 驱动
    input  wire        tpu_status_busy,
    input  wire        tpu_status_done,
    input  wire        tpu_status_error,

    // TPU 控制块导出的任务级控制寄存器
    output wire        tpu_launch_pulse,
    output wire        tpu_soft_reset_pulse,
    output wire [31:0] tpu_mode_reg,
    output wire [31:0] tpu_net_id_reg,
    output wire [31:0] tpu_desc_lo_reg,
    output wire [31:0] tpu_desc_hi_reg,
    output wire        tpu_irq_en_reg,
    output wire [31:0] tpu_perf_cycle_reg,

    // 仿真旁路：仅在 testbench 中可直接驱动 TPU_CTRL AXI-Lite，默认关闭
    input  wire [31:0] sim_tpu_ctrl_axil_awaddr,
    input  wire [2:0]  sim_tpu_ctrl_axil_awprot,
    input  wire        sim_tpu_ctrl_axil_awvalid,
    output wire        sim_tpu_ctrl_axil_awready,
    input  wire [31:0] sim_tpu_ctrl_axil_wdata,
    input  wire [3:0]  sim_tpu_ctrl_axil_wstrb,
    input  wire        sim_tpu_ctrl_axil_wvalid,
    output wire        sim_tpu_ctrl_axil_wready,
    output wire [1:0]  sim_tpu_ctrl_axil_bresp,
    output wire        sim_tpu_ctrl_axil_bvalid,
    input  wire        sim_tpu_ctrl_axil_bready,
    input  wire [31:0] sim_tpu_ctrl_axil_araddr,
    input  wire [2:0]  sim_tpu_ctrl_axil_arprot,
    input  wire        sim_tpu_ctrl_axil_arvalid,
    output wire        sim_tpu_ctrl_axil_arready,
    output wire [31:0] sim_tpu_ctrl_axil_rdata,
    output wire [1:0]  sim_tpu_ctrl_axil_rresp,
    output wire        sim_tpu_ctrl_axil_rvalid,
    input  wire        sim_tpu_ctrl_axil_rready,

    // 未来 TPU DMA master 接口占位
    input  wire [31:0] tpu_axi_araddr,
    input  wire [1:0]  tpu_axi_arburst,
    input  wire [7:0]  tpu_axi_arlen,
    input  wire [2:0]  tpu_axi_arsize,
    input  wire [3:0]  tpu_axi_arcache,
    input  wire        tpu_axi_arvalid,
    output wire        tpu_axi_arready,
    input  wire [31:0] tpu_axi_awaddr,
    input  wire [1:0]  tpu_axi_awburst,
    input  wire [7:0]  tpu_axi_awlen,
    input  wire [2:0]  tpu_axi_awsize,
    input  wire [3:0]  tpu_axi_awcache,
    input  wire        tpu_axi_awvalid,
    output wire        tpu_axi_awready,
    output wire [1:0]  tpu_axi_bresp,
    output wire        tpu_axi_bvalid,
    input  wire        tpu_axi_bready,
    output wire [31:0] tpu_axi_rdata,
    output wire [1:0]  tpu_axi_rresp,
    output wire        tpu_axi_rlast,
    output wire        tpu_axi_rvalid,
    input  wire        tpu_axi_rready,
    input  wire [31:0] tpu_axi_wdata,
    input  wire [3:0]  tpu_axi_wstrb,
    input  wire        tpu_axi_wlast,
    input  wire        tpu_axi_wvalid,
    output wire        tpu_axi_wready
);

    wire sw_reset;
    wire sys_resetn;
    wire sys_reset_req;

    assign sw_reset = 1'b0;

    panda_risc_v_reset #(
        .simulation_delay(simulation_delay)
    ) panda_risc_v_reset_u (
        .clk(clk),
        .ext_resetn(ext_resetn),
        .sw_reset(sw_reset),
        .sys_resetn(sys_resetn),
        .sys_reset_req(sys_reset_req),
        .sys_reset_fns()
    );

    // CPU 外设控制面 AXI-Lite-ish 主机
    wire [31:0] m_axi_dbus_araddr;
    wire [1:0]  m_axi_dbus_arburst;
    wire [7:0]  m_axi_dbus_arlen;
    wire [2:0]  m_axi_dbus_arsize;
    wire [3:0]  m_axi_dbus_arcache;
    wire        m_axi_dbus_arvalid;
    wire        m_axi_dbus_arready;
    wire [31:0] m_axi_dbus_awaddr;
    wire [1:0]  m_axi_dbus_awburst;
    wire [7:0]  m_axi_dbus_awlen;
    wire [2:0]  m_axi_dbus_awsize;
    wire [3:0]  m_axi_dbus_awcache;
    wire        m_axi_dbus_awvalid;
    wire        m_axi_dbus_awready;
    wire [1:0]  m_axi_dbus_bresp;
    wire        m_axi_dbus_bvalid;
    wire        m_axi_dbus_bready;
    wire [31:0] m_axi_dbus_rdata;
    wire [1:0]  m_axi_dbus_rresp;
    wire        m_axi_dbus_rlast;
    wire        m_axi_dbus_rvalid;
    wire        m_axi_dbus_rready;
    wire [31:0] m_axi_dbus_wdata;
    wire [3:0]  m_axi_dbus_wstrb;
    wire        m_axi_dbus_wlast;
    wire        m_axi_dbus_wvalid;
    wire        m_axi_dbus_wready;

    // CPU dcache 数据面 AXI 主机
    wire [31:0] m_axi_dcache_araddr;
    wire [1:0]  m_axi_dcache_arburst;
    wire [7:0]  m_axi_dcache_arlen;
    wire [2:0]  m_axi_dcache_arsize;
    wire [3:0]  m_axi_dcache_arcache;
    wire        m_axi_dcache_arvalid;
    wire        m_axi_dcache_arready;
    wire [31:0] m_axi_dcache_awaddr;
    wire [1:0]  m_axi_dcache_awburst;
    wire [7:0]  m_axi_dcache_awlen;
    wire [2:0]  m_axi_dcache_awsize;
    wire [3:0]  m_axi_dcache_awcache;
    wire        m_axi_dcache_awvalid;
    wire        m_axi_dcache_awready;
    wire [1:0]  m_axi_dcache_bresp;
    wire        m_axi_dcache_bvalid;
    wire        m_axi_dcache_bready;
    wire [31:0] m_axi_dcache_rdata;
    wire [1:0]  m_axi_dcache_rresp;
    wire        m_axi_dcache_rlast;
    wire        m_axi_dcache_rvalid;
    wire        m_axi_dcache_rready;
    wire [31:0] m_axi_dcache_wdata;
    wire [3:0]  m_axi_dcache_wstrb;
    wire        m_axi_dcache_wlast;
    wire        m_axi_dcache_wvalid;
    wire        m_axi_dcache_wready;

    // CPU dbus 经过地址分流后的 legacy AXI-Lite 路径（UART/APB）
    wire [31:0] legacy_axil_awaddr;
    wire [2:0]  legacy_axil_awprot;
    wire        legacy_axil_awvalid;
    wire        legacy_axil_awready;
    wire [31:0] legacy_axil_wdata;
    wire [3:0]  legacy_axil_wstrb;
    wire        legacy_axil_wvalid;
    wire        legacy_axil_wready;
    wire [1:0]  legacy_axil_bresp;
    wire        legacy_axil_bvalid;
    wire        legacy_axil_bready;
    wire [31:0] legacy_axil_araddr;
    wire [2:0]  legacy_axil_arprot;
    wire        legacy_axil_arvalid;
    wire        legacy_axil_arready;
    wire [31:0] legacy_axil_rdata;
    wire [1:0]  legacy_axil_rresp;
    wire        legacy_axil_rvalid;
    wire        legacy_axil_rready;

    // TPU_CTRL AXI-Lite：CPU splitter 输出 / 仿真旁路输入 / 寄存器块输入三者分层
    wire [31:0] tpu_ctrl_axil_int_awaddr;
    wire [2:0]  tpu_ctrl_axil_int_awprot;
    wire        tpu_ctrl_axil_int_awvalid;
    wire        tpu_ctrl_axil_int_awready;
    wire [31:0] tpu_ctrl_axil_int_wdata;
    wire [3:0]  tpu_ctrl_axil_int_wstrb;
    wire        tpu_ctrl_axil_int_wvalid;
    wire        tpu_ctrl_axil_int_wready;
    wire [1:0]  tpu_ctrl_axil_int_bresp;
    wire        tpu_ctrl_axil_int_bvalid;
    wire        tpu_ctrl_axil_int_bready;
    wire [31:0] tpu_ctrl_axil_int_araddr;
    wire [2:0]  tpu_ctrl_axil_int_arprot;
    wire        tpu_ctrl_axil_int_arvalid;
    wire        tpu_ctrl_axil_int_arready;
    wire [31:0] tpu_ctrl_axil_int_rdata;
    wire [1:0]  tpu_ctrl_axil_int_rresp;
    wire        tpu_ctrl_axil_int_rvalid;
    wire        tpu_ctrl_axil_int_rready;

    wire [31:0] tpu_ctrl_axil_awaddr;
    wire [2:0]  tpu_ctrl_axil_awprot;
    wire        tpu_ctrl_axil_awvalid;
    wire        tpu_ctrl_axil_awready;
    wire [31:0] tpu_ctrl_axil_wdata;
    wire [3:0]  tpu_ctrl_axil_wstrb;
    wire        tpu_ctrl_axil_wvalid;
    wire        tpu_ctrl_axil_wready;
    wire [1:0]  tpu_ctrl_axil_bresp;
    wire        tpu_ctrl_axil_bvalid;
    wire        tpu_ctrl_axil_bready;
    wire [31:0] tpu_ctrl_axil_araddr;
    wire [2:0]  tpu_ctrl_axil_arprot;
    wire        tpu_ctrl_axil_arvalid;
    wire        tpu_ctrl_axil_arready;
    wire [31:0] tpu_ctrl_axil_rdata;
    wire [1:0]  tpu_ctrl_axil_rresp;
    wire        tpu_ctrl_axil_rvalid;
    wire        tpu_ctrl_axil_rready;

    wire        tpu_stub_status_busy;
    wire        tpu_stub_status_done;
    wire        tpu_stub_status_error;
    wire        tpu_dma_stub_status_busy;
    wire        tpu_dma_stub_status_done;
    wire        tpu_dma_stub_status_error;
    wire        tpu_ctrl_status_busy;
    wire        tpu_ctrl_status_done;
    wire        tpu_ctrl_status_error;

    wire [31:0] tpu_dma_stub_desc_net_id;
    wire [31:0] tpu_dma_stub_desc_input_addr;
    wire [31:0] tpu_dma_stub_desc_output_addr;
    wire [31:0] tpu_dma_stub_desc_param_addr;
    wire [31:0] tpu_dma_stub_desc_scratch_addr;
    wire [31:0] tpu_dma_stub_desc_input_words;
    wire [31:0] tpu_dma_stub_desc_output_words;
    wire [31:0] tpu_dma_stub_desc_flags;
    wire [31:0] tpu_dma_stub_input_fetch_word_count;
    wire [31:0] tpu_dma_stub_input_checksum;
    wire [31:0] tpu_dma_stub_input_last_word;
    wire [31:0] tpu_dma_stub_param_fetch_word_count;
    wire [31:0] tpu_dma_stub_param_checksum;
    wire [31:0] tpu_dma_stub_param_last_word;

    wire [31:0] tpu_dma_stub_axi_araddr;
    wire [1:0]  tpu_dma_stub_axi_arburst;
    wire [7:0]  tpu_dma_stub_axi_arlen;
    wire [2:0]  tpu_dma_stub_axi_arsize;
    wire [3:0]  tpu_dma_stub_axi_arcache;
    wire        tpu_dma_stub_axi_arvalid;
    wire        tpu_dma_stub_axi_arready;
    wire [31:0] tpu_dma_stub_axi_awaddr;
    wire [1:0]  tpu_dma_stub_axi_awburst;
    wire [7:0]  tpu_dma_stub_axi_awlen;
    wire [2:0]  tpu_dma_stub_axi_awsize;
    wire [3:0]  tpu_dma_stub_axi_awcache;
    wire        tpu_dma_stub_axi_awvalid;
    wire        tpu_dma_stub_axi_awready;
    wire [1:0]  tpu_dma_stub_axi_bresp;
    wire        tpu_dma_stub_axi_bvalid;
    wire        tpu_dma_stub_axi_bready;
    wire [31:0] tpu_dma_stub_axi_rdata;
    wire [1:0]  tpu_dma_stub_axi_rresp;
    wire        tpu_dma_stub_axi_rlast;
    wire        tpu_dma_stub_axi_rvalid;
    wire        tpu_dma_stub_axi_rready;
    wire [31:0] tpu_dma_stub_axi_wdata;
    wire [3:0]  tpu_dma_stub_axi_wstrb;
    wire        tpu_dma_stub_axi_wlast;
    wire        tpu_dma_stub_axi_wvalid;
    wire        tpu_dma_stub_axi_wready;

    wire [31:0] tpu_mem_axi_araddr;
    wire [1:0]  tpu_mem_axi_arburst;
    wire [7:0]  tpu_mem_axi_arlen;
    wire [2:0]  tpu_mem_axi_arsize;
    wire [3:0]  tpu_mem_axi_arcache;
    wire        tpu_mem_axi_arvalid;
    wire        tpu_mem_axi_arready;
    wire [31:0] tpu_mem_axi_awaddr;
    wire [1:0]  tpu_mem_axi_awburst;
    wire [7:0]  tpu_mem_axi_awlen;
    wire [2:0]  tpu_mem_axi_awsize;
    wire [3:0]  tpu_mem_axi_awcache;
    wire        tpu_mem_axi_awvalid;
    wire        tpu_mem_axi_awready;
    wire [1:0]  tpu_mem_axi_bresp;
    wire        tpu_mem_axi_bvalid;
    wire        tpu_mem_axi_bready;
    wire [31:0] tpu_mem_axi_rdata;
    wire [1:0]  tpu_mem_axi_rresp;
    wire        tpu_mem_axi_rlast;
    wire        tpu_mem_axi_rvalid;
    wire        tpu_mem_axi_rready;
    wire [31:0] tpu_mem_axi_wdata;
    wire [3:0]  tpu_mem_axi_wstrb;
    wire        tpu_mem_axi_wlast;
    wire        tpu_mem_axi_wvalid;
    wire        tpu_mem_axi_wready;

    assign tpu_ctrl_axil_awaddr  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_awaddr  : tpu_ctrl_axil_int_awaddr;
    assign tpu_ctrl_axil_awprot  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_awprot  : tpu_ctrl_axil_int_awprot;
    assign tpu_ctrl_axil_awvalid = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_awvalid : tpu_ctrl_axil_int_awvalid;
    assign tpu_ctrl_axil_wdata   = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_wdata   : tpu_ctrl_axil_int_wdata;
    assign tpu_ctrl_axil_wstrb   = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_wstrb   : tpu_ctrl_axil_int_wstrb;
    assign tpu_ctrl_axil_wvalid  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_wvalid  : tpu_ctrl_axil_int_wvalid;
    assign tpu_ctrl_axil_bready  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_bready  : tpu_ctrl_axil_int_bready;
    assign tpu_ctrl_axil_araddr  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_araddr  : tpu_ctrl_axil_int_araddr;
    assign tpu_ctrl_axil_arprot  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_arprot  : tpu_ctrl_axil_int_arprot;
    assign tpu_ctrl_axil_arvalid = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_arvalid : tpu_ctrl_axil_int_arvalid;
    assign tpu_ctrl_axil_rready  = SIM_TPU_CTRL_AXIL_BYPASS ? sim_tpu_ctrl_axil_rready  : tpu_ctrl_axil_int_rready;

    assign sim_tpu_ctrl_axil_awready = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_awready : 1'b0;
    assign sim_tpu_ctrl_axil_wready  = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_wready  : 1'b0;
    assign sim_tpu_ctrl_axil_bresp   = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_bresp   : 2'b00;
    assign sim_tpu_ctrl_axil_bvalid  = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_bvalid  : 1'b0;
    assign sim_tpu_ctrl_axil_arready = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_arready : 1'b0;
    assign sim_tpu_ctrl_axil_rdata   = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_rdata   : 32'd0;
    assign sim_tpu_ctrl_axil_rresp   = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_rresp   : 2'b00;
    assign sim_tpu_ctrl_axil_rvalid  = SIM_TPU_CTRL_AXIL_BYPASS ? tpu_ctrl_axil_rvalid  : 1'b0;

    assign tpu_ctrl_axil_int_awready = SIM_TPU_CTRL_AXIL_BYPASS ? 1'b0   : tpu_ctrl_axil_awready;
    assign tpu_ctrl_axil_int_wready  = SIM_TPU_CTRL_AXIL_BYPASS ? 1'b0   : tpu_ctrl_axil_wready;
    assign tpu_ctrl_axil_int_bresp   = SIM_TPU_CTRL_AXIL_BYPASS ? 2'b00  : tpu_ctrl_axil_bresp;
    assign tpu_ctrl_axil_int_bvalid  = SIM_TPU_CTRL_AXIL_BYPASS ? 1'b0   : tpu_ctrl_axil_bvalid;
    assign tpu_ctrl_axil_int_arready = SIM_TPU_CTRL_AXIL_BYPASS ? 1'b0   : tpu_ctrl_axil_arready;
    assign tpu_ctrl_axil_int_rdata   = SIM_TPU_CTRL_AXIL_BYPASS ? 32'd0  : tpu_ctrl_axil_rdata;
    assign tpu_ctrl_axil_int_rresp   = SIM_TPU_CTRL_AXIL_BYPASS ? 2'b00  : tpu_ctrl_axil_rresp;
    assign tpu_ctrl_axil_int_rvalid  = SIM_TPU_CTRL_AXIL_BYPASS ? 1'b0   : tpu_ctrl_axil_rvalid;

    assign tpu_ctrl_status_busy  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_status_busy  : (USE_TPU_STATUS_STUB ? tpu_stub_status_busy  : tpu_status_busy);
    assign tpu_ctrl_status_done  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_status_done  : (USE_TPU_STATUS_STUB ? tpu_stub_status_done  : tpu_status_done);
    assign tpu_ctrl_status_error = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_status_error : (USE_TPU_STATUS_STUB ? tpu_stub_status_error : tpu_status_error);

    assign tpu_mem_axi_araddr   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_araddr   : tpu_axi_araddr;
    assign tpu_mem_axi_arburst  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_arburst  : tpu_axi_arburst;
    assign tpu_mem_axi_arlen    = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_arlen    : tpu_axi_arlen;
    assign tpu_mem_axi_arsize   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_arsize   : tpu_axi_arsize;
    assign tpu_mem_axi_arcache  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_arcache  : tpu_axi_arcache;
    assign tpu_mem_axi_arvalid  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_arvalid  : tpu_axi_arvalid;
    assign tpu_mem_axi_awaddr   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_awaddr   : tpu_axi_awaddr;
    assign tpu_mem_axi_awburst  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_awburst  : tpu_axi_awburst;
    assign tpu_mem_axi_awlen    = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_awlen    : tpu_axi_awlen;
    assign tpu_mem_axi_awsize   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_awsize   : tpu_axi_awsize;
    assign tpu_mem_axi_awcache  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_awcache  : tpu_axi_awcache;
    assign tpu_mem_axi_awvalid  = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_awvalid  : tpu_axi_awvalid;
    assign tpu_mem_axi_bready   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_bready   : tpu_axi_bready;
    assign tpu_mem_axi_rready   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_rready   : tpu_axi_rready;
    assign tpu_mem_axi_wdata    = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_wdata    : tpu_axi_wdata;
    assign tpu_mem_axi_wstrb    = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_wstrb    : tpu_axi_wstrb;
    assign tpu_mem_axi_wlast    = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_wlast    : tpu_axi_wlast;
    assign tpu_mem_axi_wvalid   = USE_TPU_DESC_DMA_STUB ? tpu_dma_stub_axi_wvalid   : tpu_axi_wvalid;

    assign tpu_dma_stub_axi_arready = tpu_mem_axi_arready;
    assign tpu_dma_stub_axi_awready = tpu_mem_axi_awready;
    assign tpu_dma_stub_axi_bresp   = tpu_mem_axi_bresp;
    assign tpu_dma_stub_axi_bvalid  = tpu_mem_axi_bvalid;
    assign tpu_dma_stub_axi_rdata   = tpu_mem_axi_rdata;
    assign tpu_dma_stub_axi_rresp   = tpu_mem_axi_rresp;
    assign tpu_dma_stub_axi_rlast   = tpu_mem_axi_rlast;
    assign tpu_dma_stub_axi_rvalid  = tpu_mem_axi_rvalid;
    assign tpu_dma_stub_axi_wready  = tpu_mem_axi_wready;

    assign tpu_axi_arready = USE_TPU_DESC_DMA_STUB ? 1'b0   : tpu_mem_axi_arready;
    assign tpu_axi_awready = USE_TPU_DESC_DMA_STUB ? 1'b0   : tpu_mem_axi_awready;
    assign tpu_axi_bresp   = USE_TPU_DESC_DMA_STUB ? 2'b00  : tpu_mem_axi_bresp;
    assign tpu_axi_bvalid  = USE_TPU_DESC_DMA_STUB ? 1'b0   : tpu_mem_axi_bvalid;
    assign tpu_axi_rdata   = USE_TPU_DESC_DMA_STUB ? 32'd0  : tpu_mem_axi_rdata;
    assign tpu_axi_rresp   = USE_TPU_DESC_DMA_STUB ? 2'b00  : tpu_mem_axi_rresp;
    assign tpu_axi_rlast   = USE_TPU_DESC_DMA_STUB ? 1'b0   : tpu_mem_axi_rlast;
    assign tpu_axi_rvalid  = USE_TPU_DESC_DMA_STUB ? 1'b0   : tpu_mem_axi_rvalid;
    assign tpu_axi_wready  = USE_TPU_DESC_DMA_STUB ? 1'b0   : tpu_mem_axi_wready;

    // 仅保留 UART 所需的 APB #0
    wire [31:0] m0_apb_paddr;
    wire        m0_apb_penable;
    wire        m0_apb_pwrite;
    wire [2:0]  m0_apb_pprot;
    wire        m0_apb_psel;
    wire [3:0]  m0_apb_pstrb;
    wire [31:0] m0_apb_pwdata;
    wire        m0_apb_pready;
    wire        m0_apb_pslverr;
    wire [31:0] m0_apb_prdata;

    // 调试/DM 相关未使用输出
    wire ibus_timeout;
    wire dbus_timeout;
    wire hart_access_en;
    wire [3:0] hart_access_wen;
    wire [29:0] hart_access_addr;
    wire [31:0] hart_access_din;
    wire [31:0] hart_access_dout;

    assign hart_access_dout = 32'd0;

    panda_risc_v_min_proc_sys #(
        .EN_DCACHE(EN_DCACHE),
        .EN_DTCM(EN_DTCM),
        .DCACHE_WAY_N(DCACHE_WAY_N),
        .DCACHE_ENTRY_N(DCACHE_ENTRY_N),
        .DCACHE_LINE_WORD_N(DCACHE_LINE_WORD_N),
        .DCACHE_TAG_WIDTH(DCACHE_TAG_WIDTH),
        .DCACHE_WBUF_ITEM_N(DCACHE_WBUF_ITEM_N),
        .imem_access_timeout_th(16),
        .inst_addr_alignment_width(32),
        .dbus_access_timeout_th(64),
        .icb_zero_latency_supported("false"),
        .en_expt_vec_vectored("false"),
        .en_performance_monitor("true"),
        .init_mtvec_base(30'd0),
        .init_mcause_interrupt(1'b0),
        .init_mcause_exception_code(31'd16),
        .init_misa_mxl(2'b01),
        .init_misa_extensions(26'b00_0000_0000_0001_0001_0000_0000),
        .init_mvendorid_bank(25'h0_00_00_00),
        .init_mvendorid_offset(7'h00),
        .init_marchid(32'h00_00_00_00),
        .init_mimpid(32'h31_2E_30_30),
        .init_mhartid(32'h00_00_00_00),
        .dpc_trace_inst_n(16),
        .inst_id_width(5),
        .en_alu_csr_rw_bypass("true"),
        .imem_baseaddr(32'h0000_0000),
        .imem_addr_range(imem_depth * 4),
        .dm_regs_baseaddr(32'hFFFF_F800),
        .dm_regs_addr_range(1024),
        .dmem_baseaddr(32'h1000_0000),
        .dmem_addr_range(dmem_depth * 4),
        .plic_baseaddr(32'hF000_0000),
        .plic_addr_range(4 * 1024 * 1024),
        .clint_baseaddr(32'hF400_0000),
        .clint_addr_range(64 * 1024 * 1024),
        .ext_peripheral_baseaddr(32'h4000_0000),
        .ext_peripheral_addr_range(16 * 4096),
        .ext_mem_baseaddr(32'h6000_0000),
        .ext_mem_addr_range(8 * 1024 * 1024),
        .ext_mem_uncached("true"),
        .en_inst_cmd_fwd("false"),
        .en_inst_rsp_bck("false"),
        .en_data_cmd_fwd("true"),
        .en_data_rsp_bck("true"),
        .en_mem_byte_write(en_mem_byte_write),
        .imem_init_file(imem_init_file),
        .imem_init_file_b0(imem_init_file_b0),
        .imem_init_file_b1(imem_init_file_b1),
        .imem_init_file_b2(imem_init_file_b2),
        .imem_init_file_b3(imem_init_file_b3),
        .sgn_period_mul(sgn_period_mul),
        .rtc_psc_r(50 * 1000),
        .debug_supported("true"),
        .DEBUG_ROM_ADDR(32'h0000_0600),
        .dscratch_n(2),
        .simulation_delay(simulation_delay)
    ) panda_risc_v_min_proc_sys_u (
        .clk(clk),
        .sys_resetn(sys_resetn),
        .sys_reset_req(sys_reset_req),
        .rst_pc(32'h0000_0800),
        .rtc_en(1'b1),
        .m_axi_dbus_araddr(m_axi_dbus_araddr),
        .m_axi_dbus_arburst(m_axi_dbus_arburst),
        .m_axi_dbus_arlen(m_axi_dbus_arlen),
        .m_axi_dbus_arsize(m_axi_dbus_arsize),
        .m_axi_dbus_arcache(m_axi_dbus_arcache),
        .m_axi_dbus_arvalid(m_axi_dbus_arvalid),
        .m_axi_dbus_arready(m_axi_dbus_arready),
        .m_axi_dbus_awaddr(m_axi_dbus_awaddr),
        .m_axi_dbus_awburst(m_axi_dbus_awburst),
        .m_axi_dbus_awlen(m_axi_dbus_awlen),
        .m_axi_dbus_awsize(m_axi_dbus_awsize),
        .m_axi_dbus_awcache(m_axi_dbus_awcache),
        .m_axi_dbus_awvalid(m_axi_dbus_awvalid),
        .m_axi_dbus_awready(m_axi_dbus_awready),
        .m_axi_dbus_bresp(m_axi_dbus_bresp),
        .m_axi_dbus_bvalid(m_axi_dbus_bvalid),
        .m_axi_dbus_bready(m_axi_dbus_bready),
        .m_axi_dbus_rdata(m_axi_dbus_rdata),
        .m_axi_dbus_rresp(m_axi_dbus_rresp),
        .m_axi_dbus_rlast(m_axi_dbus_rlast),
        .m_axi_dbus_rvalid(m_axi_dbus_rvalid),
        .m_axi_dbus_rready(m_axi_dbus_rready),
        .m_axi_dbus_wdata(m_axi_dbus_wdata),
        .m_axi_dbus_wstrb(m_axi_dbus_wstrb),
        .m_axi_dbus_wlast(m_axi_dbus_wlast),
        .m_axi_dbus_wvalid(m_axi_dbus_wvalid),
        .m_axi_dbus_wready(m_axi_dbus_wready),
        .m_axi_dcache_araddr(m_axi_dcache_araddr),
        .m_axi_dcache_arburst(m_axi_dcache_arburst),
        .m_axi_dcache_arlen(m_axi_dcache_arlen),
        .m_axi_dcache_arsize(m_axi_dcache_arsize),
        .m_axi_dcache_arcache(m_axi_dcache_arcache),
        .m_axi_dcache_arvalid(m_axi_dcache_arvalid),
        .m_axi_dcache_arready(m_axi_dcache_arready),
        .m_axi_dcache_awaddr(m_axi_dcache_awaddr),
        .m_axi_dcache_awburst(m_axi_dcache_awburst),
        .m_axi_dcache_awlen(m_axi_dcache_awlen),
        .m_axi_dcache_awsize(m_axi_dcache_awsize),
        .m_axi_dcache_awcache(m_axi_dcache_awcache),
        .m_axi_dcache_awvalid(m_axi_dcache_awvalid),
        .m_axi_dcache_awready(m_axi_dcache_awready),
        .m_axi_dcache_bresp(m_axi_dcache_bresp),
        .m_axi_dcache_bvalid(m_axi_dcache_bvalid),
        .m_axi_dcache_bready(m_axi_dcache_bready),
        .m_axi_dcache_rdata(m_axi_dcache_rdata),
        .m_axi_dcache_rresp(m_axi_dcache_rresp),
        .m_axi_dcache_rlast(m_axi_dcache_rlast),
        .m_axi_dcache_rvalid(m_axi_dcache_rvalid),
        .m_axi_dcache_rready(m_axi_dcache_rready),
        .m_axi_dcache_wdata(m_axi_dcache_wdata),
        .m_axi_dcache_wstrb(m_axi_dcache_wstrb),
        .m_axi_dcache_wlast(m_axi_dcache_wlast),
        .m_axi_dcache_wvalid(m_axi_dcache_wvalid),
        .m_axi_dcache_wready(m_axi_dcache_wready),
        .ibus_timeout(ibus_timeout),
        .dbus_timeout(dbus_timeout),
        .ext_itr_req_vec(63'd0),
        .hart_access_en(hart_access_en),
        .hart_access_wen(hart_access_wen),
        .hart_access_addr(hart_access_addr),
        .hart_access_din(hart_access_din),
        .hart_access_dout(hart_access_dout),
        .dbg_halt_req(1'b0),
        .dbg_halt_on_reset_req(1'b0)
    );

    cpu_tpu_axil_splitter #(
        .TPU_BASE_ADDR(32'h4000_4000),
        .TPU_ADDR_RANGE(4096)
    ) cpu_tpu_axil_splitter_u (
        .aclk(clk),
        .aresetn(sys_resetn),
        .s_axil_awaddr(m_axi_dbus_awaddr),
        .s_axil_awprot(3'b000),
        .s_axil_awvalid(m_axi_dbus_awvalid),
        .s_axil_awready(m_axi_dbus_awready),
        .s_axil_wdata(m_axi_dbus_wdata),
        .s_axil_wstrb(m_axi_dbus_wstrb),
        .s_axil_wvalid(m_axi_dbus_wvalid),
        .s_axil_wready(m_axi_dbus_wready),
        .s_axil_bresp(m_axi_dbus_bresp),
        .s_axil_bvalid(m_axi_dbus_bvalid),
        .s_axil_bready(m_axi_dbus_bready),
        .s_axil_araddr(m_axi_dbus_araddr),
        .s_axil_arprot(3'b000),
        .s_axil_arvalid(m_axi_dbus_arvalid),
        .s_axil_arready(m_axi_dbus_arready),
        .s_axil_rdata(m_axi_dbus_rdata),
        .s_axil_rresp(m_axi_dbus_rresp),
        .s_axil_rvalid(m_axi_dbus_rvalid),
        .s_axil_rready(m_axi_dbus_rready),
        .m0_axil_awaddr(legacy_axil_awaddr),
        .m0_axil_awprot(legacy_axil_awprot),
        .m0_axil_awvalid(legacy_axil_awvalid),
        .m0_axil_awready(legacy_axil_awready),
        .m0_axil_wdata(legacy_axil_wdata),
        .m0_axil_wstrb(legacy_axil_wstrb),
        .m0_axil_wvalid(legacy_axil_wvalid),
        .m0_axil_wready(legacy_axil_wready),
        .m0_axil_bresp(legacy_axil_bresp),
        .m0_axil_bvalid(legacy_axil_bvalid),
        .m0_axil_bready(legacy_axil_bready),
        .m0_axil_araddr(legacy_axil_araddr),
        .m0_axil_arprot(legacy_axil_arprot),
        .m0_axil_arvalid(legacy_axil_arvalid),
        .m0_axil_arready(legacy_axil_arready),
        .m0_axil_rdata(legacy_axil_rdata),
        .m0_axil_rresp(legacy_axil_rresp),
        .m0_axil_rvalid(legacy_axil_rvalid),
        .m0_axil_rready(legacy_axil_rready),
        .m1_axil_awaddr(tpu_ctrl_axil_int_awaddr),
        .m1_axil_awprot(tpu_ctrl_axil_int_awprot),
        .m1_axil_awvalid(tpu_ctrl_axil_int_awvalid),
        .m1_axil_awready(tpu_ctrl_axil_int_awready),
        .m1_axil_wdata(tpu_ctrl_axil_int_wdata),
        .m1_axil_wstrb(tpu_ctrl_axil_int_wstrb),
        .m1_axil_wvalid(tpu_ctrl_axil_int_wvalid),
        .m1_axil_wready(tpu_ctrl_axil_int_wready),
        .m1_axil_bresp(tpu_ctrl_axil_int_bresp),
        .m1_axil_bvalid(tpu_ctrl_axil_int_bvalid),
        .m1_axil_bready(tpu_ctrl_axil_int_bready),
        .m1_axil_araddr(tpu_ctrl_axil_int_araddr),
        .m1_axil_arprot(tpu_ctrl_axil_int_arprot),
        .m1_axil_arvalid(tpu_ctrl_axil_int_arvalid),
        .m1_axil_arready(tpu_ctrl_axil_int_arready),
        .m1_axil_rdata(tpu_ctrl_axil_int_rdata),
        .m1_axil_rresp(tpu_ctrl_axil_int_rresp),
        .m1_axil_rvalid(tpu_ctrl_axil_int_rvalid),
        .m1_axil_rready(tpu_ctrl_axil_int_rready)
    );

    axi_apb_bridge_wrapper #(
        .apb_slave_n(1),
        .apb_s0_baseaddr(32'h4000_3000),
        .apb_s0_range(4096),
        .simulation_delay(simulation_delay)
    ) axi_apb_bridge_wrapper_u (
        .clk(clk),
        .rst_n(sys_resetn),
        .s_axi_araddr(legacy_axil_araddr),
        .s_axi_arprot(legacy_axil_arprot),
        .s_axi_arvalid(legacy_axil_arvalid),
        .s_axi_arready(legacy_axil_arready),
        .s_axi_awaddr(legacy_axil_awaddr),
        .s_axi_awprot(legacy_axil_awprot),
        .s_axi_awvalid(legacy_axil_awvalid),
        .s_axi_awready(legacy_axil_awready),
        .s_axi_bresp(legacy_axil_bresp),
        .s_axi_bvalid(legacy_axil_bvalid),
        .s_axi_bready(legacy_axil_bready),
        .s_axi_rdata(legacy_axil_rdata),
        .s_axi_rresp(legacy_axil_rresp),
        .s_axi_rvalid(legacy_axil_rvalid),
        .s_axi_rready(legacy_axil_rready),
        .s_axi_wdata(legacy_axil_wdata),
        .s_axi_wstrb(legacy_axil_wstrb),
        .s_axi_wvalid(legacy_axil_wvalid),
        .s_axi_wready(legacy_axil_wready),
        .m0_apb_paddr(m0_apb_paddr),
        .m0_apb_penable(m0_apb_penable),
        .m0_apb_pwrite(m0_apb_pwrite),
        .m0_apb_pprot(m0_apb_pprot),
        .m0_apb_psel(m0_apb_psel),
        .m0_apb_pstrb(m0_apb_pstrb),
        .m0_apb_pwdata(m0_apb_pwdata),
        .m0_apb_pready(m0_apb_pready),
        .m0_apb_pslverr(m0_apb_pslverr),
        .m0_apb_prdata(m0_apb_prdata),
        .m1_apb_paddr(), .m1_apb_penable(), .m1_apb_pwrite(), .m1_apb_pprot(), .m1_apb_psel(), .m1_apb_pstrb(), .m1_apb_pwdata(), .m1_apb_pready(1'b1), .m1_apb_pslverr(1'b0), .m1_apb_prdata(32'd0),
        .m2_apb_paddr(), .m2_apb_penable(), .m2_apb_pwrite(), .m2_apb_pprot(), .m2_apb_psel(), .m2_apb_pstrb(), .m2_apb_pwdata(), .m2_apb_pready(1'b1), .m2_apb_pslverr(1'b0), .m2_apb_prdata(32'd0),
        .m3_apb_paddr(), .m3_apb_penable(), .m3_apb_pwrite(), .m3_apb_pprot(), .m3_apb_psel(), .m3_apb_pstrb(), .m3_apb_pwdata(), .m3_apb_pready(1'b1), .m3_apb_pslverr(1'b0), .m3_apb_prdata(32'd0),
        .m4_apb_paddr(), .m4_apb_penable(), .m4_apb_pwrite(), .m4_apb_pprot(), .m4_apb_psel(), .m4_apb_pstrb(), .m4_apb_pwdata(), .m4_apb_pready(1'b1), .m4_apb_pslverr(1'b0), .m4_apb_prdata(32'd0),
        .m5_apb_paddr(), .m5_apb_penable(), .m5_apb_pwrite(), .m5_apb_pprot(), .m5_apb_psel(), .m5_apb_pstrb(), .m5_apb_pwdata(), .m5_apb_pready(1'b1), .m5_apb_pslverr(1'b0), .m5_apb_prdata(32'd0),
        .m6_apb_paddr(), .m6_apb_penable(), .m6_apb_pwrite(), .m6_apb_pprot(), .m6_apb_psel(), .m6_apb_pstrb(), .m6_apb_pwdata(), .m6_apb_pready(1'b1), .m6_apb_pslverr(1'b0), .m6_apb_prdata(32'd0),
        .m7_apb_paddr(), .m7_apb_penable(), .m7_apb_pwrite(), .m7_apb_pprot(), .m7_apb_psel(), .m7_apb_pstrb(), .m7_apb_pwdata(), .m7_apb_pready(1'b1), .m7_apb_pslverr(1'b0), .m7_apb_prdata(32'd0),
        .m8_apb_paddr(), .m8_apb_penable(), .m8_apb_pwrite(), .m8_apb_pprot(), .m8_apb_psel(), .m8_apb_pstrb(), .m8_apb_pwdata(), .m8_apb_pready(1'b1), .m8_apb_pslverr(1'b0), .m8_apb_prdata(32'd0),
        .m9_apb_paddr(), .m9_apb_penable(), .m9_apb_pwrite(), .m9_apb_pprot(), .m9_apb_psel(), .m9_apb_pstrb(), .m9_apb_pwdata(), .m9_apb_pready(1'b1), .m9_apb_pslverr(1'b0), .m9_apb_prdata(32'd0),
        .m10_apb_paddr(), .m10_apb_penable(), .m10_apb_pwrite(), .m10_apb_pprot(), .m10_apb_psel(), .m10_apb_pstrb(), .m10_apb_pwdata(), .m10_apb_pready(1'b1), .m10_apb_pslverr(1'b0), .m10_apb_prdata(32'd0),
        .m11_apb_paddr(), .m11_apb_penable(), .m11_apb_pwrite(), .m11_apb_pprot(), .m11_apb_psel(), .m11_apb_pstrb(), .m11_apb_pwdata(), .m11_apb_pready(1'b1), .m11_apb_pslverr(1'b0), .m11_apb_prdata(32'd0),
        .m12_apb_paddr(), .m12_apb_penable(), .m12_apb_pwrite(), .m12_apb_pprot(), .m12_apb_psel(), .m12_apb_pstrb(), .m12_apb_pwdata(), .m12_apb_pready(1'b1), .m12_apb_pslverr(1'b0), .m12_apb_prdata(32'd0),
        .m13_apb_paddr(), .m13_apb_penable(), .m13_apb_pwrite(), .m13_apb_pprot(), .m13_apb_psel(), .m13_apb_pstrb(), .m13_apb_pwdata(), .m13_apb_pready(1'b1), .m13_apb_pslverr(1'b0), .m13_apb_prdata(32'd0),
        .m14_apb_paddr(), .m14_apb_penable(), .m14_apb_pwrite(), .m14_apb_pprot(), .m14_apb_psel(), .m14_apb_pstrb(), .m14_apb_pwdata(), .m14_apb_pready(1'b1), .m14_apb_pslverr(1'b0), .m14_apb_prdata(32'd0),
        .m15_apb_paddr(), .m15_apb_penable(), .m15_apb_pwrite(), .m15_apb_pprot(), .m15_apb_psel(), .m15_apb_pstrb(), .m15_apb_pwdata(), .m15_apb_pready(1'b1), .m15_apb_pslverr(1'b0), .m15_apb_prdata(32'd0)
    );

    tpu_desc_fetch_dma_stub tpu_desc_fetch_dma_stub_u (
        .clk(clk),
        .rst_n(sys_resetn),
        .launch_pulse(tpu_launch_pulse),
        .soft_reset_pulse(tpu_soft_reset_pulse),
        .desc_base_addr(tpu_desc_lo_reg),
        .status_busy(tpu_dma_stub_status_busy),
        .status_done(tpu_dma_stub_status_done),
        .status_error(tpu_dma_stub_status_error),
        .desc_net_id_reg(tpu_dma_stub_desc_net_id),
        .desc_input_addr_reg(tpu_dma_stub_desc_input_addr),
        .desc_output_addr_reg(tpu_dma_stub_desc_output_addr),
        .desc_param_addr_reg(tpu_dma_stub_desc_param_addr),
        .desc_scratch_addr_reg(tpu_dma_stub_desc_scratch_addr),
        .desc_input_words_reg(tpu_dma_stub_desc_input_words),
        .desc_output_words_reg(tpu_dma_stub_desc_output_words),
        .desc_flags_reg(tpu_dma_stub_desc_flags),
        .input_fetch_word_count_reg(tpu_dma_stub_input_fetch_word_count),
        .input_checksum_reg(tpu_dma_stub_input_checksum),
        .input_last_word_reg(tpu_dma_stub_input_last_word),
        .param_fetch_word_count_reg(tpu_dma_stub_param_fetch_word_count),
        .param_checksum_reg(tpu_dma_stub_param_checksum),
        .param_last_word_reg(tpu_dma_stub_param_last_word),
        .m_axi_araddr(tpu_dma_stub_axi_araddr),
        .m_axi_arburst(tpu_dma_stub_axi_arburst),
        .m_axi_arlen(tpu_dma_stub_axi_arlen),
        .m_axi_arsize(tpu_dma_stub_axi_arsize),
        .m_axi_arcache(tpu_dma_stub_axi_arcache),
        .m_axi_arvalid(tpu_dma_stub_axi_arvalid),
        .m_axi_arready(tpu_dma_stub_axi_arready),
        .m_axi_awaddr(tpu_dma_stub_axi_awaddr),
        .m_axi_awburst(tpu_dma_stub_axi_awburst),
        .m_axi_awlen(tpu_dma_stub_axi_awlen),
        .m_axi_awsize(tpu_dma_stub_axi_awsize),
        .m_axi_awcache(tpu_dma_stub_axi_awcache),
        .m_axi_awvalid(tpu_dma_stub_axi_awvalid),
        .m_axi_awready(tpu_dma_stub_axi_awready),
        .m_axi_bresp(tpu_dma_stub_axi_bresp),
        .m_axi_bvalid(tpu_dma_stub_axi_bvalid),
        .m_axi_bready(tpu_dma_stub_axi_bready),
        .m_axi_rdata(tpu_dma_stub_axi_rdata),
        .m_axi_rresp(tpu_dma_stub_axi_rresp),
        .m_axi_rlast(tpu_dma_stub_axi_rlast),
        .m_axi_rvalid(tpu_dma_stub_axi_rvalid),
        .m_axi_rready(tpu_dma_stub_axi_rready),
        .m_axi_wdata(tpu_dma_stub_axi_wdata),
        .m_axi_wstrb(tpu_dma_stub_axi_wstrb),
        .m_axi_wlast(tpu_dma_stub_axi_wlast),
        .m_axi_wvalid(tpu_dma_stub_axi_wvalid),
        .m_axi_wready(tpu_dma_stub_axi_wready)
    );

    tpu_ctrl_task_stub #(
        .DONE_LATENCY_CYCLES(TPU_STUB_DONE_LATENCY)
    ) tpu_ctrl_task_stub_u (
        .clk(clk),
        .rst_n(sys_resetn),
        .launch_pulse(tpu_launch_pulse),
        .soft_reset_pulse(tpu_soft_reset_pulse),
        .mode_reg(tpu_mode_reg),
        .net_id_reg(tpu_net_id_reg),
        .desc_lo_reg(tpu_desc_lo_reg),
        .desc_hi_reg(tpu_desc_hi_reg),
        .status_busy(tpu_stub_status_busy),
        .status_done(tpu_stub_status_done),
        .status_error(tpu_stub_status_error)
    );

    tpu_ctrl_axil_regs #(
        .TPU_BASE_ADDR(32'h4000_4000)
    ) tpu_ctrl_axil_regs_u (
        .clk(clk),
        .rst_n(sys_resetn),
        .s_axil_awaddr(tpu_ctrl_axil_awaddr),
        .s_axil_awprot(tpu_ctrl_axil_awprot),
        .s_axil_awvalid(tpu_ctrl_axil_awvalid),
        .s_axil_awready(tpu_ctrl_axil_awready),
        .s_axil_wdata(tpu_ctrl_axil_wdata),
        .s_axil_wstrb(tpu_ctrl_axil_wstrb),
        .s_axil_wvalid(tpu_ctrl_axil_wvalid),
        .s_axil_wready(tpu_ctrl_axil_wready),
        .s_axil_bresp(tpu_ctrl_axil_bresp),
        .s_axil_bvalid(tpu_ctrl_axil_bvalid),
        .s_axil_bready(tpu_ctrl_axil_bready),
        .s_axil_araddr(tpu_ctrl_axil_araddr),
        .s_axil_arprot(tpu_ctrl_axil_arprot),
        .s_axil_arvalid(tpu_ctrl_axil_arvalid),
        .s_axil_arready(tpu_ctrl_axil_arready),
        .s_axil_rdata(tpu_ctrl_axil_rdata),
        .s_axil_rresp(tpu_ctrl_axil_rresp),
        .s_axil_rvalid(tpu_ctrl_axil_rvalid),
        .s_axil_rready(tpu_ctrl_axil_rready),
        .status_busy(tpu_ctrl_status_busy),
        .status_done(tpu_ctrl_status_done),
        .status_error(tpu_ctrl_status_error),
        .launch_pulse(tpu_launch_pulse),
        .soft_reset_pulse(tpu_soft_reset_pulse),
        .mode_reg(tpu_mode_reg),
        .net_id_reg(tpu_net_id_reg),
        .desc_lo_reg(tpu_desc_lo_reg),
        .desc_hi_reg(tpu_desc_hi_reg),
        .irq_en_reg(tpu_irq_en_reg),
        .perf_cycle_reg(tpu_perf_cycle_reg)
    );

    apb_uart #(
        .clk_frequency_MHz(clk_frequency_MHz),
        .baud_rate(115200),
        .tx_rx_fifo_ram_type("bram"),
        .tx_fifo_depth(2048),
        .rx_fifo_depth(4096),
        .en_itr("false"),
        .simulation_delay(simulation_delay)
    ) apb_uart_u (
        .clk(clk),
        .resetn(sys_resetn),
        .paddr(m0_apb_paddr),
        .psel(m0_apb_psel),
        .penable(m0_apb_penable),
        .pwrite(m0_apb_pwrite),
        .pwdata(m0_apb_pwdata),
        .pready_out(m0_apb_pready),
        .prdata_out(m0_apb_prdata),
        .pslverr_out(m0_apb_pslverr),
        .uart_tx(uart0_tx),
        .uart_rx(uart0_rx),
        .uart_itr()
    );

    panda_soc_shared_mem_subsys panda_soc_shared_mem_subsys_u (
        .clk(clk),
        .rst(~sys_resetn),
        .cpu_axi_araddr(m_axi_dcache_araddr),
        .cpu_axi_arburst(m_axi_dcache_arburst),
        .cpu_axi_arlen(m_axi_dcache_arlen),
        .cpu_axi_arsize(m_axi_dcache_arsize),
        .cpu_axi_arcache(m_axi_dcache_arcache),
        .cpu_axi_arvalid(m_axi_dcache_arvalid),
        .cpu_axi_arready(m_axi_dcache_arready),
        .cpu_axi_awaddr(m_axi_dcache_awaddr),
        .cpu_axi_awburst(m_axi_dcache_awburst),
        .cpu_axi_awlen(m_axi_dcache_awlen),
        .cpu_axi_awsize(m_axi_dcache_awsize),
        .cpu_axi_awcache(m_axi_dcache_awcache),
        .cpu_axi_awvalid(m_axi_dcache_awvalid),
        .cpu_axi_awready(m_axi_dcache_awready),
        .cpu_axi_bresp(m_axi_dcache_bresp),
        .cpu_axi_bvalid(m_axi_dcache_bvalid),
        .cpu_axi_bready(m_axi_dcache_bready),
        .cpu_axi_rdata(m_axi_dcache_rdata),
        .cpu_axi_rresp(m_axi_dcache_rresp),
        .cpu_axi_rlast(m_axi_dcache_rlast),
        .cpu_axi_rvalid(m_axi_dcache_rvalid),
        .cpu_axi_rready(m_axi_dcache_rready),
        .cpu_axi_wdata(m_axi_dcache_wdata),
        .cpu_axi_wstrb(m_axi_dcache_wstrb),
        .cpu_axi_wlast(m_axi_dcache_wlast),
        .cpu_axi_wvalid(m_axi_dcache_wvalid),
        .cpu_axi_wready(m_axi_dcache_wready),
        .tpu_axi_araddr(tpu_mem_axi_araddr),
        .tpu_axi_arburst(tpu_mem_axi_arburst),
        .tpu_axi_arlen(tpu_mem_axi_arlen),
        .tpu_axi_arsize(tpu_mem_axi_arsize),
        .tpu_axi_arcache(tpu_mem_axi_arcache),
        .tpu_axi_arvalid(tpu_mem_axi_arvalid),
        .tpu_axi_arready(tpu_mem_axi_arready),
        .tpu_axi_awaddr(tpu_mem_axi_awaddr),
        .tpu_axi_awburst(tpu_mem_axi_awburst),
        .tpu_axi_awlen(tpu_mem_axi_awlen),
        .tpu_axi_awsize(tpu_mem_axi_awsize),
        .tpu_axi_awcache(tpu_mem_axi_awcache),
        .tpu_axi_awvalid(tpu_mem_axi_awvalid),
        .tpu_axi_awready(tpu_mem_axi_awready),
        .tpu_axi_bresp(tpu_mem_axi_bresp),
        .tpu_axi_bvalid(tpu_mem_axi_bvalid),
        .tpu_axi_bready(tpu_mem_axi_bready),
        .tpu_axi_rdata(tpu_mem_axi_rdata),
        .tpu_axi_rresp(tpu_mem_axi_rresp),
        .tpu_axi_rlast(tpu_mem_axi_rlast),
        .tpu_axi_rvalid(tpu_mem_axi_rvalid),
        .tpu_axi_rready(tpu_mem_axi_rready),
        .tpu_axi_wdata(tpu_mem_axi_wdata),
        .tpu_axi_wstrb(tpu_mem_axi_wstrb),
        .tpu_axi_wlast(tpu_mem_axi_wlast),
        .tpu_axi_wvalid(tpu_mem_axi_wvalid),
        .tpu_axi_wready(tpu_mem_axi_wready)
    );

endmodule
`default_nettype wire
