`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
TPU descriptor/data fetch DMA 占位模块
@brief  最小数据面原型：收到 launch 后，作为 AXI master 从 shared SRAM 依次执行：
        1. 读取 8-word descriptor
        2. 读取 input blob
        3. 读取 param blob(由 net_id 对应固定表决定 word 数)
        4. 生成最小结果并写回 output blob

        当前仍不接真实 TPU core，只做系统级闭环占位：
        - DMA 将 input/param word 以流式 valid 喂给可替换 compute block
        - compute block 生成 output，DMA 负责写回 shared SRAM
@date   2026/04/16
************************************************************************************************************************/
module tpu_desc_fetch_dma_stub #(
    parameter [2:0] AXI_SIZE_WORD = 3'b010,
    parameter [31:0] NET0_PARAM_WORDS = 32'd4,
    parameter [31:0] NET1_PARAM_WORDS = 32'd6,
    parameter [31:0] NET2_PARAM_WORDS = 32'd8,
    parameter [31:0] NET3_PARAM_WORDS = 32'd0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        launch_pulse,
    input  wire        soft_reset_pulse,
    input  wire [31:0] desc_base_addr,

    output reg         status_busy,
    output reg         status_done,
    output reg         status_error,

    output reg  [31:0] desc_net_id_reg,
    output reg  [31:0] desc_input_addr_reg,
    output reg  [31:0] desc_output_addr_reg,
    output reg  [31:0] desc_param_addr_reg,
    output reg  [31:0] desc_scratch_addr_reg,
    output reg  [31:0] desc_input_words_reg,
    output reg  [31:0] desc_output_words_reg,
    output reg  [31:0] desc_flags_reg,

    output wire [31:0] input_fetch_word_count_reg,
    output wire [31:0] input_checksum_reg,
    output wire [31:0] input_last_word_reg,
    output wire [31:0] param_fetch_word_count_reg,
    output wire [31:0] param_checksum_reg,
    output wire [31:0] param_last_word_reg,

    output reg  [31:0] m_axi_araddr,
    output wire [1:0]  m_axi_arburst,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [3:0]  m_axi_arcache,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    output reg  [31:0] m_axi_awaddr,
    output wire [1:0]  m_axi_awburst,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [3:0]  m_axi_awcache,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready
);

    localparam [2:0]
        ST_IDLE = 3'd0,
        ST_AR   = 3'd1,
        ST_R    = 3'd2,
        ST_AW   = 3'd3,
        ST_W    = 3'd4,
        ST_B    = 3'd5,
        ST_DONE = 3'd6;

    localparam [1:0]
        PHASE_DESC   = 2'd0,
        PHASE_INPUT  = 2'd1,
        PHASE_PARAM  = 2'd2,
        PHASE_OUTPUT = 2'd3;

    reg [2:0]  state_reg;
    reg [1:0]  phase_reg;
    reg [31:0] desc_base_reg;
    reg [31:0] curr_addr_reg;
    reg [31:0] word_idx_reg;
    reg [31:0] phase_total_words_reg;
    reg [31:0] param_words_target_reg;
    reg        compute_clear_pulse;
    reg        compute_input_word_valid;
    reg        compute_param_word_valid;
    wire       compute_clear_req;
    wire [31:0] compute_output_word;

    assign m_axi_arburst = 2'b01;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = AXI_SIZE_WORD;
    assign m_axi_arcache = 4'b0011;

    assign m_axi_awburst = 2'b01;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = AXI_SIZE_WORD;
    assign m_axi_awcache = 4'b0011;

    assign compute_clear_req = soft_reset_pulse | compute_clear_pulse;

    tpu_mlp_compute_stub compute_stub_u (
        .clk(clk),
        .rst_n(rst_n),
        .clear_pulse(compute_clear_req),
        .net_id(desc_net_id_reg),
        .flags(desc_flags_reg),
        .input_word_valid(compute_input_word_valid),
        .input_word(m_axi_rdata),
        .param_word_valid(compute_param_word_valid),
        .param_word(m_axi_rdata),
        .output_word_index(word_idx_reg),
        .input_word_count(input_fetch_word_count_reg),
        .input_checksum(input_checksum_reg),
        .input_last_word(input_last_word_reg),
        .param_word_count(param_fetch_word_count_reg),
        .param_checksum(param_checksum_reg),
        .param_last_word(param_last_word_reg),
        .output_word(compute_output_word)
    );

    function [31:0] param_words_for_net;
        input [31:0] net_id;
        begin
            case(net_id)
                32'd0: param_words_for_net = NET0_PARAM_WORDS;
                32'd1: param_words_for_net = NET1_PARAM_WORDS;
                32'd2: param_words_for_net = NET2_PARAM_WORDS;
                32'd3: param_words_for_net = NET3_PARAM_WORDS;
                default: param_words_for_net = 32'd0;
            endcase
        end
    endfunction

    task clear_desc_regs;
        begin
            desc_net_id_reg       <= 32'd0;
            desc_input_addr_reg   <= 32'd0;
            desc_output_addr_reg  <= 32'd0;
            desc_param_addr_reg   <= 32'd0;
            desc_scratch_addr_reg <= 32'd0;
            desc_input_words_reg  <= 32'd0;
            desc_output_words_reg <= 32'd0;
            desc_flags_reg        <= 32'd0;
        end
    endtask

    task clear_fetch_regs;
        begin
            compute_clear_pulse <= 1'b1;
        end
    endtask

    task clear_axi_master_regs;
        begin
            m_axi_araddr  <= 32'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_awaddr  <= 32'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_wdata   <= 32'd0;
            m_axi_wstrb   <= 4'd0;
            m_axi_wlast   <= 1'b0;
            m_axi_wvalid  <= 1'b0;
        end
    endtask

    task start_read_phase;
        input [1:0]  phase;
        input [31:0] base_addr;
        input [31:0] total_words;
        begin
            phase_reg             <= phase;
            curr_addr_reg         <= base_addr;
            word_idx_reg          <= 32'd0;
            phase_total_words_reg <= total_words;
            m_axi_araddr          <= base_addr;
            m_axi_arvalid         <= 1'b1;
            m_axi_awvalid         <= 1'b0;
            m_axi_wvalid          <= 1'b0;
            m_axi_bready          <= 1'b0;
            state_reg             <= ST_AR;
        end
    endtask

    task start_output_phase;
        input [31:0] base_addr;
        input [31:0] total_words;
        begin
            phase_reg             <= PHASE_OUTPUT;
            curr_addr_reg         <= base_addr;
            word_idx_reg          <= 32'd0;
            phase_total_words_reg <= total_words;
            m_axi_awaddr          <= base_addr;
            m_axi_awvalid         <= 1'b1;
            m_axi_arvalid         <= 1'b0;
            m_axi_rready          <= 1'b0;
            m_axi_wvalid          <= 1'b0;
            m_axi_bready          <= 1'b0;
            state_reg             <= ST_AW;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_reg              <= ST_IDLE;
            phase_reg              <= PHASE_DESC;
            desc_base_reg          <= 32'd0;
            curr_addr_reg          <= 32'd0;
            word_idx_reg           <= 32'd0;
            phase_total_words_reg  <= 32'd0;
            param_words_target_reg <= 32'd0;
            compute_clear_pulse     <= 1'b0;
            compute_input_word_valid <= 1'b0;
            compute_param_word_valid <= 1'b0;
            status_busy            <= 1'b0;
            status_done            <= 1'b0;
            status_error           <= 1'b0;
            clear_desc_regs();
            clear_fetch_regs();
            clear_axi_master_regs();
        end else if(soft_reset_pulse) begin
            state_reg              <= ST_IDLE;
            phase_reg              <= PHASE_DESC;
            desc_base_reg          <= 32'd0;
            curr_addr_reg          <= 32'd0;
            word_idx_reg           <= 32'd0;
            phase_total_words_reg  <= 32'd0;
            param_words_target_reg <= 32'd0;
            compute_clear_pulse     <= 1'b0;
            compute_input_word_valid <= 1'b0;
            compute_param_word_valid <= 1'b0;
            status_busy            <= 1'b0;
            status_done            <= 1'b0;
            status_error           <= 1'b0;
            clear_desc_regs();
            clear_fetch_regs();
            clear_axi_master_regs();
        end else begin
            compute_clear_pulse      <= 1'b0;
            compute_input_word_valid <= 1'b0;
            compute_param_word_valid <= 1'b0;

            case(state_reg)
                ST_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    status_busy   <= 1'b0;

                    if(launch_pulse) begin
                        clear_desc_regs();
                        clear_fetch_regs();
                        desc_base_reg          <= desc_base_addr;
                        param_words_target_reg <= 32'd0;
                        compute_clear_pulse     <= 1'b1;
                        status_done            <= 1'b0;
                        status_error           <= 1'b0;
                        if(desc_base_addr == 32'd0) begin
                            status_error <= 1'b1;
                        end else begin
                            status_busy <= 1'b1;
                            start_read_phase(PHASE_DESC, desc_base_addr, 32'd8);
                        end
                    end
                end

                ST_AR: begin
                    if(m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state_reg     <= ST_R;
                    end
                end

                ST_R: begin
                    if(m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;

                        if(m_axi_rresp != 2'b00) begin
                            status_busy  <= 1'b0;
                            status_done  <= 1'b0;
                            status_error <= 1'b1;
                            state_reg    <= ST_IDLE;
                        end else begin
                            case(phase_reg)
                                PHASE_DESC: begin
                                    case(word_idx_reg)
                                        32'd0: desc_net_id_reg       <= m_axi_rdata;
                                        32'd1: desc_input_addr_reg   <= m_axi_rdata;
                                        32'd2: desc_output_addr_reg  <= m_axi_rdata;
                                        32'd3: desc_param_addr_reg   <= m_axi_rdata;
                                        32'd4: desc_scratch_addr_reg <= m_axi_rdata;
                                        32'd5: desc_input_words_reg  <= m_axi_rdata;
                                        32'd6: desc_output_words_reg <= m_axi_rdata;
                                        32'd7: desc_flags_reg        <= m_axi_rdata;
                                        default: begin end
                                    endcase

                                    if(word_idx_reg + 32'd1 >= phase_total_words_reg) begin
                                        param_words_target_reg <= param_words_for_net(desc_net_id_reg);
                                        if(desc_input_words_reg != 32'd0) begin
                                            start_read_phase(PHASE_INPUT, desc_input_addr_reg, desc_input_words_reg);
                                        end else if(param_words_for_net(desc_net_id_reg) != 32'd0) begin
                                            start_read_phase(PHASE_PARAM, desc_param_addr_reg, param_words_for_net(desc_net_id_reg));
                                        end else if(desc_output_words_reg != 32'd0) begin
                                            start_output_phase(desc_output_addr_reg, desc_output_words_reg);
                                        end else begin
                                            status_busy <= 1'b0;
                                            status_done <= 1'b1;
                                            state_reg   <= ST_DONE;
                                        end
                                    end else begin
                                        word_idx_reg  <= word_idx_reg + 32'd1;
                                        curr_addr_reg <= curr_addr_reg + 32'd4;
                                        m_axi_araddr  <= curr_addr_reg + 32'd4;
                                        m_axi_arvalid <= 1'b1;
                                        state_reg     <= ST_AR;
                                    end
                                end

                                PHASE_INPUT: begin
                                    compute_input_word_valid <= 1'b1;

                                    if(word_idx_reg + 32'd1 >= phase_total_words_reg) begin
                                        if(param_words_target_reg != 32'd0) begin
                                            start_read_phase(PHASE_PARAM, desc_param_addr_reg, param_words_target_reg);
                                        end else if(desc_output_words_reg != 32'd0) begin
                                            start_output_phase(desc_output_addr_reg, desc_output_words_reg);
                                        end else begin
                                            status_busy <= 1'b0;
                                            status_done <= 1'b1;
                                            state_reg   <= ST_DONE;
                                        end
                                    end else begin
                                        word_idx_reg  <= word_idx_reg + 32'd1;
                                        curr_addr_reg <= curr_addr_reg + 32'd4;
                                        m_axi_araddr  <= curr_addr_reg + 32'd4;
                                        m_axi_arvalid <= 1'b1;
                                        state_reg     <= ST_AR;
                                    end
                                end

                                PHASE_PARAM: begin
                                    compute_param_word_valid <= 1'b1;

                                    if(word_idx_reg + 32'd1 >= phase_total_words_reg) begin
                                        if(desc_output_words_reg != 32'd0) begin
                                            start_output_phase(desc_output_addr_reg, desc_output_words_reg);
                                        end else begin
                                            status_busy <= 1'b0;
                                            status_done <= 1'b1;
                                            state_reg   <= ST_DONE;
                                        end
                                    end else begin
                                        word_idx_reg  <= word_idx_reg + 32'd1;
                                        curr_addr_reg <= curr_addr_reg + 32'd4;
                                        m_axi_araddr  <= curr_addr_reg + 32'd4;
                                        m_axi_arvalid <= 1'b1;
                                        state_reg     <= ST_AR;
                                    end
                                end

                                default: begin
                                    status_busy  <= 1'b0;
                                    status_done  <= 1'b0;
                                    status_error <= 1'b1;
                                    state_reg    <= ST_IDLE;
                                end
                            endcase
                        end
                    end
                end

                ST_AW: begin
                    if(m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata   <= compute_output_word;
                        m_axi_wstrb   <= 4'hF;
                        m_axi_wlast   <= 1'b1;
                        m_axi_wvalid  <= 1'b1;
                        state_reg     <= ST_W;
                    end
                end

                ST_W: begin
                    if(m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state_reg    <= ST_B;
                    end
                end

                ST_B: begin
                    if(m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        if(m_axi_bresp != 2'b00) begin
                            status_busy  <= 1'b0;
                            status_done  <= 1'b0;
                            status_error <= 1'b1;
                            state_reg    <= ST_IDLE;
                        end else if(word_idx_reg + 32'd1 >= phase_total_words_reg) begin
                            status_busy <= 1'b0;
                            status_done <= 1'b1;
                            state_reg   <= ST_DONE;
                        end else begin
                            word_idx_reg  <= word_idx_reg + 32'd1;
                            curr_addr_reg <= curr_addr_reg + 32'd4;
                            m_axi_awaddr  <= curr_addr_reg + 32'd4;
                            m_axi_awvalid <= 1'b1;
                            state_reg     <= ST_AW;
                        end
                    end
                end

                ST_DONE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    if(launch_pulse) begin
                        clear_desc_regs();
                        clear_fetch_regs();
                        desc_base_reg          <= desc_base_addr;
                        param_words_target_reg <= 32'd0;
                        compute_clear_pulse     <= 1'b1;
                        status_done            <= 1'b0;
                        status_error           <= 1'b0;
                        if(desc_base_addr == 32'd0) begin
                            status_busy  <= 1'b0;
                            status_done  <= 1'b0;
                            status_error <= 1'b1;
                            state_reg    <= ST_IDLE;
                        end else begin
                            status_busy <= 1'b1;
                            start_read_phase(PHASE_DESC, desc_base_addr, 32'd8);
                        end
                    end
                end

                default: begin
                    state_reg <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
