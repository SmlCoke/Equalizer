`timescale 1ns / 1ps
/*
 * 模块名称: equalizer
 * 作者: Equalizer 团队
 * 日期: 2026-04-18
 * 版本: v1.0
 *
 * 功能概述:
 *   11 阶均衡滤波器，脉动阵列实现
 *
 * 计算复杂度分析: 
 *   - 乘法器数量: 8 个（对应 8 个非零抽头）
 *   - 加法器数量: 7 个
 * 
 * 关键路径分析: 
 *   - 1 Mult + 1 Add
 *   - 后续可以在 Mult 单元和 Add 单元之间插入寄存器来打断关键路径，达到更高的时钟频率。
 * 
 * 版本定位:
 *   - v1.0 实现了基本的功能，满足正确性要求。 
 *     
 */

module equalizer_systolic #(
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

    integer i;
    
    // 乘法器的输出
    wire signed [15:0] multi_out [0:7]; // 8 个乘法器的输出，每个输出 16 位
    // 加法器输出
    wire signed [22:0] add_out [0:6]; // 7 个加法器的输出，每个输出 23 位
        // 10 级移位寄存器，打断串行加法器的关键路径
    reg signed [22:0] shift_data [0:9];
    
    // 输入数据打拍寄存
    reg valid_in_reg;
    reg signed [7:0] data_in_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_in_reg <= 1'b0;
            data_in_reg  <= 8'sb0;
        end else begin
            valid_in_reg <= valid_in;
            data_in_reg  <= data_in;
        end
    end

    // 乘法器逻辑：输入广播到所有乘法器
    assign multi_out[0] = data_in_reg * multi_coeffs_0; // x[n] * h[0]
    assign multi_out[1] = data_in_reg * multi_coeffs_1; // x[n] * h[1]
    assign multi_out[2] = data_in_reg * multi_coeffs_2; // x[n] * h[2]
    assign multi_out[3] = data_in_reg * multi_coeffs_3; // x[n] * h[3]
    assign multi_out[4] = data_in_reg * multi_coeffs_4; // x[n] * h[4]
    assign multi_out[5] = data_in_reg * multi_coeffs_5; // x[n] * h[5]
    assign multi_out[6] = data_in_reg * multi_coeffs_6; // x[n] * h[6]
    assign multi_out[7] = data_in_reg * multi_coeffs_7; // x[n] * h[7]

    // 加法器逻辑：与移位寄存器中的数据进行累加
    assign add_out[0] = multi_out[0] + shift_data[9];
    assign add_out[1] = multi_out[1] + shift_data[8]; 
    assign add_out[2] = multi_out[2] + shift_data[6];
    assign add_out[3] = multi_out[3] + shift_data[5];
    assign add_out[4] = multi_out[4] + shift_data[3];
    assign add_out[5] = multi_out[5] + shift_data[2];
    assign add_out[6] = multi_out[6] + shift_data[0];


    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 10; i = i + 1) begin
                shift_data[i] <= 23'sb0;
            end
        end else if (valid_in_reg) begin
            // 仅当输入有效时进行数据移位，否则冻结移位寄存器，防止无效数据进入计算
            shift_data[0] <= multi_out[7];
            shift_data[1] <= add_out[6];
            shift_data[2] <= shift_data[1];
            shift_data[3] <= add_out[5];
            shift_data[4] <= add_out[4];
            shift_data[5] <= shift_data[4];
            shift_data[6] <= add_out[3];
            shift_data[7] <= add_out[2];
            shift_data[8] <= shift_data[7];
            shift_data[9] <= add_out[1];
        end
    end

    // 输出逻辑：输出必须被打一拍寄存，以隔离组合电路的半周期竞争与 Testbench 的错位采样
    // Testbench 中，往往在时钟下降沿给数据，此时组合逻辑会直接计算出 valid_out = 1 ，导致错误
    // 事实上，输出往往应该打拍寄存
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            data_out  <= 23'sd0;
        end else begin
            valid_out <= valid_in_reg;
            if (valid_in_reg) begin
                data_out <= add_out[0];
            end
        end
    end
endmodule
