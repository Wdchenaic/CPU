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
本模块: ID/EX流水级寄存器

描述:
在译码/派遣与执行单元之间插入1级显式流水寄存器,
将当前分散的执行请求整理为一个统一的ID/EX边界。

注意:
仅在当前指令涉及的所有执行部件均就绪时, 该级才向后推进。

协议:
REQ/ACK

作者: OpenAI Codex
日期: 2026/04/04
********************************************************************/

module panda_risc_v_id_ex_pipe #(
    parameter integer inst_id_width = 4,
    parameter real simulation_delay = 1
)(
    input wire clk,
    input wire sys_resetn,

    input wire sys_reset_req,
    input wire flush_req,

    output wire s_issue_ready,

    input wire[3:0] s_alu_op_mode,
    input wire[31:0] s_alu_op1,
    input wire[31:0] s_alu_op2,
    input wire s_alu_addr_gen_sel,
    input wire[2:0] s_alu_err_code,
    input wire[31:0] s_alu_pc_of_inst,
    input wire s_alu_is_b_inst,
    input wire s_alu_is_jal_inst,
    input wire s_alu_is_jalr_inst,
    input wire s_alu_is_ecall_inst,
    input wire s_alu_is_mret_inst,
    input wire s_alu_is_csr_rw_inst,
    input wire s_alu_is_fence_i_inst,
    input wire s_alu_is_ebreak_inst,
    input wire s_alu_is_dret_inst,
    input wire s_alu_is_first_inst_after_rst,
    input wire[31:0] s_alu_brc_pc_upd,
    input wire[31:0] s_alu_prdt_pc,
    input wire s_alu_prdt_jump,
    input wire[4:0] s_alu_rd_id,
    input wire s_alu_rd_vld,
    input wire s_alu_is_long_inst,
    input wire[inst_id_width-1:0] s_alu_inst_id,
    input wire s_alu_valid,

    input wire s_ls_sel,
    input wire[2:0] s_ls_type,
    input wire[4:0] s_rd_id_for_ld,
    input wire[31:0] s_ls_din,
    input wire[inst_id_width-1:0] s_lsu_inst_id,
    input wire s_lsu_valid,

    input wire[11:0] s_csr_addr,
    input wire[1:0] s_csr_upd_type,
    input wire[31:0] s_csr_upd_mask_v,
    input wire[4:0] s_csr_rw_rd_id,
    input wire[inst_id_width-1:0] s_csr_rw_inst_id,
    input wire s_csr_rw_valid,

    input wire[32:0] s_mul_op_a,
    input wire[32:0] s_mul_op_b,
    input wire s_mul_res_sel,
    input wire[4:0] s_mul_rd_id,
    input wire[inst_id_width-1:0] s_mul_inst_id,
    input wire s_mul_valid,

    input wire[32:0] s_div_op_a,
    input wire[32:0] s_div_op_b,
    input wire s_div_rem_sel,
    input wire[4:0] s_div_rd_id,
    input wire[inst_id_width-1:0] s_div_inst_id,
    input wire s_div_valid,

    output wire[3:0] m_alu_op_mode,
    output wire[31:0] m_alu_op1,
    output wire[31:0] m_alu_op2,
    output wire m_alu_addr_gen_sel,
    output wire[2:0] m_alu_err_code,
    output wire[31:0] m_alu_pc_of_inst,
    output wire m_alu_is_b_inst,
    output wire m_alu_is_jal_inst,
    output wire m_alu_is_jalr_inst,
    output wire m_alu_is_ecall_inst,
    output wire m_alu_is_mret_inst,
    output wire m_alu_is_csr_rw_inst,
    output wire m_alu_is_fence_i_inst,
    output wire m_alu_is_ebreak_inst,
    output wire m_alu_is_dret_inst,
    output wire m_alu_is_first_inst_after_rst,
    output wire[31:0] m_alu_brc_pc_upd,
    output wire[31:0] m_alu_prdt_pc,
    output wire m_alu_prdt_jump,
    output wire[4:0] m_alu_rd_id,
    output wire m_alu_rd_vld,
    output wire m_alu_is_long_inst,
    output wire[inst_id_width-1:0] m_alu_inst_id,
    output wire m_alu_valid,
    input wire m_alu_ready,

    output wire m_ls_sel,
    output wire[2:0] m_ls_type,
    output wire[4:0] m_rd_id_for_ld,
    output wire[31:0] m_ls_din,
    output wire[inst_id_width-1:0] m_lsu_inst_id,
    output wire m_lsu_valid,
    input wire m_lsu_ready,

    output wire[11:0] m_csr_addr,
    output wire[1:0] m_csr_upd_type,
    output wire[31:0] m_csr_upd_mask_v,
    output wire[4:0] m_csr_rw_rd_id,
    output wire[inst_id_width-1:0] m_csr_rw_inst_id,
    output wire m_csr_rw_valid,
    input wire m_csr_rw_ready,

    output wire[32:0] m_mul_op_a,
    output wire[32:0] m_mul_op_b,
    output wire m_mul_res_sel,
    output wire[4:0] m_mul_rd_id,
    output wire[inst_id_width-1:0] m_mul_inst_id,
    output wire m_mul_valid,
    input wire m_mul_ready,

    output wire[32:0] m_div_op_a,
    output wire[32:0] m_div_op_b,
    output wire m_div_rem_sel,
    output wire[4:0] m_div_rd_id,
    output wire[inst_id_width-1:0] m_div_inst_id,
    output wire m_div_valid,
    input wire m_div_ready
);

    reg pipe_valid;

    reg[3:0] pipe_alu_op_mode;
    reg[31:0] pipe_alu_op1;
    reg[31:0] pipe_alu_op2;
    reg pipe_alu_addr_gen_sel;
    reg[2:0] pipe_alu_err_code;
    reg[31:0] pipe_alu_pc_of_inst;
    reg pipe_alu_is_b_inst;
    reg pipe_alu_is_jal_inst;
    reg pipe_alu_is_jalr_inst;
    reg pipe_alu_is_ecall_inst;
    reg pipe_alu_is_mret_inst;
    reg pipe_alu_is_csr_rw_inst;
    reg pipe_alu_is_fence_i_inst;
    reg pipe_alu_is_ebreak_inst;
    reg pipe_alu_is_dret_inst;
    reg pipe_alu_is_first_inst_after_rst;
    reg[31:0] pipe_alu_brc_pc_upd;
    reg[31:0] pipe_alu_prdt_pc;
    reg pipe_alu_prdt_jump;
    reg[4:0] pipe_alu_rd_id;
    reg pipe_alu_rd_vld;
    reg pipe_alu_is_long_inst;
    reg[inst_id_width-1:0] pipe_alu_inst_id;
    reg pipe_alu_valid;

    reg pipe_ls_sel;
    reg[2:0] pipe_ls_type;
    reg[4:0] pipe_rd_id_for_ld;
    reg[31:0] pipe_ls_din;
    reg[inst_id_width-1:0] pipe_lsu_inst_id;
    reg pipe_lsu_valid;

    reg[11:0] pipe_csr_addr;
    reg[1:0] pipe_csr_upd_type;
    reg[31:0] pipe_csr_upd_mask_v;
    reg[4:0] pipe_csr_rw_rd_id;
    reg[inst_id_width-1:0] pipe_csr_rw_inst_id;
    reg pipe_csr_rw_valid;

    reg[32:0] pipe_mul_op_a;
    reg[32:0] pipe_mul_op_b;
    reg pipe_mul_res_sel;
    reg[4:0] pipe_mul_rd_id;
    reg[inst_id_width-1:0] pipe_mul_inst_id;
    reg pipe_mul_valid;

    reg[32:0] pipe_div_op_a;
    reg[32:0] pipe_div_op_b;
    reg pipe_div_rem_sel;
    reg[4:0] pipe_div_rd_id;
    reg[inst_id_width-1:0] pipe_div_inst_id;
    reg pipe_div_valid;

    wire pipe_issue_valid;
    wire pipe_downstream_ready;

    assign pipe_issue_valid =
        s_alu_valid |
        s_lsu_valid |
        s_csr_rw_valid |
        s_mul_valid |
        s_div_valid;

    assign pipe_downstream_ready =
        m_alu_ready &
        ((~pipe_lsu_valid) | m_lsu_ready) &
        ((~pipe_csr_rw_valid) | m_csr_rw_ready) &
        ((~pipe_mul_valid) | m_mul_ready) &
        ((~pipe_div_valid) | m_div_ready);

    assign s_issue_ready = (~pipe_valid) | pipe_downstream_ready;

    always @(posedge clk or negedge sys_resetn)
    begin
        if(~sys_resetn)
            pipe_valid <= 1'b0;
        else if(sys_reset_req | flush_req)
            pipe_valid <= # simulation_delay 1'b0;
        else if(s_issue_ready)
            pipe_valid <= # simulation_delay pipe_issue_valid;
    end

    always @(posedge clk)
    begin
        if(s_issue_ready & pipe_issue_valid)
        begin
            pipe_alu_op_mode <= # simulation_delay s_alu_op_mode;
            pipe_alu_op1 <= # simulation_delay s_alu_op1;
            pipe_alu_op2 <= # simulation_delay s_alu_op2;
            pipe_alu_addr_gen_sel <= # simulation_delay s_alu_addr_gen_sel;
            pipe_alu_err_code <= # simulation_delay s_alu_err_code;
            pipe_alu_pc_of_inst <= # simulation_delay s_alu_pc_of_inst;
            pipe_alu_is_b_inst <= # simulation_delay s_alu_is_b_inst;
            pipe_alu_is_jal_inst <= # simulation_delay s_alu_is_jal_inst;
            pipe_alu_is_jalr_inst <= # simulation_delay s_alu_is_jalr_inst;
            pipe_alu_is_ecall_inst <= # simulation_delay s_alu_is_ecall_inst;
            pipe_alu_is_mret_inst <= # simulation_delay s_alu_is_mret_inst;
            pipe_alu_is_csr_rw_inst <= # simulation_delay s_alu_is_csr_rw_inst;
            pipe_alu_is_fence_i_inst <= # simulation_delay s_alu_is_fence_i_inst;
            pipe_alu_is_ebreak_inst <= # simulation_delay s_alu_is_ebreak_inst;
            pipe_alu_is_dret_inst <= # simulation_delay s_alu_is_dret_inst;
            pipe_alu_is_first_inst_after_rst <= # simulation_delay s_alu_is_first_inst_after_rst;
            pipe_alu_brc_pc_upd <= # simulation_delay s_alu_brc_pc_upd;
            pipe_alu_prdt_pc <= # simulation_delay s_alu_prdt_pc;
            pipe_alu_prdt_jump <= # simulation_delay s_alu_prdt_jump;
            pipe_alu_rd_id <= # simulation_delay s_alu_rd_id;
            pipe_alu_rd_vld <= # simulation_delay s_alu_rd_vld;
            pipe_alu_is_long_inst <= # simulation_delay s_alu_is_long_inst;
            pipe_alu_inst_id <= # simulation_delay s_alu_inst_id;
            pipe_alu_valid <= # simulation_delay s_alu_valid;

            pipe_ls_sel <= # simulation_delay s_ls_sel;
            pipe_ls_type <= # simulation_delay s_ls_type;
            pipe_rd_id_for_ld <= # simulation_delay s_rd_id_for_ld;
            pipe_ls_din <= # simulation_delay s_ls_din;
            pipe_lsu_inst_id <= # simulation_delay s_lsu_inst_id;
            pipe_lsu_valid <= # simulation_delay s_lsu_valid;

            pipe_csr_addr <= # simulation_delay s_csr_addr;
            pipe_csr_upd_type <= # simulation_delay s_csr_upd_type;
            pipe_csr_upd_mask_v <= # simulation_delay s_csr_upd_mask_v;
            pipe_csr_rw_rd_id <= # simulation_delay s_csr_rw_rd_id;
            pipe_csr_rw_inst_id <= # simulation_delay s_csr_rw_inst_id;
            pipe_csr_rw_valid <= # simulation_delay s_csr_rw_valid;

            pipe_mul_op_a <= # simulation_delay s_mul_op_a;
            pipe_mul_op_b <= # simulation_delay s_mul_op_b;
            pipe_mul_res_sel <= # simulation_delay s_mul_res_sel;
            pipe_mul_rd_id <= # simulation_delay s_mul_rd_id;
            pipe_mul_inst_id <= # simulation_delay s_mul_inst_id;
            pipe_mul_valid <= # simulation_delay s_mul_valid;

            pipe_div_op_a <= # simulation_delay s_div_op_a;
            pipe_div_op_b <= # simulation_delay s_div_op_b;
            pipe_div_rem_sel <= # simulation_delay s_div_rem_sel;
            pipe_div_rd_id <= # simulation_delay s_div_rd_id;
            pipe_div_inst_id <= # simulation_delay s_div_inst_id;
            pipe_div_valid <= # simulation_delay s_div_valid;
        end
    end

    assign m_alu_op_mode = pipe_alu_op_mode;
    assign m_alu_op1 = pipe_alu_op1;
    assign m_alu_op2 = pipe_alu_op2;
    assign m_alu_addr_gen_sel = pipe_alu_addr_gen_sel;
    assign m_alu_err_code = pipe_alu_err_code;
    assign m_alu_pc_of_inst = pipe_alu_pc_of_inst;
    assign m_alu_is_b_inst = pipe_alu_is_b_inst;
    assign m_alu_is_jal_inst = pipe_alu_is_jal_inst;
    assign m_alu_is_jalr_inst = pipe_alu_is_jalr_inst;
    assign m_alu_is_ecall_inst = pipe_alu_is_ecall_inst;
    assign m_alu_is_mret_inst = pipe_alu_is_mret_inst;
    assign m_alu_is_csr_rw_inst = pipe_alu_is_csr_rw_inst;
    assign m_alu_is_fence_i_inst = pipe_alu_is_fence_i_inst;
    assign m_alu_is_ebreak_inst = pipe_alu_is_ebreak_inst;
    assign m_alu_is_dret_inst = pipe_alu_is_dret_inst;
    assign m_alu_is_first_inst_after_rst = pipe_alu_is_first_inst_after_rst;
    assign m_alu_brc_pc_upd = pipe_alu_brc_pc_upd;
    assign m_alu_prdt_pc = pipe_alu_prdt_pc;
    assign m_alu_prdt_jump = pipe_alu_prdt_jump;
    assign m_alu_rd_id = pipe_alu_rd_id;
    assign m_alu_rd_vld = pipe_alu_rd_vld;
    assign m_alu_is_long_inst = pipe_alu_is_long_inst;
    assign m_alu_inst_id = pipe_alu_inst_id;
    assign m_alu_valid = pipe_valid & pipe_alu_valid;

    assign m_ls_sel = pipe_ls_sel;
    assign m_ls_type = pipe_ls_type;
    assign m_rd_id_for_ld = pipe_rd_id_for_ld;
    assign m_ls_din = pipe_ls_din;
    assign m_lsu_inst_id = pipe_lsu_inst_id;
    assign m_lsu_valid = pipe_valid & pipe_lsu_valid;

    assign m_csr_addr = pipe_csr_addr;
    assign m_csr_upd_type = pipe_csr_upd_type;
    assign m_csr_upd_mask_v = pipe_csr_upd_mask_v;
    assign m_csr_rw_rd_id = pipe_csr_rw_rd_id;
    assign m_csr_rw_inst_id = pipe_csr_rw_inst_id;
    assign m_csr_rw_valid = pipe_valid & pipe_csr_rw_valid;

    assign m_mul_op_a = pipe_mul_op_a;
    assign m_mul_op_b = pipe_mul_op_b;
    assign m_mul_res_sel = pipe_mul_res_sel;
    assign m_mul_rd_id = pipe_mul_rd_id;
    assign m_mul_inst_id = pipe_mul_inst_id;
    assign m_mul_valid = pipe_valid & pipe_mul_valid;

    assign m_div_op_a = pipe_div_op_a;
    assign m_div_op_b = pipe_div_op_b;
    assign m_div_rem_sel = pipe_div_rem_sel;
    assign m_div_rd_id = pipe_div_rd_id;
    assign m_div_inst_id = pipe_div_inst_id;
    assign m_div_valid = pipe_valid & pipe_div_valid;

endmodule
