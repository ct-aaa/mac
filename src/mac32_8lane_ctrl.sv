`timescale 1ns/1ps

// ============================================================================
// 文件名称：mac32_8lane_ctrl.sv
// 模块名称：mac32_8lane_ctrl
// 功能说明：8 路 MAC 点积核的事务控制器。
//           一个事务接收 4 个有效 beat，每个 beat 包含 8 对操作数。
//           in_valid=0 的周期作为气泡，不增加 beat 计数。
// 设计语言：SystemVerilog
// 设计风格：可综合、单时钟同步时序、低有效异步复位、无锁存器
// 作者：changting
// 日期：2026-09-08
// 版本：1.0
// ============================================================================
module mac32_8lane_ctrl (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic in_valid,
    input  logic result_valid,
    output logic in_ready,
    output logic lane_valid,
    output logic lane_first,
    output logic lane_last,
    output logic busy
);

    localparam logic [1:0] IDLE = 2'd0;
    localparam logic [1:0] LOAD = 2'd1;
    localparam logic [1:0] WAIT_RESULT = 2'd2;

    logic [1:0] state;
    logic [1:0] beat_count;
    logic       accept_first;
    logic       accept_load;

    // ------------------------------------------------------------------------
    // 组合功能：译码握手条件，并向 8 路 MAC 广播统一的有效与边界标志。
    // 所有组合输出均在本块内完整赋值，避免推断锁存器。
    // ------------------------------------------------------------------------
    always_comb begin
        // result_valid 周期允许上游准备下一事务，实现最短 8 周期启动间隔。
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

    // ------------------------------------------------------------------------
    // 状态转换：
    //   IDLE        等待带 start 的首拍；
    //   LOAD        接收剩余三个有效拍，气泡周期保持状态和计数；
    //   WAIT_RESULT 等待归约结果，并允许结果周期接收下一事务首拍。
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            beat_count <= 2'd0;
        end else begin
            case (state)
                // 空闲阶段：只接受同时具有 start 和 in_valid 的事务首拍。
                IDLE: begin
                    if (accept_first) begin
                        state      <= LOAD;
                        beat_count <= 2'd1;
                    end
                end

                // 输入阶段：累计有效 beat，第四拍完成后等待计算结果。
                LOAD: begin
                    if (accept_load) begin
                        if (beat_count == 2'd3) begin
                            state <= WAIT_RESULT;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                // 等待阶段：结果有效后返回空闲或无缝启动下一事务。
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
