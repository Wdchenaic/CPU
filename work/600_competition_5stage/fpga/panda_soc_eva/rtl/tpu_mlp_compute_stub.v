`timescale 1ns / 1ps
`default_nettype none

/************************************************************************************************************************
TPU MLP compute block
@brief  Replaceable streaming compute block used by the stage2 DMA prototype.
        The DMA owns AXI/descriptor movement.  This block owns input/param
        ingestion and output-word generation.  flags[16] enables the current
        2x2 Q8.8 MAC tile mode; the default path remains a checksum-compatible
        placeholder for existing SoC boot tests.
@date   2026/04/17
************************************************************************************************************************/
module tpu_mlp_compute_stub (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear_pulse,

    input  wire [31:0] net_id,
    input  wire [31:0] flags,

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

    reg signed [15:0] tile_x0_reg;
    reg signed [15:0] tile_x1_reg;
    reg signed [15:0] tile_w00_reg;
    reg signed [15:0] tile_w01_reg;
    reg signed [15:0] tile_w10_reg;
    reg signed [15:0] tile_w11_reg;
    reg signed [15:0] tile_b0_reg;
    reg signed [15:0] tile_b1_reg;

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

    wire signed [31:0] tile_acc0;
    wire signed [31:0] tile_acc1;
    wire signed [15:0] tile_y0;
    wire signed [15:0] tile_y1;
    wire [31:0]        tile_output_word0;

    assign tile_acc0 = q8_8_mul_to_32(tile_x0_reg, tile_w00_reg) +
                       q8_8_mul_to_32(tile_x1_reg, tile_w01_reg) +
                       {{16{tile_b0_reg[15]}}, tile_b0_reg};
    assign tile_acc1 = q8_8_mul_to_32(tile_x0_reg, tile_w10_reg) +
                       q8_8_mul_to_32(tile_x1_reg, tile_w11_reg) +
                       {{16{tile_b1_reg[15]}}, tile_b1_reg};
    assign tile_y0 = q8_8_saturate(tile_acc0);
    assign tile_y1 = q8_8_saturate(tile_acc1);
    assign tile_output_word0 = {tile_y1, tile_y0};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            input_word_count <= 32'd0;
            input_checksum   <= 32'd0;
            input_last_word  <= 32'd0;
            param_word_count <= 32'd0;
            param_checksum   <= 32'd0;
            param_last_word  <= 32'd0;
            tile_x0_reg      <= 16'sd0;
            tile_x1_reg      <= 16'sd0;
            tile_w00_reg     <= 16'sd0;
            tile_w01_reg     <= 16'sd0;
            tile_w10_reg     <= 16'sd0;
            tile_w11_reg     <= 16'sd0;
            tile_b0_reg      <= 16'sd0;
            tile_b1_reg      <= 16'sd0;
        end else if(clear_pulse) begin
            input_word_count <= 32'd0;
            input_checksum   <= 32'd0;
            input_last_word  <= 32'd0;
            param_word_count <= 32'd0;
            param_checksum   <= 32'd0;
            param_last_word  <= 32'd0;
            tile_x0_reg      <= 16'sd0;
            tile_x1_reg      <= 16'sd0;
            tile_w00_reg     <= 16'sd0;
            tile_w01_reg     <= 16'sd0;
            tile_w10_reg     <= 16'sd0;
            tile_w11_reg     <= 16'sd0;
            tile_b0_reg      <= 16'sd0;
            tile_b1_reg      <= 16'sd0;
        end else begin
            if(input_word_valid) begin
                input_word_count <= input_word_count + 32'd1;
                input_checksum   <= input_checksum + input_word;
                input_last_word  <= input_word;
                if(input_word_count == 32'd0) begin
                    tile_x0_reg <= input_word[15:0];
                    tile_x1_reg <= input_word[31:16];
                end
            end

            if(param_word_valid) begin
                param_word_count <= param_word_count + 32'd1;
                param_checksum   <= param_checksum + param_word;
                param_last_word  <= param_word;
                case(param_word_count)
                    32'd0: begin
                        tile_w00_reg <= param_word[15:0];
                        tile_w01_reg <= param_word[31:16];
                    end
                    32'd1: begin
                        tile_w10_reg <= param_word[15:0];
                        tile_w11_reg <= param_word[31:16];
                    end
                    32'd2: begin
                        tile_b0_reg <= param_word[15:0];
                        tile_b1_reg <= param_word[31:16];
                    end
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        case(net_id)
            32'd0, 32'd1, 32'd2: begin
                if(flags[16]) begin
                    output_word = (output_word_index == 32'd0) ? tile_output_word0 : 32'd0;
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
