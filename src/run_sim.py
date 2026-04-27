'''
脚本: run_sim.py
作者: Equalizer 团队
日期: 2026-04-18
版本: v1.0
功能: 
    1. 自动解析输入数据形状以及输入输出位宽，获取编译宏
    2. 调用 Icarus Verilog 工具编译 testbench 以及 RTL 模块
    3. 调用 vvp 工具运行仿真，生成输出结果文件
    4. 将仿真结果从二进制补码转换为浮点，保存到文件，方便对比
    5. 根据用户参数决定是否打开波形文件和预览输出值
    6. 对比 RTL 仿真输出与 MATLAB 的标准输出，验证 RTL 功能正确性
'''
import argparse
import subprocess
import sys
from pathlib import Path
from common import print_summary_box, run_cmd, resolve_user_path, get_tb_file, parse_port_width, scan_input_file

def parse_args():
    parser = argparse.ArgumentParser(description="Equalizer simulation runner")
    # 输入 RTL 模块，默认 baseline 方案
    parser.add_argument("--rtl-file", default="rtl/baseline/equalizer.v", help="RTL top file, relative to src/")
    # testbench 顶层模块名
    parser.add_argument("--data-dir", default="../examples/len_100_counts_1000", help="Input data directory")
    # 输出数据小数部分位宽，默认为10，整个实验中一般不会改动
    parser.add_argument("--frac-bits", type=int, default=10, help="Fraction bits for float conversion")
    # 每个样本的最大等待周期数，默认为4096，过小可能导致仿真不完整，过大可能导致仿真时间过长。
    parser.add_argument("--timeout-cycles", type=int, default=4096, help="Max wait cycles per example")
    # 是否打印波形
    parser.add_argument("--wave", action="store_true", help="Dump VCD waveform")
    # 是否在仿真结束后自动打开波形文件
    parser.add_argument("--view-wave", action="store_true", help="Open waveform with gtkwave")
    return parser.parse_args()



# 根据自定义量化格式，将二进制补码转化为浮点数，方便对比和分析
def bin_to_float(bin_str, frac_bits):
    '''
    将二进制补码字符串转换为浮点数，frac_bits 指定小数部分的位宽
    总位宽由字符串长度决定，因此整数部分位宽可以自动推断出。
    整个实验项目中，小数部分位宽一般固定为10位
    '''
    value = int(bin_str, 2)
    width = len(bin_str)
    if value & (1 << (width - 1)):
        value -= 1 << width
    return value / (2 ** frac_bits)

# 将仿真输出的二进制补码文本文件转换为浮点数文本文件，方便对比和分析
def write_float_file(bin_file, float_file, frac_bits):
    """
    Write one float-output txt with the same line structure as the raw binary txt.
    """
    with bin_file.open("r", encoding="utf-8") as fin, float_file.open("w", encoding="utf-8") as fout:
        for line in fin:
            tokens = line.strip().split()
            if not tokens:
                continue
            values = [f"{bin_to_float(token, frac_bits):.16g}" for token in tokens]
            fout.write(" ".join(values) + "\n")

# 预览输出 float
def preview_line(float_file, limit):
    with float_file.open("r", encoding="utf-8") as fin:
        first_line = fin.readline().strip().split()
    if not first_line:
        return ""
    return " ".join(first_line[:limit])
    
def verify(float_file, gold_file, mismatch_file):
    '''
    逐行、逐个对比 float 结果
    如果不匹配，把所有不匹配的信息保存到 csv
    '''
    mismatch = []
    example_counts = 0
    symbol_counts = 0
    with float_file.open("r", encoding="utf-8") as f1, gold_file.open("r", encoding="utf-8") as f2:
        for line_num, (line1, line2) in enumerate(zip(f1, f2), start=1):
            tokens1 = line1.strip().split()
            tokens2 = line2.strip().split()
            if len(tokens1) != len(tokens2):
                raise ValueError(f"Line {line_num}: token count mismatch: {len(tokens1)} vs {len(tokens2)}")
            for idx, (t1, t2) in enumerate(zip(tokens1, tokens2)):
                f1_val = float(t1)
                f2_val = float(t2)
                if abs(f1_val - f2_val) > 1e-6:
                    mismatch.append((line_num, idx + 1, f1_val, f2_val))
            # 统计符号数量和样本数量
            symbol_counts += len(tokens1)
            example_counts += 1
    if not mismatch:
        print_summary_box("Verification Report", [
            ("Status", "^_^ Passed!"),
            ("Example Count", str(example_counts)),
            ("Symbol Count", str(symbol_counts))
        ])
    else:
        with mismatch_file.open("w", encoding="utf-8") as fout:
            fout.write("line_num,token_idx,rtl_value,gold_value\n")
            for line_num, token_idx, rtl_val, gold_val in mismatch:
                fout.write(f"{line_num},{token_idx},{rtl_val:.16g},{gold_val:.16g}\n")
        print_summary_box(f"Verification Report" , [
            ("Status", "T_T Failed!"),
            ("Total Mismatch", str(len(mismatch))),
            ("Mismatch File", mismatch_file.name)
        ])


def main():
    # step 1. 解析参数
    args = parse_args()

    # step 2. 获取各个文件的文件目录
    base_dir = Path(__file__).resolve().parent
    # 解析 RTL 模块路径
    rtl_file = resolve_user_path(base_dir, args.rtl_file)
    # 解析输入数据文件夹路径
    data_dir = resolve_user_path(base_dir, args.data_dir)
    # 解析 Testbench 文件路径
    tb_file = get_tb_file(base_dir, rtl_file)
    # 强制指定 testbench 顶层模块名为 equalizer_tb，保持和 testbench 文件中的一致，简化用户输入
    tb_top = "equalizer_tb"  
    input_file = data_dir / "input_fix.txt"

    if not rtl_file.exists():
        raise FileNotFoundError(f"RTL file not found: {rtl_file}")
    if not tb_file.exists():
        raise FileNotFoundError(f"Testbench file not found: {tb_file}")
    if not input_file.exists():
        raise FileNotFoundError(f"Input file not found: {input_file}")

    # Step 3. 正则表达式自动获取 RTL 模块的 data_in, data_out 位宽，兼容多种声明格式
    if ("unfolding" in rtl_file.parent.name):
        input_width = parse_port_width(rtl_file, "data_in_even", "input")
        output_width = parse_port_width(rtl_file, "data_out_even", "output")
    else:
        input_width = parse_port_width(rtl_file, "data_in", "input")
        output_width = parse_port_width(rtl_file, "data_out", "output")

    # Step 4. 扫描输入文件，获取 example_count 和 symbol_count
    # 当然，我们也可以直接从 config_meta.json 中读取
    example_count, symbol_count = scan_input_file(input_file)

    # Step 5. 创建编译产物和输出文件路径
    rtl_tag = rtl_file.parent.name
    build_dir = base_dir / "rtl" / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    vvp_file = build_dir / f"{rtl_tag}.vvp"
    vcd_file = build_dir / f"{rtl_tag}.vcd"
    bin_file = data_dir / f"{rtl_tag}_rtl_output_fix.txt"
    float_file = data_dir / f"{rtl_tag}_rtl_output_float.txt"

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
    # 根据输入参数决定是否打印波形
    if args.wave or args.view_wave:
        compile_cmd.append("-DDUMP_VCD")
    compile_cmd.extend(str(path) for path in sources)

    print("Design compiling...")
    run_cmd(compile_cmd)

    # Step 7. 调用 vvp 工具运行仿真
    # 这一步传入的关键参数为仿真时参数，比如输入文件路径、输出结果路径等
    vvp_cmd = [
        "vvp",
        str(vvp_file),
        f"+IN_FILE={input_file.as_posix()}",
        f"+OUT_FILE={bin_file.as_posix()}",
        f"+TIMEOUT_CYCLES={args.timeout_cycles}",
    ]
    # 根据输入参数决定是否打印波形，如果打印波形则传入波形文件路径参数，供 testbench 中的 $dumpfile 使用
    if args.wave or args.view_wave:
        vvp_cmd.append(f"+VCD_FILE={vcd_file.as_posix()}")

    print("Running simulation...")
    run_cmd(vvp_cmd)

    # Step 8. testbench 将二进制补码形式的结果保存到文件，由 python 转换为浮点数形式
    write_float_file(bin_file, float_file, args.frac_bits)

    # Step 9. 打印本次仿真报告
    print_summary_box("Simulation Report",[
        ("RTL", rtl_file.name),
        ("Testbench", tb_file.name),
        ("Input Width", str(input_width)),
        ("Output Width", str(output_width)),
        ("Example Count", str(example_count)),
        ("Symbol Count", str(symbol_count)),
        ("Bin Result", bin_file.name),
        ("Float Result", float_file.name),
        ("Preiview", preview_line(float_file, 4))
    ])

    # Step 10. 验证输出结果是否正确
    gold_file = data_dir / "output_float.txt"
    mismatch_file = data_dir / "mismatch.csv"
    if not gold_file.exists():
        print(f"Gold file not found: {gold_file}")
        sys.exit(1)

    print("Verifying RTL output against gold output...")
    verify(float_file, gold_file, mismatch_file)

    # Step 10. 根据 view_wave 参数决定是否调用 gtkwave 工具打开波形文件
    if args.view_wave:
        subprocess.Popen(["gtkwave", str(vcd_file)])




if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError:
        sys.exit(1)
    except Exception as exc:
        print(exc)
        sys.exit(1)
