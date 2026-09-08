`timescale 1ns/1ps

// ============================================================================
// 文件名称：reduce_tree8_q15.v
// 模块名称：reduce_tree8_q15
// 功能说明：把展平总线中的 8 路 40 bit 局部和通过三级平衡树归约。
// 位宽增长：8x40 -> 4x41 -> 2x42 -> 1x43。
// 设计语言：Verilog-2001
// 作者：changting
// 日期：2026-09-08
// 版本：1.1
// ============================================================================
module reduce_tree8_q15 (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    input  wire [319:0]               partial_sum,
    output wire                       out_valid,
    output wire signed [39:0]         result
);

    wire signed [39:0] partial_sum_0;
    wire signed [39:0] partial_sum_1;
    wire signed [39:0] partial_sum_2;
    wire signed [39:0] partial_sum_3;
    wire signed [39:0] partial_sum_4;
    wire signed [39:0] partial_sum_5;
    wire signed [39:0] partial_sum_6;
    wire signed [39:0] partial_sum_7;

    reg signed [40:0] sum_l1_0;
    reg signed [40:0] sum_l1_1;
    reg signed [40:0] sum_l1_2;
    reg signed [40:0] sum_l1_3;
    reg signed [41:0] sum_l2_0;
    reg signed [41:0] sum_l2_1;
    reg signed [42:0] sum_l3;
    reg        [2:0]  valid_pipe;

    assign partial_sum_0 = partial_sum[ 39:  0];
    assign partial_sum_1 = partial_sum[ 79: 40];
    assign partial_sum_2 = partial_sum[119: 80];
    assign partial_sum_3 = partial_sum[159:120];
    assign partial_sum_4 = partial_sum[199:160];
    assign partial_sum_5 = partial_sum[239:200];
    assign partial_sum_6 = partial_sum[279:240];
    assign partial_sum_7 = partial_sum[319:280];

    // 三级流水归约；每一级增加 1 bit，避免中间加法溢出。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 3'b000;
            sum_l1_0   <= 41'sd0;
            sum_l1_1   <= 41'sd0;
            sum_l1_2   <= 41'sd0;
            sum_l1_3   <= 41'sd0;
            sum_l2_0   <= 42'sd0;
            sum_l2_1   <= 42'sd0;
            sum_l3     <= 43'sd0;
        end else begin
            valid_pipe[0] <= in_valid;
            valid_pipe[1] <= valid_pipe[0];
            valid_pipe[2] <= valid_pipe[1];

            sum_l1_0 <= $signed({partial_sum_0[39], partial_sum_0}) +
                        $signed({partial_sum_1[39], partial_sum_1});
            sum_l1_1 <= $signed({partial_sum_2[39], partial_sum_2}) +
                        $signed({partial_sum_3[39], partial_sum_3});
            sum_l1_2 <= $signed({partial_sum_4[39], partial_sum_4}) +
                        $signed({partial_sum_5[39], partial_sum_5});
            sum_l1_3 <= $signed({partial_sum_6[39], partial_sum_6}) +
                        $signed({partial_sum_7[39], partial_sum_7});

            sum_l2_0 <= $signed({sum_l1_0[40], sum_l1_0}) +
                        $signed({sum_l1_1[40], sum_l1_1});
            sum_l2_1 <= $signed({sum_l1_2[40], sum_l1_2}) +
                        $signed({sum_l1_3[40], sum_l1_3});

            sum_l3 <= $signed({sum_l2_0[41], sum_l2_0}) +
                      $signed({sum_l2_1[41], sum_l2_1});
        end
    end

    assign out_valid = valid_pipe[2];
    assign result    = sum_l3[39:0];

endmodule
