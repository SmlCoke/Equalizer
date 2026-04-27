function batch_data_get(custom_symbol_counts, custom_example_counts, custom_ebn0_dB, custom_batch_flag)
% ------------- Equalizer Batch Data Get Module -------------
% 生成批量统计数据：
% 1) 保存 data0（二进制 01 序列）
% 2) 保存 data3_fix（定点化后的接收信号）
% 3) 统计每个 Eb/N0 下 3 种场景的误比特数
% --------------------------------------------------

% ----------------- Environment Clear -----------------
clc;
% clear; % 将脚本转换为函数模式以接收命令行参数，需注释掉改行以免清空入参

% ----------------- User Configuration -----------------
rng(20260418);               % 固定随机种子，保证回归可复现

% ----------------- Path Preparation -----------------
this_dir = fileparts(mfilename('fullpath'));            % .../src/matlab
repo_root = fileparts(fileparts(this_dir));             % .../equalizer
coeffs_path = fullfile(this_dir, 'equalizer_coeffs.mat');

if ~exist(coeffs_path, 'file')
    error('找不到系数文件: %s', coeffs_path);
end

load(coeffs_path, 'h_opt_scale');
if ~exist('h_opt_scale', 'var')
    error('equalizer_coeffs.mat 中缺少 h_opt_scale，请先运行 calc_equalizer_coeffs.m。');
end

% ----------------- Parameter Preparation -----------------
symbol_rate = 256000;
modulation_level = 1;
bit_rate = symbol_rate * modulation_level;

% 解析命令行参数传入的 symbol_counts
if nargin >= 1 && ~isempty(custom_symbol_counts)
    if ischar(custom_symbol_counts) || isstring(custom_symbol_counts)
        symbol_counts = str2double(custom_symbol_counts);
    else
        symbol_counts = custom_symbol_counts;
    end
else
    symbol_counts = 100; % 默认值
end

% 解析命令行参数传入的 example_counts
if nargin >= 2 && ~isempty(custom_example_counts)
    if ischar(custom_example_counts) || isstring(custom_example_counts)
        example_counts = str2double(custom_example_counts);
    else
        example_counts = custom_example_counts;
    end
else
    example_counts = 1000; % 默认值
end

% 解析命令行参数传入的 ebn0_dB
if nargin >= 3 && ~isempty(custom_ebn0_dB)
    if ischar(custom_ebn0_dB) || isstring(custom_ebn0_dB)
        ebn0_dB = str2double(custom_ebn0_dB);
    else
        ebn0_dB = custom_ebn0_dB;
    end
else
    ebn0_dB = 23; % 默认值
end

if nargin >= 4 && ~isempty(custom_batch_flag)
    if ischar(custom_batch_flag) || isstring(custom_batch_flag)
        batch_flag = str2double(custom_batch_flag);
    else
        batch_flag = custom_batch_flag;
    end
else
    batch_flag = 0; % 默认值
end

% Step 0. 固定系数与算术格式
h_fix = h_opt_scale;
word_width = h_fix.WordLength;
frac_width = h_fix.FractionLength;
fm = fimath(h_fix);
a_fix = fi(1, 1, 2, 0, 'fimath', fm);

% ----------------- File Output -----------------
if batch_flag == 0
    out_dir = fullfile(repo_root, 'examples', sprintf('len_%d_counts_%d', symbol_counts, example_counts));
else
    out_dir = fullfile(repo_root, 'examples', sprintf('batch_len_%d_counts_%d', symbol_counts, example_counts), sprintf('ebn0_%ddB', ebn0_dB));
end

if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

data0_path = fullfile(out_dir, 'data0.txt');
data3_fix_path = fullfile(out_dir, 'data3_fix.txt');

fid_data0 = fopen(data0_path, 'w', 'n', 'UTF-8');
if fid_data0 == -1
    error('无法创建文件: %s', data0_path);
end

fid_data3_fix = fopen(data3_fix_path, 'w', 'n', 'UTF-8');
if fid_data3_fix == -1
    fclose(fid_data0);
    error('无法创建文件: %s', data3_fix_path);
end

bit_errors_case1 = 0;
bit_errors_case2 = 0;
bit_errors_case3 = 0;

tic;
for ex = 1:example_counts
    % Step 1. 随机产生输入比特并进行 BPSK 调制
    data0 = rand(1, symbol_counts * modulation_level) > 0.5;
    data1 = data0 * 2 - 1;

    % Step 2. 场景 1：AWGN 信道，无多径
    data2_case1 = data1;
    spow_case1 = sum(data2_case1 .* data2_case1) / symbol_counts;
    attn_case1 = 0.5 * spow_case1 * symbol_rate / bit_rate * 10^(-ebn0_dB / 10);
    awgn_case1 = randn(1, length(data2_case1)) .* sqrt(attn_case1);
    data3_case1 = data2_case1 + awgn_case1;
    bits_case1 = data3_case1 >= 0;
    bit_errors_case1 = bit_errors_case1 + sum(bits_case1 ~= data0);

    % Step 3. 场景 2/3：AWGN 信道，有多径
    mpc = [1, 0.9, 0.8];
    data2 = filter(mpc, 1, data1);
    spow = sum(data2 .* data2) / symbol_counts;
    attn = 0.5 * spow * symbol_rate / bit_rate * 10^(-ebn0_dB / 10);
    awgn = randn(1, length(data2)) .* sqrt(attn);
    data3 = data2 + awgn;

    % 场景 2：有多径，无滤波
    bits_case2 = data3 >= 0;
    bit_errors_case2 = bit_errors_case2 + sum(bits_case2 ~= data0);

    % 场景 3：有多径，有滤波
    data3_fix = fi(data3, 1, word_width, frac_width, ...
        'RoundingMethod', 'Floor', ...
        'OverflowAction', 'Saturate', ...
        'fimath', fm);
    data4_fix = filter(h_fix, a_fix, data3_fix);
    data4 = double(data4_fix);
    bits_case3 = data4 >= 0;
    bit_errors_case3 = bit_errors_case3 + sum(bits_case3 ~= data0);

    % Step 4. 数据写文件（每行 1 个样本）
    % data0 保存为 01 序列
    data0_items = compose('%d', data0(:).');
    fprintf(fid_data0, '%s\n', strjoin(cellstr(data0_items), ' '));

    % data3_fix 保存为定点补码二进制字符串
    data3_fix_int = storedInteger(data3_fix);
    data3_fix_bin = int_to_twos_bin(data3_fix_int, word_width);
    fprintf(fid_data3_fix, '%s\n', strjoin(cellstr(data3_fix_bin), ' '));
end
toc;

% 关闭文件
fclose(fid_data0);
fclose(fid_data3_fix);
disp('测试数据导出成功');

disp(sprintf('Eb/N0 = %d dB, 错误比特统计已写入 config_meta.json：[%d, %d, %d]', ...
    ebn0_dB, bit_errors_case1, bit_errors_case2, bit_errors_case3));

% ----------------- Parameter JSON Export -----------------
input_word_len = h_fix.WordLength;
input_frac_len = h_fix.FractionLength;
input_int_len  = input_word_len - input_frac_len - 1;

output_word_len = data4_fix.WordLength;
output_frac_len = data4_fix.FractionLength;
output_int_len  = output_word_len - output_frac_len - 1;

n_tap = length(h_fix);

config_meta = struct(...
    'ebn0_dB', ebn0_dB, ...
    'input_format', struct('sign_bit', 1, 'int_bits', input_int_len, 'frac_bits', input_frac_len, 'total_bits', input_word_len), ...
    'filter_taps', n_tap, ...
    'filter_coeffs', double(h_fix), ...
    'output_format', struct('sign_bit', 1, 'int_bits', output_int_len, 'frac_bits', output_frac_len, 'total_bits', output_word_len), ...
    'bit_errors', struct( ...
        'awgn_no_multipath', bit_errors_case1, ...
        'awgn_multipath_no_filter', bit_errors_case2, ...
        'awgn_multipath_with_filter', bit_errors_case3 ...
    ) ...
);

json_path = fullfile(out_dir, 'config_meta.json');
fid_json = fopen(json_path, 'w', 'n', 'UTF-8');
if fid_json ~= -1
    fwrite(fid_json, jsonencode(config_meta, 'PrettyPrint', true), 'char');
    fclose(fid_json);
    disp(['Metadata JSON saved: ', json_path]);
else
    warning('无法创建 JSON 文件: %s', json_path);
end

end % 结束主程序

function bin_lines = int_to_twos_bin(values, width)
% 将传入的数据变为一维向量
vals = double(values(:));
% 计算模数，进行模运算得到无符号整数值（补码）
modulus = 2^width;
unsigned_vals = mod(vals, modulus);
% 将整数值转换为二进制字符串，使用 dec2bin 函数，指定宽度
bin_lines = dec2bin(unsigned_vals, width);
end
