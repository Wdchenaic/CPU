`timescale 1ns / 1ps
`default_nettype none

module tb_panda_soc_stage2_smoke;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] TPU_BASE_ADDR    = 32'h4000_4000;
    localparam [31:0] DESC_BASE_ADDR   = 32'h6001_0000;
    localparam [31:0] INPUT_BASE_ADDR  = 32'h6001_0100;
    localparam [31:0] OUTPUT_BASE_ADDR = 32'h6001_0400;
    localparam [31:0] PARAM_BASE_ADDR  = 32'h6000_4000;

    reg clk;
    reg ext_resetn;
    reg uart0_rx;
    wire uart0_tx;

    reg  [31:0] sim_tpu_ctrl_axil_awaddr;
    reg  [2:0]  sim_tpu_ctrl_axil_awprot;
    reg         sim_tpu_ctrl_axil_awvalid;
    wire        sim_tpu_ctrl_axil_awready;
    reg  [31:0] sim_tpu_ctrl_axil_wdata;
    reg  [3:0]  sim_tpu_ctrl_axil_wstrb;
    reg         sim_tpu_ctrl_axil_wvalid;
    wire        sim_tpu_ctrl_axil_wready;
    wire [1:0]  sim_tpu_ctrl_axil_bresp;
    wire        sim_tpu_ctrl_axil_bvalid;
    reg         sim_tpu_ctrl_axil_bready;
    reg  [31:0] sim_tpu_ctrl_axil_araddr;
    reg  [2:0]  sim_tpu_ctrl_axil_arprot;
    reg         sim_tpu_ctrl_axil_arvalid;
    wire        sim_tpu_ctrl_axil_arready;
    wire [31:0] sim_tpu_ctrl_axil_rdata;
    wire [1:0]  sim_tpu_ctrl_axil_rresp;
    wire        sim_tpu_ctrl_axil_rvalid;
    reg         sim_tpu_ctrl_axil_rready;

    wire        tpu_launch_pulse;
    wire        tpu_soft_reset_pulse;
    wire [31:0] tpu_mode_reg;
    wire [31:0] tpu_net_id_reg;
    wire [31:0] tpu_desc_lo_reg;
    wire [31:0] tpu_desc_hi_reg;
    wire        tpu_irq_en_reg;
    wire [31:0] tpu_perf_cycle_reg;

    reg [31:0] read_data_reg;
    integer poll_count;
    integer output_index;
    integer wait_cycles;
    reg [31:0] expected_output_word;

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
            sim_tpu_ctrl_axil_awaddr  = 32'd0;
            sim_tpu_ctrl_axil_awprot  = 3'd0;
            sim_tpu_ctrl_axil_awvalid = 1'b0;
            sim_tpu_ctrl_axil_wdata   = 32'd0;
            sim_tpu_ctrl_axil_wstrb   = 4'd0;
            sim_tpu_ctrl_axil_wvalid  = 1'b0;
            sim_tpu_ctrl_axil_bready  = 1'b0;
            sim_tpu_ctrl_axil_araddr  = 32'd0;
            sim_tpu_ctrl_axil_arprot  = 3'd0;
            sim_tpu_ctrl_axil_arvalid = 1'b0;
            sim_tpu_ctrl_axil_rready  = 1'b0;
        end
    endtask

    task mmio_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            sim_tpu_ctrl_axil_awaddr  = addr;
            sim_tpu_ctrl_axil_awprot  = 3'b000;
            sim_tpu_ctrl_axil_awvalid = 1'b1;
            sim_tpu_ctrl_axil_wdata   = data;
            sim_tpu_ctrl_axil_wstrb   = 4'hF;
            sim_tpu_ctrl_axil_wvalid  = 1'b1;
            sim_tpu_ctrl_axil_bready  = 1'b1;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                #1;
                if(sim_tpu_ctrl_axil_awready && sim_tpu_ctrl_axil_wready) begin
                    wait_cycles = 256;
                end
            end
            if(!(sim_tpu_ctrl_axil_awready && sim_tpu_ctrl_axil_wready)) begin
                tb_fail("TPU_CTRL write handshake timeout");
            end

            sim_tpu_ctrl_axil_awvalid = 1'b0;
            sim_tpu_ctrl_axil_wvalid  = 1'b0;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                #1;
                if(sim_tpu_ctrl_axil_bvalid) begin
                    wait_cycles = 256;
                end
            end
            if(!sim_tpu_ctrl_axil_bvalid) begin
                tb_fail("TPU_CTRL write bvalid timeout");
            end
            if(sim_tpu_ctrl_axil_bresp != 2'b00) begin
                tb_fail("TPU_CTRL write response error");
            end

            @(posedge clk);
            sim_tpu_ctrl_axil_bready = 1'b0;
        end
    endtask

    task mmio_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            sim_tpu_ctrl_axil_araddr  = addr;
            sim_tpu_ctrl_axil_arprot  = 3'b000;
            sim_tpu_ctrl_axil_arvalid = 1'b1;
            sim_tpu_ctrl_axil_rready  = 1'b1;

            for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                #1;
                if(sim_tpu_ctrl_axil_arready) begin
                    wait_cycles = 256;
                end
            end
            if(!sim_tpu_ctrl_axil_arready) begin
                tb_fail("TPU_CTRL read arready timeout");
            end

            #1;
            if(!sim_tpu_ctrl_axil_rvalid) begin
                for(wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
                    @(posedge clk);
                    #1;
                    if(sim_tpu_ctrl_axil_rvalid) begin
                        wait_cycles = 256;
                    end
                end
            end
            sim_tpu_ctrl_axil_arvalid = 1'b0;
            if(!sim_tpu_ctrl_axil_rvalid) begin
                $display("[TB][DBG] read timeout sim_arvalid=%0b sim_arready=%0b sim_rvalid=%0b sim_rready=%0b top_arvalid=%0b top_arready=%0b top_rvalid=%0b top_rready=%0b regs_arvalid=%0b regs_arready=%0b regs_rvalid=%0b regs_rready=%0b regs_rdata=%08x",
                    sim_tpu_ctrl_axil_arvalid, sim_tpu_ctrl_axil_arready, sim_tpu_ctrl_axil_rvalid, sim_tpu_ctrl_axil_rready,
                    dut.tpu_ctrl_axil_arvalid, dut.tpu_ctrl_axil_arready, dut.tpu_ctrl_axil_rvalid, dut.tpu_ctrl_axil_rready,
                    dut.tpu_ctrl_axil_regs_u.s_axil_arvalid, dut.tpu_ctrl_axil_regs_u.s_axil_arready, dut.tpu_ctrl_axil_regs_u.s_axil_rvalid, dut.tpu_ctrl_axil_regs_u.s_axil_rready, dut.tpu_ctrl_axil_regs_u.s_axil_rdata);
                tb_fail("TPU_CTRL read rvalid timeout");
            end
            if(sim_tpu_ctrl_axil_rresp != 2'b00) begin
                tb_fail("TPU_CTRL read response error");
            end

            data = sim_tpu_ctrl_axil_rdata;
            @(posedge clk);
            sim_tpu_ctrl_axil_rready = 1'b0;
        end
    endtask

    panda_soc_stage2_base_top #(
        .EN_DCACHE("true"),
        .USE_TPU_STATUS_STUB(1),
        .USE_TPU_DESC_DMA_STUB(1),
        .SIM_TPU_CTRL_AXIL_BYPASS(1)
    ) dut (
        .clk(clk),
        .ext_resetn(ext_resetn),
        .uart0_rx(uart0_rx),
        .uart0_tx(uart0_tx),
        .tpu_status_busy(1'b0),
        .tpu_status_done(1'b0),
        .tpu_status_error(1'b0),
        .tpu_launch_pulse(tpu_launch_pulse),
        .tpu_soft_reset_pulse(tpu_soft_reset_pulse),
        .tpu_mode_reg(tpu_mode_reg),
        .tpu_net_id_reg(tpu_net_id_reg),
        .tpu_desc_lo_reg(tpu_desc_lo_reg),
        .tpu_desc_hi_reg(tpu_desc_hi_reg),
        .tpu_irq_en_reg(tpu_irq_en_reg),
        .tpu_perf_cycle_reg(tpu_perf_cycle_reg),
        .sim_tpu_ctrl_axil_awaddr(sim_tpu_ctrl_axil_awaddr),
        .sim_tpu_ctrl_axil_awprot(sim_tpu_ctrl_axil_awprot),
        .sim_tpu_ctrl_axil_awvalid(sim_tpu_ctrl_axil_awvalid),
        .sim_tpu_ctrl_axil_awready(sim_tpu_ctrl_axil_awready),
        .sim_tpu_ctrl_axil_wdata(sim_tpu_ctrl_axil_wdata),
        .sim_tpu_ctrl_axil_wstrb(sim_tpu_ctrl_axil_wstrb),
        .sim_tpu_ctrl_axil_wvalid(sim_tpu_ctrl_axil_wvalid),
        .sim_tpu_ctrl_axil_wready(sim_tpu_ctrl_axil_wready),
        .sim_tpu_ctrl_axil_bresp(sim_tpu_ctrl_axil_bresp),
        .sim_tpu_ctrl_axil_bvalid(sim_tpu_ctrl_axil_bvalid),
        .sim_tpu_ctrl_axil_bready(sim_tpu_ctrl_axil_bready),
        .sim_tpu_ctrl_axil_araddr(sim_tpu_ctrl_axil_araddr),
        .sim_tpu_ctrl_axil_arprot(sim_tpu_ctrl_axil_arprot),
        .sim_tpu_ctrl_axil_arvalid(sim_tpu_ctrl_axil_arvalid),
        .sim_tpu_ctrl_axil_arready(sim_tpu_ctrl_axil_arready),
        .sim_tpu_ctrl_axil_rdata(sim_tpu_ctrl_axil_rdata),
        .sim_tpu_ctrl_axil_rresp(sim_tpu_ctrl_axil_rresp),
        .sim_tpu_ctrl_axil_rvalid(sim_tpu_ctrl_axil_rvalid),
        .sim_tpu_ctrl_axil_rready(sim_tpu_ctrl_axil_rready),
        .tpu_axi_araddr(32'd0),
        .tpu_axi_arburst(2'd0),
        .tpu_axi_arlen(8'd0),
        .tpu_axi_arsize(3'd0),
        .tpu_axi_arcache(4'd0),
        .tpu_axi_arvalid(1'b0),
        .tpu_axi_arready(),
        .tpu_axi_awaddr(32'd0),
        .tpu_axi_awburst(2'd0),
        .tpu_axi_awlen(8'd0),
        .tpu_axi_awsize(3'd0),
        .tpu_axi_awcache(4'd0),
        .tpu_axi_awvalid(1'b0),
        .tpu_axi_awready(),
        .tpu_axi_bresp(),
        .tpu_axi_bvalid(),
        .tpu_axi_bready(1'b0),
        .tpu_axi_rdata(),
        .tpu_axi_rresp(),
        .tpu_axi_rlast(),
        .tpu_axi_rvalid(),
        .tpu_axi_rready(1'b0),
        .tpu_axi_wdata(32'd0),
        .tpu_axi_wstrb(4'd0),
        .tpu_axi_wlast(1'b0),
        .tpu_axi_wvalid(1'b0),
        .tpu_axi_wready()
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(2_000_000);
        tb_fail("global timeout waiting for stage2 top smoke completion");
    end

    initial begin
        ext_resetn = 1'b0;
        uart0_rx   = 1'b1;
        read_data_reg = 32'd0;
        expected_output_word = 32'd0;

        force dut.panda_risc_v_min_proc_sys_u.sys_resetn = 1'b0;
        axil_idle();

        repeat(8) @(posedge clk);
        ext_resetn = 1'b1;
        repeat(6) @(posedge clk);

        $display("[TB] preload shared SRAM inside stage2 top");
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 0] = 32'h0000_0002;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 1] = INPUT_BASE_ADDR;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 2] = OUTPUT_BASE_ADDR;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 3] = PARAM_BASE_ADDR;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 4] = 32'h6001_0800;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 5] = 32'd4;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 6] = 32'd4;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((DESC_BASE_ADDR   & 32'h007f_ffff) >> 2) + 7] = 32'h0000_0005;

        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'd17;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'd34;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 2] = 32'd51;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((INPUT_BASE_ADDR  & 32'h007f_ffff) >> 2) + 3] = 32'd68;

        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 0] = 32'd1;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 1] = 32'd2;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 2] = 32'd3;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 3] = 32'd4;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 4] = 32'd5;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 5] = 32'd6;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 6] = 32'd7;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((PARAM_BASE_ADDR  & 32'h007f_ffff) >> 2) + 7] = 32'd8;

        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 0] = 32'hDEAD_BEEF;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 1] = 32'hDEAD_BEEF;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 2] = 32'hDEAD_BEEF;
        dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + 3] = 32'hDEAD_BEEF;

        mmio_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if(read_data_reg !== 32'd0) begin
            tb_fail("initial STATUS expected 0");
        end

        mmio_write(TPU_BASE_ADDR + 32'h08, 32'h0000_0000);
        mmio_write(TPU_BASE_ADDR + 32'h0C, 32'h0000_0002);
        mmio_write(TPU_BASE_ADDR + 32'h10, DESC_BASE_ADDR);
        mmio_write(TPU_BASE_ADDR + 32'h14, 32'h0000_0000);

        if(tpu_net_id_reg !== 32'h0000_0002) begin
            tb_fail("top-level tpu_net_id_reg mismatch after MMIO write");
        end
        if(tpu_desc_lo_reg !== DESC_BASE_ADDR) begin
            tb_fail("top-level tpu_desc_lo_reg mismatch after MMIO write");
        end

        mmio_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0001);

        mmio_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if((read_data_reg & 32'h1) == 0) begin
            tb_fail("STATUS.busy not asserted after start");
        end
        $display("[TB] stage2 top busy asserted after MMIO start");

        poll_count = 0;
        while((read_data_reg & 32'h2) == 0) begin
            mmio_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
            poll_count = poll_count + 1;
            if(read_data_reg[2]) begin
                tb_fail("STATUS.error asserted unexpectedly");
            end
            if(poll_count > 128) begin
                tb_fail("timeout waiting for STATUS.done");
            end
        end

        if(read_data_reg[0]) begin
            tb_fail("STATUS.done and busy both set");
        end
        $display("[TB] stage2 top done observed after %0d polls", poll_count);

        mmio_read(TPU_BASE_ADDR + 32'h18, read_data_reg);
        if(read_data_reg == 32'd0) begin
            tb_fail("PERF_CYCLE did not increment through top path");
        end

        for(output_index = 0; output_index < 4; output_index = output_index + 1) begin
            expected_output_word = 32'd213 + output_index;
            if(dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[((OUTPUT_BASE_ADDR & 32'h007f_ffff) >> 2) + output_index] !== expected_output_word) begin
                tb_fail("top-level output blob mismatch");
            end
        end

        mmio_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0002);
        mmio_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if(read_data_reg !== 32'd0) begin
            tb_fail("STATUS not cleared after soft reset through top path");
        end

        mmio_write(TPU_BASE_ADDR + 32'h10, 32'd0);
        mmio_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0001);
        mmio_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if((read_data_reg & 32'h4) == 0) begin
            tb_fail("top-level zero desc launch did not assert error");
        end

        $display("[TB][PASS] stage2 top MMIO -> TPU_CTRL -> DMA stub -> shared SRAM smoke test passed");
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
