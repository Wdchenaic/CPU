/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: IF/ID流水级寄存器

描述:
在取指单元与译码/派遣单元之间插入1级显式流水寄存器,
将当前的取指结果握手边界转化为可见的IF/ID阶段边界。

协议:
REQ/ACK

作者: OpenAI Codex
日期: 2026/04/04
********************************************************************/

module panda_risc_v_if_id_pipe #(
    parameter integer inst_id_width = 4,
    parameter real simulation_delay = 1
)(
    input wire clk,
    input wire sys_resetn,

    input wire sys_reset_req,
    input wire flush_req,

    input wire[127:0] s_if_res_data,
    input wire[3:0] s_if_res_msg,
    input wire[inst_id_width-1:0] s_if_res_id,
    input wire s_if_res_is_first_inst_after_rst,
    input wire s_if_res_valid,
    output wire s_if_res_ready,

    output wire[127:0] m_if_res_data,
    output wire[3:0] m_if_res_msg,
    output wire[inst_id_width-1:0] m_if_res_id,
    output wire m_if_res_is_first_inst_after_rst,
    output wire m_if_res_valid,
    input wire m_if_res_ready
);

    reg pipe_valid;
    reg[127:0] pipe_data;
    reg[3:0] pipe_msg;
    reg[inst_id_width-1:0] pipe_id;
    reg pipe_is_first_inst_after_rst;

    assign s_if_res_ready = (~(sys_reset_req | flush_req)) & ((~pipe_valid) | m_if_res_ready);

    always @(posedge clk or negedge sys_resetn)
    begin
        if(~sys_resetn)
            pipe_valid <= 1'b0;
        else if(sys_reset_req | flush_req)
            pipe_valid <= # simulation_delay 1'b0;
        else if(s_if_res_ready)
            pipe_valid <= # simulation_delay s_if_res_valid;
    end

    always @(posedge clk)
    begin
        if((~(sys_reset_req | flush_req)) & s_if_res_ready & s_if_res_valid)
        begin
            pipe_data <= # simulation_delay s_if_res_data;
            pipe_msg <= # simulation_delay s_if_res_msg;
            pipe_id <= # simulation_delay s_if_res_id;
            pipe_is_first_inst_after_rst <= # simulation_delay s_if_res_is_first_inst_after_rst;
        end
    end

    assign m_if_res_data = pipe_data;
    assign m_if_res_msg = pipe_msg;
    assign m_if_res_id = pipe_id;
    assign m_if_res_is_first_inst_after_rst = pipe_is_first_inst_after_rst;
    assign m_if_res_valid = pipe_valid;

endmodule
