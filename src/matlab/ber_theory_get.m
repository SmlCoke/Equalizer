% 1. 设置 0 到 30 的坐标
ebn0_theory_bpsk = 0:30;

% 2. 调用内置函数计算理想 BPSK 在对应 Eb/N0 下的误码率
ber_theory_bpsk = berawgn(ebn0_theory_bpsk, 'psk', 2, 'nondiff');

% 3. 保存为新的 mat 文件
save('bpsk_theory_extend.mat', 'ebn0_theory_bpsk', 'ber_theory_bpsk');