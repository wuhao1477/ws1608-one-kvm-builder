# WS1608 Armbian HCODEC 实机验收

## 当前证据边界

| 项目 | 状态 |
| --- | --- |
| `base-20260804-consolefix` 启动、HDMI、网络、SSH、eMMC | 已验证 |
| Armbian `6.12.28-current-meson` 与 One-KVM 运行 | 已验证 |
| H.264/H.265/VP8/VP9 软件编码路径 | 已验证 |
| ARMv7 `meson-venc` 模块、DTB 与工具 artifact | 已刷写并完成启动检查 |
| HCODEC V4L2 M2M H.264 | GitHub Actions `34345081710` 的 `run-32-1` 在稳定 One-KVM 用户空间完成 640×480 30 帧编码、独立解码和 60 秒健康记录；探针后设备需重启，稳定性验收未通过 |
| One-KVM `h264_v4l2m2m` | 尚未实机验证 |
| 1080p30、128 MiB CMA、长时间稳定性 | 尚未实机验证 |

稳定基础的已有证据不能自动继承给改变内核或 DTB 的 HCODEC 候选。每个新
候选从 `hardware_boot_tested=false` 和 `hardware_encoder_tested=false` 开始。
`run-29-1` 的硬件编码结果已生成并独立解码，但测试后设备失联，仍因稳定性探针
未完整退出而保持未验收状态。

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

测试工具必须由候选 manifest 固定的 ARMv7 源码构建。当前候选仅运行一个
640×480 MMAP 会话，并使用 artifact 的稳定性包装器：

```sh
./capture-stability-probe.sh results ./tools/meson-venc-smoke \
  "$encoder" results/stream.h264 640 480 30 30 4294967295 motion
```

该脚本会先保存命令、探针输出和 dmesg，再写入 60 秒健康记录。当前不运行
DMABUF、720p、1080p 或 One-KVM 集成。每次记录测试前后的：

```sh
grep -E 'CmaTotal|CmaFree' /proc/meminfo
dmesg >candidate-kernel.log
```

每次只运行一个编码会话；第二并发会话应被驱动拒绝，而不是破坏当前码流。

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

`run-16-1` 的唯一一次 640×480、MMAP、1 帧实机结果：内核日志记录
`SEQUENCE`、`PICTURE`、`IDR` 完成，输出 6547 字节；码流含 SPS/PPS/IDR，
`ffprobe` 识别为 640×480 Baseline 并读到 1 帧，`ffmpeg` 解码退出码为 0，输出
SHA-256 为 `af392c6132fb1b349c62a0609164a5d92fb5dbda0805709614e00dfa636f407a`。
但工具在随后 `STREAMOFF` 清理阶段未返回并导致 SSH 超时；因此该候选只证明
编码数据路径，不能标为完整验收通过，也不得进入 DMABUF、720p、1080p 或 One-KVM。

`run-29-1` 的 640×480、MMAP、30 帧实机结果：退出码 `0`，内核日志记录 1 个
IDR、29 个 P 帧、两个 `STREAMOFF` 和 `power_off end`；输出 6866 字节，SHA-256
为 `7d50f102b6405fcc637467a61a8c5ef62ef0c90f2af88136a2f9f9ae97f6413f`。
`ffprobe` 识别 30 帧 Baseline H.264，`ffmpeg` 解码成功。测试后设备失联，下一
候选必须通过 `capture-stability-probe.sh` 保存编码后健康记录，仍不能进入更高
分辨率、DMABUF 或 One-KVM。

CNB `run-30-1` 的 640×480、MMAP motion 30 帧实机结果：退出码 `0`，内核日志
记录 30 次 `device_run`、1 个 IDR、29 个 P 帧、两个 `stop_streaming` 和
`power_off end`；输出 44137 字节，SHA-256 为
`334a7bca58cda061d28ddaf4410bfebec79c0e50d0cd09466ab2929ad288a9a2`。
`ffprobe` 识别 640×480 Baseline H.264，`ffmpeg` 解码成功；60 条健康记录全部
保持 eth0/carrier 在线，HCODEC 错误、panic 和 oops 筛查为 0。探针后设备仍需
重启恢复 SSH，因此稳定性验收未通过，不能进入 DMABUF、720p、1080p 或 One-KVM。

将同一 artifact 安装到稳定 One-KVM 用户空间后进行的 `results-stable-30f` 复验：
One-KVM 服务和健康接口在探针前后正常，退出码 `0`，内核日志记录 30 次
`device_run`、1 个 IDR、29 个 P 帧、两个队列停止和完整 `power_off begin/end`；
输出 44127 字节，SHA-256 为
`d1daed2cda6353b1b7d2f692abcf3803ef9076b6e0dc550652bafd66b97e818a`。
`ffprobe`/`ffmpeg` 通过，60 条健康记录保持 eth0/carrier 在线，HCODEC 错误、
panic 和 oops 筛查为 0；探针后设备仍失联并需重启恢复，因此仍不能进入 DMABUF、
720p、1080p 或 One-KVM 集成。

GitHub Actions run `34345081710` 的 `run-32-1` artifact 已完成云端构建、独立复验、
安装和重启。640×480 MMAP motion probe 退出码为 `0`，内核 trace 记录 30 次
`device_run`、32 次 IRQ、1 个 IDR、29 个 P 帧和 1 次 `power_off deferred`；输出
44127 字节 Annex-B H.264，码流 SHA-256 为
`d1daed2cda6353b1b7d2f692abcf3803ef9076b6e0dc550652bafd66b97e818a`。本地
`ffprobe` 读到 30 帧 640×480 H.264，`ffmpeg` 解码退出码为 `0`；`kernel.health.log`
为空，60 条健康记录完整，探针后设备仍需重启恢复 SSH。因此该候选仍不能进入
DMABUF、720p、1080p 或 One-KVM 集成。

GitHub Actions run `34441199008` 的 `run-39-1` artifact 已完成云端构建、独立复验、
正确模块安装、重启和 hash 核验。640×480 MMAP motion probe 退出码为 `0`，输出
44137 字节 Annex-B H.264，包含 1 个 IDR 和 29 个 P 帧；码流 SHA-256 为
`334a7bca58cda061d28ddaf4410bfebec79c0e50d0cd09466ab2929ad288a9a2`，本地
`ffprobe` 读到 30 帧 640×480 Baseline H.264，`ffmpeg` 解码退出码为 `0`。内核
trace 记录 30 次 `device_run`、32 次 IRQ 和 1 次 `stop_streaming: power_off deferred`；
60 条健康记录全部保持 eth0/carrier/IP 在线，探针结束后 SSH 仍可访问。该结果通过
640×480 独立稳定性门槛，但不代表 DMABUF、720p、1080p 或 One-KVM 集成已验证。

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
