% ------------- Equalizer Coeffs Get Model -------------
% 该脚本用于计算抵消多径信道 [1, 0.9, 0.8] 的 N 抽头均衡滤波器系数
% 默认方法为 "causal_zf"(全因果迫零)，以保证 N=3 时得到示例结果 [1, -0.9, 0.01]
% 也可选择 "ls"(全长度最小二乘)，并设定 decision_delay 和 lambda 参数
% --------------------------------------------------

% ----------------- Environment Clear -----------------
clc;
clear;

% ----------------- Parameter Preparation -----------------
% 多径信道冲激响应
% y[n] = x[n] + 0.9*x[n-1] + 0.8*x[n-2]
mpc = [1, 0.9, 0.8];

% 均衡器抽头数
N_tap = 18;

% 求解方式选择
% "causal_zf": 因果迫零（课堂推导一致）
% "ls":        全长度最小二乘（可设 delay）
solve_mode = "ls";

% 仅在 solve_mode="ls" 时生效
decision_delay = 0; % 单位: sample，合法范围 [0, N_tap+length(mpc)-2]
lambda = 0;         % L2 正则项，0 表示纯 LS

% ----------------- 构造卷积矩阵(toeplitz 矩阵)并求解均衡器系数 -----------------
% 计算原理：C * h_opt = d
% (1) 对于因果迫零，d = [1, 0, 0, ..., 0], L = N
% (2) 对于全长度 LS，d 的 1 位置由 decision_delay 决定，L = N + length(mpc) - 1
% toeplitz 矩阵形式：
% [mpc(1)   0       0       ...     0      ]
% [mpc(2)  mpc(1)   0       ...     0      ]
% [mpc(3)  mpc(2)  mpc(1)   ...     0      ]
% [0       mpc(3)  mpc(2)   ...     0      ]
% [0       0       mpc(3)   ...     0      ]
% -------------------------------------------------------------------------

% 信道冲激响应长度
L = length(mpc);
% 信道响应与均衡器的卷积长度
conv_len = N_tap + L - 1;

% 构造 toeplitz 矩阵的首列，形式：[mpc, 0, 0, 0]
c_col = [mpc, zeros(1, N_tap - 1)]';
% 构造 toeplitz 矩阵的首行，形式：[mpc(1), 0, 0, 0]
r_row = [mpc(1), zeros(1, N_tap - 1)];
% 构造卷积矩阵 C
C = toeplitz(c_col, r_row); % [conv_len x N_tap]


% 求解均衡器系数 h_opt
if solve_mode == "causal_zf"
	% 让卷积前 N_tap 个点满足: [1, 0, 0, ..., 0]
	% 这会得到课堂中 3 抽头手算结果 [1, -0.9, 0.01]
	A = C(1:N_tap, :);
	b = zeros(N_tap, 1);
	b(1) = 1;
	h_opt_col = A \ b;
	main_idx = 1;
else
	% 全长度 LS: 最小化 ||C*h - d||_2
	d = zeros(conv_len, 1);
	decision_delay = max(0, min(decision_delay, conv_len - 1));
	d(decision_delay + 1) = 1;

	if lambda > 0
		h_opt_col = (C' * C + lambda * eye(N_tap)) \ (C' * d);
	else
		h_opt_col = C \ d;
	end
	main_idx = decision_delay + 1;
end

% 转置为行向量形式，便于 equalizer.m 直接使用
h_opt = h_opt_col';

% 计算卷积结果，观察主抽头位置外的残余 ISI 能量
combined = conv(mpc, h_opt);

% 使用 fi 对 h_opt 的系数进行定点量化: 1 sign + 2 int + 5 frac = 8 bit total
h_opt_scale = fi(h_opt, 1, 8, 5);

% 输出结果
disp("----------------------------------------------");
disp("Equalizer Coefficient Solver");
disp(["solve_mode = ", char(solve_mode)]);
disp(["N_tap      = ", num2str(N_tap)]);
disp(["channel     = [", num2str(mpc), "]"]);
disp("h_opt =");
disp(h_opt);
disp("h_opt_scale =");
disp(h_opt_scale)
disp("combined response conv(mpc, h_opt) =");
disp(combined);

% 统计主抽头外残余 ISI 能量
isi = combined;
isi(main_idx) = 0;
isi_energy = sum(isi .^ 2);
disp(["residual ISI energy = ", num2str(isi_energy)]);
disp("----------------------------------------------");

% 可视化
fig_eq = figure;

% (1) 均衡器系数 h_opt
subplot(2,1,1);
stem(0:N_tap-1, h_opt, 'filled', 'LineWidth', 1.2);
title([num2str(N_tap), '-tap Equalizer Coefficients']);
xlabel('tap index');
ylabel('h[k]');
grid on;

% (2) 卷积结果 conv(mpc, h_opt)
subplot(2,1,2);
stem(0:conv_len-1, combined, 'filled', 'LineWidth', 1.2);
title('Combined Response conv(channel, equalizer)');
xlabel('sample index');
ylabel('amplitude');
grid on;

% ----------------- 图片导出 ----------------
fig_dir = fullfile('results', 'figures', sprintf('tab%d_%s', N_tap, solve_mode));
if ~exist(fig_dir, 'dir')
	mkdir(fig_dir);
end

eq_svg_path = fullfile(fig_dir, 'equalizer.svg');
drawnow;

try
	exportgraphics(fig_eq, eq_svg_path, 'ContentType', 'vector');
catch
	saveas(fig_eq, eq_svg_path);
end

disp(['figure saved: ', eq_svg_path]);

% 8) 可选保存，便于 equalizer.m 直接 load 使用
save('equalizer_coeffs.mat', 'h_opt', 'N_tap', 'h_opt_scale', 'solve_mode');

% 9) 导出系数到 txt（十进制 + 定点二进制）
script_fullpath = mfilename('fullpath');
if isempty(script_fullpath)
	script_dir = pwd;
else
	script_dir = fileparts(script_fullpath);
end

% 创建 results 目录（如果不存在）用于保存 csv 文件
results_dir = fullfile(script_dir, 'results', 'coeffs');
if ~exist(results_dir, 'dir')
	mkdir(results_dir);
end

% csv 文件名和路径
csv_name = sprintf('coeffs_%d_%s.csv', N_tap, solve_mode);
csv_path = fullfile(results_dir, csv_name);

% 收集滤波器系数
h_opt_col = h_opt(:);
h_opt_scale_col = h_opt_scale(:);
% 将定点量化结果转换为二进制字符串
bin_mat = bin(h_opt_scale_col);
tap_index = (0:N_tap-1)';
h_opt_scale_binary = cellstr(bin_mat);
% 创建表格并保存为 csv文件
coeff_table = table(tap_index, h_opt_col, double(h_opt_scale_col), h_opt_scale_binary, ...
	'VariableNames', {'tap_index', 'h_opt_decimal', 'h_opt_scale_decimal', 'h_opt_scale_binary'});

writetable(coeff_table, csv_path);
disp(['coefficients csv saved: ', csv_path]);

