`timescale 1ns/1ps

// ============================================================================
// 文件名称：tb_mac32_8lane_top.v
// 模块名称：tb_mac32_8lane_top
// 功能说明：8 路、4 beat 的 32 项点积 Verilog-2001 自检测试平台。
//           覆盖边界值、已知平方和、随机向量、输入气泡、延迟和吞吐。
// 设计属性：仅用于仿真，不参与综合
// 作者：changting
// 日期：2026-09-08
// 版本：1.1
// ============================================================================
module tb_mac32_8lane_top;
    parameter RANDOM_CASES = 128;

    reg clk;
    reg rst_n;
    reg start;
    reg in_valid;
    wire in_ready;
    reg [127:0] a_in;
    reg [127:0] b_in;
    wire result_valid;
    wire busy;
    wire signed [39:0] result;

    reg signed [15:0] vector_a [0:31];
    reg signed [15:0] vector_b [0:31];
    reg signed [63:0] expected;
    reg signed [63:0] av;
    reg signed [63:0] bv;
    integer cycle_count;
    integer errors;
    integer checked;
    integer previous_start_cycle;
    integer current_start_cycle;
    integer current_last_cycle;
    integer current_result_cycle;
    integer inserted_bubbles;
    integer i;
    integer case_index;

    mac32_8lane_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .a_in(a_in),
        .b_in(b_in),
        .result_valid(result_valid),
        .busy(busy),
        .result(result)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // 生成测试向量，并用独立的 64 bit 有符号累加计算黄金结果。
    task prepare_vector;
        input integer pattern_id;
        integer index;
        begin
            for (index = 0; index < 32; index = index + 1) begin
                case (pattern_id)
                    0: begin
                        vector_a[index] = 16'sd0;
                        vector_b[index] = 16'sd0;
                    end
                    1: begin
                        vector_a[index] = 16'sh4000;
                        vector_b[index] = 16'sh4000;
                    end
                    2: begin
                        vector_a[index] = 16'sh7fff;
                        vector_b[index] = 16'sh7fff;
                    end
                    3: begin
                        vector_a[index] = 16'sh8000;
                        vector_b[index] = 16'sh8000;
                    end
                    4: begin
                        if ((index % 2) != 0) begin
                            vector_a[index] = 16'sh7fff;
                            vector_b[index] = 16'sh8000;
                        end else begin
                            vector_a[index] = 16'sh8000;
                            vector_b[index] = 16'sh7fff;
                        end
                    end
                    5: begin
                        vector_a[index] = index + 1;
                        vector_b[index] = index + 1;
                    end
                    default: begin
                        vector_a[index] = $random;
                        vector_b[index] = $random;
                    end
                endcase
            end

            expected = 64'sd0;
            for (index = 0; index < 32; index = index + 1) begin
                av = vector_a[index];
                bv = vector_b[index];
                expected = expected + av * bv;
            end
        end
    endtask

    // 驱动一个空闲周期。
    task drive_idle;
        begin
            @(negedge clk);
            start    = 1'b0;
            in_valid = 1'b0;
            a_in     = 128'd0;
            b_in     = 128'd0;
        end
    endtask

    // 发送四个有效 beat，可按 bubble_mask 在 beat 前插入空拍。
    task run_case;
        input integer pattern_id;
        input integer bubble_mask;
        integer beat;
        integer lane;
        integer start_interval;
        begin
            prepare_vector(pattern_id);
            inserted_bubbles = 0;

            while (!in_ready)
                @(negedge clk);

            for (beat = 0; beat < 4; beat = beat + 1) begin
                if ((beat > 0) && ((bubble_mask & (1 << beat)) != 0)) begin
                    drive_idle;
                    inserted_bubbles = inserted_bubbles + 1;
                end

                @(negedge clk);
                start    = (beat == 0);
                in_valid = 1'b1;
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    a_in[(lane*16) +: 16] = vector_a[(beat*8) + lane];
                    b_in[(lane*16) +: 16] = vector_b[(beat*8) + lane];
                end

                if (beat == 0)
                    current_start_cycle = cycle_count + 1;
                if (beat == 3)
                    current_last_cycle = cycle_count + 1;
            end

            drive_idle;
            wait (result_valid === 1'b1);
            #1;
            current_result_cycle = cycle_count;
            checked = checked + 1;

            if ($signed(result) !== $signed(expected[39:0])) begin
                errors = errors + 1;
                $display("[FAIL] case=%0d got=%0d expected=%0d",
                         checked, $signed(result), expected);
            end
            if ((current_result_cycle-current_start_cycle) !=
                (7+inserted_bubbles)) begin
                errors = errors + 1;
                $display("[FAIL] case=%0d latency=%0d expected=%0d",
                         checked, current_result_cycle-current_start_cycle,
                         7+inserted_bubbles);
            end
            if ((current_result_cycle-current_last_cycle) != 4) begin
                errors = errors + 1;
                $display("[FAIL] case=%0d last_to_result=%0d expected=4",
                         checked, current_result_cycle-current_last_cycle);
            end

            if ((previous_start_cycle >= 0) && (bubble_mask == 0)) begin
                start_interval = current_start_cycle - previous_start_cycle;
                if (start_interval != 8) begin
                    errors = errors + 1;
                    $display("[FAIL] case=%0d start_interval=%0d expected=8",
                             checked, start_interval);
                end
            end
            previous_start_cycle = current_start_cycle;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        in_valid = 1'b0;
        a_in = 128'd0;
        b_in = 128'd0;
        errors = 0;
        checked = 0;
        previous_start_cycle = -1;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (case_index = 0; case_index < 6; case_index = case_index + 1)
            run_case(case_index, 0);

        for (case_index = 0; case_index < RANDOM_CASES;
             case_index = case_index + 1)
            run_case(6, 0);

        run_case(6, 2);
        run_case(6, 4);
        run_case(6, 10);

        if (errors == 0) begin
            $display("===== ALL TESTS PASSED =====");
            $display("[METRIC] checked_dot_products=%0d", checked);
            $display("[METRIC] input_beats_per_dot=4");
            $display("[METRIC] no_bubble_latency=7 cycles");
            $display("[METRIC] minimum_initiation_interval=8 cycles");
            $display("[METRIC] peak_compute=8 MAC/cycle");
            $display("[METRIC] sustained_without_overlap=32/8=4 MAC/cycle");
        end else begin
            $display("===== TESTS FAILED: errors=%0d =====", errors);
        end
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] simulation timeout");
        $finish;
    end
endmodule
