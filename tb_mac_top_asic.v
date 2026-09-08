`timescale 1ns/1ps

// ============================================================================
// tb_mac_led_square
// 验证 mac_led_square：
//   - 内部自动生成 i*i (i=1..32) 并累加
//   - 结果正确（=11440）时 led 点亮并保持
// 通过内部层次引用 u_dut.acc_out 观察累加值。
// ============================================================================
module tb_mac_top;

    reg  clk;
    reg  rst_n;
    wire led;

    // DUT
    mac_top #(
        .DATA_W (16),
        .ACC_W  (40),
        .N      (32),
        .EN_GAP (0),
        .TARGET (40'd11440)
    ) u_dut (
        .clk   (clk),
        .rst_n (rst_n),
        .led   (led)
    );

    // 10ns 时钟
    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    
    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        errors = 0;

        // 复位释放
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // 等 led 点亮
        wait (led === 1'b1);

        // 点亮瞬间，通过层次引用检查累加结果
        @(negedge clk);
        if (u_dut.acc_out == $signed(40'd11440))
            $display("[PASS] at led rising acc_out=%0d (expect 11440)", $signed(u_dut.acc_out));
        else begin
            errors = errors + 1;
            $display("[FAIL] led lit but acc_out=%0d (expect 11440)", $signed(u_dut.acc_out));
        end

        // 检查 led 保持点亮（连续多拍不回落）
        repeat (50) @(posedge clk);
        if (led === 1'b1)
            $display("[PASS] led stays high (held)");
        else begin
            errors = errors + 1;
            $display("[FAIL] led went low after lighting");
        end

        // 汇总
        if (errors == 0)
            $display("===== ALL PASSED =====");
        else
            $display("===== %0d TEST(S) FAILED =====", errors);
        $finish;
    end

    // 超时保护
    initial begin
        #200000;
        if (led == 1'b0)
            $display("[TIMEOUT] led never went high!");
        $finish;
    end



endmodule
