`timescale 1ns/1ps

// ============================================================================
// 文件名称：mac32_8lane_top.v
// 模块名称：mac32_8lane_top
// 功能说明：8 路 MAC、4 beat 输入的 32 项 Q1.15 点积顶层。
//           a_in/b_in 各为 128 bit 展平总线，[16*i +: 16] 对应 lane i。
// 设计语言：Verilog-2001
// 作者：changting
// 日期：2026-09-08
// 版本：1.1
// ============================================================================
module mac32_8lane_top (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,
    input  wire                       in_valid,
    output wire                       in_ready,
    input  wire [127:0]               a_in,
    input  wire [127:0]               b_in,
    output wire                       result_valid,
    output wire                       busy,
    output wire signed [39:0]         result
);

    wire         lane_valid;
    wire         lane_first;
    wire         lane_last;
    wire [7:0]   lane_done;
    wire [319:0] lane_acc;
    wire         all_lanes_done;

    mac32_8lane_ctrl u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .in_valid(in_valid),
        .result_valid(result_valid),
        .in_ready(in_ready),
        .lane_valid(lane_valid),
        .lane_first(lane_first),
        .lane_last(lane_last),
        .busy(busy)
    );

    // 8 个完全相同的流水 MAC 单元；generate 为结构展开，不是过程式循环。
    genvar lane;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : g_mac_lanes
            mac_lane_q15 u_lane (
                .clk(clk),
                .rst_n(rst_n),
                .in_valid(lane_valid),
                .in_first(lane_first),
                .in_last(lane_last),
                .a_in(a_in[(lane*16) +: 16]),
                .b_in(b_in[(lane*16) +: 16]),
                .done(lane_done[lane]),
                .acc_out(lane_acc[(lane*40) +: 40])
            );
        end
    endgenerate

    assign all_lanes_done = lane_done[0] & lane_done[1] & lane_done[2] &
                            lane_done[3] & lane_done[4] & lane_done[5] &
                            lane_done[6] & lane_done[7];

    reduce_tree8_q15 u_reduce_tree (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(all_lanes_done),
        .partial_sum(lane_acc),
        .out_valid(result_valid),
        .result(result)
    );

endmodule
