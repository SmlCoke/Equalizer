# =========================================================
# Vivado Non-Project Mode Synthesis Script (类似 Design Compiler)
# =========================================================

# 1. 设定全局变量
set TOP_MODULE "equalizer_unfolding_n2"   ;# 替换为你的顶层模块名
set PART "xcku040-ffva1156-2-e"         ;# KCU105 开发板对应的 FPGA 型号
set REPORT_DIR "../reports/"              ;# 报告输出目录

# 创建报告文件夹
file mkdir $REPORT_DIR

# 2. 读入源文件 (RTL)
# 如果是 Verilog:
read_verilog [glob ../../../src/rtl/unfolding/*.v]

# 3. 读入约束文件 (XDC)
read_xdc ../scripts/equalizer.xdc

# =========================================================
# 4. 执行综合 (等同于 DC 中的 compile 或 compile_ultra)
# =========================================================
puts "Starting Synthesis..."
synth_design -top $TOP_MODULE -part $PART -flatten_hierarchy rebuilt

# =========================================================
# 5. 生成报告 (等同于 DC 的 report_xxx 命令)
# =========================================================
puts "Generating Reports..."

#[1 & 3] 资源与面积报告 (Resource & Area)
# 注意：FPGA 没有绝对面积(um^2)，它的“面积”就是 LUT、FF、DSP、BRAM 的消耗量
report_utilization -file $REPORT_DIR/resource_area_utilization.rpt

# [2] 全局时序概览 (Timing Summary)
# 查看 WNS (最差负时序裕量), TNS (总负时序裕量) 等
report_timing_summary -file $REPORT_DIR/timing_summary.rpt

# [4] 关键路径报告 (Critical Path)
# 报出最差的 10 条路径的详细延时细节 (Cell Delay, Net Delay)
report_timing -sort_by group -max_paths 10 -nworst 1 -file $REPORT_DIR/critical_path.rpt

# [Bonus] 逻辑级数与设计分析 (类似 DC 的 report_qor / 逻辑深度分析)
# 查看关键路径的逻辑层级(Logic Levels)，如果太深(比如>10)会导致时序违例
report_design_analysis -logic_level_distribution -file $REPORT_DIR/design_analysis.rpt

# =========================================================
# 6. 保存综合后的设计数据库 (相当于 DC 的 write -f ddc)
# =========================================================
# 保存 Checkpoint，以后可以用 Vivado 打开这个 dcp 直接看网表和原理图
write_checkpoint -force ./post_synth.dcp

puts "Synthesis and Reporting Completed Successfully!"