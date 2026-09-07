`timescale 1ns/1ps

// ============================================================================
// 模块名称：reduce_tree8_q15
// 功能说明：把 8 路 40 bit 局部累加结果通过三级平衡树归约为一个结果。
// 位宽增长：8×40 -> 4×41 -> 2×42 -> 1×43。
//           32 项 Q1.15 点积的真实结果最多需要 37 bit，故输出低 40 bit
//           保留完整数值；高 3 bit 只应为符号扩展。
// ============================================================================
module reduce_tree8_q15 (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       in_valid,
    input  logic signed [39:0]         partial_sum [0:7],
    output wire                        out_valid,
    output wire signed [39:0]          result
);

    logic signed [40:0] sum_l1 [0:3];
    logic signed [41:0] sum_l2 [0:1];
    logic signed [42:0] sum_l3;
    logic [2:0]         valid_pipe;

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '0;
            for (i = 0; i < 4; i = i + 1)
                sum_l1[i] <= '0;
            for (i = 0; i < 2; i = i + 1)
                sum_l2[i] <= '0;
            sum_l3 <= '0;
        end else begin
            valid_pipe[0] <= in_valid;
            valid_pipe[1] <= valid_pipe[0];
            valid_pipe[2] <= valid_pipe[1];

            // 第一级：8 路归约为 4 路。
            for (i = 0; i < 4; i = i + 1) begin
                sum_l1[i] <=
                    $signed({partial_sum[2*i][39],   partial_sum[2*i]}) +
                    $signed({partial_sum[2*i+1][39], partial_sum[2*i+1]});
            end

            // 第二级：4 路归约为 2 路。
            for (i = 0; i < 2; i = i + 1) begin
                sum_l2[i] <=
                    $signed({sum_l1[2*i][40],   sum_l1[2*i]}) +
                    $signed({sum_l1[2*i+1][40], sum_l1[2*i+1]});
            end

            // 第三级：得到完整的 43 bit 中间和。
            sum_l3 <= $signed({sum_l2[0][41], sum_l2[0]}) +
                      $signed({sum_l2[1][41], sum_l2[1]});
        end
    end

    assign out_valid = valid_pipe[2];
    assign result = sum_l3[39:0];

endmodule
