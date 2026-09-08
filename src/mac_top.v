`timescale 1ns/1ps

// ============================================================================
// 文件名称：mac_top.v
// 模块名称：mac_top
// 功能说明：FPGA 自运行展示顶层。复位释放后自动向 8 路 MAC 核发送
//           1..32，两侧输入相同，从而计算 1^2+2^2+...+32^2。
//           结果等于 TARGET 时 LED 锁存点亮，直到下一次复位。
// 设计语言：Verilog-2001
// 作者：changting
// 日期：2026-09-08
// 版本：1.0
// ============================================================================
module mac_top #(
    parameter DATA_W = 16,
    parameter ACC_W  = 40,
    parameter N      = 32,
    parameter EN_GAP = 0,
    parameter [ACC_W-1:0] TARGET = 40'd11440
) (
    input  wire clk,
    input  wire rst_n,
    output reg  led
);

    localparam [1:0] SEND_DATA   = 2'd0;
    localparam [1:0] WAIT_RESULT = 2'd1;
    localparam [1:0] FINISHED    = 2'd2;

    reg  [1:0]              state;
    reg  [1:0]              beat_count;
    reg                     gap_cycle;
    reg  [(8*DATA_W)-1:0]   data_bus;

    wire                    start;
    wire                    in_valid;
    wire                    in_ready;
    wire                    result_valid;
    wire                    busy;
    wire signed [ACC_W-1:0] acc_out;

    // 当前拍的 8 个操作数。最低 16 bit 对应 lane 0。
    always @* begin
        case (beat_count)
            2'd0: data_bus = {16'd8,  16'd7,  16'd6,  16'd5,
                              16'd4,  16'd3,  16'd2,  16'd1};
            2'd1: data_bus = {16'd16, 16'd15, 16'd14, 16'd13,
                              16'd12, 16'd11, 16'd10, 16'd9};
            2'd2: data_bus = {16'd24, 16'd23, 16'd22, 16'd21,
                              16'd20, 16'd19, 16'd18, 16'd17};
            default:
                   data_bus = {16'd32, 16'd31, 16'd30, 16'd29,
                               16'd28, 16'd27, 16'd26, 16'd25};
        endcase
    end

    assign in_valid = (state == SEND_DATA) && !gap_cycle;
    assign start    = in_valid && (beat_count == 2'd0);

    mac32_8lane_top u_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .a_in(data_bus),
        .b_in(data_bus),
        .result_valid(result_valid),
        .busy(busy),
        .result(acc_out)
    );

    // 只执行一次演示事务；EN_GAP 非零时在相邻有效拍之间插入一个空拍。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= SEND_DATA;
            beat_count <= 2'd0;
            gap_cycle  <= 1'b0;
            led        <= 1'b0;
        end else begin
            case (state)
                SEND_DATA: begin
                    if (gap_cycle) begin
                        gap_cycle <= 1'b0;
                    end else if (in_ready) begin
                        if (beat_count == 2'd3) begin
                            state <= WAIT_RESULT;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                            if (EN_GAP != 0)
                                gap_cycle <= 1'b1;
                        end
                    end
                end

                WAIT_RESULT: begin
                    if (result_valid) begin
                        if (acc_out == TARGET)
                            led <= 1'b1;
                        else
                            led <= 1'b0;
                        state <= FINISHED;
                    end
                end

                FINISHED: begin
                    state <= FINISHED;
                end

                default: begin
                    state      <= SEND_DATA;
                    beat_count <= 2'd0;
                    gap_cycle  <= 1'b0;
                    led        <= 1'b0;
                end
            endcase
        end
    end

endmodule
