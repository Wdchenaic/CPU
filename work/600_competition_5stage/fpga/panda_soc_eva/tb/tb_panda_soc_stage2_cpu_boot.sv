`timescale 1ns / 1ps
`default_nettype none

module tb_panda_soc_stage2_cpu_boot;

    localparam integer CLK_PERIOD = 10;
    localparam [31:0] TPU_DESC0_BASE    = 32'h6001_0000;
    localparam [31:0] TPU_DESC1_BASE    = 32'h6001_1000;
    localparam [31:0] TPU_OUT_BUF0_BASE = 32'h6001_0400;
    localparam [31:0] TPU_OUT_BUF1_BASE = 32'h6001_1400;

    localparam [31:0] EXPECT_STAGE0_SEED = 32'h0010_002B;
    localparam [31:0] EXPECT_STAGE1_SEED = 32'h0009_00F7;
    localparam [31:0] EXPECT_STAGE2_SEED = 32'h0000_D69A;

    localparam integer OUT0_WORD_INDEX = (TPU_OUT_BUF0_BASE - 32'h6000_0000) >> 2;
    localparam integer OUT1_WORD_INDEX = (TPU_OUT_BUF1_BASE - 32'h6000_0000) >> 2;
    localparam integer PARAM_KEY_INDEX = (32'h6000_0000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_OTHER_INDEX = (32'h6000_2000 - 32'h6000_0000) >> 2;
    localparam integer PARAM_CLASSIFIER_INDEX = (32'h6000_4000 - 32'h6000_0000) >> 2;
    localparam integer DESC0_WORD_INDEX = (TPU_DESC0_BASE - 32'h6000_0000) >> 2;
    localparam integer DESC1_WORD_INDEX = (TPU_DESC1_BASE - 32'h6000_0000) >> 2;

    localparam IMEM_INIT_FILE    = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem.txt";
    localparam IMEM_INIT_FILE_B0 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem_b0.txt";
    localparam IMEM_INIT_FILE_B1 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem_b1.txt";
    localparam IMEM_INIT_FILE_B2 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem_b2.txt";
    localparam IMEM_INIT_FILE_B3 = "/home/jjt/soc/my_soc/CPU_Copetition_tpu_soc/work/600_competition_5stage/fpga/stage2_programs/breath_tpu_soc_demo/breath_tpu_soc_demo_imem_b3.txt";

    reg clk;
    reg ext_resetn;
    reg uart0_rx;
    wire uart0_tx;

    wire        tpu_launch_pulse;
    wire        tpu_soft_reset_pulse;
    wire [31:0] tpu_mode_reg;
    wire [31:0] tpu_net_id_reg;
    wire [31:0] tpu_desc_lo_reg;
    wire [31:0] tpu_desc_hi_reg;
    wire        tpu_irq_en_reg;
    wire [31:0] tpu_perf_cycle_reg;

    integer launch_count;
    integer wait_cycles;
    integer dbus_aw_hs;
    integer dbus_ar_hs;
    integer dcache_aw_hs;
    integer dcache_ar_hs;
    integer inst_cmd_hs;
    integer inst_rsp_hs;
    integer data_cmd_hs;
    integer data_rsp_hs;
    integer dtcm_cmd_hs;
    integer dtcm_rsp_hs;

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(10) @(posedge clk);
            $finish;
        end
    endtask

    task expect_launch;
        input integer expected_idx;
        input [31:0] expected_net_id;
        input [31:0] expected_desc_addr;
        begin
            while(tpu_launch_pulse !== 1'b1)
                @(posedge clk);

            launch_count = launch_count + 1;
            $display("[TB] observed launch #%0d net_id=0x%08x desc=0x%08x", launch_count, tpu_net_id_reg, tpu_desc_lo_reg);

            if(launch_count != expected_idx)
                tb_fail("unexpected launch count order");
            if(tpu_net_id_reg != expected_net_id)
                tb_fail("unexpected net_id on launch");
            if(tpu_desc_lo_reg != expected_desc_addr)
                tb_fail("unexpected desc address on launch");

            dump_desc_words(expected_desc_addr);

            @(posedge clk);
        end
    endtask

    task expect_word;
        input integer word_index;
        input [31:0] expected_word;
        input [255:0] tag;
        reg [31:0] actual_word;
        begin
            actual_word = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[word_index];
            if(actual_word !== expected_word) begin
                $display("[TB][DBG] word_index=0x%0x actual=0x%08x expected=0x%08x", word_index, actual_word, expected_word);
                tb_fail(tag);
            end
        end
    endtask

    task dump_desc_words;
        input [31:0] desc_addr;
        integer desc_word_index;
        integer input_word_index;
        integer param_word_index;
        reg [31:0] input_addr;
        reg [31:0] param_addr;
        begin
            desc_word_index = (desc_addr - 32'h6000_0000) >> 2;
            input_addr = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 1];
            param_addr = dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 3];
            input_word_index = (input_addr - 32'h6000_0000) >> 2;
            param_word_index = (param_addr - 32'h6000_0000) >> 2;

            $display("[TB][DBG] desc_memx%08x = %08x %08x %08x %08x %08x %08x %08x %08x",
                desc_addr,
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 0],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 1],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 2],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 3],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 4],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 5],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 6],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[desc_word_index + 7]);

            if((input_addr >= 32'h6000_0000) && (input_addr < 32'h6080_0000)) begin
                $display("[TB][DBG] input_memx%08x = %08x %08x",
                    input_addr,
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[input_word_index + 0],
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[input_word_index + 1]);
            end

            if((param_addr >= 32'h6000_0000) && (param_addr < 32'h6080_0000)) begin
                $display("[TB][DBG] param_memx%08x = %08x %08x",
                    param_addr,
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[param_word_index + 0],
                    dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[param_word_index + 1]);
            end
        end
    endtask

    panda_soc_stage2_base_top #(
        .EN_DCACHE("true"),
        .EN_DTCM("true"),
        .USE_TPU_STATUS_STUB(1),
        .USE_TPU_DESC_DMA_STUB(1),
        .SIM_TPU_CTRL_AXIL_BYPASS(0),
        .imem_init_file(IMEM_INIT_FILE),
        .imem_init_file_b0(IMEM_INIT_FILE_B0),
        .imem_init_file_b1(IMEM_INIT_FILE_B1),
        .imem_init_file_b2(IMEM_INIT_FILE_B2),
        .imem_init_file_b3(IMEM_INIT_FILE_B3)
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
        .sim_tpu_ctrl_axil_awaddr(32'd0),
        .sim_tpu_ctrl_axil_awprot(3'd0),
        .sim_tpu_ctrl_axil_awvalid(1'b0),
        .sim_tpu_ctrl_axil_awready(),
        .sim_tpu_ctrl_axil_wdata(32'd0),
        .sim_tpu_ctrl_axil_wstrb(4'd0),
        .sim_tpu_ctrl_axil_wvalid(1'b0),
        .sim_tpu_ctrl_axil_wready(),
        .sim_tpu_ctrl_axil_bresp(),
        .sim_tpu_ctrl_axil_bvalid(),
        .sim_tpu_ctrl_axil_bready(1'b0),
        .sim_tpu_ctrl_axil_araddr(32'd0),
        .sim_tpu_ctrl_axil_arprot(3'd0),
        .sim_tpu_ctrl_axil_arvalid(1'b0),
        .sim_tpu_ctrl_axil_arready(),
        .sim_tpu_ctrl_axil_rdata(),
        .sim_tpu_ctrl_axil_rresp(),
        .sim_tpu_ctrl_axil_rvalid(),
        .sim_tpu_ctrl_axil_rready(1'b0),
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

    always @(posedge clk) begin
        if(ext_resetn) begin
            if(dut.m_axi_dbus_awvalid && dut.m_axi_dbus_awready)
                dbus_aw_hs <= dbus_aw_hs + 1;
            if(dut.m_axi_dbus_arvalid && dut.m_axi_dbus_arready)
                dbus_ar_hs <= dbus_ar_hs + 1;
            if(dut.m_axi_dcache_awvalid && dut.m_axi_dcache_awready)
                dcache_aw_hs <= dcache_aw_hs + 1;
            if(dut.m_axi_dcache_arvalid && dut.m_axi_dcache_arready)
                dcache_ar_hs <= dcache_ar_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_inst_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_inst_ready)
                inst_cmd_hs <= inst_cmd_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_inst_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_inst_ready)
                inst_rsp_hs <= inst_rsp_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_ready)
                data_cmd_hs <= data_cmd_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_data_valid && dut.panda_risc_v_min_proc_sys_u.m_icb_rsp_data_ready)
                data_rsp_hs <= data_rsp_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_valid && dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_ready)
                dtcm_cmd_hs <= dtcm_cmd_hs + 1;
            if(dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_rsp_valid && dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_rsp_ready)
                dtcm_rsp_hs <= dtcm_rsp_hs + 1;
        end
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(50_000_000);
        $display("[TB][DBG] timeout launch_count=%0d pc=0x%08x inst_cmd_hs=%0d inst_rsp_hs=%0d data_cmd_hs=%0d data_rsp_hs=%0d dtcm_cmd_hs=%0d dtcm_rsp_hs=%0d dbus_aw_hs=%0d dbus_ar_hs=%0d dcache_aw_hs=%0d dcache_ar_hs=%0d inst_addr=0x%08x data_addr=0x%08x dtcm_addr=0x%08x dmem_en=%0b dmem_wen=0x%x dmem_addr=0x%08x ibus_timeout=%0b dbus_timeout=%0b tpu_busy=%0b tpu_done=%0b tpu_error=%0b tpu_mode=0x%08x tpu_net=0x%08x tpu_desc=0x%08x out0[0]=0x%08x out1[0]=0x%08x",
            launch_count,
            dut.panda_risc_v_min_proc_sys_u.panda_risc_v_u.panda_risc_v_ifu_u.now_pc,
            inst_cmd_hs, inst_rsp_hs, data_cmd_hs, data_rsp_hs, dtcm_cmd_hs, dtcm_rsp_hs,
            dbus_aw_hs, dbus_ar_hs, dcache_aw_hs, dcache_ar_hs,
            dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_inst_addr,
            dut.panda_risc_v_min_proc_sys_u.m_icb_cmd_data_addr,
            dut.panda_risc_v_min_proc_sys_u.m0_icb_dstb_cmd_addr,
            dut.panda_risc_v_min_proc_sys_u.dmem_en,
            dut.panda_risc_v_min_proc_sys_u.dmem_wen,
            {dut.panda_risc_v_min_proc_sys_u.dmem_addr, 2'b00},
            dut.ibus_timeout, dut.dbus_timeout,
            dut.tpu_ctrl_status_busy, dut.tpu_ctrl_status_done, dut.tpu_ctrl_status_error,
            tpu_mode_reg, tpu_net_id_reg, tpu_desc_lo_reg,
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
            dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 0]);
        tb_fail("global timeout waiting for cpu boot stage2 completion");
    end

    initial begin
        ext_resetn = 1'b0;
        uart0_rx = 1'b1;
        launch_count = 0;
        dbus_aw_hs = 0;
        dbus_ar_hs = 0;
        dcache_aw_hs = 0;
        dcache_ar_hs = 0;
        inst_cmd_hs = 0;
        inst_rsp_hs = 0;
        data_cmd_hs = 0;
        data_rsp_hs = 0;
        dtcm_cmd_hs = 0;
        dtcm_rsp_hs = 0;

        repeat(20) @(posedge clk);
        ext_resetn = 1'b1;

        expect_launch(1, 32'd0, TPU_DESC0_BASE);
        expect_launch(2, 32'd1, TPU_DESC1_BASE);
        expect_launch(3, 32'd2, TPU_DESC0_BASE);

        for(wait_cycles = 0; wait_cycles < 200000; wait_cycles = wait_cycles + 1) begin
            @(posedge clk);
            if(dut.tpu_ctrl_status_done) begin
                wait_cycles = 200000;
            end
        end
        if(!dut.tpu_ctrl_status_done) begin
            $display("[TB][DBG] third launch wait expired busy=%0b done=%0b error=%0b perf=0x%08x desc_net=0x%08x input_words=%0d output_words=%0d input_wc=%0d param_wc=%0d out0[0]=0x%08x out0[1]=0x%08x out1[0]=0x%08x out1[1]=0x%08x",
                dut.tpu_ctrl_status_busy, dut.tpu_ctrl_status_done, dut.tpu_ctrl_status_error, tpu_perf_cycle_reg,
                dut.tpu_dma_stub_desc_net_id, dut.tpu_dma_stub_desc_input_words, dut.tpu_dma_stub_desc_output_words,
                dut.tpu_dma_stub_input_fetch_word_count, dut.tpu_dma_stub_param_fetch_word_count,
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 0],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT0_WORD_INDEX + 1],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 0],
                dut.panda_soc_shared_mem_subsys_u.axi_ram_u.mem[OUT1_WORD_INDEX + 1]);
            tb_fail("final done was not observed after third launch");
        end

        expect_word(PARAM_KEY_INDEX + 0, 32'd1,   "param_pool key[0] mismatch");
        expect_word(PARAM_KEY_INDEX + 1, 32'd2,   "param_pool key[1] mismatch");
        expect_word(PARAM_OTHER_INDEX + 0, 32'd11, "param_pool other[0] mismatch");
        expect_word(PARAM_OTHER_INDEX + 5, 32'd66, "param_pool other[5] mismatch");
        expect_word(PARAM_CLASSIFIER_INDEX + 0, 32'd101, "param_pool classifier[0] mismatch");
        expect_word(PARAM_CLASSIFIER_INDEX + 7, 32'd108, "param_pool classifier[7] mismatch");

        expect_word(OUT1_WORD_INDEX + 0,  EXPECT_STAGE1_SEED + 32'd0,  "stage1 output[0] mismatch");
        expect_word(OUT1_WORD_INDEX + 15, EXPECT_STAGE1_SEED + 32'd15, "stage1 output[15] mismatch");
        expect_word(OUT0_WORD_INDEX + 0,  EXPECT_STAGE2_SEED + 32'd0,  "stage2 output[0] mismatch");
        expect_word(OUT0_WORD_INDEX + 1,  EXPECT_STAGE2_SEED + 32'd1,  "stage2 output[1] mismatch");

        $display("[TB] cpu boot launched all three stages and shared SRAM contents match expectations");
        $display("[TB] CPU top-level stage2 boot test passed");
        repeat(20) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
