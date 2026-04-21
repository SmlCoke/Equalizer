`timescale 1ns / 1ps
/*
 * 模块名: equalizer_unfolding_n2
 * 功能说明:
 *   基于 11 阶稀疏抽头均衡器的 N=2 展开实现。
 *   每个有效周期并行输入两个连续采样点:
 *     data_in_even = x[2k], data_in_odd = x[2k+1]
 *   并行输出两个滤波结果:
 *     data_out_even = y[2k], data_out_odd = y[2k+1]
 *
 * 原始非零抽头响应:
 *   y[n] = h0*x[n] + h1*x[n-1] + h2*x[n-3] + h3*x[n-4]
 *        + h4*x[n-6] + h5*x[n-7] + h6*x[n-9] + h7*x[n-10]
 */

module equalizer_unfolding_n2 #(
    parameter signed [7:0] multi_coeffs_0 = 8'sb00011111,  // h0
    parameter signed [7:0] multi_coeffs_1 = 8'sb11100100,  // h1
    parameter signed [7:0] multi_coeffs_2 = 8'sb00010101,  // h2
    parameter signed [7:0] multi_coeffs_3 = 8'sb11101110,  // h3
    parameter signed [7:0] multi_coeffs_4 = 8'sb00001100,  // h4
    parameter signed [7:0] multi_coeffs_5 = 8'sb11110110,  // h5
    parameter signed [7:0] multi_coeffs_6 = 8'sb00000110,  // h6
    parameter signed [7:0] multi_coeffs_7 = 8'sb11111100   // h7
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               valid_in,
    input  wire signed [7:0]  data_in_even,  // 偶序列输入 x[2k]
    input  wire signed [7:0]  data_in_odd,   // 奇序列输入 x[2k+1]
    output wire               valid_out,
    output wire signed [18:0] data_out_even, // 偶序列输出 y[2k]
    output wire signed [18:0] data_out_odd   // 奇序列输出 y[2k+1]
);

    // 抽取后的历史样本缓存:
    // x_even_d[i] = x[2k-2i], x_odd_d[i] = x[2k+1-2i]
    reg signed [7:0] x_even_d [0:5];
    reg signed [7:0] x_odd_d  [0:5];

    // 偶/奇两路各 8 项乘法
    wire signed [15:0] m_even [0:7];
    wire signed [15:0] m_odd  [0:7];

    // 偶路平衡加法树
    wire signed [16:0] ps1_even [0:3];
    wire signed [17:0] ps2_even [0:1];

    // 奇路平衡加法树
    wire signed [16:0] ps1_odd [0:3];
    wire signed [17:0] ps2_odd [0:1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 6; i = i + 1) begin
                x_even_d[i] <= 8'sb0;
                x_odd_d[i]  <= 8'sb0;
            end
        end else if (valid_in) begin
            x_even_d[5] <= x_even_d[4];
            x_even_d[4] <= x_even_d[3];
            x_even_d[3] <= x_even_d[2];
            x_even_d[2] <= x_even_d[1];
            x_even_d[1] <= x_even_d[0];
            x_even_d[0] <= data_in_even;

            x_odd_d[5] <= x_odd_d[4];
            x_odd_d[4] <= x_odd_d[3];
            x_odd_d[3] <= x_odd_d[2];
            x_odd_d[2] <= x_odd_d[1];
            x_odd_d[1] <= x_odd_d[0];
            x_odd_d[0] <= data_in_odd;
        end
    end

    assign valid_out = valid_in;

    // 偶路输出方程:
    // y[2k] = h0*xe[k] + h1*xo[k-1] + h2*xo[k-2] + h3*xe[k-2]
    //       + h4*xe[k-3] + h5*xo[k-4] + h6*xo[k-5] + h7*xe[k-5]
    assign m_even[0] = x_even_d[0] * multi_coeffs_0;
    assign m_even[1] = x_odd_d[1]  * multi_coeffs_1;
    assign m_even[2] = x_odd_d[2]  * multi_coeffs_2;
    assign m_even[3] = x_even_d[2] * multi_coeffs_3;
    assign m_even[4] = x_even_d[3] * multi_coeffs_4;
    assign m_even[5] = x_odd_d[4]  * multi_coeffs_5;
    assign m_even[6] = x_odd_d[5]  * multi_coeffs_6;
    assign m_even[7] = x_even_d[5] * multi_coeffs_7;

    // 奇路输出方程:
    // y[2k+1] = h0*xo[k] + h1*xe[k] + h2*xe[k-1] + h3*xo[k-2]
    //         + h4*xo[k-3] + h5*xe[k-3] + h6*xe[k-4] + h7*xo[k-5]
    assign m_odd[0] = x_odd_d[0]  * multi_coeffs_0;
    assign m_odd[1] = x_even_d[0] * multi_coeffs_1;
    assign m_odd[2] = x_even_d[1] * multi_coeffs_2;
    assign m_odd[3] = x_odd_d[2]  * multi_coeffs_3;
    assign m_odd[4] = x_odd_d[3]  * multi_coeffs_4;
    assign m_odd[5] = x_even_d[3] * multi_coeffs_5;
    assign m_odd[6] = x_even_d[4] * multi_coeffs_6;
    assign m_odd[7] = x_odd_d[5]  * multi_coeffs_7;

    // 偶路加法树
    assign ps1_even[0] = m_even[0] + m_even[1];
    assign ps1_even[1] = m_even[2] + m_even[3];
    assign ps1_even[2] = m_even[4] + m_even[5];
    assign ps1_even[3] = m_even[6] + m_even[7];
    assign ps2_even[0] = ps1_even[0] + ps1_even[1];
    assign ps2_even[1] = ps1_even[2] + ps1_even[3];
    assign data_out_even = ps2_even[0] + ps2_even[1];

    // 奇路加法树
    assign ps1_odd[0] = m_odd[0] + m_odd[1];
    assign ps1_odd[1] = m_odd[2] + m_odd[3];
    assign ps1_odd[2] = m_odd[4] + m_odd[5];
    assign ps1_odd[3] = m_odd[6] + m_odd[7];
    assign ps2_odd[0] = ps1_odd[0] + ps1_odd[1];
    assign ps2_odd[1] = ps1_odd[2] + ps1_odd[3];
    assign data_out_odd = ps2_odd[0] + ps2_odd[1];

endmodule
