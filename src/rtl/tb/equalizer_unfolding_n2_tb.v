`timescale 1ns / 1ps

// 所有关键尺寸都通过编译宏传入，这样同一个 testbench 可以复用到不同 RTL 实现。

`ifndef INPUT_WIDTH
`define INPUT_WIDTH 8
`endif

`ifndef OUT_WIDTH
`define OUT_WIDTH 19
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
    reg signed [`INPUT_WIDTH-1:0] data_in_even;
    reg signed [`INPUT_WIDTH-1:0] data_in_odd;

    wire valid_out;
    wire signed [`OUT_WIDTH-1:0] data_out_even;
    wire signed [`OUT_WIDTH-1:0] data_out_odd;

    integer fd_in;
    integer fd_out;
    integer i;
    integer j;
    integer status;
    integer out_count;
    integer timeout_count;
    integer timeout_limit;

    integer pair_count;
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

    equalizer_unfolding_n2 dut (
        .clk(clk),                   // in: 时钟
        .rst_n(rst_n),               // in: 复位，低有效
        .valid_in(valid_in),         // in: 输入有效信号
        .data_in_even(data_in_even), // in: 偶序列输入
        .data_in_odd(data_in_odd),   // in: 奇序列输入
        .valid_out(valid_out),       // out: 输出有效信号
        .data_out_even(data_out_even), // out: 偶序列输出
        .data_out_odd(data_out_odd)    // out: 奇序列输出
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
        data_in_even = {`INPUT_WIDTH{1'b0}};
        data_in_odd = {`INPUT_WIDTH{1'b0}};
        repeat (`RESET_CYCLES) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
    end
    endtask

    initial begin
        rst_n = 1'b0;
        valid_in = 1'b0;
        data_in_even = {`INPUT_WIDTH{1'b0}};
        data_in_odd = {`INPUT_WIDTH{1'b0}};
        capture_active = 1'b0;
        example_done = 1'b0;
        out_count = 0;
        timeout_limit = `TIMEOUT_CYCLES;

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

`ifdef DUMP_VCD
        if (!$value$plusargs("VCD_FILE=%s", vcd_file_path)) begin
            vcd_file_path = "equalizer_unfolding_n2.vcd";
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
            capture_active = 1'b1;
            pair_count = (`SYMBOL_COUNT + 1) / 2;

            for (j = 0; j < pair_count; j = j + 1) begin
                // 每个时钟下降沿输入一对数据，最后一个奇位不足时补零。
                @(negedge clk);
                valid_in = 1'b1;
                data_in_even = input_mem[2*j];
                if ((2*j + 1) < `SYMBOL_COUNT) begin
                    data_in_odd = input_mem[2*j + 1];
                end else begin
                    data_in_odd = {`INPUT_WIDTH{1'b0}};
                end
            end

            // 输入完一行后，停止输入并等待输出完成。这里通过一个超时计数器来避免死循环。
            @(negedge clk);
            valid_in = 1'b0;
            data_in_even = {`INPUT_WIDTH{1'b0}};
            data_in_odd = {`INPUT_WIDTH{1'b0}};

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
            // 如果输出有效并且处于输出数据接收 flow, 按 even->odd 顺序写回单序列文件。
            if (capture_active && !example_done && valid_out) begin
                if (out_count < `SYMBOL_COUNT) begin
                    if (out_count > 0) begin
                        $fwrite(fd_out, " ");
                    end
                    $fwrite(fd_out, "%b", data_out_even);
                    out_count = out_count + 1;
                end

                if (out_count < `SYMBOL_COUNT) begin
                    if (out_count > 0) begin
                        $fwrite(fd_out, " ");
                    end
                    $fwrite(fd_out, "%b", data_out_odd);
                    out_count = out_count + 1;
                end

                if (out_count >= `SYMBOL_COUNT) begin
                    $fwrite(fd_out, "\n");
                    example_done = 1'b1;
                end
            end
        end
    end

endmodule

