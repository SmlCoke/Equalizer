import textwrap
import subprocess
import re
from pathlib import Path
from typing import List, Tuple

def add_box_field(lines: List[str], label: str, value: str, wrap_width: int = 54) -> None:
    """给终端摘要框追加一个自动换行的字段。"""
    prefix = f"{label:<12}: "
    wrapped = textwrap.wrap(value, width=wrap_width) or ["None"]
    lines.append(prefix + wrapped[0])
    lines.extend((" " * len(prefix)) + item for item in wrapped[1:])


def print_summary_box(title: str, fields: List[Tuple[str, str]]) -> None:
    """打印最终通过/失败摘要框。"""
    lines: List[str] = [title, ""]
    for label, value in fields:
        add_box_field(lines, label, value)

    inner_width = max(len(line) for line in lines)
    border = "+" + ("-" * (inner_width + 2)) + "+"
    print(border)
    for line in lines:
        print(f"| {line.ljust(inner_width)} |")
    print(border)


def run_cmd(cmd):
    subprocess.run(cmd, check=True)


def resolve_user_path(base_dir, path_str):
    path = Path(path_str)
    if not path.is_absolute():
        path = base_dir / path
    return path.resolve()

# 根据 RTL 文件路径自动推断 Testbench 文件路径
def get_tb_file(base_dir, rtl_file):
    rtl_name = rtl_file.stem
    candidate_tb = base_dir / "rtl" / "tb" / f"{rtl_name}_tb.v"
    if candidate_tb.exists():
        return candidate_tb
    else:
        raise FileNotFoundError(f"Testbench file not found for {rtl_file}. Expected at {candidate_tb}")
    

def strip_comments(text):
    '''
    去除 Verilog 代码中的注释，支持单行注释 // 和多行注释 /* */
    防止注释干扰正则表达式匹配端口声明
    '''
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//.*", " ", text)
    return " ".join(text.split())

# 解析 RTL 模块的输入/输出数据位宽
def parse_port_width(rtl_file, port_name, direction):
    '''
    解析 RTL 模块的输入/输出数据位宽
    rtl_file: RTL 文件路径
    port_name: 端口名称，如 data_in 或 data_out
    direction: "input" 或 "output"
    '''
    text = strip_comments(rtl_file.read_text(encoding="utf-8"))
    # 正则匹配输入/输出端口声明，支持 wire/reg、signed、input/output、位宽
    pattern = re.compile(
        rf"\b{direction}\b\s+(?:wire\s+|reg\s+)?(?:signed\s+)?"
        rf"(?:\[\s*(\d+)\s*:\s*(\d+)\s*\]\s+)?{port_name}\b"
    )
    match = pattern.search(text)
    if match is None:
        # 如果没有找到匹配的端口声明，抛出错误提示用户检查 RTL 文件
        raise ValueError(f"cannot find {direction} port '{port_name}' in {rtl_file}")
    if match.group(1) is None:
        # 如果没有位宽声明，默认为 1 位
        return 1
    # 计算位宽，msb - lsb + 1 就是位宽
    msb = int(match.group(1))
    lsb = int(match.group(2))
    return abs(msb - lsb) + 1

# 扫描输入文件，统计样本数量和每个样本的符号数量
def scan_input_file(input_file):
    '''
    扫描输入文件，统计:
    example_count: 样本数量，即行数
    symbol_count: 每个样本的符号数量，即行的二进制编码个数
    '''
    example_count = 0
    symbol_count = 0
    with input_file.open("r", encoding="utf-8") as fin:
        for line in fin:
            tokens = line.strip().split()
            if not tokens:
                continue
            if example_count == 0:
                symbol_count = len(tokens)
            example_count += 1
    if example_count == 0 or symbol_count == 0:
        raise ValueError(f"empty input file: {input_file}")
    return example_count, symbol_count