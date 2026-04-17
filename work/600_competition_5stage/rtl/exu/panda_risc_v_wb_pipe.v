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
本模块: 写回阶段输入寄存器

描述:
在EXU内部的各类结果源与写回单元之间插入1级显式寄存器,
将写回入口整理为可见的WB阶段边界。

注意:
该级为保守实现。
当寄存器中仍有待仲裁的写回源时, 不再接受新的写回源集合。

协议:
REQ/ACK

作者: OpenAI Codex
日期: 2026/04/04
********************************************************************/

module panda_risc_v_wb_pipe #(
    parameter integer inst_id_width = 4,
    parameter real simulation_delay = 1
)(
    input wire clk,
    input wire resetn,

    input wire s_pst_res_inst_cmt,
    input wire s_pst_res_need_imdt_wbk,
    input wire s_pst_res_valid,
    output wire s_pst_res_ready,

    input wire s_alu_csr_wbk_is_csr_rw_inst,
    input wire[31:0] s_alu_csr_wbk_csr_v,
    input wire[31:0] s_alu_csr_wbk_alu_res,
    input wire[4:0] s_alu_csr_wbk_csr_rw_rd_id,
    input wire[4:0] s_alu_csr_wbk_alu_rd_id,
    input wire s_alu_csr_wbk_rd_vld,
    input wire[inst_id_width-1:0] s_alu_csr_wbk_csr_rw_inst_id,
    input wire[inst_id_width-1:0] s_alu_csr_wbk_alu_inst_id,
    input wire s_alu_csr_wbk_valid,
    output wire s_alu_csr_wbk_ready,

    input wire s_lsu_wbk_ls_sel,
    input wire[4:0] s_lsu_wbk_rd_id_for_ld,
    input wire[31:0] s_lsu_wbk_dout,
    input wire[31:0] s_lsu_wbk_ls_addr,
    input wire[1:0] s_lsu_wbk_err,
    input wire[inst_id_width-1:0] s_lsu_wbk_inst_id,
    input wire s_lsu_wbk_valid,
    output wire s_lsu_wbk_ready,

    input wire[31:0] s_mul_wbk_data,
    input wire[4:0] s_mul_wbk_rd_id,
    input wire[inst_id_width-1:0] s_mul_wbk_inst_id,
    input wire s_mul_wbk_valid,
    output wire s_mul_wbk_ready,

    input wire[31:0] s_div_wbk_data,
    input wire[4:0] s_div_wbk_rd_id,
    input wire[inst_id_width-1:0] s_div_wbk_inst_id,
    input wire s_div_wbk_valid,
    output wire s_div_wbk_ready,

    output wire m_pst_res_inst_cmt,
    output wire m_pst_res_need_imdt_wbk,
    output wire m_pst_res_valid,
    input wire m_pst_res_ready,

    output wire m_alu_csr_wbk_is_csr_rw_inst,
    output wire[31:0] m_alu_csr_wbk_csr_v,
    output wire[31:0] m_alu_csr_wbk_alu_res,
    output wire[4:0] m_alu_csr_wbk_csr_rw_rd_id,
    output wire[4:0] m_alu_csr_wbk_alu_rd_id,
    output wire m_alu_csr_wbk_rd_vld,
    output wire[inst_id_width-1:0] m_alu_csr_wbk_csr_rw_inst_id,
    output wire[inst_id_width-1:0] m_alu_csr_wbk_alu_inst_id,
    output wire m_alu_csr_wbk_valid,
    input wire m_alu_csr_wbk_ready,

    output wire m_lsu_wbk_ls_sel,
    output wire[4:0] m_lsu_wbk_rd_id_for_ld,
    output wire[31:0] m_lsu_wbk_dout,
    output wire[31:0] m_lsu_wbk_ls_addr,
    output wire[1:0] m_lsu_wbk_err,
    output wire[inst_id_width-1:0] m_lsu_wbk_inst_id,
    output wire m_lsu_wbk_valid,
    input wire m_lsu_wbk_ready,

    output wire[31:0] m_mul_wbk_data,
    output wire[4:0] m_mul_wbk_rd_id,
    output wire[inst_id_width-1:0] m_mul_wbk_inst_id,
    output wire m_mul_wbk_valid,
    input wire m_mul_wbk_ready,

    output wire[31:0] m_div_wbk_data,
    output wire[4:0] m_div_wbk_rd_id,
    output wire[inst_id_width-1:0] m_div_wbk_inst_id,
    output wire m_div_wbk_valid,
    input wire m_div_wbk_ready
);

    reg pipe_pst_res_inst_cmt;
    reg pipe_pst_res_need_imdt_wbk;
    reg pipe_pst_res_valid;

    reg pipe_alu_csr_wbk_is_csr_rw_inst;
    reg[31:0] pipe_alu_csr_wbk_csr_v;
    reg[31:0] pipe_alu_csr_wbk_alu_res;
    reg[4:0] pipe_alu_csr_wbk_csr_rw_rd_id;
    reg[4:0] pipe_alu_csr_wbk_alu_rd_id;
    reg pipe_alu_csr_wbk_rd_vld;
    reg[inst_id_width-1:0] pipe_alu_csr_wbk_csr_rw_inst_id;
    reg[inst_id_width-1:0] pipe_alu_csr_wbk_alu_inst_id;
    reg pipe_alu_csr_wbk_valid;

    reg pipe_lsu_wbk_ls_sel;
    reg[4:0] pipe_lsu_wbk_rd_id_for_ld;
    reg[31:0] pipe_lsu_wbk_dout;
    reg[31:0] pipe_lsu_wbk_ls_addr;
    reg[1:0] pipe_lsu_wbk_err;
    reg[inst_id_width-1:0] pipe_lsu_wbk_inst_id;
    reg pipe_lsu_wbk_valid;

    reg[31:0] pipe_mul_wbk_data;
    reg[4:0] pipe_mul_wbk_rd_id;
    reg[inst_id_width-1:0] pipe_mul_wbk_inst_id;
    reg pipe_mul_wbk_valid;

    reg[31:0] pipe_div_wbk_data;
    reg[4:0] pipe_div_wbk_rd_id;
    reg[inst_id_width-1:0] pipe_div_wbk_inst_id;
    reg pipe_div_wbk_valid;

    wire alu_csr_input_valid;
    wire upstream_bundle_valid;
    wire clear_pst;
    wire clear_alu_csr;
    wire clear_lsu;
    wire clear_mul;
    wire clear_div;
    wire bundle_drained;
    wire accept_new_bundle;

    assign alu_csr_input_valid =
        s_alu_csr_wbk_valid & ((~s_pst_res_inst_cmt) | s_pst_res_need_imdt_wbk);

    assign upstream_bundle_valid =
        s_pst_res_valid |
        alu_csr_input_valid |
        s_lsu_wbk_valid |
        s_mul_wbk_valid |
        s_div_wbk_valid;

    assign clear_pst = pipe_pst_res_valid & m_pst_res_ready;
    assign clear_alu_csr = pipe_alu_csr_wbk_valid & m_alu_csr_wbk_ready;
    assign clear_lsu = pipe_lsu_wbk_valid & m_lsu_wbk_ready;
    assign clear_mul = pipe_mul_wbk_valid & m_mul_wbk_ready;
    assign clear_div = pipe_div_wbk_valid & m_div_wbk_ready;

    assign bundle_drained =
        (~pipe_pst_res_valid | clear_pst) &
        (~pipe_alu_csr_wbk_valid | clear_alu_csr) &
        (~pipe_lsu_wbk_valid | clear_lsu) &
        (~pipe_mul_wbk_valid | clear_mul) &
        (~pipe_div_wbk_valid | clear_div);

    assign accept_new_bundle = bundle_drained;

    assign s_pst_res_ready = accept_new_bundle;
    assign s_alu_csr_wbk_ready = accept_new_bundle;
    assign s_lsu_wbk_ready = accept_new_bundle;
    assign s_mul_wbk_ready = accept_new_bundle;
    assign s_div_wbk_ready = accept_new_bundle;

    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            pipe_pst_res_valid <= 1'b0;
            pipe_alu_csr_wbk_valid <= 1'b0;
            pipe_lsu_wbk_valid <= 1'b0;
            pipe_mul_wbk_valid <= 1'b0;
            pipe_div_wbk_valid <= 1'b0;
        end
        else
        begin
            if(accept_new_bundle)
            begin
                pipe_pst_res_valid <= # simulation_delay s_pst_res_valid;
                pipe_alu_csr_wbk_valid <= # simulation_delay alu_csr_input_valid;
                pipe_lsu_wbk_valid <= # simulation_delay s_lsu_wbk_valid;
                pipe_mul_wbk_valid <= # simulation_delay s_mul_wbk_valid;
                pipe_div_wbk_valid <= # simulation_delay s_div_wbk_valid;
            end
            else if(bundle_drained)
            begin
                pipe_pst_res_valid <= # simulation_delay 1'b0;
                pipe_alu_csr_wbk_valid <= # simulation_delay 1'b0;
                pipe_lsu_wbk_valid <= # simulation_delay 1'b0;
                pipe_mul_wbk_valid <= # simulation_delay 1'b0;
                pipe_div_wbk_valid <= # simulation_delay 1'b0;
            end
        end
    end

    always @(posedge clk)
    begin
        if(accept_new_bundle & upstream_bundle_valid)
        begin
            pipe_pst_res_inst_cmt <= # simulation_delay s_pst_res_inst_cmt;
            pipe_pst_res_need_imdt_wbk <= # simulation_delay s_pst_res_need_imdt_wbk;

            pipe_alu_csr_wbk_is_csr_rw_inst <= # simulation_delay s_alu_csr_wbk_is_csr_rw_inst;
            pipe_alu_csr_wbk_csr_v <= # simulation_delay s_alu_csr_wbk_csr_v;
            pipe_alu_csr_wbk_alu_res <= # simulation_delay s_alu_csr_wbk_alu_res;
            pipe_alu_csr_wbk_csr_rw_rd_id <= # simulation_delay s_alu_csr_wbk_csr_rw_rd_id;
            pipe_alu_csr_wbk_alu_rd_id <= # simulation_delay s_alu_csr_wbk_alu_rd_id;
            pipe_alu_csr_wbk_rd_vld <= # simulation_delay s_alu_csr_wbk_rd_vld;
            pipe_alu_csr_wbk_csr_rw_inst_id <= # simulation_delay s_alu_csr_wbk_csr_rw_inst_id;
            pipe_alu_csr_wbk_alu_inst_id <= # simulation_delay s_alu_csr_wbk_alu_inst_id;

            pipe_lsu_wbk_ls_sel <= # simulation_delay s_lsu_wbk_ls_sel;
            pipe_lsu_wbk_rd_id_for_ld <= # simulation_delay s_lsu_wbk_rd_id_for_ld;
            pipe_lsu_wbk_dout <= # simulation_delay s_lsu_wbk_dout;
            pipe_lsu_wbk_ls_addr <= # simulation_delay s_lsu_wbk_ls_addr;
            pipe_lsu_wbk_err <= # simulation_delay s_lsu_wbk_err;
            pipe_lsu_wbk_inst_id <= # simulation_delay s_lsu_wbk_inst_id;

            pipe_mul_wbk_data <= # simulation_delay s_mul_wbk_data;
            pipe_mul_wbk_rd_id <= # simulation_delay s_mul_wbk_rd_id;
            pipe_mul_wbk_inst_id <= # simulation_delay s_mul_wbk_inst_id;

            pipe_div_wbk_data <= # simulation_delay s_div_wbk_data;
            pipe_div_wbk_rd_id <= # simulation_delay s_div_wbk_rd_id;
            pipe_div_wbk_inst_id <= # simulation_delay s_div_wbk_inst_id;
        end
    end

    assign m_pst_res_inst_cmt = pipe_pst_res_inst_cmt;
    assign m_pst_res_need_imdt_wbk = pipe_pst_res_need_imdt_wbk;
    assign m_pst_res_valid = pipe_pst_res_valid;

    assign m_alu_csr_wbk_is_csr_rw_inst = pipe_alu_csr_wbk_is_csr_rw_inst;
    assign m_alu_csr_wbk_csr_v = pipe_alu_csr_wbk_csr_v;
    assign m_alu_csr_wbk_alu_res = pipe_alu_csr_wbk_alu_res;
    assign m_alu_csr_wbk_csr_rw_rd_id = pipe_alu_csr_wbk_csr_rw_rd_id;
    assign m_alu_csr_wbk_alu_rd_id = pipe_alu_csr_wbk_alu_rd_id;
    assign m_alu_csr_wbk_rd_vld = pipe_alu_csr_wbk_rd_vld;
    assign m_alu_csr_wbk_csr_rw_inst_id = pipe_alu_csr_wbk_csr_rw_inst_id;
    assign m_alu_csr_wbk_alu_inst_id = pipe_alu_csr_wbk_alu_inst_id;
    assign m_alu_csr_wbk_valid = pipe_alu_csr_wbk_valid;

    assign m_lsu_wbk_ls_sel = pipe_lsu_wbk_ls_sel;
    assign m_lsu_wbk_rd_id_for_ld = pipe_lsu_wbk_rd_id_for_ld;
    assign m_lsu_wbk_dout = pipe_lsu_wbk_dout;
    assign m_lsu_wbk_ls_addr = pipe_lsu_wbk_ls_addr;
    assign m_lsu_wbk_err = pipe_lsu_wbk_err;
    assign m_lsu_wbk_inst_id = pipe_lsu_wbk_inst_id;
    assign m_lsu_wbk_valid = pipe_lsu_wbk_valid;

    assign m_mul_wbk_data = pipe_mul_wbk_data;
    assign m_mul_wbk_rd_id = pipe_mul_wbk_rd_id;
    assign m_mul_wbk_inst_id = pipe_mul_wbk_inst_id;
    assign m_mul_wbk_valid = pipe_mul_wbk_valid;

    assign m_div_wbk_data = pipe_div_wbk_data;
    assign m_div_wbk_rd_id = pipe_div_wbk_rd_id;
    assign m_div_wbk_inst_id = pipe_div_wbk_inst_id;
    assign m_div_wbk_valid = pipe_div_wbk_valid;

endmodule
