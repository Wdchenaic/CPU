`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
共享存储子系统
@brief  二阶段 CPU+TPU SoC 的数据面共享内存骨架：
        CPU dcache AXI master + TPU DMA AXI master -> axi_interconnect -> axi_ram
@date   2026/04/16
************************************************************************************************************************/
module panda_soc_shared_mem_subsys #(
    parameter integer SHARED_SRAM_ADDR_WIDTH = 23,
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer AXI_ID_WIDTH = 1,
    parameter integer PIPELINE_OUTPUT = 0
)(
    input wire clk,
    input wire rst,

    // CPU dcache AXI master（来自 panda_risc_v_min_proc_sys）
    input  wire [AXI_ADDR_WIDTH-1:0] cpu_axi_araddr,
    input  wire [1:0]                cpu_axi_arburst,
    input  wire [7:0]                cpu_axi_arlen,
    input  wire [2:0]                cpu_axi_arsize,
    input  wire [3:0]                cpu_axi_arcache,
    input  wire                      cpu_axi_arvalid,
    output wire                      cpu_axi_arready,
    input  wire [AXI_ADDR_WIDTH-1:0] cpu_axi_awaddr,
    input  wire [1:0]                cpu_axi_awburst,
    input  wire [7:0]                cpu_axi_awlen,
    input  wire [2:0]                cpu_axi_awsize,
    input  wire [3:0]                cpu_axi_awcache,
    input  wire                      cpu_axi_awvalid,
    output wire                      cpu_axi_awready,
    output wire [1:0]                cpu_axi_bresp,
    output wire                      cpu_axi_bvalid,
    input  wire                      cpu_axi_bready,
    output wire [AXI_DATA_WIDTH-1:0] cpu_axi_rdata,
    output wire [1:0]                cpu_axi_rresp,
    output wire                      cpu_axi_rlast,
    output wire                      cpu_axi_rvalid,
    input  wire                      cpu_axi_rready,
    input  wire [AXI_DATA_WIDTH-1:0] cpu_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] cpu_axi_wstrb,
    input  wire                      cpu_axi_wlast,
    input  wire                      cpu_axi_wvalid,
    output wire                      cpu_axi_wready,

    // TPU DMA AXI master（后续由真实 DMA 引擎驱动）
    input  wire [AXI_ADDR_WIDTH-1:0] tpu_axi_araddr,
    input  wire [1:0]                tpu_axi_arburst,
    input  wire [7:0]                tpu_axi_arlen,
    input  wire [2:0]                tpu_axi_arsize,
    input  wire [3:0]                tpu_axi_arcache,
    input  wire                      tpu_axi_arvalid,
    output wire                      tpu_axi_arready,
    input  wire [AXI_ADDR_WIDTH-1:0] tpu_axi_awaddr,
    input  wire [1:0]                tpu_axi_awburst,
    input  wire [7:0]                tpu_axi_awlen,
    input  wire [2:0]                tpu_axi_awsize,
    input  wire [3:0]                tpu_axi_awcache,
    input  wire                      tpu_axi_awvalid,
    output wire                      tpu_axi_awready,
    output wire [1:0]                tpu_axi_bresp,
    output wire                      tpu_axi_bvalid,
    input  wire                      tpu_axi_bready,
    output wire [AXI_DATA_WIDTH-1:0] tpu_axi_rdata,
    output wire [1:0]                tpu_axi_rresp,
    output wire                      tpu_axi_rlast,
    output wire                      tpu_axi_rvalid,
    input  wire                      tpu_axi_rready,
    input  wire [AXI_DATA_WIDTH-1:0] tpu_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] tpu_axi_wstrb,
    input  wire                      tpu_axi_wlast,
    input  wire                      tpu_axi_wvalid,
    output wire                      tpu_axi_wready
);

    localparam integer AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    localparam [AXI_ADDR_WIDTH-1:0] SHARED_SRAM_BASE_ADDR = 32'h6000_0000;

    // Interconnect <-> RAM 单一主口
    wire [AXI_ID_WIDTH-1:0] ram_axi_awid;
    wire [AXI_ADDR_WIDTH-1:0] ram_axi_awaddr;
    wire [7:0] ram_axi_awlen;
    wire [2:0] ram_axi_awsize;
    wire [1:0] ram_axi_awburst;
    wire ram_axi_awlock;
    wire [3:0] ram_axi_awcache;
    wire [2:0] ram_axi_awprot;
    wire [3:0] ram_axi_awqos;
    wire [3:0] ram_axi_awregion;
    wire ram_axi_awvalid;
    wire ram_axi_awready;
    wire [AXI_DATA_WIDTH-1:0] ram_axi_wdata;
    wire [AXI_STRB_WIDTH-1:0] ram_axi_wstrb;
    wire ram_axi_wlast;
    wire ram_axi_wvalid;
    wire ram_axi_wready;
    wire [AXI_ID_WIDTH-1:0] ram_axi_bid;
    wire [1:0] ram_axi_bresp;
    wire ram_axi_bvalid;
    wire ram_axi_bready;
    wire [AXI_ID_WIDTH-1:0] ram_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0] ram_axi_araddr;
    wire [7:0] ram_axi_arlen;
    wire [2:0] ram_axi_arsize;
    wire [1:0] ram_axi_arburst;
    wire ram_axi_arlock;
    wire [3:0] ram_axi_arcache;
    wire [2:0] ram_axi_arprot;
    wire [3:0] ram_axi_arqos;
    wire [3:0] ram_axi_arregion;
    wire ram_axi_arvalid;
    wire ram_axi_arready;
    wire [AXI_ID_WIDTH-1:0] ram_axi_rid;
    wire [AXI_DATA_WIDTH-1:0] ram_axi_rdata;
    wire [1:0] ram_axi_rresp;
    wire ram_axi_rlast;
    wire ram_axi_rvalid;
    wire ram_axi_rready;

    axi_interconnect #(
        .S_COUNT(2),
        .M_COUNT(1),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .STRB_WIDTH(AXI_STRB_WIDTH),
        .ID_WIDTH(AXI_ID_WIDTH),
        .AWUSER_ENABLE(0),
        .WUSER_ENABLE(0),
        .BUSER_ENABLE(0),
        .ARUSER_ENABLE(0),
        .RUSER_ENABLE(0),
        .FORWARD_ID(0),
        .M_REGIONS(1),
        .M_BASE_ADDR({SHARED_SRAM_BASE_ADDR}),
        .M_ADDR_WIDTH({32'd23}),
        .M_CONNECT_READ({2'b11}),
        .M_CONNECT_WRITE({2'b11}),
        .M_SECURE(1'b0)
    ) axi_interconnect_u (
        .clk(clk),
        .rst(rst),

        .s_axi_awid({{AXI_ID_WIDTH{1'b0}}, {AXI_ID_WIDTH{1'b0}}}),
        .s_axi_awaddr({tpu_axi_awaddr, cpu_axi_awaddr}),
        .s_axi_awlen({tpu_axi_awlen, cpu_axi_awlen}),
        .s_axi_awsize({tpu_axi_awsize, cpu_axi_awsize}),
        .s_axi_awburst({tpu_axi_awburst, cpu_axi_awburst}),
        .s_axi_awlock({1'b0, 1'b0}),
        .s_axi_awcache({tpu_axi_awcache, cpu_axi_awcache}),
        .s_axi_awprot(6'b0),
        .s_axi_awqos(8'b0),
        .s_axi_awuser(2'b0),
        .s_axi_awvalid({tpu_axi_awvalid, cpu_axi_awvalid}),
        .s_axi_awready({tpu_axi_awready, cpu_axi_awready}),
        .s_axi_wdata({tpu_axi_wdata, cpu_axi_wdata}),
        .s_axi_wstrb({tpu_axi_wstrb, cpu_axi_wstrb}),
        .s_axi_wlast({tpu_axi_wlast, cpu_axi_wlast}),
        .s_axi_wuser(2'b0),
        .s_axi_wvalid({tpu_axi_wvalid, cpu_axi_wvalid}),
        .s_axi_wready({tpu_axi_wready, cpu_axi_wready}),
        .s_axi_bid(),
        .s_axi_bresp({tpu_axi_bresp, cpu_axi_bresp}),
        .s_axi_buser(),
        .s_axi_bvalid({tpu_axi_bvalid, cpu_axi_bvalid}),
        .s_axi_bready({tpu_axi_bready, cpu_axi_bready}),
        .s_axi_arid({{AXI_ID_WIDTH{1'b0}}, {AXI_ID_WIDTH{1'b0}}}),
        .s_axi_araddr({tpu_axi_araddr, cpu_axi_araddr}),
        .s_axi_arlen({tpu_axi_arlen, cpu_axi_arlen}),
        .s_axi_arsize({tpu_axi_arsize, cpu_axi_arsize}),
        .s_axi_arburst({tpu_axi_arburst, cpu_axi_arburst}),
        .s_axi_arlock({1'b0, 1'b0}),
        .s_axi_arcache({tpu_axi_arcache, cpu_axi_arcache}),
        .s_axi_arprot(6'b0),
        .s_axi_arqos(8'b0),
        .s_axi_aruser(2'b0),
        .s_axi_arvalid({tpu_axi_arvalid, cpu_axi_arvalid}),
        .s_axi_arready({tpu_axi_arready, cpu_axi_arready}),
        .s_axi_rid(),
        .s_axi_rdata({tpu_axi_rdata, cpu_axi_rdata}),
        .s_axi_rresp({tpu_axi_rresp, cpu_axi_rresp}),
        .s_axi_rlast({tpu_axi_rlast, cpu_axi_rlast}),
        .s_axi_ruser(),
        .s_axi_rvalid({tpu_axi_rvalid, cpu_axi_rvalid}),
        .s_axi_rready({tpu_axi_rready, cpu_axi_rready}),

        .m_axi_awid(ram_axi_awid),
        .m_axi_awaddr(ram_axi_awaddr),
        .m_axi_awlen(ram_axi_awlen),
        .m_axi_awsize(ram_axi_awsize),
        .m_axi_awburst(ram_axi_awburst),
        .m_axi_awlock(ram_axi_awlock),
        .m_axi_awcache(ram_axi_awcache),
        .m_axi_awprot(ram_axi_awprot),
        .m_axi_awqos(ram_axi_awqos),
        .m_axi_awregion(ram_axi_awregion),
        .m_axi_awuser(),
        .m_axi_awvalid(ram_axi_awvalid),
        .m_axi_awready(ram_axi_awready),
        .m_axi_wdata(ram_axi_wdata),
        .m_axi_wstrb(ram_axi_wstrb),
        .m_axi_wlast(ram_axi_wlast),
        .m_axi_wuser(),
        .m_axi_wvalid(ram_axi_wvalid),
        .m_axi_wready(ram_axi_wready),
        .m_axi_bid(ram_axi_bid),
        .m_axi_bresp(ram_axi_bresp),
        .m_axi_buser(1'b0),
        .m_axi_bvalid(ram_axi_bvalid),
        .m_axi_bready(ram_axi_bready),
        .m_axi_arid(ram_axi_arid),
        .m_axi_araddr(ram_axi_araddr),
        .m_axi_arlen(ram_axi_arlen),
        .m_axi_arsize(ram_axi_arsize),
        .m_axi_arburst(ram_axi_arburst),
        .m_axi_arlock(ram_axi_arlock),
        .m_axi_arcache(ram_axi_arcache),
        .m_axi_arprot(ram_axi_arprot),
        .m_axi_arqos(ram_axi_arqos),
        .m_axi_arregion(ram_axi_arregion),
        .m_axi_aruser(),
        .m_axi_arvalid(ram_axi_arvalid),
        .m_axi_arready(ram_axi_arready),
        .m_axi_rid(ram_axi_rid),
        .m_axi_rdata(ram_axi_rdata),
        .m_axi_rresp(ram_axi_rresp),
        .m_axi_rlast(ram_axi_rlast),
        .m_axi_ruser(1'b0),
        .m_axi_rvalid(ram_axi_rvalid),
        .m_axi_rready(ram_axi_rready)
    );

    axi_ram #(
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ADDR_WIDTH(SHARED_SRAM_ADDR_WIDTH),
        .STRB_WIDTH(AXI_STRB_WIDTH),
        .ID_WIDTH(AXI_ID_WIDTH),
        .PIPELINE_OUTPUT(PIPELINE_OUTPUT)
    ) axi_ram_u (
        .clk(clk),
        .rst(rst),
        .s_axi_awid(ram_axi_awid),
        .s_axi_awaddr(ram_axi_awaddr[SHARED_SRAM_ADDR_WIDTH-1:0]),
        .s_axi_awlen(ram_axi_awlen),
        .s_axi_awsize(ram_axi_awsize),
        .s_axi_awburst(ram_axi_awburst),
        .s_axi_awlock(ram_axi_awlock),
        .s_axi_awcache(ram_axi_awcache),
        .s_axi_awprot(ram_axi_awprot),
        .s_axi_awvalid(ram_axi_awvalid),
        .s_axi_awready(ram_axi_awready),
        .s_axi_wdata(ram_axi_wdata),
        .s_axi_wstrb(ram_axi_wstrb),
        .s_axi_wlast(ram_axi_wlast),
        .s_axi_wvalid(ram_axi_wvalid),
        .s_axi_wready(ram_axi_wready),
        .s_axi_bid(ram_axi_bid),
        .s_axi_bresp(ram_axi_bresp),
        .s_axi_bvalid(ram_axi_bvalid),
        .s_axi_bready(ram_axi_bready),
        .s_axi_arid(ram_axi_arid),
        .s_axi_araddr(ram_axi_araddr[SHARED_SRAM_ADDR_WIDTH-1:0]),
        .s_axi_arlen(ram_axi_arlen),
        .s_axi_arsize(ram_axi_arsize),
        .s_axi_arburst(ram_axi_arburst),
        .s_axi_arlock(ram_axi_arlock),
        .s_axi_arcache(ram_axi_arcache),
        .s_axi_arprot(ram_axi_arprot),
        .s_axi_arvalid(ram_axi_arvalid),
        .s_axi_arready(ram_axi_arready),
        .s_axi_rid(ram_axi_rid),
        .s_axi_rdata(ram_axi_rdata),
        .s_axi_rresp(ram_axi_rresp),
        .s_axi_rlast(ram_axi_rlast),
        .s_axi_rvalid(ram_axi_rvalid),
        .s_axi_rready(ram_axi_rready)
    );

endmodule
`default_nettype wire
