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
本模块: EX/MEM流水级寄存器

描述:
在执行单元产生的LSU请求与LSU本体之间插入1级显式流水寄存器,
将加载/存储地址与写数据的形成边界整理为可见的EX/MEM阶段边界。

协议:
REQ/ACK

作者: OpenAI Codex
日期: 2026/04/05
********************************************************************/

module panda_risc_v_ex_mem_pipe #(
    parameter integer inst_id_width = 4,
    parameter real simulation_delay = 1
)(
    input wire clk,
    input wire sys_resetn,

    input wire flush_req,

    input wire s_ls_sel,
    input wire[2:0] s_ls_type,
    input wire[4:0] s_rd_id_for_ld,
    input wire[31:0] s_ls_addr,
    input wire[31:0] s_ls_din,
    input wire[inst_id_width-1:0] s_lsu_inst_id,
    input wire s_lsu_valid,
    output wire s_lsu_ready,

    output wire m_ls_sel,
    output wire[2:0] m_ls_type,
    output wire[4:0] m_rd_id_for_ld,
    output wire[31:0] m_ls_addr,
    output wire[31:0] m_ls_din,
    output wire[inst_id_width-1:0] m_lsu_inst_id,
    output wire m_lsu_valid,
    input wire m_lsu_ready
);

    reg pipe_valid;
    reg pipe_ls_sel;
    reg[2:0] pipe_ls_type;
    reg[4:0] pipe_rd_id_for_ld;
    reg[31:0] pipe_ls_addr;
    reg[31:0] pipe_ls_din;
    reg[inst_id_width-1:0] pipe_lsu_inst_id;

    assign s_lsu_ready = (~pipe_valid) | m_lsu_ready;

    always @(posedge clk or negedge sys_resetn)
    begin
        if(~sys_resetn)
            pipe_valid <= 1'b0;
        else if(flush_req)
            pipe_valid <= # simulation_delay 1'b0;
        else if(s_lsu_ready)
            pipe_valid <= # simulation_delay s_lsu_valid;
    end

    always @(posedge clk)
    begin
        if(s_lsu_ready & s_lsu_valid)
        begin
            pipe_ls_sel <= # simulation_delay s_ls_sel;
            pipe_ls_type <= # simulation_delay s_ls_type;
            pipe_rd_id_for_ld <= # simulation_delay s_rd_id_for_ld;
            pipe_ls_addr <= # simulation_delay s_ls_addr;
            pipe_ls_din <= # simulation_delay s_ls_din;
            pipe_lsu_inst_id <= # simulation_delay s_lsu_inst_id;
        end
    end

    assign m_ls_sel = pipe_ls_sel;
    assign m_ls_type = pipe_ls_type;
    assign m_rd_id_for_ld = pipe_rd_id_for_ld;
    assign m_ls_addr = pipe_ls_addr;
    assign m_ls_din = pipe_ls_din;
    assign m_lsu_inst_id = pipe_lsu_inst_id;
    assign m_lsu_valid = pipe_valid & (~flush_req);

endmodule
