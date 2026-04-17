`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
TPU 控制面任务级占位状态机
@brief  在真实 TPU DMA/launch engine 接入前，先提供最小 busy/done/error 行为，
        让 CPU -> TPU_CTRL -> status 这条控制面链路能够闭环。
@date   2026/04/16
************************************************************************************************************************/
module tpu_ctrl_task_stub #(
    parameter integer DONE_LATENCY_CYCLES = 64
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        launch_pulse,
    input  wire        soft_reset_pulse,
    input  wire [31:0] mode_reg,
    input  wire [31:0] net_id_reg,
    input  wire [31:0] desc_lo_reg,
    input  wire [31:0] desc_hi_reg,
    output reg         status_busy,
    output reg         status_done,
    output reg         status_error
);

    reg [31:0] countdown_reg;

    wire launch_req;
    wire launch_has_error;
    wire [31:0] cfg_reduce;

    assign launch_req = launch_pulse && (!status_busy);
    assign launch_has_error = (desc_lo_reg == 32'd0);
    assign cfg_reduce = mode_reg ^ net_id_reg ^ desc_hi_reg;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            status_busy  <= 1'b0;
            status_done  <= 1'b0;
            status_error <= 1'b0;
            countdown_reg <= 32'd0;
        end else if(soft_reset_pulse) begin
            status_busy  <= 1'b0;
            status_done  <= 1'b0;
            status_error <= 1'b0;
            countdown_reg <= 32'd0;
        end else begin
            if(launch_req) begin
                status_done  <= 1'b0;
                status_error <= 1'b0;

                if(launch_has_error) begin
                    status_busy  <= 1'b0;
                    status_done  <= 1'b0;
                    status_error <= 1'b1;
                    countdown_reg <= 32'd0;
                end else begin
                    status_busy <= 1'b1;
                    countdown_reg <= (DONE_LATENCY_CYCLES > 0) ? (DONE_LATENCY_CYCLES - 1 + cfg_reduce[0]) : 32'd0;
                end
            end else if(status_busy) begin
                if(countdown_reg == 32'd0) begin
                    status_busy <= 1'b0;
                    status_done <= 1'b1;
                end else begin
                    countdown_reg <= countdown_reg - 32'd1;
                end
            end
        end
    end
endmodule
`default_nettype wire
