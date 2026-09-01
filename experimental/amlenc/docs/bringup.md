# WS1608 Armbian 6.12 HCODEC bring-up

当前状态：**尚未通过实机验证**。本流程只适用于 Linux 6.12
`meson-venc` HCODEC V4L2 M2M 候选，不改变稳定 Release。

## 候选产物

开始实机测试前必须具有同一 manifest 管理的：

- ARMv7 Linux 6.12 内核和 `.config`；
- `meson-venc.ko` 及完整模块依赖；
- OneCloud DTB；
- `meson/venc/meson8b_h264.bin`；
- ARMv7 `meson-venc-smoke` 和 DMABUF 测试工具；
- 驱动、补丁、固件、DTB、工具链和测试工具 SHA-256；
- `hardware_boot_tested=false`、`hardware_encoder_tested=false` 的候选报告。

资料中的 AArch64 预编译模块不能进入该清单。18 个补丁与最终源码只能选择
一个一致实现基线。

## 1. 稳定系统回归

刷入候选后先确认 Armbian 基础功能：

```sh
uname -a
cat /proc/cmdline
findmnt -no SOURCE,FSTYPE,OPTIONS /
ip -brief address
systemctl is-active one-kvm.service
curl -fsS http://127.0.0.1:8080/api/health
```

HDMI、网络、SSH、eMMC 或 One-KVM 软件路径任一失败时停止，不运行 HCODEC。

## 2. HCODEC probe

```sh
zgrep -E 'CONFIG_VIDEO_MESON_VENC|CONFIG_V4L2_MEM2MEM_DEV|CONFIG_MESON_CANVAS' /proc/config.gz
grep -E 'CmaTotal|CmaFree' /proc/meminfo
v4l2-ctl --list-devices
media-ctl -p
dmesg | grep -Ei 'meson-venc|hcodec|firmware|cma|dma|canvas|timeout|oops|panic'
```

确认编码器节点后读取其 capability 和格式；不要根据 `/dev/video*` 编号猜测
设备类型。

## 3. 固定探针

```sh
printf 'Encoder device path: '
read -r encoder
test -c "$encoder"
./meson-venc-smoke "$encoder" 640x480-300f.h264 640 480 300
ffprobe -v error -show_streams 640x480-300f.h264
ffmpeg -v error -i 640x480-300f.h264 -f null -

./meson-venc-smoke "$encoder" 1280x720-1800f.h264 1280 720 1800
ffprobe -v error -show_streams 1280x720-1800f.h264
ffmpeg -v error -i 1280x720-1800f.h264 -f null -
```

MMAP 通过后再运行 DMABUF。720p 通过后才测试 1080p 和长时间运行。每项
保存 CMA 前后值、输出 SHA-256、测试参数和筛选后的 dmesg。

## 4. One-KVM 探针

独立探针通过后临时运行：

```sh
ONE_KVM_V4L2M2M_ALLOW=1 /usr/bin/one-kvm
```

确认 `h264_v4l2m2m` 被注册且实际流可解码。该变量不写入稳定 systemd 环境。

## 停止条件

以下任一情况立即停止后续测试：

- 系统基础功能回归失败；
- 模块架构或 vermagic 不匹配；
- DT、时钟、HHI、Canvas、IRQ 或固件 probe 失败；
- CMA/DMA 分配失败；
- timeout、oops、panic 或损坏码流；
- 缺少 SPS/PPS/IDR、帧数错误或 FFmpeg 解码失败；
- One-KVM 硬件失败后软件编码也不可用。

只有独立码流、One-KVM、视频、HID、虚拟介质、重启和稳定性全部通过，才
能更新候选硬件状态。完整记录格式见
[实机验收](../../../docs/hardware-validation.md)。
