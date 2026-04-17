`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
TPU MLP compute block
@brief  Replaceable streaming compute block used by the stage2 DMA prototype.
        The DMA owns AXI/descriptor movement.  This block owns input/param
        ingestion and output-word generation.  flags[16] enables the packed
        Q8.8 linear tile mode; the default path remains a checksum-compatible
        placeholder for existing SoC boot tests.
@date   2026/04/17
************************************************************************************************************************/
module tpu_mlp_compute_stub #(
    parameter integer INPUT_MEM_WORDS = 256,
    parameter integer PARAM_MEM_WORDS = 2048
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear_pulse,

    input  wire [31:0] net_id,
    input  wire [31:0] flags,
    input  wire [31:0] input_words,

    input  wire        input_word_valid,
    input  wire [31:0] input_word,
    input  wire        param_word_valid,
    input  wire [31:0] param_word,

    input  wire [31:0] output_word_index,

    output reg  [31:0] input_word_count,
    output reg  [31:0] input_checksum,
    output reg  [31:0] input_last_word,
    output reg  [31:0] param_word_count,
    output reg  [31:0] param_checksum,
    output reg  [31:0] param_last_word,
    output reg  [31:0] output_word
);

    localparam integer TPU_DESC_F_RELU_BIT          = 0;
    localparam integer TPU_DESC_F_TILE2X2_Q8_8_BIT = 16;

    reg [31:0] input_mem [0:INPUT_MEM_WORDS-1];
    reg [31:0] param_mem [0:PARAM_MEM_WORDS-1];

    integer input_mem_idx;
    integer param_mem_idx;
    integer linear_input_idx;

    reg [31:0] linear_stride_words;
    reg [31:0] linear_param_base;
    reg [31:0] linear_param_word0;
    reg [31:0] linear_param_word1;
    reg [31:0] linear_bias_word;
    reg signed [31:0] linear_acc0;
    reg signed [31:0] linear_acc1;
    reg signed [15:0] linear_x0;
    reg signed [15:0] linear_x1;
    reg signed [15:0] linear_w00;
    reg signed [15:0] linear_w01;
    reg signed [15:0] linear_w10;
    reg signed [15:0] linear_w11;
    reg signed [15:0] linear_b0;
    reg signed [15:0] linear_b1;
    reg signed [15:0] linear_y0;
    reg signed [15:0] linear_y1;
    reg [31:0]        linear_output_word;

    function signed [31:0] q8_8_mul_to_32;
        input signed [15:0] a;
        input signed [15:0] b;
        reg signed [31:0] product;
        begin
            product = a * b;
            q8_8_mul_to_32 = product >>> 8;
        end
    endfunction

    function signed [15:0] q8_8_saturate;
        input signed [31:0] value;
        begin
            if(value > 32'sd32767) begin
                q8_8_saturate = 16'sh7fff;
            end else if(value < -32'sd32768) begin
                q8_8_saturate = 16'sh8000;
            end else begin
                q8_8_saturate = value[15:0];
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            input_word_count <= 32'd0;
            input_checksum   <= 32'd0;
            input_last_word  <= 32'd0;
            param_word_count <= 32'd0;
            param_checksum   <= 32'd0;
            param_last_word  <= 32'd0;
            for(input_mem_idx = 0; input_mem_idx < INPUT_MEM_WORDS; input_mem_idx = input_mem_idx + 1) begin
                input_mem[input_mem_idx] <= 32'd0;
            end
            for(param_mem_idx = 0; param_mem_idx < PARAM_MEM_WORDS; param_mem_idx = param_mem_idx + 1) begin
                param_mem[param_mem_idx] <= 32'd0;
            end
        end else if(clear_pulse) begin
            input_word_count <= 32'd0;
            input_checksum   <= 32'd0;
            input_last_word  <= 32'd0;
            param_word_count <= 32'd0;
            param_checksum   <= 32'd0;
            param_last_word  <= 32'd0;
            for(input_mem_idx = 0; input_mem_idx < INPUT_MEM_WORDS; input_mem_idx = input_mem_idx + 1) begin
                input_mem[input_mem_idx] <= 32'd0;
            end
            for(param_mem_idx = 0; param_mem_idx < PARAM_MEM_WORDS; param_mem_idx = param_mem_idx + 1) begin
                param_mem[param_mem_idx] <= 32'd0;
            end
        end else begin
            if(input_word_valid) begin
                input_word_count <= input_word_count + 32'd1;
                input_checksum   <= input_checksum + input_word;
                input_last_word  <= input_word;
                if(input_word_count < INPUT_MEM_WORDS) begin
                    input_mem[input_word_count] <= input_word;
                end
            end

            if(param_word_valid) begin
                param_word_count <= param_word_count + 32'd1;
                param_checksum   <= param_checksum + param_word;
                param_last_word  <= param_word;
                if(param_word_count < PARAM_MEM_WORDS) begin
                    param_mem[param_word_count] <= param_word;
                end
            end
        end
    end

    always @(*) begin
        linear_stride_words = (input_words << 1) + 32'd1;
        linear_param_base   = output_word_index * linear_stride_words;
        linear_acc0         = 32'sd0;
        linear_acc1         = 32'sd0;
        linear_bias_word    = 32'd0;

        for(linear_input_idx = 0; linear_input_idx < INPUT_MEM_WORDS; linear_input_idx = linear_input_idx + 1) begin
            if((linear_input_idx < input_words) &&
               ((linear_param_base + (linear_input_idx << 1) + 32'd1) < PARAM_MEM_WORDS)) begin
                linear_param_word0 = param_mem[linear_param_base + (linear_input_idx << 1)];
                linear_param_word1 = param_mem[linear_param_base + (linear_input_idx << 1) + 32'd1];
                linear_x0          = input_mem[linear_input_idx][15:0];
                linear_x1          = input_mem[linear_input_idx][31:16];
                linear_w00         = linear_param_word0[15:0];
                linear_w01         = linear_param_word0[31:16];
                linear_w10         = linear_param_word1[15:0];
                linear_w11         = linear_param_word1[31:16];
                linear_acc0        = linear_acc0 +
                                     q8_8_mul_to_32(linear_x0, linear_w00) +
                                     q8_8_mul_to_32(linear_x1, linear_w01);
                linear_acc1        = linear_acc1 +
                                     q8_8_mul_to_32(linear_x0, linear_w10) +
                                     q8_8_mul_to_32(linear_x1, linear_w11);
            end
        end

        if((linear_param_base + (input_words << 1)) < PARAM_MEM_WORDS) begin
            linear_bias_word = param_mem[linear_param_base + (input_words << 1)];
        end

        linear_b0  = linear_bias_word[15:0];
        linear_b1  = linear_bias_word[31:16];
        linear_acc0 = linear_acc0 + {{16{linear_b0[15]}}, linear_b0};
        linear_acc1 = linear_acc1 + {{16{linear_b1[15]}}, linear_b1};

        if(flags[TPU_DESC_F_RELU_BIT] && (linear_acc0 < 32'sd0)) begin
            linear_y0 = 16'sd0;
        end else begin
            linear_y0 = q8_8_saturate(linear_acc0);
        end

        if(flags[TPU_DESC_F_RELU_BIT] && (linear_acc1 < 32'sd0)) begin
            linear_y1 = 16'sd0;
        end else begin
            linear_y1 = q8_8_saturate(linear_acc1);
        end

        linear_output_word = {linear_y1, linear_y0};

        case(net_id)
            32'd0, 32'd1, 32'd2: begin
                if(flags[TPU_DESC_F_TILE2X2_Q8_8_BIT]) begin
                    output_word = linear_output_word;
                end else begin
                    output_word = input_checksum + param_checksum + net_id + flags + output_word_index;
                end
            end
            default: begin
                output_word = 32'hBAD0_0000 | output_word_index;
            end
        endcase
    end

endmodule
`default_nettype wire
