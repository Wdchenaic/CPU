`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
TPU 控制寄存器块
@brief  二阶段 SoC 最小 TPU_CTRL：
        CTRL / STATUS / MODE / NET_ID / DESC_LO / DESC_HI / PERF_CYCLE
@date   2026/04/16
************************************************************************************************************************/
module tpu_ctrl_axil_regs #(
    parameter [31:0] TPU_BASE_ADDR = 32'h4000_4000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] s_axil_awaddr,
    input  wire [2:0]  s_axil_awprot,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,

    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,

    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,

    input  wire [31:0] s_axil_araddr,
    input  wire [2:0]  s_axil_arprot,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,

    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    input  wire        status_busy,
    input  wire        status_done,
    input  wire        status_error,

    output reg         launch_pulse,
    output reg         soft_reset_pulse,
    output reg  [31:0] mode_reg,
    output reg  [31:0] net_id_reg,
    output reg  [31:0] desc_lo_reg,
    output reg  [31:0] desc_hi_reg,
    output reg         irq_en_reg,
    output reg  [31:0] perf_cycle_reg
);

    localparam [11:0] REG_CTRL       = 12'h000;
    localparam [11:0] REG_STATUS     = 12'h004;
    localparam [11:0] REG_MODE       = 12'h008;
    localparam [11:0] REG_NET_ID     = 12'h00C;
    localparam [11:0] REG_DESC_LO    = 12'h010;
    localparam [11:0] REG_DESC_HI    = 12'h014;
    localparam [11:0] REG_PERF_CYCLE = 12'h018;

    wire [11:0] aw_ofs;
    wire [11:0] ar_ofs;
    reg  [11:0] aw_ofs_reg;
    reg  [31:0] wdata_reg;
    reg  [3:0]  wstrb_reg;
    reg         aw_pending_reg;
    reg         w_pending_reg;

    assign aw_ofs = s_axil_awaddr[11:0] - TPU_BASE_ADDR[11:0];
    assign ar_ofs = s_axil_araddr[11:0] - TPU_BASE_ADDR[11:0];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            s_axil_awready    <= 1'b1;
            s_axil_wready     <= 1'b1;
            s_axil_bresp      <= 2'b00;
            s_axil_bvalid     <= 1'b0;
            s_axil_arready    <= 1'b1;
            s_axil_rdata      <= 32'd0;
            s_axil_rresp      <= 2'b00;
            s_axil_rvalid     <= 1'b0;
            launch_pulse      <= 1'b0;
            soft_reset_pulse  <= 1'b0;
            mode_reg          <= 32'd0;
            net_id_reg        <= 32'd0;
            desc_lo_reg       <= 32'd0;
            desc_hi_reg       <= 32'd0;
            irq_en_reg        <= 1'b0;
            perf_cycle_reg    <= 32'd0;
            aw_ofs_reg        <= 12'd0;
            wdata_reg         <= 32'd0;
            wstrb_reg         <= 4'd0;
            aw_pending_reg    <= 1'b0;
            w_pending_reg     <= 1'b0;
        end else begin
            launch_pulse     <= 1'b0;
            soft_reset_pulse <= 1'b0;
            s_axil_awready   <= (!aw_pending_reg) && (!s_axil_bvalid);
            s_axil_wready    <= (!w_pending_reg)  && (!s_axil_bvalid);

            if(status_busy) begin
                perf_cycle_reg <= perf_cycle_reg + 32'd1;
            end

            if(s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
            if(s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end

            if((!aw_pending_reg) && s_axil_awvalid && s_axil_awready) begin
                aw_ofs_reg     <= aw_ofs;
                aw_pending_reg <= 1'b1;
            end

            if((!w_pending_reg) && s_axil_wvalid && s_axil_wready) begin
                wdata_reg     <= s_axil_wdata;
                wstrb_reg     <= s_axil_wstrb;
                w_pending_reg <= 1'b1;
            end

            if(aw_pending_reg && w_pending_reg && !s_axil_bvalid) begin
                case(aw_ofs_reg)
                    REG_CTRL: begin
                        if(wstrb_reg[0]) begin
                            launch_pulse     <= wdata_reg[0];
                            soft_reset_pulse <= wdata_reg[1];
                            irq_en_reg       <= wdata_reg[2];
                            if(wdata_reg[1]) begin
                                perf_cycle_reg <= 32'd0;
                            end
                        end
                    end
                    REG_MODE: begin
                        mode_reg <= wdata_reg;
                    end
                    REG_NET_ID: begin
                        net_id_reg <= wdata_reg;
                    end
                    REG_DESC_LO: begin
                        desc_lo_reg <= wdata_reg;
                    end
                    REG_DESC_HI: begin
                        desc_hi_reg <= wdata_reg;
                    end
                    REG_PERF_CYCLE: begin
                        perf_cycle_reg <= wdata_reg;
                    end
                    default: begin
                    end
                endcase

                aw_pending_reg <= 1'b0;
                w_pending_reg  <= 1'b0;
                s_axil_bresp   <= 2'b00;
                s_axil_bvalid  <= 1'b1;
            end

            if(s_axil_arvalid && s_axil_arready && !s_axil_rvalid) begin
                case(ar_ofs)
                    REG_CTRL: begin
                        s_axil_rdata <= {29'd0, irq_en_reg, 1'b0, 1'b0};
                    end
                    REG_STATUS: begin
                        s_axil_rdata <= {29'd0, status_error, status_done, status_busy};
                    end
                    REG_MODE: begin
                        s_axil_rdata <= mode_reg;
                    end
                    REG_NET_ID: begin
                        s_axil_rdata <= net_id_reg;
                    end
                    REG_DESC_LO: begin
                        s_axil_rdata <= desc_lo_reg;
                    end
                    REG_DESC_HI: begin
                        s_axil_rdata <= desc_hi_reg;
                    end
                    REG_PERF_CYCLE: begin
                        s_axil_rdata <= perf_cycle_reg;
                    end
                    default: begin
                        s_axil_rdata <= 32'd0;
                    end
                endcase
                s_axil_rresp  <= 2'b00;
                s_axil_rvalid <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
