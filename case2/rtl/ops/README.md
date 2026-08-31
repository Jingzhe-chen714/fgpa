# case2 像素算子（`rtl/ops`）

当前实现是单像素基线，独立于 framebuffer、命令解析器和板级 top。所有模块都
使用标准 SystemVerilog，不依赖 Xilinx/Efinix 原语。

## 像素格式与字节序

`PIXEL_FORMAT=0`（默认）为 RGB565：`pixel[15:11]=R5`、`pixel[10:5]=G6`、
`pixel[4:0]=B5`。`PIXEL_FORMAT=1` 为 RGB888：`pixel[23:16]=R8`、
`pixel[15:8]=G8`、`pixel[7:0]=B8`。默认像素总线宽度分别为 16 和 24 bit，
也可通过 `PIXEL_W` 显式设置为对应宽度。

`pixel_pack_bytes`/`pixel_unpack_bytes` 统一低地址字节序：RGB565 的
`byte0=pixel[7:0]`、`byte1=pixel[15:8]`，RGB888 的
`byte0=B`、`byte1=G`、`byte2=R`。`pixel_pack`/`pixel_unpack` 负责 8-bit
通道与打包像素之间的转换；RGB565 通道量化取高位，解包采用位复制扩展。

## `alpha_blend_pixel`

组合逻辑接口：

```systemverilog
alpha_blend_pixel #(.PIXEL_FORMAT(0)) u_blend (
  .fg_pixel(fg), .bg_pixel(bg), .alpha(alpha), .out_pixel(out)
);
```

每个原生通道独立计算：

```text
round((fg * alpha + bg * (255 - alpha)) / 255)
```

实现为整数 `(numerator + 128) / 255`，即明确使用 `+128` 四舍五入偏置；结果
随后裁剪到通道最大值（RGB565 为 31/63/31，RGB888 为 255）。因此 alpha=0
严格输出背景，alpha=255 严格输出前景。`alpha_blend_rgb565` 和
`alpha_blend_rgb888` 是固定格式别名。

## `alpha_blend` / `color_key` 流接口

两个模块都是一个寄存器深度的 ready/valid 弹性缓冲：

```systemverilog
input  clk, rst_n;                 // rst_n：低有效异步复位
input  in_valid; output in_ready;
// alpha_blend: fg_pixel, bg_pixel, alpha
// color_key:   src_pixel, background_pixel, key_pixel
output out_valid; input out_ready; output out_pixel;
```

仅在 `in_valid && in_ready` 时采样输入；当 `out_valid=1 && out_ready=0` 时，
输出数据和 valid 保持不变。输出被消费的同一拍可以接收下一像素。`color_key`
还输出与该结果对齐的 `out_key_hit`。

## `color_key_pixel`

组合逻辑接口为 `src_pixel`、`background_pixel`、`key_pixel`、`out_pixel` 和
`key_hit`。命中 key 时认为源像素透明，输出背景；未命中时原样复制源像素。
RGB565 比较按 R5/G6/B5 字段进行，避免帧缓存字节交换造成误命中。

## 自检仿真

`tb_pixel_ops.sv` 覆盖 alpha=0/255、RGB565 舍入、RGB888 参数化路径、打包/解包、
color-key 命中/未命中以及 ready/valid 背压。Vivado XSIM 示例：

```powershell
xvlog.bat -sv pixel_pack.sv alpha_blend_pixel.sv alpha_blend.sv `
  color_key_pixel.sv color_key.sv tb_pixel_ops.sv
xelab.bat tb_pixel_ops -s tb_pixel_ops_sim
xsim.bat tb_pixel_ops_sim -runall
```

成功时打印 `TB_PIXEL_OPS_PASS`。

