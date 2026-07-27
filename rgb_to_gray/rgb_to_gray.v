module rgb_to_gray (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        pixel_valid,
    input  wire [7:0]  rgb_r,
    input  wire [7:0]  rgb_g,
    input  wire [7:0]  rgb_b,

    output reg         gray_valid,
    output reg  [7:0]  gray_data
);

    // 第一级流水线：分别进行乘法
    reg [15:0] r_mult;
    reg [15:0] g_mult;
    reg [15:0] b_mult;
    reg        valid_d1;

    // 第二级流水线：求和
    reg [17:0] gray_sum;
    reg        valid_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_mult    <= 16'd0;
            g_mult    <= 16'd0;
            b_mult    <= 16'd0;
            valid_d1  <= 1'b0;

            gray_sum  <= 18'd0;
            valid_d2  <= 1'b0;

            gray_data  <= 8'd0;
            gray_valid <= 1'b0;
        end else begin
            // 第一级：乘法运算
            r_mult   <= rgb_r * 8'd77;
            g_mult   <= rgb_g * 8'd150;
            b_mult   <= rgb_b * 8'd29;
            valid_d1 <= pixel_valid;

            // 第二级：三路结果相加
            gray_sum <= r_mult + g_mult + b_mult;
            valid_d2 <= valid_d1;

            // 第三级：除以256，即右移8位
            gray_data  <= gray_sum[15:8];
            gray_valid <= valid_d2;
        end
    end

endmodule
