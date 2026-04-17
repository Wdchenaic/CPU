`timescale 1ns / 1ps
`default_nettype none

module tb_tpu_ctrl_task_stub;

    localparam [31:0] TPU_BASE_ADDR = 32'h4000_4000;
    localparam integer CLK_PERIOD = 10;
    localparam integer DONE_LATENCY_CYCLES = 8;

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

    wire        status_busy;
    wire        status_done;
    wire        status_error;
    wire        launch_pulse;
    wire        soft_reset_pulse;
    wire [31:0] mode_reg;
    wire [31:0] net_id_reg;
    wire [31:0] desc_lo_reg;
    wire [31:0] desc_hi_reg;
    wire        irq_en_reg;
    wire [31:0] perf_cycle_reg;

    reg [31:0] read_data_reg;
    integer poll_count;

    task tb_fail;
        input [255:0] msg;
        begin
            $display("[TB][FAIL] %0s", msg);
            repeat(5) @(posedge clk);
            $finish;
        end
    endtask

    tpu_ctrl_axil_regs #(
        .TPU_BASE_ADDR(TPU_BASE_ADDR)
    ) dut_regs (
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

    tpu_ctrl_task_stub #(
        .DONE_LATENCY_CYCLES(DONE_LATENCY_CYCLES)
    ) dut_stub (
        .clk(clk),
        .rst_n(rst_n),
        .launch_pulse(launch_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .mode_reg(mode_reg),
        .net_id_reg(net_id_reg),
        .desc_lo_reg(desc_lo_reg),
        .desc_hi_reg(desc_hi_reg),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_error(status_error)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

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

            wait(s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 1'b0;
            s_axil_wvalid  <= 1'b0;

            wait(s_axil_bvalid);
            if(s_axil_bresp != 2'b00) begin
                tb_fail("write response error");
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

            wait(s_axil_arready);
            @(posedge clk);
            s_axil_arvalid <= 1'b0;

            wait(s_axil_rvalid);
            if(s_axil_rresp != 2'b00) begin
                tb_fail("read response error");
            end
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        s_axil_awaddr = 32'd0;
        s_axil_awprot = 3'd0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata = 32'd0;
        s_axil_wstrb = 4'd0;
        s_axil_wvalid = 1'b0;
        s_axil_bready = 1'b0;
        s_axil_araddr = 32'd0;
        s_axil_arprot = 3'd0;
        s_axil_arvalid = 1'b0;
        s_axil_rready = 1'b0;
        read_data_reg = 32'd0;

        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        $display("[TB] reset released");

        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if(read_data_reg !== 32'd0) begin
            tb_fail("initial STATUS expected 0");
        end

        axil_write(TPU_BASE_ADDR + 32'h08, 32'h0000_0000);
        axil_write(TPU_BASE_ADDR + 32'h0C, 32'h0000_0002);
        axil_write(TPU_BASE_ADDR + 32'h10, 32'h6001_0000);
        axil_write(TPU_BASE_ADDR + 32'h14, 32'h0000_0000);
        axil_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0001);

        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if((read_data_reg & 32'h1) == 0) begin
            tb_fail("STATUS.busy was not asserted after launch");
        end
        $display("[TB] busy asserted after launch");

        poll_count = 0;
        while((read_data_reg & 32'h2) == 0) begin
            axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
            poll_count = poll_count + 1;
            if(read_data_reg[2]) begin
                tb_fail("STATUS.error asserted unexpectedly");
            end
            if(poll_count > 64) begin
                tb_fail("timeout waiting for done");
            end
        end

        if(read_data_reg[0]) begin
            tb_fail("STATUS.done and busy both set");
        end
        $display("[TB] done observed after %0d polls", poll_count);

        axil_read(TPU_BASE_ADDR + 32'h18, read_data_reg);
        if(read_data_reg == 32'd0) begin
            tb_fail("PERF_CYCLE did not increment");
        end
        $display("[TB] perf counter incremented to %0d", read_data_reg);

        axil_write(TPU_BASE_ADDR + 32'h10, 32'h0000_0000);
        axil_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0001);
        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if((read_data_reg & 32'h4) == 0) begin
            tb_fail("STATUS.error was not asserted for zero desc base");
        end
        $display("[TB] error path observed as expected");

        axil_write(TPU_BASE_ADDR + 32'h00, 32'h0000_0002);
        axil_read(TPU_BASE_ADDR + 32'h04, read_data_reg);
        if(read_data_reg !== 32'd0) begin
            tb_fail("STATUS not cleared after soft reset");
        end

        $display("[TB][PASS] TPU_CTRL + task stub directed test passed");
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule
`default_nettype wire
