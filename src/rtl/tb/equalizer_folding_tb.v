`timescale 1ns / 1ps

// 所有关键尺寸都通过编译宏传入，这样同一个 testbench 可以复用到不同 RTL 实现。
`ifndef INPUT_WIDTH
`define INPUT_WIDTH 8
`endif

`ifndef OUT_WIDTH
`define OUT_WIDTH 23
`endif

`ifndef SYMBOL_COUNT
`define SYMBOL_COUNT 100
`endif

`ifndef EXAMPLE_COUNT
`define EXAMPLE_COUNT 1
`endif

`ifndef RESET_CYCLES
`define RESET_CYCLES 4
`endif

`ifndef TIMEOUT_CYCLES
`define TIMEOUT_CYCLES 4096
`endif

module equalizer_tb;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg signed [`INPUT_WIDTH-1:0] data_in;

    wire valid_out;
    wire signed [`OUT_WIDTH-1:0] data_out;

    integer fd_in;
    integer fd_out;
    integer i;
    integer j;
    integer status;
    integer out_count;
    integer timeout_count;
    integer timeout_limit;

    reg capture_active;
    reg example_done;
    // 文件路径字符串
    reg [2047:0] in_file_path;
    // 输出文件路径
    reg [2047:0] out_file_path;

`ifdef DUMP_VCD
    reg [2047:0] vcd_file_path;
`endif

    // 输入数据存储器，存放了一整行 symbol_count 个输入信元，每个信元宽度为 input_width 位。
    reg signed [`INPUT_WIDTH-1:0] input_mem [0:`SYMBOL_COUNT-1];

    equalizer_folding dut (
        .clk(clk),               // in: 时钟
        .rst_n(rst_n),           // in: 复位，低有效
        .valid_in(valid_in),     // in: 输入有效信号
        .data_in(data_in),       // in: 输入数据，8 位有符号整数
        .valid_out(valid_out),   // out: 输出有效信号
        .data_out(data_out)      // out: 输出数据
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 每个样本前都复位一次 DUT，保证不同样本之间完全独立。
    task apply_reset;
    begin
        capture_active = 1'b0;
        example_done = 1'b0;
        out_count = 0;
        rst_n = 1'b0;
        valid_in = 1'b0;
        data_in = {`INPUT_WIDTH{1'b0}};
        repeat (`RESET_CYCLES) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
    end
    endtask

    // 按 folding 结构的节奏输入：
    // 1 个周期送入 1 个 symbol，随后保持 7 个周期空闲，
    // 因而相邻两次 valid_in 脉冲之间固定相隔 8 个周期。
    task send_symbol;
        input signed [`INPUT_WIDTH-1:0] symbol;
        integer idle_idx;
    begin
        @(negedge clk);
        valid_in = 1'b1;
        data_in = symbol;

        @(negedge clk);
        valid_in = 1'b0;
        data_in = {`INPUT_WIDTH{1'b0}};

        for (idle_idx = 0; idle_idx < 6; idle_idx = idle_idx + 1) begin
            @(negedge clk);
            valid_in = 1'b0;
            data_in = {`INPUT_WIDTH{1'b0}};
        end
    end
    endtask

    initial begin
        rst_n = 1'b0;
        valid_in = 1'b0;
        data_in = {`INPUT_WIDTH{1'b0}};
        capture_active = 1'b0;
        example_done = 1'b0;
        out_count = 0;
        timeout_limit = `TIMEOUT_CYCLES;

        // 解析命令行参数，获取输入输出文件路径和超时周期数。
        if (!$value$plusargs("IN_FILE=%s", in_file_path)) begin
            $display("ERROR: +IN_FILE missing");
            $finish;
        end
        if (!$value$plusargs("OUT_FILE=%s", out_file_path)) begin
            $display("ERROR: +OUT_FILE missing");
            $finish;
        end
        // status 表示成功解析到参数的数量，应该是 1，否则说明参数缺失或格式错误。
        status = $value$plusargs("TIMEOUT_CYCLES=%d", timeout_limit);

        // 打开输入输出文件，每一行是一个样本，包含多个信元
        fd_in = $fopen(in_file_path, "r");
        // 输出文件以写模式打开，如果文件已存在会被覆盖。
        fd_out = $fopen(out_file_path, "w");
        // 检查文件是否成功打开
        if (!fd_in || !fd_out) begin
            $display("ERROR: cannot open input/output file");
            $finish;
        end

        // 如果启用了 VCD 波形输出，检查是否提供了文件路径参数，否则使用默认路径。
`ifdef DUMP_VCD
        // 解析命令行参数获取 VCD 文件路径，如果没有提供则使用默认路径 "equalizer_folding.vcd"。
        if (!$value$plusargs("VCD_FILE=%s", vcd_file_path)) begin
            vcd_file_path = "equalizer_folding.vcd";
        end
        $dumpfile(vcd_file_path);
        $dumpvars(0, equalizer_tb);
`endif

        // 每行输入对应一个样本，每个样本抓取固定数量的有效输出并单独换行。
        for (i = 0; i < `EXAMPLE_COUNT; i = i + 1) begin
            for (j = 0; j < `SYMBOL_COUNT; j = j + 1) begin
                // 每个输入信元都是一个二进制字符串，解析到 input_mem 中。
                status = $fscanf(fd_in, "%b", input_mem[j]);
                if (status != 1) begin
                    $display("ERROR: failed to read input, example=%0d symbol=%0d", i, j);
                    $finish;
                end
            end

            // 对 DUT 施加复位，并开始抓取输出。
            apply_reset();
            // 开始抓取输出。
            capture_active = 1'b1;

            for (j = 0; j < `SYMBOL_COUNT; j = j + 1) begin
                // 每 8 个周期送入一个 symbol，输出的采样时刻由 DUT 的 valid_out 决定。
                send_symbol(input_mem[j]);
            end

            // 输入完一行后，停止输入并等待输出完成。这里通过一个超时计数器来避免死循环。
            timeout_count = 0;
            while (!example_done && timeout_count < timeout_limit) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end

            if (!example_done) begin
                $display("ERROR: output timeout, example=%0d", i);
                $finish;
            end

            capture_active = 1'b0;
        end

        // 所有样本处理完成后，关闭文件并结束仿真。
        $fclose(fd_in);
        $fclose(fd_out);
        $finish;
    end

    // 在时钟沿后稍等一小步，确保 DUT 的寄存器和组合逻辑都稳定下来。
    always @(posedge clk) begin
        if (!rst_n) begin
            out_count = 0;
            example_done = 1'b0;
        end else begin
            #1;
            // 如果输出有效并且处于输出数据接收 flow，则将输出数据写入文件。
            if (capture_active && !example_done && valid_out) begin
                // 每个输出数据之间用空格分隔，每行 `SYMBOL_COUNT` 个输出数据，最后一行结束后换行。
                if (out_count > 0) begin
                    // 写入一个空格
                    $fwrite(fd_out, " ");
                end
                // 写入输出数据的二进制字符串
                $fwrite(fd_out, "%b", data_out);
                out_count = out_count + 1;
                if (out_count >= `SYMBOL_COUNT) begin
                    $fwrite(fd_out, "\n");
                    example_done = 1'b1;
                end
            end
        end
    end

endmodule
