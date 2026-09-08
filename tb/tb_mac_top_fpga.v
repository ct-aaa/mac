`timescale 1ns/1ps

// ============================================================================
// 文件名称：tb_mac_top_fpga.v
// 模块名称：tb_mac_top_fpga
// 功能说明：验证 FPGA 自运行顶层的平方和结果及 LED 锁存行为。
// 设计语言：Verilog-2001
// ============================================================================
module tb_mac_top_fpga;

    reg  clk;
    reg  rst_n;
    wire led;
    integer errors;

    mac_top #(
        .DATA_W(16),
        .ACC_W(40),
        .N(32),
        .EN_GAP(0),
        .TARGET(40'd11440)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .led(led)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst_n  = 1'b0;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        wait (led === 1'b1);
        @(negedge clk);

        if ($signed(u_dut.acc_out) == 40'sd11440)
            $display("[PASS] acc_out=%0d (expect 11440)",
                     $signed(u_dut.acc_out));
        else begin
            errors = errors + 1;
            $display("[FAIL] led lit but acc_out=%0d (expect 11440)",
                     $signed(u_dut.acc_out));
        end

        repeat (50) @(posedge clk);
        if (led === 1'b1)
            $display("[PASS] led stays high (held)");
        else begin
            errors = errors + 1;
            $display("[FAIL] led went low after lighting");
        end

        if (errors == 0)
            $display("===== ALL PASSED =====");
        else
            $display("===== %0d TEST(S) FAILED =====", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("[TIMEOUT] led never went high");
        $finish;
    end

endmodule
