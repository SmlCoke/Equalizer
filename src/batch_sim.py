'''
脚本: batch_sim.py
作者: Equalizer 团队
日期: 2026-04-27
版本: v1.0
功能: 
    1. 解析命令行参数
    2. 调用 MATLAB 脚本 test_data_get.m 自动生成每个 ebn0 下的测试数据（自动判断是否存在）
    3. 调用 Icarus Verilog 工具编译 testbench 以及 RTL 模块
    4. 调用 vvp 工具运行多次仿真，生成每个 ebn0 下的输出结果文件
'''
import argparse
import subprocess
import sys
from pathlib import Path
from common import print_summary_box, run_cmd, resolve_user_path, get_tb_file, parse_port_width

def parse_args():
    parser = argparse.ArgumentParser(description="Equalizer simulation runner")
    # 输入 RTL 模块，默认 baseline 方案
    parser.add_argument("--rtl-file", default="rtl/baseline/equalizer.v", help="RTL top file, relative to src/")
    # 输入 MATLAV 数据生成脚本路径，默认 matlab/batch_data_get.m
    parser.add_argument("--matlab-script", default="matlab/batch_data_get.m", help="MATLAB script for data generation")
    # 每一个 ebn0 的测试样本数量
    parser.add_argument("--example-count", type=int, default=10000, help="Example count per ebn0")
    # 每一个样本的符号数量
    parser.add_argument("--symbol-count", type=int, default=1000, help="Symbol count per example")
    # 输出数据小数部分位宽，默认为10，整个实验中一般不会改动
    parser.add_argument("--frac-bits", type=int, default=10, help="Fraction bits for float conversion")
    # 每个样本的最大等待周期数，默认为4096，过小可能导致仿真不完整，过大可能导致仿真时间过长。
    parser.add_argument("--timeout-cycles", type=int, default=4096, help="Max wait cycles per example")
    
    return parser.parse_args()

def verify_output(bin_file, golden_file, output_file):
    '''
    gold_file 格式：example_counts 行，每一行 symbol_count 个符号 {0, 1}，空格分隔
    bin_file 格式：example_counts 行，每一行 symbol_count 个二进制补码，空格分隔
    BPSK 调制后，0 映射为 -1， 1 映射为 +1
    判决时，补码首位为 1 判决为 0，补码首位为 0 判决为 1
    output_file 存储一个数，错误比特数
    '''
    with open(golden_file, "r") as gf, open(bin_file, "r") as bf:
        golden_lines = gf.readlines()
        bin_lines = bf.readlines()
        if len(golden_lines) != len(bin_lines):
            raise ValueError(f"Example count mismatch: {len(golden_lines)} in golden file vs {len(bin_lines)} in bin file")
        
        error_bits = 0
        for g_line, b_line in zip(golden_lines, bin_lines):
            g_symbols = g_line.strip().split()
            b_values = b_line.strip().split()
            if len(g_symbols) != len(b_values):
                raise ValueError(f"Symbol count mismatch in line: {g_line} vs {b_line}")
            for g_sym, b_val in zip(g_symbols, b_values):
                g_bit = int(g_sym)
                b_decision = 0 if b_val[0] == "1" else 1
                if g_bit != b_decision:
                    error_bits += 1
        
        # Save the error bits to the output file
        with open(output_file, "w") as f:
            f.write(str(error_bits))
        
        return error_bits

def main():
    # step 1. 解析参数
    args = parse_args()

    # step 2. 获取各个文件的文件目录以及其他参数
    base_dir = Path(__file__).resolve().parent
    # 解析 RTL 模块路径
    rtl_file = resolve_user_path(base_dir, args.rtl_file)
    # 解析 MATLAB 数据生成脚本路径
    matlab_script = resolve_user_path(base_dir, args.matlab_script)
    # 推断 Testbench 文件路径
    tb_file = get_tb_file(base_dir, rtl_file)
    # 强制指定 testbench 顶层模块名为 equalizer_tb
    tb_top = "equalizer_tb"  
    # 解析 example_count 和 symbol_count 参数
    example_count = args.example_count
    symbol_count = args.symbol_count

    if not rtl_file.exists():
        raise FileNotFoundError(f"RTL file not found: {rtl_file}")
    if not tb_file.exists():
        raise FileNotFoundError(f"Testbench file not found: {tb_file}")

    # Step 3. 正则表达式自动获取 RTL 模块的 data_in, data_out 位宽，兼容多种声明格式
    if ("unfolding" in rtl_file.parent.name):
        input_width = parse_port_width(rtl_file, "data_in_even", "input")
        output_width = parse_port_width(rtl_file, "data_out_even", "output")
    else:
        input_width = parse_port_width(rtl_file, "data_in", "input")
        output_width = parse_port_width(rtl_file, "data_out", "output")


    # Step 4. 创建编译产物和输出文件路径
    rtl_tag = rtl_file.parent.name
    build_dir = base_dir / "rtl" / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    vvp_file = build_dir / f"{rtl_tag}.vvp"

    # Step 5. 调用 MATLAB 脚本生成测试数据
    if not matlab_script.exists():
        raise FileNotFoundError(f"MATLAB script not found: {matlab_script}")
    matlab_script_name = matlab_script.stem
    for ebn0 in range(31):
        matlab_cmd = [
            "matlab",
            "-batch",
            f"addpath('./matlab'); {matlab_script_name}({symbol_count}, {example_count}, {ebn0}, 1)"
        ]
        print(f"Generating test data for Eb/N0 = {ebn0} dB...")
        if (base_dir / ".." / "examples" / f"batch_len_{symbol_count}_counts_{example_count}" / f"ebn0_{ebn0}dB" / "data3_fix.txt").exists():
            print(f"Test data for Eb/N0 = {ebn0} dB already exists, skipping MATLAB generation.")
            continue
        else:
            run_cmd(matlab_cmd)

    # Step 6. 调用 Icarus Verilog 工具编译 testbench 以及 RTL 模块
    # 关键参数通过编译宏导入，适配不同优化方案的 RTL 文件
    sources = [tb_file] + sorted(rtl_file.parent.glob("*.v"))
    compile_cmd = [
        "iverilog",
        "-g2001",
        "-s",
        tb_top,
        f"-DINPUT_WIDTH={input_width}",
        f"-DOUT_WIDTH={output_width}",
        f"-DSYMBOL_COUNT={symbol_count}",
        f"-DEXAMPLE_COUNT={example_count}",
        f"-DTIMEOUT_CYCLES={args.timeout_cycles}",
        "-I",
        str(tb_file.parent),
        "-I",
        str(rtl_file.parent),
        "-o",
        str(vvp_file),
    ]
    compile_cmd.extend(str(path) for path in sources)

    print("Design compiling...")
    run_cmd(compile_cmd)

    # Step 8. 调用 vvp 工具运行仿真，遍历每一个 ebn0，生成对应的输出结果文件
    # 然后进行验证，统计错误比特数，然后删除仿真生成的中间文件
    # 这一步传入的关键参数为仿真时参数，比如输入文件路径、输出结果路径等
    data_dir = base_dir / ".." / "examples" / f"batch_len_{symbol_count}_counts_{example_count}"
    for i in range(31):
        ebn0 = i  # Eb/N0 从 0 到 30 dB
        golden_file = data_dir / f"ebn0_{ebn0}dB" / "data0.txt"
        input_file = data_dir / f"ebn0_{ebn0}dB" / "data3_fix.txt"
        bin_file = data_dir / f"ebn0_{ebn0}dB" / f"{rtl_tag}_rtl_output_fix.txt"
        if not input_file.exists():
            raise FileNotFoundError(f"Input file not found: {input_file}")
        vvp_cmd = [
            "vvp",
            str(vvp_file),
            f"+IN_FILE={input_file.as_posix()}",
            f"+OUT_FILE={bin_file.as_posix()}",
            f"+TIMEOUT_CYCLES={args.timeout_cycles}",
        ]
        print(f"Running simulation for Eb/N0 = {ebn0} dB...")
        run_cmd(vvp_cmd)
        print(f"Simulation completed for Eb/N0 = {ebn0} dB.")
        output_file = data_dir / f"ebn0_{ebn0}dB" / f"{rtl_tag}_error_bits.txt"
        
        # 执行验证，统计错误比特数，并将结果保存到 output_file 中
        print(f"Beginning verification for Eb/N0 = {ebn0} dB...")
        error_bits = verify_output(bin_file, golden_file, output_file)
        print(f"Verification completed for Eb/N0 = {ebn0} dB. Output saved to {output_file}. Error bits: {error_bits}")

        # 删除仿真生成的中间文件
        if bin_file.exists():
            bin_file.unlink()
            print(f"Deleted intermediate file: {bin_file}")

    print_summary_box("Batch Simulation Completed!", [
        f"RTL Module: {rtl_file.name}",
        f"Testbench: {tb_file.name}",
        f"Example Count: {example_count}",
        f"Symbol Count: {symbol_count}",
        f"Output Directory: {data_dir}"
    ])



if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError:
        sys.exit(1)
    except Exception as exc:
        print(exc)
        sys.exit(1)
