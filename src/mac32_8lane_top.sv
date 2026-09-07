`timescale 1ns/1ps

// ============================================================================
// 文件名称：mac32_8lane_top.sv
// 模块名称：mac32_8lane_top
// 功能说明：8 路 MAC、4 beat 输入的 32 项 Q1.15 点积顶层。
//           控制通路与数据通路分离：控制器管理输入事务，8 路 MAC 完成
//           四拍局部累加，三级平衡加法树完成全局归约。
//
// 输入映射：
//   beat 0 -> 向量元素  0.. 7
//   beat 1 -> 向量元素  8..15
//   beat 2 -> 向量元素 16..23
//   beat 3 -> 向量元素 24..31
//
// 无气泡时序：连续 4 周期输入，乘法/本地累加排空 1 周期，三级归约；
//             首个输入采样边沿到 result_valid 相隔 7 个周期，最短 II=8。
// 设计语言：SystemVerilog
// 设计风格：可综合、单时钟同步时序、低有效异步复位、无锁存器
// 作者：changting
// 日期：2026-09-08
// 版本：1.0
// ============================================================================
module mac32_8lane_top (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       start,
    input  logic                       in_valid,
    output logic                       in_ready,
    input  logic signed [15:0]         a_in [0:7],
    input  logic signed [15:0]         b_in [0:7],
    output wire                        result_valid,
    output logic                       busy,
    output wire signed [39:0]          result
);

    logic lane_valid;
    logic lane_first;
    logic lane_last;
    wire  lane_done [0:7];
    wire signed [39:0] lane_acc [0:7];
    wire all_lanes_done;

    // ------------------------------------------------------------------------
    // 控制模块：处理 start/in_valid/in_ready 握手、有效拍计数和忙状态。
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // 数据通路：生成 8 个结构完全相同的 Q1.15 流水 MAC 单元。
    // 每个单元在四个有效拍内负责向量中固定模 8 位置的四项乘加。
    // ------------------------------------------------------------------------
    genvar lane;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : g_mac_lanes
            mac_lane_q15 u_lane (
                .clk(clk),
                .rst_n(rst_n),
                .in_valid(lane_valid),
                .in_first(lane_first),
                .in_last(lane_last),
                .a_in(a_in[lane]),
                .b_in(b_in[lane]),
                .done(lane_done[lane]),
                .acc_out(lane_acc[lane])
            );
        end
    endgenerate

    // 完成汇聚：8 路在同一周期结束，统一触发后级平衡加法树。
    assign all_lanes_done = lane_done[0] & lane_done[1] & lane_done[2] & lane_done[3] &
                            lane_done[4] & lane_done[5] & lane_done[6] & lane_done[7];

    // ------------------------------------------------------------------------
    // 结果归约：将 8 个 40 bit 局部累加值通过三级流水树求和。
    // ------------------------------------------------------------------------
    reduce_tree8_q15 u_reduce_tree (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(all_lanes_done),
        .partial_sum(lane_acc),
        .out_valid(result_valid),
        .result(result)
    );

endmodule
