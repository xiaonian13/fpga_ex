# FPGA 图像处理入门学习笔记：RGB 转灰度与综合网表分析

## 1. FPGA 做图像处理，是否需要理解算法？

需要理解，但不一定要先把算法推导到很深。

FPGA 图像处理的重点不是只会背数学公式，而是要把算法转换成硬件可以执行的数据流结构。至少需要弄清楚：

- 输入是什么、输出是什么；
- 每个像素如何计算；
- 需要保存多少历史像素；
- 哪些运算可以并行；
- 哪些运算需要流水线；
- 中间结果需要多少位；
- 如何处理溢出、截断和舍入；
- 数据和有效信号如何保持同步。

对于一个图像算法，最好能回答下面几个问题：

1. 当前输出像素依赖哪些输入像素？
2. 每个像素需要进行哪些乘法、加法或比较？
3. 中间结果最大可能是多少？
4. 是否需要行缓存或滑动窗口？
5. 能否做到每个时钟处理一个像素？
6. 整个流水线延迟多少拍？

推荐学习路线：

```text
灰度转换
→ 二值化
→ RGB 转 YCbCr
→ Sobel 边缘检测
→ 均值滤波
→ 高斯滤波
→ 中值滤波
→ 腐蚀与膨胀
→ 图像缩放
```

推荐实践方式：

```text
理解算法
→ 用 Python 或 MATLAB 验证
→ 拆成逐像素计算
→ 设计 FPGA 流水线
→ 编写 Verilog
→ 仿真
→ 综合并分析电路
```

---

## 2. RGB 转灰度算法

常用灰度公式：

\[
Gray = 0.299R + 0.587G + 0.114B
\]

FPGA 中通常不用浮点小数，而是改写为定点整数：

\[
Gray = \frac{77R + 150G + 29B}{256}
\]

Verilog 中可写为：

```verilog
gray = (77 * R + 150 * G + 29 * B) >> 8;
```

其中：

```text
>> 8
```

相当于除以 \(256\)。

因为：

\[
77 + 150 + 29 = 256
\]

当：

```text
R = G = B = 255
```

时：

\[
Gray = 255
\]

---

## 3. RGB 转灰度流水线结构

一个典型三级流水线为：

```text
RGB 输入
   │
   ▼
第 1 级：三个常数乘法
R×77、G×150、B×29
   │
   ▼
第 2 级：三路相加
   │
   ▼
第 3 级：右移 8 位
   │
   ▼
Gray 输出
```

对应时钟过程：

```text
T0：输入 Pixel0，进行乘法
T1：Pixel0 进入加法级，Pixel1 进入乘法级
T2：Pixel0 进入右移级，Pixel1 进入加法级，Pixel2 进入乘法级
T3：输出 Gray0
T4：输出 Gray1
T5：输出 Gray2
```

特点：

- 首个结果需要等待约 3 个时钟周期；
- 流水线填满后，每个时钟可输出一个像素；
- 吞吐率为 `1 pixel/clock`；
- 延迟和吞吐率是两个不同概念。

---

## 4. RGB 转灰度 Verilog 示例

```verilog
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

    reg [15:0] r_mult;
    reg [15:0] g_mult;
    reg [15:0] b_mult;
    reg        valid_d1;

    reg [17:0] gray_sum;
    reg        valid_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_mult     <= 16'd0;
            g_mult     <= 16'd0;
            b_mult     <= 16'd0;
            valid_d1   <= 1'b0;

            gray_sum   <= 18'd0;
            valid_d2   <= 1'b0;

            gray_data  <= 8'd0;
            gray_valid <= 1'b0;
        end
        else begin
            // 第一级：常数乘法
            r_mult   <= rgb_r * 8'd77;
            g_mult   <= rgb_g * 8'd150;
            b_mult   <= rgb_b * 8'd29;
            valid_d1 <= pixel_valid;

            // 第二级：求和
            gray_sum <= r_mult + g_mult + b_mult;
            valid_d2 <= valid_d1;

            // 第三级：除以 256
            gray_data  <= gray_sum[15:8];
            gray_valid <= valid_d2;
        end
    end

endmodule
```

---

## 5. `gray_valid <= valid_d2;` 的作用

代码：

```verilog
valid_d1   <= pixel_valid;
valid_d2   <= valid_d1;
gray_valid <= valid_d2;
```

作用是把输入有效信号延迟到与灰度数据输出对齐。

数据路径：

```text
RGB 输入
→ 乘法
→ 加法
→ 右移
→ gray_data
```

有效信号路径：

```text
pixel_valid
→ valid_d1
→ valid_d2
→ gray_valid
```

二者都经过相同拍数。

因此：

```text
gray_valid = 1
```

表示当前的 `gray_data` 是有效像素。

下游通常这样使用：

```verilog
if (gray_valid) begin
    // 使用 gray_data
end
```

不能直接写：

```verilog
gray_valid <= pixel_valid;
```

否则有效信号会比数据提前，导致控制信号与像素错位。

### 非阻塞赋值的意义

```verilog
<=
```

是非阻塞赋值。

同一个时钟沿下：

```verilog
valid_d1   <= pixel_valid;
valid_d2   <= valid_d1;
gray_valid <= valid_d2;
```

每一级读取的是时钟沿到来前的旧值，因此每个时钟只向后传递一级。

---

## 6. 仿真程序的核心思路

测试平台需要完成以下工作：

1. 产生时钟；
2. 产生复位；
3. 连续输入多组 RGB 像素；
4. 计算期望灰度值；
5. 等待 `gray_valid`；
6. 自动比较 `gray_data` 与期望值；
7. 插入一个无效周期，检查 valid 流水线；
8. 输出 PASS 或 ERROR。

核心期望值计算：

```verilog
expected_gray =
    (77 * red + 150 * green + 29 * blue) >> 8;
```

建议测试数据：

| RGB 输入 | 预期灰度 |
|---|---:|
| `(0, 0, 0)` | 0 |
| `(255, 255, 255)` | 255 |
| `(255, 0, 0)` | 76 |
| `(0, 255, 0)` | 149 |
| `(0, 0, 255)` | 28 |
| `(100, 150, 200)` | 140 |
| `(25, 50, 75)` | 45 |

波形中重点观察：

```text
pixel_valid
valid_d1
valid_d2
gray_valid
r_mult
g_mult
b_mult
gray_sum
gray_data
```

---

## 7. 为什么综合后没有使用 DSP？

虽然 RTL 中写了：

```verilog
rgb_g * 8'd150
```

但 Verilog 只描述“需要乘法功能”，并没有规定必须使用 DSP。

Vivado 综合工具会根据以下因素决定使用 DSP 还是 LUT：

- 输入位宽；
- 乘数是否为常数；
- 时序要求；
- DSP 资源是否紧张；
- 综合策略；
- 逻辑资源与 DSP 的平衡。

这里的乘法具有两个特点：

```text
输入只有 8 位
乘数是固定常数
```

所以 Vivado 可能把它优化成移位和加法。

例如：

\[
150 = 128 + 16 + 4 + 2
\]

因此：

\[
G\times150=(G\ll7)+(G\ll4)+(G\ll2)+(G\ll1)
\]

移位通常只是布线，真正消耗资源的是加法。

于是综合结果可能使用：

```text
LUT + CARRY8 + FDCE
```

而不是 DSP48。

### 查看 DSP 是否使用

Vivado 中可查看：

```text
Open Synthesized Design
→ Report Utilization
→ DSP
```

也可在 Tcl Console 中执行：

```tcl
report_utilization
```

---

## 8. 左移与右移

### 左移

```verilog
A << n
```

表示二进制整体向左移动 \(n\) 位，低位补 0。

数学上相当于：

\[
A \times 2^n
\]

例如：

```text
00000101 = 5
00001010 = 5 << 1 = 10
00010100 = 5 << 2 = 20
```

### 右移

```verilog
A >> n
```

表示二进制整体向右移动 \(n\) 位，低位被丢弃。

对于无符号数，数学上相当于：

\[
\left\lfloor \frac{A}{2^n} \right\rfloor
\]

例如：

```text
00101000 = 40
00010100 = 40 >> 1 = 20
00000101 = 40 >> 3 = 5
```

### 固定移位在 FPGA 中的实现

固定移位通常不是一个真正的“移位器”，而是重新连接信号线。

例如：

```verilog
g_ext << 7
```

可理解为：

```text
输出高位连接输入各位
输出低 7 位接 0
```

### 位宽注意事项

不建议直接写：

```verilog
assign y = rgb_g << 7;
```

因为 `rgb_g` 只有 8 位，可能造成高位截断。

更稳妥的写法：

```verilog
wire [15:0] g_ext;

assign g_ext = {8'd0, rgb_g};

assign y = g_ext << 7;
```

---

## 9. LUT 如何实现乘法？

LUT 不是专用乘法器。

乘法可以拆分为：

```text
部分积生成
+ 移位
+ 多级加法
```

二进制乘法本质上是：

```text
与运算 + 移位 + 加法
```

例如：

```text
A × B
=
(A 与 b0) << 0
+
(A 与 b1) << 1
+
(A 与 b2) << 2
...
```

LUT 可以实现：

- 与、或、异或；
- 多路选择；
- 加法中的和位逻辑；
- 进位生成与传播逻辑；
- 常数乘法经过优化后的任意布尔逻辑。

实际 FPGA 结构常为：

```text
LUT：生成局部逻辑和加法条件
CARRY8：高速传播进位
FDCE：保存结果
```

---

## 10. `IBUF` 是什么？

`IBUF` 是 Input Buffer，即输入缓冲器。

RTL 中写：

```verilog
input [7:0] rgb_g;
```

综合后，每个外部输入引脚通常会经过一个 IBUF：

```text
FPGA 外部引脚
→ IBUF
→ FPGA 内部逻辑
```

例如：

```text
rgb_g_IBUF[0]_inst
rgb_g_IBUF[1]_inst
rgb_g_IBUF[2]_inst
```

分别对应 `rgb_g[0]`、`rgb_g[1]`、`rgb_g[2]` 的输入缓冲器实例。

作用：

- 接收芯片外部电平；
- 转换为 FPGA 内部可用的逻辑信号；
- 为每一个输入引脚提供标准输入通道。

---

## 11. `FDCE` 是什么？

`FDCE` 是 Xilinx FPGA 的触发器原语。

可以理解为：

```text
D 触发器
+ Clock Enable
+ 异步清零
```

端口：

| 端口 | 含义 |
|---|---|
| `D` | 数据输入 |
| `Q` | 数据输出 |
| `C` | 时钟 |
| `CE` | 时钟使能 |
| `CLR` | 高电平异步清零 |

等价 RTL：

```verilog
always @(posedge clk or posedge clr) begin
    if (clr)
        q <= 1'b0;
    else if (ce)
        q <= d;
end
```

主要作用：

- 保存 1 位数据；
- 产生 1 个时钟周期延迟；
- 构成流水线寄存器；
- 在复位时清零；
- 保持数据和控制信号同步。

例如：

```text
pixel_valid
→ FDCE
→ valid_d1
→ FDCE
→ valid_d2
→ FDCE
→ gray_valid
```

若 `g_mult` 是 16 位，则通常需要 16 个触发器分别保存每一位。

---

## 12. `CARRY8` 是什么？

`CARRY8` 是 Xilinx FPGA 内部的 8 位高速进位链。

主要用于：

- 加法器；
- 减法器；
- 计数器；
- 比较器；
- 常数乘法中的加法网络。

主要端口：

| 端口 | 含义 |
|---|---|
| `CI` | 低位进位输入 |
| `CI_TOP` | 另一进位输入通道 |
| `DI[7:0]` | 进位生成数据输入 |
| `S[7:0]` | 进位传播/选择输入 |
| `O[7:0]` | 和位输出 |
| `CO[7:0]` | 各级进位输出 |

典型配合方式：

```text
LUT
→ 产生每一位的和/进位条件
→ CARRY8
→ 高速传播进位
→ FDCE
→ 保存加法结果
```

为什么不用 LUT 一层层传播进位？

因为普通 LUT 级联传播较慢，而 CARRY8 使用 FPGA 芯片内部专门设计的高速进位通道。

---

## 13. 综合网表中的 `g_mult` 电路

RTL：

```verilog
g_mult <= rgb_g * 8'd150;
```

综合后大致变成：

```text
rgb_g 外部引脚
      │
      ▼
    IBUF
      │
      ▼
LUT3 / LUT4 / LUT5 / LUT6
      │
      ▼
    CARRY8
      │
      ▼
    FDCE
      │
      ▼
 g_mult 寄存结果
```

各部分作用：

```text
IBUF：输入缓冲
LUT：实现常数乘法的组合逻辑
CARRY8：完成高速加法和进位传播
FDCE：保存乘法结果，形成流水线
```

---

## 14. 整个 RGB 转灰度模块综合后的结构

完整结构可概括为：

```text
                    RGB 外部输入
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
       IBUF            IBUF            IBUF
         │               │               │
         ▼               ▼               ▼
       R[7:0]          G[7:0]          B[7:0]
         │               │               │
         ▼               ▼               ▼
      R×77            G×150            B×29
   LUT+CARRY8       LUT+CARRY8       LUT+CARRY8
         │               │               │
         ▼               ▼               ▼
       FDCE            FDCE            FDCE
         │               │               │
         └───────────────┼───────────────┘
                         ▼
                    三路加法网络
                    LUT + CARRY8
                         │
                         ▼
                       FDCE
                         │
                         ▼
                     gray_sum
                         │
                         ▼
                      右移 8 位
                      固定布线
                         │
                         ▼
                       FDCE
                         │
                         ▼
                     gray_data
```

与此同时，控制信号走另一条流水线：

```text
pixel_valid
→ valid_d1
→ valid_d2
→ gray_valid
```

最终保证：

```text
gray_valid 与 gray_data 同时有效
```

---

## 15. 该电路的主要特点

### 1. 数据流结构

不是 CPU 逐条执行指令，而是专门构造一条数据通路：

```text
输入 → 乘法 → 加法 → 右移 → 输出
```

### 2. 三级流水线

每一级之间都有寄存器：

```text
常数乘法 → 寄存器
三路加法 → 寄存器
右移输出 → 寄存器
```

### 3. 高吞吐率

流水线填满后：

```text
每个时钟输入 1 个像素
每个时钟输出 1 个灰度像素
```

### 4. 固定系数乘法没有使用 DSP

综合工具将乘法优化为：

```text
移位 + LUT + CARRY8
```

### 5. 右移通常只是布线

```verilog
gray_sum >> 8
```

主要是选择高位输出，不需要复杂运算单元。

---

## 16. 组合逻辑与时序逻辑的区分

### 组合逻辑

常见器件：

```text
LUT3
LUT4
LUT5
LUT6
CARRY8
```

特点：

- 输出由当前输入决定；
- 不保存历史状态；
- 不需要时钟；
- 负责计算。

### 时序逻辑

常见器件：

```text
FDCE
FDRE
```

特点：

- 在时钟沿保存数据；
- 能记住上一拍结果；
- 构成流水线；
- 负责状态和延迟。

### 输入/输出接口逻辑

常见器件：

```text
IBUF
OBUF
```

特点：

- 连接 FPGA 外部引脚与内部逻辑；
- 不属于算法核心运算。

---

## 17. 最终总结

这段 RGB 转灰度代码综合后，不是一个软件式的“乘法函数”，而是一条真实存在的硬件流水线：

```text
IBUF
→ LUT
→ CARRY8
→ FDCE
→ LUT/CARRY8 加法网络
→ FDCE
→ 固定右移布线
→ FDCE
```

其中：

- `IBUF` 负责把外部 RGB 信号送入 FPGA；
- `LUT` 负责实现常数乘法和局部组合逻辑；
- `CARRY8` 负责高速加法和进位传播；
- `FDCE` 负责保存中间结果并形成流水线；
- `valid_d1`、`valid_d2`、`gray_valid` 负责让控制信号与像素数据对齐；
- 流水线延迟约为 3 个时钟周期；
- 流水线填满后吞吐率为每时钟 1 个像素。

一句话概括：

> FPGA 综合工具把 `Gray = (77R + 150G + 29B) >> 8` 转换成了由输入缓冲、LUT、专用进位链和寄存器组成的三级定点流水线电路。
