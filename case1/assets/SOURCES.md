# Case 1 测试图像来源与使用边界

核对日期：2026-08-24。

本目录把测试资产分成两类：

1. `images/` 中许可明确的图片可用于算法回归、演示和随工程再分发；
2. `local_only/` 中版权链不完整的经典测试图片只作为本地可选回归输入，不应提交到公开仓库、比赛交付物或答辩材料。

## 默认测试集：许可明确、可再分发

以下文件固定取自 scikit-image `v0.25.2` 标签，而不是会变化的 `main` 分支。scikit-image 的[数据文档](https://scikit-image.org/docs/stable/api/skimage.data)逐项给出了图片来源和许可；软件本身的 BSD 许可不能替代这些图片各自的许可说明。

| 本地文件 | 固定版本来源 | 许可/来源说明 | 主要测试用途 |
|---|---|---|---|
| `images/astronaut.png` | [scikit-image v0.25.2 astronaut.png](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/astronaut.png) | NASA 来源；scikit-image 文档标注为 public domain | 人物、肤色、平滑区域和细节 |
| `images/brick.png` | [scikit-image v0.25.2 brick.png](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/brick.png) | 原图来自 CC0Textures；CC0 | 周期纹理、卷积和行缓存 |
| `images/camera.png` | [scikit-image v0.25.2 camera.png](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/camera.png) | 摄影师 Lav Varshney；CC0。scikit-image 0.18 起已用此图替换旧的版权受限 cameraman 图 | 灰阶、中性色和动态范围 |
| `images/chelsea.png` | [scikit-image v0.25.2 chelsea.png](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/chelsea.png) | 摄影师 Stefan van der Walt；CC0 | 毛发、高频纹理和斜向边缘 |
| `images/coffee.png` | [scikit-image v0.25.2 coffee.png](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/coffee.png) | 摄影师 Rachel Michetti；CC0 | 暖色、渐变和木纹 |
| `images/rocket.jpg` | [scikit-image v0.25.2 rocket.jpg](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/rocket.jpg) | SpaceX 拍摄；scikit-image 文档标注为 public domain | 暗部、大面积渐变和强轮廓 |

### 功能性风格训练目标

| 本地文件 | 固定来源页 | 许可/来源说明 | 使用边界 |
|---|---|---|---|
| `styles/starry_night_public_domain.jpg` | [Wikimedia Commons: TheStarryNightByVincentVanGogh.jpg](https://commons.wikimedia.org/wiki/File:TheStarryNightByVincentVanGogh.jpg)；下载时使用 Commons `Special:Redirect/file/...?...width=1024` 缩略图接口 | Vincent van Gogh 1889 年作品；Commons 文件页标记 Public Domain Mark 1.0，并说明作品及该文件无已知版权限制 | 仅作为 `MicroStyle-24` 功能性短程训练的单风格目标；训练产物明确不宣称最终画质收敛 |

该风格文件单独放在 `styles/`，不是默认内容测试集成员。`model/train_microstyle_qat.py` 只使用上表六张许可明确的默认图片作为内容样本。

公开展示优先使用以上图片、团队自行拍摄的图片，以及 `generated/` 中的确定性合成图。

## 确定性合成资产

`generated/` 由 [`../golden/generate_synthetic_assets.py`](../golden/generate_synthetic_assets.py) 离线生成，不下载或嵌入任何第三方图像。默认包含全黑、全白、中灰、RGB 色条、水平/垂直灰阶 ramp、1 像素与 8 像素 checkerboard、中心 impulse 和固定 seed 随机图，并覆盖多种奇偶尺寸。

从仓库根目录复现：

```powershell
D:\miniconda\miniconda\envs\SWPC_ENV\python.exe .\case1\golden\generate_synthetic_assets.py
```

脚本会写出 `generated/manifest.json`，记录生成参数、尺寸和文件清单；不依赖文件摘要作为验证手段。

## 本地可选测试集：不建议再分发

下列现有文件保留给本地兼容性或历史基准测试，但来源仓库或镜像不等于版权许可。它们不应成为默认回归的必需输入，也不应出现在公开答辩材料中。

| 本地文件 | 当前获取来源 | 使用边界 |
|---|---|---|
| `local_only/lena_color_512.tif` | `androbaza/standard-test-images` 的第三方副本 | Lenna 源自 Playboy 照片，版权链不适合再分发；USC-SIPI 已[停止分发 Lena](https://sipi.usc.edu/database/database.php?volume=misc)。仅本地可选，公开材料禁用 |
| `local_only/mandril_color.tif` | `androbaza/standard-test-images` 的第三方副本 | Mandrill/Baboon 的来源及授权不清；仅本地可选，不建议再分发 |
| `local_only/peppers.png`、`local_only/peppers_color.tif` | 第三方代码仓库或经典测试图集合 | Peppers 的来源及授权不清；仅本地可选，不建议再分发 |
| `local_only/kodim23.png` | [非官方 Kodak PCD0992 镜像](https://r0k.us/graphics/kodak/) | 镜像站仅称“据其理解”可 unrestricted usage，没有给出原始许可文件；Kodak 当前[样例图片说明](https://www.kodak.com/en/company/page/frequently-asked-questions/)又限制再分发。仅本地可选，不建议再分发 |
| `local_only/cameraman.tif`、`local_only/house.tif` | `androbaza/standard-test-images` 的第三方副本 | 与许可明确的 `camera.png` 不同；未核实到可靠的逐图授权，仅本地可选 |

[USC-SIPI 的版权说明](https://sipi.usc.edu/database/copyright.php)明确指出其数据库中许多图片的来源或版权状态未知，并且 USC 无权代替版权人授权。Mandrill、Peppers、Boat、House 等“经典测试图”不能仅凭被广泛用于论文就视为公有领域。

默认脚本只扫描 `images/`，不会再把本地可选资产带入公开回归。确需复现经典图结果时，应显式把 `local_only/` 作为 `--images` 输入；其派生结果也必须写入 `outputs/local_only/`。
