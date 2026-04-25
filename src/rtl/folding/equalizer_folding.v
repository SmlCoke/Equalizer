`timescale 1ns / 1ps
/*
 * 模块名称: equalizer
 * 作者: Equalizer 团队
 * 日期: 2026-04-21
 * 版本: v1.0
 *
 * 功能概述:
 *   11 阶均衡滤波器横向原始实现，使用最小二乘法设计，适用于高速通信系统中的信道均衡。
 *   滤波器冲激响应: 
 *     y[n] = 0.96875 * x[n] 
 *          - 0.875   * x[n-1] 
 *          + 0.65625 * x[n-3] 
 *          - 0.5625  * x[n-4] 
 *          + 0.375   * x[n-6] 
 *          - 0.3125  * x[n-7] 
 *          + 0.1875  * x[n-9] 
 *          - 0.125   * x[n-10]
 *   示例计算：
 *     y[0] = 0.96875 * x[0]
 *     y[1] = 0.96875 * x[1] - 0.875 * x[0]
 *     y[2] = 0.96875 * x[2] - 0.875 * x[1]
 *
 *   在原始有限长横向滤波器的基础上，选择折叠因子为 8 的折叠技术进行优化。
 *   采样频率会降低为原来的 1/8，但每个输入样本的处理时间会增加到 8 个时钟周期。
 *   当且仅当 输入数据为
 *
 * 计算复杂度分析: 
 *   - 1 个 INT8 乘法器 + 1 个 加法器
 *   
 * 版本定位:
 *   - v1.0 
 *     
 */

module equalizer_folding #(
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


    // ------------------- 1. 数据移位寄存器 (Data Delay Line) -------------------
    // 构造出输入的数据移位寄存器，构造出 x[n], x[n-2], x[n-3], x[n-5], x[n-6], x[n-8], x[n-9] 的数据路径。
    // 我们将 x[n] 作为 shift_data[0]
    reg signed [7:0] shift_data [0:9];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<10; i=i+1) begin
                shift_data[i] <= 8'sd0;
            end
        end else if (valid_in) begin
            // shift_data[0] 作为起点，即选通 乘法器在 {0,1} 时的选通输入
            shift_data[0] <= data_in;
            // 当且仅当输入有效时，发生一次移位
            for (i=1; i<10; i=i+1) begin
                shift_data[i] <= shift_data[i-1];
            end
        end
    end

    // ------------------- 2. 折叠控制状态机，只有 8 个状态 -------------------
    // 当 valid_in 脉冲到来时，启动连续 8 个周期的乘加运算。
    // 这里无需用三段式有限状态机写法，因为折叠电路中各个状态机的转换逻辑很简单
    reg [2:0] fold_cnt;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fold_cnt <= 3'b000; // 初始状态
        end else begin
            if (valid_in) begin
                fold_cnt <= 3'b000; // 接到有效数据，开始第 0 个周期
            end else if (fold_cnt == 3'b111) begin
                fold_cnt <= 3'b000; // 第 7 个周期结束，回到初始状态
            end else begin
                fold_cnt <= fold_cnt + 1;
            end
        end
    end

    reg active; // 表示当前是否处于输入状态（防止 valid_out 信号在非输入状态下被激活）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
        end else if (valid_in) begin
            active <= 1'b1;
        end else if (fold_cnt == 3'b111) begin
            active <= 1'b0; // 在第 7 个周期结束时，回到非输入状态
        end
    end

    // ------------------- 3. 乘法器及乘法器输出的移位寄存器 -------------------
    // 乘法器的输入数据和系数
    reg signed [7:0] mux_data;
    reg signed [7:0] mux_coeff;
    
    always @(*) begin
        case (fold_cnt)
            3'b000: begin mux_data = shift_data[0];  mux_coeff = multi_coeffs_0; end
            3'b001: begin mux_data = shift_data[0];  mux_coeff = multi_coeffs_1; end
            3'b010: begin mux_data = shift_data[2];  mux_coeff = multi_coeffs_2; end
            3'b011: begin mux_data = shift_data[3];  mux_coeff = multi_coeffs_3; end
            3'b100: begin mux_data = shift_data[5];  mux_coeff = multi_coeffs_4; end
            3'b101: begin mux_data = shift_data[6];  mux_coeff = multi_coeffs_5; end
            3'b110: begin mux_data = shift_data[8];  mux_coeff = multi_coeffs_6; end
            3'b111: begin mux_data = shift_data[9];  mux_coeff = multi_coeffs_7; end
            default: begin mux_data = 8'sd0;       mux_coeff = 8'sd0;          end
        endcase
    end

    // 组合逻辑的乘法器 
    wire signed [15:0] mult_out;
    assign mult_out = mux_data * mux_coeff;
    
    reg signed [15:0] mult_out_d [0:7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<8; i=i+1) begin
                mult_out_d[i] <= 16'sd0;
            end
        end else begin
            mult_out_d[0] <= mult_out;
            for (i=1; i<8; i=i+1) begin
                mult_out_d[i] <= mult_out_d[i-1];
            end
        end
    end

    // ------------------- 4. 加法器 -------------------
    // 加法器的输入数据
    reg  signed [22:0] add_in_1;
    reg  signed [22:0] add_in_2;
    wire signed [22:0] add_out;
    reg  signed [22:0] add_out_d;

    always @(*) begin
        case (fold_cnt)
            3'b000:  begin add_in_1 = 23'sd0;        add_in_2 = 23'sd0;         end
            3'b001:  begin add_in_1 = mult_out_d[0]; add_in_2 = mult_out_d[7];  end
            3'b010:  begin add_in_1 = add_out_d;     add_in_2 = mult_out_d[7];  end
            3'b011:  begin add_in_1 = add_out_d;     add_in_2 = mult_out_d[7];  end
            3'b100:  begin add_in_1 = add_out_d;     add_in_2 = mult_out_d[7];  end
            3'b101:  begin add_in_1 = add_out_d;     add_in_2 = mult_out_d[7];  end
            3'b110:  begin add_in_1 = add_out_d;     add_in_2 = mult_out_d[7];  end
            3'b111:  begin add_in_1 = add_out_d;     add_in_2 = mult_out_d[7];  end
            default: begin add_in_1 = 23'sd0;        add_in_2 = 23'sd0;        end
        endcase
    end

    // 组合逻辑的加法器 
    assign add_out = fold_cnt == 3'b000 ? 23'b0 : add_in_1 + add_in_2;
    
    // 加法器的移位寄存器
    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_out_d <= 23'sd0;
        end else begin
            add_out_d <= add_out;
        end
    end

    // ------------------- 5. 输出逻辑 -------------------
    // 输出在选通 {1} 的时候有效，从加法器的输出口输出
    // 只有在第 1 个周期时输出有效信号，并寄存器打拍输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            data_out  <= 23'sd0;
        end else begin
            valid_out <= (fold_cnt == 3'b111) && active ? 1'b1 : 1'b0;
            data_out  <= add_out;
        end
    end
    
endmodule
