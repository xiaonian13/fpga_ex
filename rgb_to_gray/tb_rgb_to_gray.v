`timescale 1ns / 1ps

module tb_rgb_to_gray;

    //==================================================
    // 1. 仿真输入信号
    //==================================================
    reg         clk;
    reg         rst_n;

    reg         pixel_valid;
    reg  [7:0]  rgb_r;
    reg  [7:0]  rgb_g;
    reg  [7:0]  rgb_b;

    //==================================================
    // 2. 仿真输出信号
    //==================================================
    wire        gray_valid;
    wire [7:0]  gray_data;

    //==================================================
    // 3. 预期结果存储
    //==================================================
    reg [7:0] expected_gray [0:31];

    integer write_ptr;
    integer read_ptr;
    integer error_count;

    //==================================================
    // 4. 例化待测试模块
    //==================================================
    rgb_to_gray uut (
        .clk         (clk),
        .rst_n       (rst_n),

        .pixel_valid (pixel_valid),
        .rgb_r       (rgb_r),
        .rgb_g       (rgb_g),
        .rgb_b       (rgb_b),

        .gray_valid  (gray_valid),
        .gray_data   (gray_data)
    );

    //==================================================
    // 5. 生成时钟
    // 时钟周期为10ns，频率为100MHz
    //==================================================
    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    //==================================================
    // 6. 输入一个有效RGB像素
    //==================================================
    task send_pixel;

        input [7:0] r;
        input [7:0] g;
        input [7:0] b;

        integer gray_temp;

        begin
            // 在时钟下降沿改变数据，
            // 保证在下一个上升沿到来前数据已经稳定
            @(negedge clk);

            pixel_valid = 1'b1;
            rgb_r       = r;
            rgb_g       = g;
            rgb_b       = b;

            // 计算该像素对应的预期灰度值
            gray_temp = (77 * r + 150 * g + 29 * b) >> 8;

            expected_gray[write_ptr] = gray_temp[7:0];

            $display(
                "[输入] time=%0t, RGB=(%0d,%0d,%0d), 预期Gray=%0d",
                $time,
                r,
                g,
                b,
                gray_temp
            );

            write_ptr = write_ptr + 1;
        end

    endtask

    //==================================================
    // 7. 发送一个无效周期
    //==================================================
    task send_invalid;

        begin
            @(negedge clk);

            pixel_valid = 1'b0;
            rgb_r       = 8'd0;
            rgb_g       = 8'd0;
            rgb_b       = 8'd0;
        end

    endtask

    //==================================================
    // 8. 自动检查输出结果
    //==================================================
    always @(posedge clk) begin

        // 等待非阻塞赋值更新完成
        #1;

        if (rst_n && gray_valid) begin

            if (read_ptr >= write_ptr) begin

                $display(
                    "[错误] time=%0t, 出现了多余的有效输出，gray_data=%0d",
                    $time,
                    gray_data
                );

                error_count = error_count + 1;

            end
            else if (gray_data !== expected_gray[read_ptr]) begin

                $display(
                    "[错误] time=%0t, 第%0d个像素：实际值=%0d，预期值=%0d",
                    $time,
                    read_ptr,
                    gray_data,
                    expected_gray[read_ptr]
                );

                error_count = error_count + 1;
                read_ptr    = read_ptr + 1;

            end
            else begin

                $display(
                    "[正确] time=%0t, 第%0d个像素：gray_data=%0d",
                    $time,
                    read_ptr,
                    gray_data
                );

                read_ptr = read_ptr + 1;

            end

        end

    end

    //==================================================
    // 9. 仿真激励
    //==================================================
    initial begin

        // 初始化
        rst_n       = 1'b0;
        pixel_valid = 1'b0;

        rgb_r = 8'd0;
        rgb_g = 8'd0;
        rgb_b = 8'd0;

        write_ptr   = 0;
        read_ptr    = 0;
        error_count = 0;

        // 保持复位3个时钟周期
        repeat (3) @(posedge clk);

        // 在下降沿释放复位
        @(negedge clk);
        rst_n = 1'b1;

        $display("========================================");
        $display("开始RGB转灰度流水线仿真");
        $display("========================================");

        // 连续输入多个像素
        send_pixel(8'd255, 8'd0,   8'd0);     // 红色，预期约76
        send_pixel(8'd0,   8'd255, 8'd0);     // 绿色，预期约149
        send_pixel(8'd0,   8'd0,   8'd255);   // 蓝色，预期约28
        send_pixel(8'd255, 8'd255, 8'd255);   // 白色，预期255
        send_pixel(8'd0,   8'd0,   8'd0);     // 黑色，预期0
        send_pixel(8'd100, 8'd150, 8'd200);   // 普通颜色

        // 加入两个无效周期
        send_invalid();
        send_invalid();

        // 再输入两个像素，验证中断后能否正常工作
        send_pixel(8'd50, 8'd100, 8'd150);
        send_pixel(8'd30, 8'd60, 8'd90);

        // 停止输入
        send_invalid();

        // 等待流水线中的数据全部输出
        repeat (8) @(posedge clk);

        #2;

        $display("========================================");

        if ((error_count == 0) && (read_ptr == write_ptr)) begin
            $display("仿真通过：所有灰度结果均正确！");
            $display("总输入像素数量：%0d", write_ptr);
            $display("总输出像素数量：%0d", read_ptr);
        end
        else begin
            $display("仿真失败！");
            $display("输入像素数量：%0d", write_ptr);
            $display("输出像素数量：%0d", read_ptr);
            $display("错误数量：%0d", error_count);
        end

        $display("========================================");

        $finish;

    end

endmodule
