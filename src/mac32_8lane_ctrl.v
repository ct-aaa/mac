`timescale 1ns/1ps

// ============================================================================
// 文件名称：mac32_8lane_ctrl.v
// 模块名称：mac32_8lane_ctrl
// 功能说明：8 路 MAC 点积核的事务控制器。
//           一个事务接收 4 个有效 beat，每个 beat 包含 8 对操作数。
//           in_valid=0 的周期作为气泡，不增加 beat 计数。
// 设计语言：Verilog-2001
// 作者：changting
// 日期：2026-09-08
// 版本：1.1
// ============================================================================
module mac32_8lane_ctrl (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire in_valid,
    input  wire result_valid,
    output reg  in_ready,
    output reg  lane_valid,
    output reg  lane_first,
    output reg  lane_last,
    output reg  busy
);

    localparam [1:0] IDLE        = 2'd0;
    localparam [1:0] LOAD        = 2'd1;
    localparam [1:0] WAIT_RESULT = 2'd2;

    reg [1:0] state;
    reg [1:0] beat_count;
    reg       accept_first;
    reg       accept_load;

    // 译码握手条件，并向 8 路 MAC 广播统一的有效与边界标志。
    always @* begin
        in_ready = (state == IDLE) || (state == LOAD) ||
                   ((state == WAIT_RESULT) && result_valid);
        accept_first = in_valid && start &&
                       ((state == IDLE) ||
                        ((state == WAIT_RESULT) && result_valid));
        accept_load = in_valid && (state == LOAD);

        lane_valid = accept_first || accept_load;
        lane_first = accept_first;
        lane_last  = accept_load && (beat_count == 2'd3);
        busy = (state != IDLE) && !result_valid;
    end

    // 四拍输入事务状态转换。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            beat_count <= 2'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (accept_first) begin
                        state      <= LOAD;
                        beat_count <= 2'd1;
                    end
                end

                LOAD: begin
                    if (accept_load) begin
                        if (beat_count == 2'd3) begin
                            state <= WAIT_RESULT;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                WAIT_RESULT: begin
                    if (result_valid) begin
                        if (accept_first) begin
                            state      <= LOAD;
                            beat_count <= 2'd1;
                        end else begin
                            state      <= IDLE;
                            beat_count <= 2'd0;
                        end
                    end
                end

                default: begin
                    state      <= IDLE;
                    beat_count <= 2'd0;
                end
            endcase
        end
    end

endmodule
