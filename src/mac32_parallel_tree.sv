`timescale 1ns/1ps

// ============================================================================
// Module  : mac32_parallel_tree
// Function: Fully parallel 32-element signed Q1.15 vector dot product.
//           result = sum(a_in[i] * b_in[i]), i = 0..31
// Author  : Codex
// Date    : 2026-09-07
// Version : 1.0
//
// Arithmetic:
//   input lane       : signed Q1.15, 16 bits
//   product          : signed Q2.30, 32 bits
//   exact 32-lane sum: signed Q7.30, 37 bits
//   output           : signed Q10.30, 40 bits (sign extension only)
//
// Pipeline contract:
//   S0 input register
//   S1 32 parallel multipliers
//   S2 16 x 33-bit partial sums
//   S3  8 x 34-bit partial sums
//   S4  4 x 35-bit partial sums
//   S5  2 x 36-bit partial sums
//   S6  1 x 37-bit exact sum
//   S7 40-bit output register
//
// An input sampled at rising edge N with in_valid=1 produces out_valid=1 and
// the matching result immediately after rising edge N+7. The initiation
// interval is one cycle; there is no output backpressure.
// ============================================================================
module mac32_parallel_tree (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       in_valid,
    input  logic signed [15:0]         a_in [0:31],
    input  logic signed [15:0]         b_in [0:31],
    output logic                       out_valid,
    output logic signed [39:0]         result
);

    // S0: registered input vectors.
    logic signed [15:0] a_s0 [0:31];
    logic signed [15:0] b_s0 [0:31];

    // S1: 16x16 products. Subsequent levels grow by one bit per reduction.
    logic signed [31:0] product_s1 [0:31];
    logic signed [32:0] sum_s2     [0:15];
    logic signed [33:0] sum_s3     [0:7];
    logic signed [34:0] sum_s4     [0:3];
    logic signed [35:0] sum_s5     [0:1];
    logic signed [36:0] sum_s6;

    // valid_pipe[0] corresponds to S0; valid_pipe[7] corresponds to S7.
    logic [7:0] valid_pipe;

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '0;
            result     <= '0;
            for (i = 0; i < 32; i = i + 1) begin
                a_s0[i]       <= '0;
                b_s0[i]       <= '0;
                product_s1[i] <= '0;
            end
            for (i = 0; i < 16; i = i + 1)
                sum_s2[i] <= '0;
            for (i = 0; i < 8; i = i + 1)
                sum_s3[i] <= '0;
            for (i = 0; i < 4; i = i + 1)
                sum_s4[i] <= '0;
            for (i = 0; i < 2; i = i + 1)
                sum_s5[i] <= '0;
            sum_s6 <= '0;
        end else begin
            // Control pipeline. Bubbles are represented only by valid bits;
            // datapath values during an invalid cycle are intentionally ignored.
            valid_pipe[0] <= in_valid;
            for (i = 1; i < 8; i = i + 1)
                valid_pipe[i] <= valid_pipe[i-1];

            // S0: capture the complete vector atomically. Zero injection on a
            // bubble reduces unnecessary unknown/switching propagation.
            for (i = 0; i < 32; i = i + 1) begin
                if (in_valid) begin
                    a_s0[i] <= a_in[i];
                    b_s0[i] <= b_in[i];
                end else begin
                    a_s0[i] <= '0;
                    b_s0[i] <= '0;
                end
            end

            // S1: 32 products in parallel. Explicit sign extension avoids
            // expression-sizing ambiguity in older Verilog/SystemVerilog tools.
            for (i = 0; i < 32; i = i + 1) begin
                product_s1[i] <=
                    $signed({{16{a_s0[i][15]}}, a_s0[i]}) *
                    $signed({{16{b_s0[i][15]}}, b_s0[i]});
            end

            // S2: 32 products -> 16 partial sums (33 bits).
            for (i = 0; i < 16; i = i + 1) begin
                sum_s2[i] <=
                    $signed({product_s1[2*i][31],   product_s1[2*i]}) +
                    $signed({product_s1[2*i+1][31], product_s1[2*i+1]});
            end

            // S3: 16 -> 8 partial sums (34 bits).
            for (i = 0; i < 8; i = i + 1) begin
                sum_s3[i] <=
                    $signed({sum_s2[2*i][32],   sum_s2[2*i]}) +
                    $signed({sum_s2[2*i+1][32], sum_s2[2*i+1]});
            end

            // S4: 8 -> 4 partial sums (35 bits).
            for (i = 0; i < 4; i = i + 1) begin
                sum_s4[i] <=
                    $signed({sum_s3[2*i][33],   sum_s3[2*i]}) +
                    $signed({sum_s3[2*i+1][33], sum_s3[2*i+1]});
            end

            // S5: 4 -> 2 partial sums (36 bits).
            for (i = 0; i < 2; i = i + 1) begin
                sum_s5[i] <=
                    $signed({sum_s4[2*i][34],   sum_s4[2*i]}) +
                    $signed({sum_s4[2*i+1][34], sum_s4[2*i+1]});
            end

            // S6: final exact 37-bit sum.
            sum_s6 <= $signed({sum_s5[0][35], sum_s5[0]}) +
                      $signed({sum_s5[1][35], sum_s5[1]});

            // S7: retain all 37 result bits and sign-extend to the 40-bit port.
            result <= {{3{sum_s6[36]}}, sum_s6};
        end
    end

    assign out_valid = valid_pipe[7];

endmodule
