`timescale 1ns/1ps

// ============================================================================
// 模块名称：mac_lane_q15
// 功能说明：单路 16 bit 有符号 Q1.15 流水乘加单元。
//           每个点积事务包含 4 个有效输入；first 用首个乘积覆盖累加器，
//           后续乘积执行累加，last 对应的乘积写入后产生 done 脉冲。
// 流水结构：输入乘法寄存一级，40 bit 累加寄存一级。
// ============================================================================
module mac_lane_q15 (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       in_valid,
    input  logic                       in_first,
    input  logic                       in_last,
    input  logic signed [15:0]         a_in,
    input  logic signed [15:0]         b_in,
    output logic                       done,
    output logic signed [39:0]         acc_out
);

    logic signed [31:0] product_d1;
    logic               valid_d1;
    logic               first_d1;
    logic               last_d1;
    logic signed [39:0] product_ext;

    // 32 bit Q2.30 乘积扩展到 40 bit 后进入累加器。
    always_comb begin
        product_ext = {{8{product_d1[31]}}, product_d1};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_d1 <= '0;
            valid_d1   <= 1'b0;
            first_d1   <= 1'b0;
            last_d1    <= 1'b0;
            done       <= 1'b0;
            acc_out    <= '0;
        end else begin
            // 第一级：乘法。显式扩展操作数，避免旧版工具的表达式位宽歧义。
            valid_d1 <= in_valid;
            first_d1 <= in_first;
            last_d1  <= in_last;
            if (in_valid) begin
                product_d1 <=
                    $signed({{16{a_in[15]}}, a_in}) *
                    $signed({{16{b_in[15]}}, b_in});
            end else begin
                product_d1 <= '0;
            end

            // 第二级：本地累加。首项直接覆盖，省去单独清零周期。
            done <= 1'b0;
            if (valid_d1) begin
                if (first_d1)
                    acc_out <= product_ext;
                else
                    acc_out <= acc_out + product_ext;
                done <= last_d1;
            end
        end
    end

endmodule
