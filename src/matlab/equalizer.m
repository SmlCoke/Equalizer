% ------------- Equalizer MATLAB Model -------------
% this model simulates the performance of equalizer in multi-path channel, 
% and compares the BER with and without equalization filter.
% --------------------------------------------------

% ----------------- Environment Clear -----------------
clc
clear

% load bpsk theory mapping table
load('bpsk_theory_extend.mat');

% load best N-tap equalizer coefficients
load('equalizer_coeffs.mat')

% ----------------- Parameter Preparation -----------------
% 每秒钟在信道上发送的符号周期数
symbol_rate = 256000;

% 单个符号所能携带的比特数量，BPSK（二进制相移键控），其射频波形只有两种相位状态  
modulation_level = 1;                       

% 比特率，信息传输速率（比特/秒）
bit_rate = symbol_rate .* modulation_level;

% 每次仿真循环中需要发送的符号总数，symbol_counts x modulation_level 就是每次循环中生成的比特总数
symbol_counts = 10000; 

ebn0 = 0:30;                         % Eb/N0
ber = zeros(1,length(ebn0));         % Bit Error Rate
eq_ber = zeros(1,length(ebn0));      % Bit Error Rate (BER) with equalization filter
% eq_ber2 = zeros(1,length(ebn0));   % ber with eq2
multi_path = 1;		                 % 1 = multi_path; 0 = no multi_path

% ----------------- Calculation Loop -----------------
% 仿真迭代次数
nloop = 1000;  

tic;

% 外层循环，迭代每一个 Eb/N0 值
for cnt = 1:length(ebn0)
    % 当前迭代的 Eb/N0 值
    disp(ebn0(cnt));
    % 无均衡滤波器误比特数统计
    error_counts = 0; 
    % 均衡滤波器误比特数统计
    eq_error_counts = 0;

    % 总比特数统计
    bit_counts = 0;
    % 内层循环，进行 nloop 次仿真迭代
    for i=1:nloop
        
        % --------------- Step 1. 随机产生指定长度的输入基带序列 ----------------
        data0 = rand(1, symbol_counts*modulation_level) > 0.5;  
        
        % ---------------- Step 2. BPSK 调制 ----------------
        % 调制方法: 0 -> -1, 1 -> 1, 即 y[n] = 2x[n] - 1
        data1 = data0.*2-1;
        
        % ---------------- Step 3. 多径信道模拟 ----------------
        switch multi_path
            case 0
                data2 = data1;
            case 1
                % multi path coefficient
                mpc = [1, 0.9, 0.8]; 
                % 信道作用用卷积运算模拟
				data2 = filter(mpc, 1, data1); 
        end

        % ---------------- Step 4. 信号功率计算与噪声添加 ----------------
        % ---------------- 理论基础 ----------------
        % Eb = 每比特能量 = 每符号能量 / 比特率 = spow / bit_rate
        % N0 = 噪声功率谱密度，总的带通噪声功率 N 在奈奎斯特带宽下（基带模拟下带宽约等于符号率一半），σ² = N0 x symbol_rate / 2 -> N0 = 2σ² / symbol_rate
        % Eb/N0 = 10^(dB/10) -> σ² = Eb / [10^(dB/10)] x symbol_rate / 2 = 0.5 x spow x symbol_rate / bit_rate x 10^(-dB/10)
        % -----------------------------------------

        % 信号功率计算：平均每个符号的功率   
        spow=sum(data2.*data2)/symbol_counts;  
        % 计算乘性缩放因子
        attn=0.5 * spow * symbol_rate / bit_rate * 10.^(-ebn0(cnt)/10);
        % 获取信号标准差，用于生成 AWGN
        attn=sqrt(attn);
        
        % 加性高斯噪声（randn的幅度是1，需要乘性缩放因子做归一化）
        awgn = randn(1,length(data2)).*attn;
        data3 = data2 + awgn;

        % ---------------- Step 5. 均衡滤波器处理 ----------------
        % 使用量化后的系数值，但在 double 域滤波，避免 fi/filter 对输入类型的严格要求
        h = double(h_opt_scale);
        % todo: fix-point       e.g. fix_data = fi(data, 1, 8, 5);
        data4 = filter(h, 1, data3);
       
        % ---------------- Step 6. BPSK 解调 ----------------
        % 解调方法: -1 -> 0, 1 -> 1, 即 x[n] = y[n] >= 0
        
        % Class 1. 没有均衡滤波器的解调结果
        demo_data = zeros(1,modulation_level*symbol_counts);
        demo_data(1:modulation_level*symbol_counts)=data3(1:modulation_level*symbol_counts)>=0;
        
        % Class 2. 均衡滤波器的解调结果
        eq_demo_data = zeros(1,modulation_level*symbol_counts);
        eq_demo_data(1:modulation_level*symbol_counts)=data4(1:modulation_level*symbol_counts)>=0;

        % ---------------- Step 7. 误比特数统计 ----------------
        % Class 1. 没有均衡滤波器的解调结果的误比特数
        error_counts_i=sum(abs(data0-demo_data));
        % Class 2. 均衡滤波器的解调结果的误比特数
        eq_error_counts_i=sum(abs(data0-eq_demo_data));

        % 本次循环中处理的比特总数
        bit_counts_i=length(data0);

        % ---------------- Step 8. 累积误比特数和总比特数 ----------------
        eq_error_counts = eq_error_counts+eq_error_counts_i;
        error_counts    = error_counts+error_counts_i;
        bit_counts      = bit_counts+bit_counts_i;

    end

    % 计算当前 Eb/N0 下的 BER 和均衡滤波器的 BER
    ber(cnt) = error_counts/bit_counts;
    eq_ber(cnt) = eq_error_counts/bit_counts;

end
toc;

% ----------------- 结果输出 ----------------
disp(['frame=',num2str(nloop)]);
disp(['BER=',num2str(ber)]);
disp(['EQ_BER=  ',num2str(eq_ber)]);
% disp(['EQ_BER2=  ',num2str(eq_ber2)]);
toc;

% ----------------- 结果可视化 ----------------
% BER 曲线比较
figure(1);
% 锁定坐标范围: x: [0, 30.5], y: [1.0e-7, 1]
axis([0 30.5 1.0e-7 1]);

% (1) 绘制 bpsk_theory.mat 中的理论 BER 曲线（理想条件，无多径，有AWGN）
semilogy(ebn0_theory_bpsk, ber_theory_bpsk,'-k>','linewidth',3,'MarkerSize',8);
hold on ;

% (2) 绘制仿真得到的 BER 曲线（有多径，无均衡滤波器）
axis([0 30.5 1.0e-7 1]);
semilogy(ebn0, ber, '-b<', 'linewidth',3, 'MarkerSize',8);

% (3) 绘制仿真得到的均衡滤波器 BER 曲线（有多径，有均衡滤波器）
axis([0 30.5 1.0e-7 1]);
semilogy(ebn0, eq_ber, '-g<', 'linewidth',3, 'MarkerSize',8);

% (4) 目标门限辅助线
% PB = 1e-6 的水平红色虚线
line([ebn0(1), ebn0(end)], [1e-6, 1e-6], 'Color', 'r', 'LineStyle', '--', 'LineWidth', 1.5);
% Eb/N0 = 23dB 的竖直绿色虚线
line([23, 23], [1.0e-7, 1], 'Color', 'g', 'LineStyle', '--', 'LineWidth', 1.5);

% 图例说明
legend('ideal', 'multi', ['multi+eq-', num2str(N_tap)]);
title('Multipath Simulation');
grid on ;
hold off;

% 信号分布比较
figure(2);
% X:[ -5, 5 ] 覆盖 BPSK 范围，Y:[ 0, 1 ] 是虚假的拉开空间
axis([-5 5 0 1]);
% 1. 颜色数组 std_c 生成 
%   - 对于每个数据点，如果对应的原始比特是 1，则颜色为红色（[1, 0, 0]），如果是 0，则颜色为蓝色（[0, 0, 1]）。这样可以通过颜色区分不同的比特值。
std_c = [ones(symbol_counts*modulation_level, 1) .* data0', zeros(symbol_counts*modulation_level, 1), ones(symbol_counts*modulation_level, 1) .* (1 - data0)'];
% 2. 绘制“未均衡信号”的数据点
scatter(data3(1:modulation_level*symbol_counts), ones(1, modulation_level*symbol_counts) .* 0.2, [], std_c);
hold on ;


axis([-5 5 0 1]);
% 3. 绘制“经过均衡滤波之后的信号”的数据点
scatter(data4(1:modulation_level*symbol_counts), ones(1, modulation_level*symbol_counts) .* 0.8, [], std_c);
title('Signal Distribution');
grid on ;
hold off;

save("example_data.mat", "data0", "data1", "data2", "data3", "data4");