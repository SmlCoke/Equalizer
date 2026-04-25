`timescale 1ns / 1ps
/*
 * 模块名称: equalizer
 * 作者: Equalizer 团队
 * 日期: 2026-04-18
 * 版本: v1.0
 *
 * 功能概述:
 *   11 阶均衡滤波器横向原始实现，使用最小二乘法设计，适用于高速通信系统中的信道均衡。
 *   滤波器冲激响应: y[n] = 0.96875*x[n] - 0.875*x[n-1] + 0.65625*x[n-3] - 0.5625*x[n-4] + 0.375*x[n-6] - 0.3125*x[n-7] + 0.1875*x[n-9] - 0.125*x[n-10]
 *   11 个系数中，有 3 个零值，因此：
 *
 * 计算复杂度分析: 
 *   - 8 个 INT8 乘法器 + 7 个 加法器
 *   - Baseline 版本不采用平衡加法树，因此加法器虽然数量一定，但是位宽偏大
 *
 * 版本定位:
 *   - v1.0 
 *     
 */

module equalizer #(
    parameter signed [7:0] multi_coeffs_0 = 8'sb00011111,  // tap 0 的系数，对应小数值 0.96875
    parameter signed [7:0] multi_coeffs_1 = 8'sb11100100,  // tap 1 的系数，对应小数值 -0.875
    parameter signed [7:0] multi_coeffs_2 = 8'sb00010101,  // tap 2 的系数，对应小数值 0.65625
    parameter signed [7:0] multi_coeffs_3 = 8'sb11101110,  // tap 3 的系数，对应小数值 -0.5625
    parameter signed [7:0] multi_coeffs_4 = 8'sb00001100,  // tap 4 的系数，对应小数值 0.375
    parameter signed [7:0] multi_coeffs_5 = 8'sb11110110,  // tap 5 的系数，对应小数值 -0.3125
    parameter signed [7:0] multi_coeffs_6 = 8'sb00000110,  // tap 6 的系数，对应小数值 0.1875
    parameter signed [7:0] multi_coeffs_7 = 8'sb11111100   // tap 7 的系数，对应小数值 -0.125
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               valid_in,       // 输入有效信号
    input  wire signed [7:0]  data_in,        // 输入信号，8 位有符号整数
    output reg                valid_out,      // 元数据，输出有效信号
    output reg  signed [22:0] data_out        // 输出信号，23 位有符号整数
);

    // 11 阶均衡器的移位寄存器，存储最近的 11 个输入数据
    reg signed [7:0] shift_data [0:10];    
    // 乘法器的输出
    wire signed [15:0] multi_out [0:7]; // 8 个乘法器的输出，每个输出 16 位

    // 加法器输出(注：此时并未采取平衡加法树)
    wire signed [16:0] add_out_0; // multi_out[0] + multi_out[1]
    wire signed [17:0] add_out_1; // add_out_0 + multi_out[2]
    wire signed [18:0] add_out_2; // add_out_1 + multi_out[3]
    wire signed [19:0] add_out_3; // add_out_2 + multi_out[4]
    wire signed [20:0] add_out_4; // add_out_3 + multi_out[5]
    wire signed [21:0] add_out_5; // add_out_4 + multi_out[6]
    wire signed [22:0] add_out_6; // add_out_5 + multi_out[7]

    // 输入数据寄存器移位逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时清空移位寄存器
            shift_data[0] <= 8'sb0;
            shift_data[1] <= 8'sb0;
            shift_data[2] <= 8'sb0;
            shift_data[3] <= 8'sb0;
            shift_data[4] <= 8'sb0;
            shift_data[5] <= 8'sb0;
            shift_data[6] <= 8'sb0;
            shift_data[7] <= 8'sb0;
            shift_data[8] <= 8'sb0;
            shift_data[9] <= 8'sb0;
            shift_data[10] <= 8'sb0;
        end else if (valid_in) begin
            // 数据输入有效时进行移位
            shift_data[10] <= shift_data[9];
            shift_data[9]  <= shift_data[8];
            shift_data[8]  <= shift_data[7];
            shift_data[7]  <= shift_data[6];
            shift_data[6]  <= shift_data[5];
            shift_data[5]  <= shift_data[4];
            shift_data[4]  <= shift_data[3];
            shift_data[3]  <= shift_data[2];
            shift_data[2]  <= shift_data[1];
            shift_data[1]  <= shift_data[0];
            shift_data[0]  <= data_in; // 新输入数据进入移位寄存器
        end
    end

    // 组合逻辑：乘法器
    assign multi_out[0] = shift_data[0] * multi_coeffs_0;
    assign multi_out[1] = shift_data[1] * multi_coeffs_1;
    assign multi_out[2] = shift_data[3] * multi_coeffs_2;
    assign multi_out[3] = shift_data[4] * multi_coeffs_3;
    assign multi_out[4] = shift_data[6] * multi_coeffs_4;
    assign multi_out[5] = shift_data[7] * multi_coeffs_5;
    assign multi_out[6] = shift_data[9] * multi_coeffs_6;
    assign multi_out[7] = shift_data[10] * multi_coeffs_7;

    // 组合逻辑：串行加法器
    assign add_out_0 = multi_out[0] + multi_out[1];
    assign add_out_1 = add_out_0 + multi_out[2];
    assign add_out_2 = add_out_1 + multi_out[3];
    assign add_out_3 = add_out_2 + multi_out[4];
    assign add_out_4 = add_out_3 + multi_out[5];
    assign add_out_5 = add_out_4 + multi_out[6];
    assign add_out_6 = add_out_5 + multi_out[7];

    // valid 要打拍一次才能和数据输出对齐，
    // 因为数据输出需要采样 shift_data 的旧值，而 valid 是采样当前输入的 valid_in
    reg valid_pipe;
    
    // 数据输出寄存器打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 1'b0;
            valid_out <= 1'b0;
            data_out  <= 23'sb0;
        end else begin
            valid_pipe <= valid_in;
            valid_out <= valid_pipe;
            data_out  <= add_out_6;
        end
    end
endmodule
