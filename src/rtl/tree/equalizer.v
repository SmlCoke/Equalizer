`timescale 1ns / 1ps
/*
 * 模块名称: equalizer
 * 作者: Equalizer 团队
 * 日期: 2026-04-18
 * 版本: v1.0
 *
 * 功能概述:
 *   11 阶均衡滤波器横向原始实现，使用最小二乘法设计，适用于高速通信系统中的信道均衡。
 *   11 个系数中，有 3 个零值，因此：
 *
 * 计算复杂度分析: 
 *   - 8 个 INT8 乘法器 + 7 个 加法器
 *   - tree 版本采用了平衡加法树，稍微减小了中间结果位宽、输出结果
 *     位宽以及关键路径长度
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
    output wire               valid_out,      // 元数据，输出有效信号
    output wire signed [18:0] data_out        // 输出信号，19 位有符号整数
);

    // 11 阶均衡器的移位寄存器，存储最近的 11 个输入数据
    reg signed [7:0] shift_data [0:10];    
    // 乘法器的输出
    wire signed [15:0] multi_out [0:7]; // 8 个乘法器的输出，每个输出 16 位

    // 加法器输出(注：采用了平衡加法树)
    // 加法树第一级结果
    wire signed [16:0] partial_sum_1 [0:3];
    // 加法树第二级结果
    wire signed [17:0] partial_sum_2 [0:1];
    // 加法树第三级结果就是最终输出

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

    // 当前实现的 data_out 是组合结果，因此 valid_out 直接跟随输入有效。
    assign valid_out = valid_in;

    // 组合逻辑：乘法器
    assign multi_out[0] = shift_data[0] * multi_coeffs_0;
    assign multi_out[1] = shift_data[1] * multi_coeffs_1;
    assign multi_out[2] = shift_data[3] * multi_coeffs_2;
    assign multi_out[3] = shift_data[4] * multi_coeffs_3;
    assign multi_out[4] = shift_data[6] * multi_coeffs_4;
    assign multi_out[5] = shift_data[7] * multi_coeffs_5;
    assign multi_out[6] = shift_data[9] * multi_coeffs_6;
    assign multi_out[7] = shift_data[10] * multi_coeffs_7;

    // 组合逻辑：三级加法树
    // 第一级加法树: INT16 + INT16 = INT17
    assign partial_sum_1[0] = multi_out[0] + multi_out[1]; // 17 位
    assign partial_sum_1[1] = multi_out[2] + multi_out[3]; // 17 位
    assign partial_sum_1[2] = multi_out[4] + multi_out[5]; // 17 位
    assign partial_sum_1[3] = multi_out[6] + multi_out[7]; // 17 位

    // 第二级加法树: INT17 + INT17 = INT18
    assign partial_sum_2[0] = partial_sum_1[0] + partial_sum_1[1]; // 18 位
    assign partial_sum_2[1] = partial_sum_1[2] + partial_sum_1[3]; // 18 位

    // 第三级加法树: INT18 + INT18 = INT19
    assign data_out = partial_sum_2[0] + partial_sum_2[1]; // 19 位
endmodule
