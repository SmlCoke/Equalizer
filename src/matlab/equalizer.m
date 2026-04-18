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
                % 信道作用用滤波运算模拟
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
        h = double(h_opt);
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

% ----------------- 判定当前 均衡器 是否达标 ----------------
% 过滤掉误码率为 0 的点（因为 log10(0) 是 -Inf，无法插值）
valid_idx = eq_ber > 0;
valid_ebn0 = ebn0(valid_idx);
valid_ber = eq_ber(valid_idx);

target_ebn0 = [];
margin = [];

if isempty(valid_ber) || min(valid_ber) > 1e-6
    disp('警告：当前仿真未达到 1e-6 误码率，或者所有达标的点误码率直接跌为 0！');
else
    % 利用对数插值，算出精确穿过 1e-6 那一瞬间的实际 Eb/N0
    target_ebn0 = interp1(log10(valid_ber), valid_ebn0, log10(1e-6), 'linear', 'extrap');
    
    % 计算当前设计的余量（Margin），即我们距离 23dB 的“死亡红线”还有多远
    margin = 23 - target_ebn0;
end


% ----------------- 结果输出与保存 ----------------
% solve_mode 数据应该来自 equalizer_coeffs.mat
if exist('solve_mode', 'var')
    solve_mode_str = char(string(solve_mode));
else
    solve_mode_str = 'unknown';
end

target_ebn0_out = 'N.A.';
margin_out = 'N.A.';
Feasibility = false;

if ~isempty(target_ebn0) && ~isempty(margin) && isfinite(target_ebn0) && isfinite(margin)
    target_ebn0_out = target_ebn0;
    margin_out = margin;
    Feasibility = (margin > 0);
end

metrics = struct( ...
    'N_tap', N_tap, ...
    'symbol_rate', symbol_rate, ...
    'modulation_level', modulation_level, ...
    'nloop', nloop, ...
    'target_ebn0', target_ebn0_out, ...
    'margin', margin_out, ...
    'Feasibility', Feasibility, ...
    'ebn0', ebn0, ...
    'ber', ber, ...
    'eq_ber', eq_ber);

% 检测是否有 results/metrics 目录，没有就创建
metrics_dir = fullfile('results', 'metrics');
if ~exist(metrics_dir, 'dir')
    mkdir(metrics_dir);
end

metrics_name = sprintf('%s_%d_frac.json', solve_mode_str, N_tap);
metrics_path = fullfile(metrics_dir, metrics_name);

fid = fopen(metrics_path, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建 metrics json 文件: %s', metrics_path);
end

fwrite(fid, jsonencode(metrics, PrettyPrint=true), 'char');
fclose(fid);
disp(['metrics json saved: ', metrics_path]);


% ----------------- 结果可视化 ----------------
% BER 曲线比较
fig_ber = figure(1);
clf;
set(gcf, 'Color', 'w', 'Position', [80, 80, 980, 540]);
ax1 = gca;
set(ax1, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 1.1, 'Box', 'on');
hold on;
set(ax1, 'YScale', 'log');

% 锁定坐标范围: x: [0, 30.5], y: [1.0e-7, 1]
xlim([0 30.5]);
ylim([1.0e-7 1]);

% 配色与统一小圆点样式
c_theory = [0.10, 0.10, 0.10];
c_multi  = [0.12, 0.42, 0.82];
c_eq     = [0.00, 0.60, 0.30];
mk_sz = 4;

% (1) 绘制 bpsk_theory.mat 中的理论 BER 曲线（理想条件，无多径，有AWGN）
semilogy(ebn0_theory_bpsk, ber_theory_bpsk, '-o', 'Color', c_theory, ...
    'LineWidth', 2.0, 'MarkerSize', mk_sz, 'MarkerFaceColor', 'w');

% (2) 绘制仿真得到的 BER 曲线（有多径，无均衡滤波器）
semilogy(ebn0, ber, '-o', 'Color', c_multi, ...
    'LineWidth', 2.0, 'MarkerSize', mk_sz, 'MarkerFaceColor', 'w');

% (3) 绘制仿真得到的均衡滤波器 BER 曲线（有多径，有均衡滤波器）
semilogy(ebn0, eq_ber, '-o', 'Color', c_eq, ...
    'LineWidth', 2.0, 'MarkerSize', mk_sz, 'MarkerFaceColor', 'w');

% (4) 目标门限辅助线
% PB = 1e-6 的水平红色虚线
line([ebn0(1), ebn0(end)], [1e-6, 1e-6], 'Color', 'r', 'LineStyle', '--', 'LineWidth', 1.5);
% Eb/N0 = 23dB 的竖直绿色虚线
line([23, 23], [1.0e-7, 1], 'Color', 'g', 'LineStyle', '--', 'LineWidth', 1.5);

% 图例说明
legend('Ideal', 'Multipath', 'Equalizer', 'Location', 'southwest', 'Box', 'off');
title('BER-Eb/N0 Performance', 'FontWeight', 'bold');
xlabel('Eb/N0 (dB)');
ylabel('Bit Error Rate');
grid on;
ax1.XMinorGrid = 'on';
ax1.YMinorGrid = 'on';
ax1.GridAlpha = 0.20;
ax1.MinorGridAlpha = 0.12;
hold off;

% 信号分布比较
fig_dist = figure(2);
clf;
set(gcf, 'Color', 'w', 'Position', [120, 120, 980, 360]);
ax2 = gca;
set(ax2, 'FontName', 'Times New Roman', 'FontSize', 11, 'LineWidth', 1.1, 'Box', 'on');
xlim([-5 5]);
ylim([0 1]);

% 1. 颜色数组 std_c 生成 
%   - 对于每个数据点，如果对应的原始比特是 1，则颜色为红色（[1, 0, 0]），如果是 0，则颜色为蓝色（[0, 0, 1]）。这样可以通过颜色区分不同的比特值。
std_c = [ones(symbol_counts*modulation_level, 1) .* data0', zeros(symbol_counts*modulation_level, 1), ones(symbol_counts*modulation_level, 1) .* (1 - data0)'];

mk_scatter = 8;

% 2. 绘制“未均衡信号”的数据点
scatter(data3(1:modulation_level*symbol_counts), ones(1, modulation_level*symbol_counts) .* 0.2, ...
    mk_scatter, std_c, 'o', 'filled', 'MarkerEdgeColor', 'none');
hold on;

xlim([-5 5]);
ylim([0 1]);
% 3. 绘制“经过均衡滤波之后的信号”的数据点
scatter(data4(1:modulation_level*symbol_counts), ones(1, modulation_level*symbol_counts) .* 0.8, ...
    mk_scatter, std_c, 'o', 'filled', 'MarkerEdgeColor', 'none');
title('Signal Distribution', 'FontWeight', 'bold');
xlabel('Signal Amplitude');
ylabel('Class Index');
grid on;
ax2.XMinorGrid = 'on';
ax2.GridAlpha = 0.20;
ax2.MinorGridAlpha = 0.12;
hold off;

% ----------------- 图片导出 ----------------
fig_dir = fullfile('results', 'figures', sprintf('tab%d_%s', N_tap, solve_mode_str));
if ~exist(fig_dir, 'dir')
    mkdir(fig_dir);
end

ber_svg_path = fullfile(fig_dir, 'ber_frac.svg');
dist_svg_path = fullfile(fig_dir, 'dist_frac.svg');

try
    exportgraphics(fig_ber, ber_svg_path, 'ContentType', 'vector');
    exportgraphics(fig_dist, dist_svg_path, 'ContentType', 'vector');
catch
    saveas(fig_ber, ber_svg_path);
    saveas(fig_dist, dist_svg_path);
end

disp(['figure saved: ', ber_svg_path]);
disp(['figure saved: ', dist_svg_path]);