`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
CPU 控制面 AXI-Lite 分流器
@brief  将 CPU `m_axi_dbus_*` 控制面分成两路：
        - m0: legacy AXI-Lite 外设路径（UART/APB）
        - m1: TPU_CTRL AXI-Lite 寄存器块
@date   2026/04/16
************************************************************************************************************************/
module cpu_tpu_axil_splitter #(
    parameter [31:0] TPU_BASE_ADDR = 32'h4000_4000,
    parameter integer TPU_ADDR_RANGE = 4096
)(
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axil_awaddr,
    input  wire [2:0]  s_axil_awprot,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,

    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,

    output wire [1:0]  s_axil_bresp,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,

    input  wire [31:0] s_axil_araddr,
    input  wire [2:0]  s_axil_arprot,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,

    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,

    output wire [31:0] m0_axil_awaddr,
    output wire [2:0]  m0_axil_awprot,
    output wire        m0_axil_awvalid,
    input  wire        m0_axil_awready,
    output wire [31:0] m0_axil_wdata,
    output wire [3:0]  m0_axil_wstrb,
    output wire        m0_axil_wvalid,
    input  wire        m0_axil_wready,
    input  wire [1:0]  m0_axil_bresp,
    input  wire        m0_axil_bvalid,
    output wire        m0_axil_bready,
    output wire [31:0] m0_axil_araddr,
    output wire [2:0]  m0_axil_arprot,
    output wire        m0_axil_arvalid,
    input  wire        m0_axil_arready,
    input  wire [31:0] m0_axil_rdata,
    input  wire [1:0]  m0_axil_rresp,
    input  wire        m0_axil_rvalid,
    output wire        m0_axil_rready,

    output wire [31:0] m1_axil_awaddr,
    output wire [2:0]  m1_axil_awprot,
    output wire        m1_axil_awvalid,
    input  wire        m1_axil_awready,
    output wire [31:0] m1_axil_wdata,
    output wire [3:0]  m1_axil_wstrb,
    output wire        m1_axil_wvalid,
    input  wire        m1_axil_wready,
    input  wire [1:0]  m1_axil_bresp,
    input  wire        m1_axil_bvalid,
    output wire        m1_axil_bready,
    output wire [31:0] m1_axil_araddr,
    output wire [2:0]  m1_axil_arprot,
    output wire        m1_axil_arvalid,
    input  wire        m1_axil_arready,
    input  wire [31:0] m1_axil_rdata,
    input  wire [1:0]  m1_axil_rresp,
    input  wire        m1_axil_rvalid,
    output wire        m1_axil_rready
);

    reg write_sel_tpu_reg;
    reg read_sel_tpu_reg;
    reg write_busy_reg;
    reg read_busy_reg;

    wire aw_sel_tpu;
    wire ar_sel_tpu;

    assign aw_sel_tpu =
        (s_axil_awaddr >= TPU_BASE_ADDR) &&
        (s_axil_awaddr < (TPU_BASE_ADDR + TPU_ADDR_RANGE));
    assign ar_sel_tpu =
        (s_axil_araddr >= TPU_BASE_ADDR) &&
        (s_axil_araddr < (TPU_BASE_ADDR + TPU_ADDR_RANGE));

    assign m0_axil_awaddr  = s_axil_awaddr;
    assign m0_axil_awprot  = s_axil_awprot;
    assign m0_axil_awvalid = s_axil_awvalid && !aw_sel_tpu && !write_busy_reg;
    assign m1_axil_awaddr  = s_axil_awaddr;
    assign m1_axil_awprot  = s_axil_awprot;
    assign m1_axil_awvalid = s_axil_awvalid && aw_sel_tpu && !write_busy_reg;

    assign s_axil_awready = !write_busy_reg && (aw_sel_tpu ? m1_axil_awready : m0_axil_awready);

    assign m0_axil_wdata  = s_axil_wdata;
    assign m0_axil_wstrb  = s_axil_wstrb;
    assign m0_axil_wvalid = s_axil_wvalid && write_busy_reg && !write_sel_tpu_reg;
    assign m1_axil_wdata  = s_axil_wdata;
    assign m1_axil_wstrb  = s_axil_wstrb;
    assign m1_axil_wvalid = s_axil_wvalid && write_busy_reg && write_sel_tpu_reg;

    assign s_axil_wready = write_busy_reg && (write_sel_tpu_reg ? m1_axil_wready : m0_axil_wready);

    assign m0_axil_bready = s_axil_bready && !write_sel_tpu_reg;
    assign m1_axil_bready = s_axil_bready && write_sel_tpu_reg;
    assign s_axil_bresp   = write_sel_tpu_reg ? m1_axil_bresp : m0_axil_bresp;
    assign s_axil_bvalid  = write_sel_tpu_reg ? m1_axil_bvalid : m0_axil_bvalid;

    assign m0_axil_araddr  = s_axil_araddr;
    assign m0_axil_arprot  = s_axil_arprot;
    assign m0_axil_arvalid = s_axil_arvalid && !ar_sel_tpu && !read_busy_reg;
    assign m1_axil_araddr  = s_axil_araddr;
    assign m1_axil_arprot  = s_axil_arprot;
    assign m1_axil_arvalid = s_axil_arvalid && ar_sel_tpu && !read_busy_reg;

    assign s_axil_arready = !read_busy_reg && (ar_sel_tpu ? m1_axil_arready : m0_axil_arready);

    assign m0_axil_rready = s_axil_rready && !read_sel_tpu_reg;
    assign m1_axil_rready = s_axil_rready && read_sel_tpu_reg;
    assign s_axil_rdata   = read_sel_tpu_reg ? m1_axil_rdata : m0_axil_rdata;
    assign s_axil_rresp   = read_sel_tpu_reg ? m1_axil_rresp : m0_axil_rresp;
    assign s_axil_rvalid  = read_sel_tpu_reg ? m1_axil_rvalid : m0_axil_rvalid;

    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            write_sel_tpu_reg <= 1'b0;
            read_sel_tpu_reg  <= 1'b0;
            write_busy_reg    <= 1'b0;
            read_busy_reg     <= 1'b0;
        end else begin
            if((!write_busy_reg) && s_axil_awvalid && s_axil_awready) begin
                write_sel_tpu_reg <= aw_sel_tpu;
                write_busy_reg    <= 1'b1;
            end else if(write_busy_reg && s_axil_bvalid && s_axil_bready) begin
                write_busy_reg <= 1'b0;
            end

            if((!read_busy_reg) && s_axil_arvalid && s_axil_arready) begin
                read_sel_tpu_reg <= ar_sel_tpu;
                read_busy_reg    <= 1'b1;
            end else if(read_busy_reg && s_axil_rvalid && s_axil_rready) begin
                read_busy_reg <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
