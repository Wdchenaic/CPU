`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_ctrl_dma_integration;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] TPU_BASE_ADDR    = 32'h4000_4000;
    localparam [31:0] DESC_BASE_ADDR   = 32'h6001_0000;
    localparam [31:0] INPUT_BASE_ADDR  = 32'h6001_0100;
    localparam [31:0] OUTPUT_BASE_ADDR = 32'h6001_0400;
    localparam [31:0] PARAM_BASE_ADDR  = 32'h6000_4000;

    reg clk;
    reg rst_n;

    reg  [31:0] s_axil_awaddr;
    reg  [2:0]  s_axil_awprot;
    reg         s_axil_awvalid;
    wire        s_axil_awready;
    reg  [31:0] s_axil_wdata;
    reg  [3:0]  s_axil_wstrb;
    reg         s_axil_wvalid;
    wire        s_axil_wready;
    wire [1:0]  s_axil_bresp;
    wire        s_axil_bvalid;
    reg         s_axil_bready;
    reg  [31:0] s_axil_araddr;
    reg  [2:0]  s_axil_arprot;
    reg         s_axil_arvalid;
    wire        s_axil_arready;
    wire [31:0] s_axil_rdata;
    wire [1:0]  s_axil_rresp;
    wire        s_axil_rvalid;
    reg         s_axil_rready;

    wire        launch_pulse;
    wire        soft_reset_pulse;
    wire [31:0] mode_reg;
    wire [31:0] net_id_reg;
    wire [31:0] desc_lo_reg;
    wire [31:0] desc_hi_reg;
    wire        irq_en_reg;
    wire [31:0] perf_cycle_reg;
    wire        status_busy;
    wire        status_done;
    wire        status_error;

    wire [31:0] dma_axi_araddr;
    wire [1:0]  dma_axi_arburst;
    wire [7:0]  dma_axi_arlen;
    wire [2:0]  dma_axi_arsize;
    wire [3:0]  dma_axi_arcache;
    wire        dma_axi_arvalid;
    wire        dma_axi_arready;
    wire [31:0] dma_axi_awaddr;
    wire [1:0]  dma_axi_awburst;
    wire [7:0]  dma_axi_awlen;
    wire [2:0]  dma_axi_awsize;
    wire [3:0]  dma_axi_awcache;
    wire        dma_axi_awvalid;
    wire        dma_axi_awready;
    wire [1:0]  dma_axi_bresp;
    wire        dma_axi_bvalid;
    wire        dma_axi_bready;
    wire [31:0] dma_axi_rdata;
    wire [1:0]  dma_axi_rresp;
    wire        dma_axi_rlast;
    wire        dma_axi_rvalid;
    wire        dma_axi_rready;
    wire [31:0] dma_axi_wdata;
    wire [3:0]  dma_axi_wstrb;
    wire        dma_axi_wlast;
    wire        dma_axi_wvalid;
    wire        dma_axi_wready;

    reg [31:0] read_data_reg;
    reg [31:0] expected_output_word;
    integer wait_cycles;
    integer poll_count;
    integer output_index;

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(5) @(posedge clk);
            $finish;
        end
    endtask

    task axil_idle;
        begin
            s_axil_awaddr  = 32'd0;
            s_axil_awprot  = 3'd0;
            s_axil_awvalid = 1'b0;
            s_axil_wdata   = 32'd0;
            s_axil_wstrb   = 4'd0;
            s_axil_wvalid  = 1'b0;
            s_axil_bready  = 1'b0;
            s_axil_araddr  = 32'd0;
            s_axil_arprot  = 3'd0;
            s_axil_arvalid = 1'b0;
            s_axil_rready  = 1'b0;
        end
    endtask

    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awprot  <= 3'b000;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                if(s_axil_awready && s_axil_wready) begin
                    wait_cycles = 256;
                end
            end
            if(!(s_axil_awready && s_axil_wready)) begin
                tb_fail("AXI-Lite write handshake timeout");
            end

            s_axil_awvalid <= 1'b0;
            s_axil_wvalid  <= 1'b0;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                if(s_axil_bvalid) begin
                    wait_cycles = 256;
                end
            end
            if(!s_axil_bvalid) begin
                tb_fail("AXI-Lite write response timeout");
            end
            if(s_axil_bresp != 2'b00) begin
                tb_fail("AXI-Lite write response error");
            end

            @(posedge clk);
            s_axil_bready <= 1'b0;
        end
    endtask

    task axil_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arprot  <= 3'b000;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                if(s_axil_arready) begin
                    wait_cycles = 256;
                end
            end
            if(!s_axil_arready) begin
                tb_fail("AXI-Lite read address timeout");
            end

            s_axil_arvalid <= 1'b0;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                if(s_axil_rvalid) begin
                    wait_cycles = 256;
                end
            end
            if(!s_axil_rvalid) begin
                tb_fail("AXI-Lite read data timeout");
            end
            if(s_axil_rresp != 2'b00) begin
                tb_fail("AXI-Lite read response error");
            end

            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 1'b0;
        end
    endtask

    tpu_ctrl_axil_regs #(
        .TPU_BASE_ADDR(TPU_BASE_ADDR)
    ) tpu_ctrl_axil_regs_u (
        .clk(clk),
        .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_awprot(s_axil_awprot),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr),
        .s_axil_arprot(s_axil_arprot),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error),
        .launch_pulse(launch_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .mode_reg(mode_reg),
        .net_id_reg(net_id_reg),
        .desc_lo_reg(desc_lo_reg),
        .desc_hi_reg(desc_hi_reg),
        .irq_en_reg(irq_en_reg),
        .perf_cycle_reg(perf_cycle_reg)
    );

    tpu_desc_fetch_dma_stub tpu_desc_fetch_dma_stub_u (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(launch_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .desc_base_addr(desc_lo_reg),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error),
        .desc_net_id_reg(),
        .desc_input_addr_reg(),
        .desc_output_addr_reg(),
        .desc_param_addr_reg(),
        .desc_scratch_addr_reg(),
        .desc_input_words_reg(),
        .desc_output_words_reg(),
        .desc_flags_reg(),
        .input_fetch_word_count_reg(),
        .input_checksum_reg(),
        .input_last_word_reg(),
        .param_fetch_word_count_reg(),
        .param_checksum_reg(),
        .param_last_word_reg(),
        .m_axi_araddr(dma_axi_araddr),
        .m_axi_arburst(dma_axi_arburst),
        .m_axi_arlen(dma_axi_arlen),
        .m_axi_arsize(dma_axi_arsize),
        .m_axi_arcache(dma_axi_arcache),
        .m_axi_arvalid(dma_axi_arvalid),
        .m_axi_arready(dma_axi_arready),
        .m_axi_awaddr(dma_axi_awaddr),
        .m_axi_awburst(dma_axi_awburst),
        .m_axi_awlen(dma_axi_awlen),
        .m_axi_awsize(dma_axi_awsize),
        .m_axi_awcache(dma_axi_awcache),
        .m_axi_awvalid(dma_axi_awvalid),
        .m_axi_awready(dma_axi_awready),
        .m_axi_bresp(dma_axi_bresp),
        .m_axi_bvalid(dma_axi_bvalid),
        .m_axi_bready(dma_axi_bready),
        .m_axi_rdata(dma_axi_rdata),
        .m_axi_rresp(dma_axi_rresp),
        .m_axi_rlast(dma_axi_rlast),
        .m_axi_rvalid(dma_axi_rvalid),
        .m_axi_rready(dma_axi_rready),
        .m_axi_wdata(dma_axi_wdata),
        .m_axi_wstrb(dma_axi_wstrb),
        .m_axi_wlast(dma_axi_wlast),
        .m_axi_wvalid(dma_axi_wvalid),
        .m_axi_wready(dma_axi_wready)
    );

    panda_soc_shared_mem_subsys panda_soc_shared_mem_subsys_u (
        .clk(clk),
        .rst(~rst_n),
        .cpu_axi_araddr(32'd0),
        .cpu_axi_arburst(2'd0),
        .cpu_axi_arlen(8'd0),
        .cpu_axi_arsize(3'd0),
        .cpu_axi_arcache(4'd0),
        .cpu_axi_arvalid(1'b0),
        .cpu_axi_arready(),
        .cpu_axi_awaddr(32'd0),
        .cpu_axi_awburst(2'd0),
        .cpu_axi_awlen(8'd0),
        .cpu_axi_awsize(3'd0),
        .cpu_axi_awcache(4'd0),
        .cpu_axi_awvalid(1'b0),
        .cpu_axi_awready(),
        .cpu_axi_bresp(),
        .cpu_axi_bvalid(),
        .cpu_axi_bready(1'b0),
        .cpu_axi_rdata(),
        .cpu_axi_rresp(),
        .cpu_axi_rlast(),
        .cpu_axi_rvalid(),
        .cpu_axi_rready(1'b0),
        .cpu_axi_wdata(32'd0),
        .cpu_axi_wstrb(4'd0),
        .cpu_axi_wlast(1'b0),
        .cpu_axi_wvalid(1'b0),
        .cpu_axi_wready(),
        .tpu_axi_araddr(dma_axi_araddr),
        .tpu_axi_arburst(dma_axi_arburst),
        .tpu_axi_arlen(dma_axi_arlen),
        .tpu_axi_arsize(dma_axi_arsize),
        .tpu_axi_arcache(dma_axi_arcache),
        .tpu_axi_arvalid(dma_axi_arvalid),
        .tpu_axi_arready(dma_axi_arready),
        .tpu_axi_awaddr(dma_axi_awaddr),
        .tpu_axi_awburst(dma_axi_awburst),
        .tpu_axi_awlen(dma_axi_awlen),
        .tpu_axi_awsize(dma_axi_awsize),
        .tpu_axi_awcache(dma_axi_awcache),
        .tpu_axi_awvalid(dma_axi_awvalid),
        .tpu_axi_awready(dma_axi_awready),
        .tpu_axi_bresp(dma_axi_bresp),
        .tpu_axi_bvalid(dma_axi_bvalid),
        .tpu_axi_bready(dma_axi_bready),
        .tpu_axi_rdata(dma_axi_rdata),
        .tpu_axi_rresp(dma_axi_rresp),
        .tpu_axi_rlast(dma_axi_rlast),
        .tpu_axi_rvalid(dma_axi_rvalid),
        .tpu_axi_rready(dma_axi_rready),
        .tpu_axi_wdata(dma_axi_wdata),
        .tpu_axi_wstrb(dma_axi_wstrb),
        .tpu_axi_wlast(dma_axi_wlast),
        .tpu_axi_wvalid(dma_axi_wvalid),
        .tpu_axi_wready(dma_axi_wready)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(2_000_000);
        tb_fail("global timeout waiting for TPU_CTRL+DMA integration test");
    end

    initial begin
        rst_n = 1'b0;
        read_data_reg = 32'd0;
        expected_output_word = 32'd0;
        axil_idle();

        repeat(8) @(posedge clk);
        rst_n = 1'b1;
        repeat(6) @(posedge clk);

        $display("[TB] preload shared SRAM for integrated TPU_CTRL+DMA test");
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 0] = 32'h0000_0002;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 1] = INPUT_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 2] = OUTPUT_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 3] = PARAM_BASE_ADDR;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 4] = 32'h6001_0800;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 5] = 32'd4;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 6] = 32'd4;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 7] = 32'h0000_0005;

        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'd17;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'd34;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 2] = 32'd51;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 3] = 32'd68;

        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'd1;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'd2;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 2] = 32'd3;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 3] = 32'd4;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 4] = 32'd5;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 5] = 32'd6;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 6] = 32'd7;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 7] = 32'd8;

        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] = 32'hDEAD_BEEF;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] = 32'hDEAD_BEEF;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 2] = 32'hDEAD_BEEF;
        panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 3] = 32'hDEAD_BEEF;

        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if(read_data_reg !== 32'd0) begin
            tb_fail("initial STATUS expected 0");
        end

        axil_write(TPU_BASE_ADDR + 32'h08, 32'h0000_0000);
        axil_write(TPU_BASE_ADDR + 32'h0C, 32'h0000_0002);
        axil_write(TPU_BASE_ADDR + 32'h10, DESC_BASE_ADDR);
        axil_write(TPU_BASE_ADDR + 32'h14, 32'h0000_0000);

        axil_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0001);
        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if((read_data_reg & 32'h1) == 0) begin
            tb_fail("STATUS.busy not asserted after start");
        end
        $display("[TB] integrated TPU_CTRL busy asserted after start");

        poll_count = 0;
        while((read_data_reg & 32'h2) == 0) begin
            axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
            poll_count = poll_count + 1;
            if(read_data_reg[2]) begin
                tb_fail("STATUS.error asserted unexpectedly");
            end
            if(poll_count > 128) begin
                tb_fail("timeout waiting for integrated STATUS.done");
            end
        end
        if(read_data_reg[0]) begin
            tb_fail("STATUS.done and busy both set");
        end
        $display("[TB] integrated TPU_CTRL done observed after %0d polls", poll_count);

        axil_read(TPU_BASE_ADDR + 32'h18, read_data_reg);
        if(read_data_reg == 32'd0) begin
            tb_fail("PERF_CYCLE did not increment in integrated test");
        end

        for(output_index = 0; output_index < 4; output_index = output_index + 1) begin
            expected_output_word = 32'd213 + output_index;
            if(panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + output_index] !== expected_output_word) begin
                tb_fail("integrated output blob mismatch");
            end
        end

        axil_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0002);
        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if(read_data_reg !== 32'd0) begin
            tb_fail("STATUS not cleared after soft reset");
        end

        axil_write(TPU_BASE_ADDR + 32'h10, 32'd0);
        axil_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0001);
        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if((read_data_reg & 32'h4) == 0) begin
            tb_fail("zero desc launch did not assert error");
        end

        $display("[TB][PASS] TPU_CTRL + DMA stub + shared SRAM integration test passed");
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
