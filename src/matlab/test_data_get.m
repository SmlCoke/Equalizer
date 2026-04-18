function test_data_get(custom_symbol_counts, custom_example_counts)
% ------------- Equalizer Test Data Get Module -------------
% 生成 RTL Testbench 需要的样本数据：
% 1) 输入数据定点编码
% 2) 输出数据定点编码
% 3) 输出数据浮点值
% --------------------------------------------------

% ----------------- Environment Clear -----------------
clc;
% clear; % 将脚本转换为函数模式以接收命令行参数，需注释掉改行以免清空入参

% ----------------- User Configuration -----------------
ebn0_dB = 23;                % 固定 Eb/N0 = 23 dB
multi_path = 1;              % 1 = multi_path; 0 = no multi_path
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

% Step 0. 固定系数与算术格式
h_fix = h_opt_scale;
word_width = h_fix.WordLength;
frac_width = h_fix.FractionLength;
fm = fimath(h_fix);
a_fix = fi(1, 1, 2, 0, 'fimath', fm);

% ----------------- File Output -----------------
out_dir = fullfile(repo_root, 'examples', sprintf('len_%d_counts_%d', symbol_counts, example_counts));
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

input_fix_path = fullfile(out_dir, 'input_fix.txt');
output_fix_path = fullfile(out_dir, 'output_fix.txt');
output_float_path = fullfile(out_dir, 'output_float.txt');

fid_in = fopen(input_fix_path, 'w', 'n', 'UTF-8');
if fid_in == -1
    error('无法创建文件: %s', input_fix_path);
end

fid_out_fix = fopen(output_fix_path, 'w', 'n', 'UTF-8');
if fid_out_fix == -1
    fclose(fid_in);
    error('无法创建文件: %s', output_fix_path);
end

fid_out_float = fopen(output_float_path, 'w', 'n', 'UTF-8');
if fid_out_float == -1
    fclose(fid_in);
    fclose(fid_out_fix);
    error('无法创建文件: %s', output_float_path);
end

tic;
for ex = 1:example_counts
    % Step 1. 随机产生输入比特并进行 BPSK 调制
    data0 = rand(1, symbol_counts * modulation_level) > 0.5;
    data1 = data0 * 2 - 1;

    % Step 2. 多径信道
    switch multi_path
        case 0
            data2 = data1;
        case 1
            mpc = [1, 0.9, 0.8];
            data2 = filter(mpc, 1, data1);
        otherwise
            error('multi_path 仅支持 0 或 1。');
    end

    % Step 3. 添加 AWGN
    spow = sum(data2 .* data2) / symbol_counts;
    attn = 0.5 * spow * symbol_rate / bit_rate * 10^(-ebn0_dB / 10);
    attn = sqrt(attn);
    awgn = randn(1, length(data2)) .* attn;
    data3 = data2 + awgn;

    % Step 4. 定点均衡滤波
    data3_fix = fi(data3, 1, word_width, frac_width, ...
        'RoundingMethod', 'Floor', ...
        'OverflowAction', 'Saturate', ...
        'fimath', fm);
    data4_fix = filter(h_fix, a_fix, data3_fix);
    data4 = double(data4_fix);

    % Step 5. 数据写文件（每行 1 个样本）
    % storedInteger 忽略小数点位置，获取定点数的整数值
    input_fix_int = storedInteger(data3_fix);
    % int_to_twos_bin 转换为二进制字符串
    input_fix_bin = int_to_twos_bin(input_fix_int, word_width);
    fprintf(fid_in, '%s\n', strjoin(cellstr(input_fix_bin), ' '));

    output_width = data4_fix.WordLength;
    output_fix_int = storedInteger(data4_fix);
    output_fix_bin = int_to_twos_bin(output_fix_int, output_width);
    fprintf(fid_out_fix, '%s\n', strjoin(cellstr(output_fix_bin), ' '));

    % 输出浮点值，使用 '%.16g' 格式化，确保足够的有效数字，同时避免不必要的零
    float_items = compose('%.16g', data4(:).');
    fprintf(fid_out_float, '%s\n', strjoin(cellstr(float_items), ' '));
end
toc;

% 关闭文件
fclose(fid_in);
fclose(fid_out_fix);
fclose(fid_out_float);
disp('测试数据导出成功');


% ----------------- Parameter JSON Export -----------------
input_word_len = h_fix.WordLength;
input_frac_len = h_fix.FractionLength;
input_int_len  = input_word_len - input_frac_len - 1; 

output_word_len = data4_fix.WordLength;
output_frac_len = data4_fix.FractionLength;
output_int_len  = output_word_len - output_frac_len - 1;

n_tap = length(h_fix);

config_meta = struct(...
    'input_format', struct('sign_bit', 1, 'int_bits', input_int_len, 'frac_bits', input_frac_len, 'total_bits', input_word_len), ...
    'filter_taps', n_tap, ...
    'filter_coeffs', double(h_fix), ...
    'output_format', struct('sign_bit', 1, 'int_bits', output_int_len, 'frac_bits', output_frac_len, 'total_bits', output_word_len) ...
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