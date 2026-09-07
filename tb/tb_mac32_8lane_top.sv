`timescale 1ns/1ps

// ============================================================================
// 文件名称：tb_mac32_8lane_top.sv
// 模块名称：tb_mac32_8lane_top
// 功能说明：8 路、4 beat 的 32 项 Q1.15 点积自检测试平台。
//           覆盖零值、0.5、正负极值、已知平方和、随机向量、输入气泡
//           以及延迟和吞吐率指标检查。
// 设计语言：SystemVerilog
// 设计属性：仅用于前仿验证，不参与综合
// 作者：changting
// 日期：2026-09-08
// 版本：1.0
// ============================================================================
module tb_mac32_8lane_top;
    localparam integer RANDOM_CASES = 128;

    logic clk;
    logic rst_n;
    logic start;
    logic in_valid;
    logic in_ready;
    logic signed [15:0] a_in [0:7];
    logic signed [15:0] b_in [0:7];
    wire result_valid;
    wire busy;
    wire signed [39:0] result;

    logic signed [15:0] vector_a [0:31];
    logic signed [15:0] vector_b [0:31];
    longint signed expected;
    longint signed av;
    longint signed bv;
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

    // 时钟与周期计数：产生 100 MHz 时钟，并记录复位释放后的周期数。
    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // ------------------------------------------------------------------------
    // 激励准备：根据 pattern_id 生成确定性边界向量或随机向量，
    // 同时使用 64 bit 有符号整数计算独立黄金参考结果。
    // ------------------------------------------------------------------------
    task automatic prepare_vector(input integer pattern_id);
        integer index;
        begin
            for (index = 0; index < 32; index = index + 1) begin
                case (pattern_id)
                    0: begin vector_a[index] = 16'sd0;    vector_b[index] = 16'sd0; end
                    1: begin vector_a[index] = 16'sh4000; vector_b[index] = 16'sh4000; end
                    2: begin vector_a[index] = 16'sh7fff; vector_b[index] = 16'sh7fff; end
                    3: begin vector_a[index] = 16'sh8000; vector_b[index] = 16'sh8000; end
                    4: begin
                        vector_a[index] = index[0] ? 16'sh7fff : 16'sh8000;
                        vector_b[index] = index[0] ? 16'sh8000 : 16'sh7fff;
                    end
                    5: begin
                        vector_a[index] = index + 1;
                        vector_b[index] = index + 1;
                    end
                    default: begin
                        vector_a[index] = $urandom;
                        vector_b[index] = $urandom;
                    end
                endcase
            end

            expected = 0;
            for (index = 0; index < 32; index = index + 1) begin
                av = $signed(vector_a[index]);
                bv = $signed(vector_b[index]);
                expected = expected + av * bv;
            end
        end
    endtask

    // 驱动空闲周期：撤销握手信号并清零输入总线。
    task automatic drive_idle;
        integer lane;
        begin
            @(negedge clk);
            start = 1'b0;
            in_valid = 1'b0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                a_in[lane] = '0;
                b_in[lane] = '0;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // 单用例执行：发送四个有效 beat，可按 bubble_mask 插入输入气泡；
    // 随后检查数值、首拍到结果延迟、末拍到结果延迟及任务启动间隔。
    // ------------------------------------------------------------------------
    task automatic run_case(input integer pattern_id, input integer bubble_mask);
        integer beat;
        integer lane;
        integer start_interval;
        begin
            prepare_vector(pattern_id);
            inserted_bubbles = 0;

            while (!in_ready)
                @(negedge clk);

            for (beat = 0; beat < 4; beat = beat + 1) begin
                // bubble_mask 的 bit1..bit3 控制对应 beat 前是否插入一个气泡。
                if ((beat > 0) && ((bubble_mask & (1 << beat)) != 0)) begin
                    drive_idle();
                    inserted_bubbles = inserted_bubbles + 1;
                end

                @(negedge clk);
                start = (beat == 0);
                in_valid = 1'b1;
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    a_in[lane] = vector_a[beat*8 + lane];
                    b_in[lane] = vector_b[beat*8 + lane];
                end

                if (beat == 0)
                    current_start_cycle = cycle_count + 1;
                if (beat == 3)
                    current_last_cycle = cycle_count + 1;
            end

            drive_idle();
            wait (result_valid === 1'b1);
            #1;
            current_result_cycle = cycle_count;
            checked = checked + 1;

            if ($signed(result) !== expected) begin
                errors = errors + 1;
                $display("[FAIL] case=%0d got=%0d expected=%0d",
                         checked, $signed(result), expected);
            end
            if ((current_result_cycle-current_start_cycle) != (7+inserted_bubbles)) begin
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

    // ------------------------------------------------------------------------
    // 主测试流程：完成复位、边界测试、随机回归和周期指标汇总。
    // ------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        in_valid = 1'b0;
        errors = 0;
        checked = 0;
        previous_start_cycle = -1;
        for (i = 0; i < 8; i = i + 1) begin
            a_in[i] = '0;
            b_in[i] = '0;
        end

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // 六个确定性边界用例。
        for (case_index = 0; case_index < 6; case_index = case_index + 1)
            run_case(case_index, 0);

        // 128 个随机无气泡用例，检查连续任务的固定 II=8。
        for (case_index = 0; case_index < RANDOM_CASES; case_index = case_index + 1)
            run_case(6, 0);

        // 三个随机气泡用例，分别在不同 beat 前暂停。
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

    // 超时保护：防止握手或状态机错误导致仿真永久等待。
    initial begin
        #500000;
        $display("[FAIL] simulation timeout");
        $finish;
    end
endmodule
