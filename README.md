<div align="center">

# ⚡️Equalizer(均衡滤波器)
**VLSI 数字通信原理与设计 · 基于折叠架构与 AI 辅助设计的均衡滤波器硬件实现**

[![Version](https://img.shields.io/badge/Version-v1.0-blue.svg)]() [![Institution](https://img.shields.io/badge/Institution-SJTU-red.svg)](https://www.sjtu.edu.cn/) [![SmlCoke](https://img.shields.io/badge/SmlCoke-https://smlcoke.com-brightgreen.svg)](https://smlcoke.com) [![License](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

[项目简介](#i-项目简介) • [仓库结构](#ii-仓库结构) • [各模块说明](#iii-各模块说明) • [Quick Start](#iv-quick-start-guide) • [设计进度](#v-设计进度)

</div>

---

## I. 项目简介

Equalizer(均衡滤波器)项目为 VLSI 数字通信原理与设计 - Lab1 的完整设计仓库。项目旨在完成一款基于 FPGA 的数字均衡滤波器硬件实现，通过定点量化技术将基于 MATLAB 的通信系统多径信道中的均衡滤波算法转换为 RTL 硬件设计，并在目标器件上进行逻辑综合和性能分析。

**设计规格与性能目标**：
- **Target Device**: Kintex-UltraScale KCU105
- **Performance**: 综合后的时钟频率（Max Clock Frequency）需超过 **300MHz**。
- **Accuracy**: 误码率 (BER) 需满足 $10^{-6}$ @ $E_b/N_0 \leq 23\text{dB}$。

本项目深入研究由 RTL 硬件描述实现的多种架构，包括：
1. **Folding Architecture (折叠架构)**：面向面积 (Area) 优化的数字滤波器实现。
2. **Unfolding / Systolic Array (展开架构/脉动阵列)**：面向处理速度 (Speed) 和吞吐率 (Throughput) 优化的结构探索。
3. **AI-assisted circuit design**: 探索使用 LLM 辅助数字电路设计，实现高效的生成与优化验证闭环。

---

## II. 仓库结构

```text
Equalizer/
│
├── demo/                         # 示例代码资源 
│   ├── matlab/                   # MATLAB 通信链路及定点化仿真代码
│   │   ├── bpsk_theory.mat       # BPSK 理论参考数据
│   │   └── main.m                # 仿真核心脚本
│   └── verilog/                  # Verilog 均衡器实现参考示例代码
│       └── EF.v                  # 均衡滤波器参考实现
│
├── docs/                         # 课程资料与设计文档
│   ├── ai/                       # AI 辅助设计日志 (包含 prompt 迭代记录)
│   │   ├── ai_studio/            # AI Studio 对话日志
│   │   └── notebooklm/           # NotebookLM 对话日志
│   ├── assets/                   # 图片等静态资源
│   └── task.md                   # 原始实验任务要求书
│ 
├── src/                          # ★ RTL 源码及 Testbench 测试平台 (本项目核心编写)
│ 
└── README.md                     # 项目详细说明与指导
```

---

## III. 各模块说明

### 3.1 `docs/` — 项目设计文档与知识库

存放了实验任务指导书、基带调制/数字电路优化技术的知识库文档以及 AI 辅助设计的对话日志。

[实验任务指导书](/docs/task.md) 详细解释了实验的设计要求、性能目标、实现细节以及提交规范，包含软件仿真验证以及硬件实现设计两个板块的介绍。

### 3.2 `demo/` — 示例参考代码

`demo/matlab/` 提供了一个完整的基带通信链路仿真。主要功能为模拟 BPSK 信号通过包含符号间干扰 (ISI) 及白噪声 (AWGN) 的多径信道。在该模块中可以：

1. **提取参数**：生成 N-tap FIR 滤波器的定点化抽头系数。
2. **时序验证**：验证设计能否在高信噪比场景下达到误码率要求（即验证能否满足 $10^{-6}$ 的 BER，且此时 $E_b/N_0 \leq 23\text{dB}$）。
3. **数据预构建**：利用 MATALB `fi()` 函数，在设定的位宽与定点表达（如 1符号位+2整数位+5小数位）下进行数据 Saturation（饱和）与 Truncation（截位），导出供 Verilog Testbench 进行验证的底层软模拟标准件流。

阅读起点：[demo/matlab/main.m](demo/matlab/main.m)

---

### 3.3 `src/` — RTL 硬件电路设计与仿真

实现定点数字均衡滤波器（Equalization Filter, DUT），涵盖从 MATLAB 仿真、RTL 实现、动态仿真到逻辑综合的完整链路。涵盖如下三种架构，采用了不同的经典数字电路优化技术：

- **A1. Folding (折叠架构)** - **折叠运算节点**，达到精简资源、极小化电路面积 (Area) 的目的。
- **A2. Unfolding (展开架构)** - 将串行操作并行化，优化时钟路径以获取**极高的目标处理频率** (Speed)。
- **A3. Systolic Array (脉动阵列)** - 通过规则化的阵列处理结构和充分深度的流水线，实现理论上的高数据吞吐率 (Throughput)。

---
## IV. Quick Start Guide

### 4.1 环境准备

请确保本地备有以下三类关键环境：
- **MATLAB**：进行全链路模拟及其数据生成的浮点/定点环境支持。
- **ModelSim/QuestaSim 或者 Icarus Verilog**：可承载复杂 `readmemb`, `fwrite` Testbench 过程调用的行为仿真器。
- **Vivado**：具备在 Kintex-UltraScale 系列芯片上的综合、布局路线处理许可环境。

本项目采用工具版本：
- MATLAB R2025b
- ModelSim 10.5c
- Vivado 2018.1



---

## V. 设计进度

| 阶段 | 内容 | 进度 |
| --- | --- | --- |
| 架构理论分析 | MATLAB 仿真建模与系数计算 | ✅️ 已完成 |
| 定点量化 | 算法 -> 硬件 | | 🔲 进行中 |
| RTL 实现 | 基础版本：折叠架构 | 🔲 待完成 |
| RTL 实现 | 进阶版本：展开架构 / 脉动阵列 | 🔲 待完成 |
| 动态仿真= | ModelSim 仿真执行以及位对标校验  | 🔲 待完成 
| 逻辑综合 | Vivado 逻辑综合与资源评估 | 🔲 待完成 |
