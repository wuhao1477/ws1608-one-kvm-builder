# WS1608 Armbian HCODEC 实机验收

## 当前证据边界

| 项目 | 状态 |
| --- | --- |
| `base-20260804-consolefix` 启动、HDMI、网络、SSH、eMMC | 已验证 |
| Armbian `6.12.28-current-meson` 与 One-KVM 运行 | 已验证 |
| H.264/H.265/VP8/VP9 软件编码路径 | 已验证 |
| ARMv7 `meson-venc` 模块、DTB 与固件 | 尚未生成可验证候选 |
| HCODEC V4L2 M2M H.264 | 尚未实机验证 |
| One-KVM `h264_v4l2m2m` | 尚未实机验证 |
| 1080p30、128 MiB CMA、长时间稳定性 | 尚未实机验证 |

稳定基础的已有证据不能自动继承给改变内核或 DTB 的 HCODEC 候选。每个新
候选从 `hardware_boot_tested=false` 和 `hardware_encoder_tested=false` 开始。

## 测试准备

- 保留当前已验证 `.burn.img` 和 USB Burning Tool 恢复路径；
- 使用与候选 manifest 完全一致的内核、模块、DTB、固件和测试工具；
- 准备 HDMI 显示器、网络、USB HDMI 采集卡和被控机 USB；
- 保存所有输入 SHA-256，连接信息和原始日志不进入公开仓库；
- 确认供电和散热后再进行 1080p 或长时间测试。

## 1. 稳定基础回归

刷入候选后先验证系统，没有通过时不运行编码测试：

```sh
cat /etc/ws1608-one-kvm-release
uname -a
cat /proc/cmdline
systemctl is-active one-kvm.service
systemctl status one-kvm-otg.service --no-pager
curl -fsS http://127.0.0.1:8080/api/health
findmnt -no SOURCE,FSTYPE,OPTIONS /
ip -brief address
```

必须确认 HDMI、网络、SSH、eMMC 和 One-KVM 软件编码仍正常。候选内核必须
属于 Linux 6.12 系列，并能从 manifest 追溯到固定源码和配置。

## 2. 内核、设备树与 CMA

```sh
uname -r
zgrep -E 'CONFIG_VIDEO_MESON_VENC|CONFIG_V4L2_MEM2MEM_DEV|CONFIG_VIDEOBUF2_DMA_CONTIG|CONFIG_MESON_CANVAS' /proc/config.gz
tr '\0' '\n' </proc/device-tree/compatible
cat /proc/cmdline
grep -E 'CmaTotal|CmaFree' /proc/meminfo
dmesg | grep -Ei 'meson-venc|hcodec|firmware|cma|dma|canvas|timeout|oops|panic'
```

检查点：

- 模块、内核和 DTB 都是 ARMv7 目标，vermagic 一致；
- OneCloud HCODEC 节点没有与其他 DOS owner 重叠；
- HHI syscon、DOS/hcodec 时钟、Canvas、IRQ 和固件探测成功；
- `meson8b_h264.bin` 摘要与 manifest 一致；
- `CmaTotal` 与本次候选配置一致。

`cma=128M` 只作为 1080p 候选。64 MiB 是否足够由实际缓冲分配结果判断，
不得仅根据启动成功下结论。

## 3. V4L2 设备和媒体拓扑

```sh
v4l2-ctl --list-devices
media-ctl -p
printf 'Encoder device path: '
read -r encoder
test -c "$encoder"
v4l2-ctl -d "$encoder" --all
v4l2-ctl -d "$encoder" --list-formats-out
v4l2-ctl -d "$encoder" --list-formats
```

不能假定编码器永久是 `/dev/video0`；采集卡和编码器可能使用不同编号。目标
节点必须同时提供 V4L2 OUTPUT 原始格式和 CAPTURE H.264 格式。

## 4. 独立 H.264 探针

测试工具必须由候选 manifest 固定的 ARMv7 源码构建。先运行 MMAP：

```sh
./meson-venc-smoke "$encoder" 640x480-300f.h264 640 480 300
./meson-venc-smoke "$encoder" 1280x720-1800f.h264 1280 720 1800
```

MMAP 通过后，以同样参数运行 DMABUF，并记录每次测试前后的：

```sh
grep -E 'CmaTotal|CmaFree' /proc/meminfo
dmesg >candidate-kernel.log
```

720p 通过后才测试 1920×1080。每次只运行一个编码会话；第二并发会话应被
驱动拒绝，而不是破坏当前码流。

## 5. 码流验证

```sh
ffprobe -v error -show_streams -show_format candidate.h264
ffmpeg -v error -i candidate.h264 -f null -
```

每项探针必须满足：

- H.264 Annex-B；
- 目标分辨率和精确帧数；
- SPS、PPS、首个 IDR 和后续 P 帧；
- FFmpeg 完整解码零错误；
- 无 firmware failure、CMA failure、DMA fault、timeout、oops 或 panic；
- 输出非空且码率、GOP、QP 控制结果与测试参数一致。

驱动不支持 B 帧，当前 CBR/VBR 是软件 QP 反馈；验收记录不得描述为硬件
VBV 码率控制。

## 6. One-KVM 显式探针

只有独立 V4L2 测试通过后才执行：

```sh
ONE_KVM_V4L2M2M_ALLOW=1 /usr/bin/one-kvm
```

这是临时实验命令，不写入稳定 systemd 环境。验证 API 注册
`h264_v4l2m2m`、实际视频流可解码、硬件失败时软件编码仍可选择。

## 7. OTG、视频和 HID

```sh
cat /sys/devices/platform/soc/c9040000.usb/usb_role/*/role
lsmod | grep -E 'libcomposite|configfs'
find /dev -maxdepth 1 -type c -name 'video*' -print
systemctl status one-kvm-otg.service --no-pager
```

接入采集卡和被控机后验证视频、键盘、鼠标、虚拟介质、断开重连及 BIOS
阶段操作。候选内核不得破坏现有 OTG 路径。

## 8. 重启和稳定性

至少完成一次冷启动和一次系统重启。720p 持续测试通过后再进行 1080p 和
长时间测试，记录分辨率、帧率、码率、CMA 峰值、温度、丢帧、超时、USB
断连和服务退出。

## 验收记录

```text
候选 tag / builder commit:
内核源码、配置、驱动、补丁、DTB、固件 SHA-256:
内核版本与 vermagic:
CMA 配置与峰值:
V4L2 设备和拓扑:
输入格式、分辨率、帧率、码率、GOP、QP、缓冲模式:
输出 H.264 SHA-256:
ffprobe / 完整解码:
内核错误扫描:
One-KVM h264_v4l2m2m:
HDMI / 网络 / eMMC / OTG / 视频 / HID / 虚拟介质:
冷启动 / 重启 / 温度 / 运行时长:
结论: pass / fail / blocked
```

只有全部核心项通过，才能把候选标为硬件已验证。提升稳定基础仍需要独立
ADR 和新的完整刷写验收。
