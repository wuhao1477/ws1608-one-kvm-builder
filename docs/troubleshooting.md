# 排障手册与已知问题

## 快速判断

| 症状 | 常见原因 | 处理 |
| --- | --- | --- |
| 稳定 build skipped | 相同上游 tag 与 Deb digest 已发布 | 正常；脚本修复需要重建时使用 `force=true` |
| 找到 0 或多个 armhf Deb | 上游资产策略变化 | 检查 Release JSON，修改精确选择规则 |
| 基础 SHA-256 不匹配 | 资产替换或下载损坏 | 创建新基础 tag，不覆盖历史资产 |
| e2fsck journal/orphan | rootfs 未严格卸载 | 停止构建，检查所有嵌套挂载 |
| Amlogic CRC/VERIFY 失败 | 容器、sparse 或摘要计算错误 | 使用固定 AmlImg 和独立 verifier |
| HCODEC 模块无法加载 | 架构、vermagic、配置或符号不匹配 | 重新为目标 ARMv7 内核构建 |
| HCODEC probe 失败 | DT 时钟、HHI、DOS、IRQ 或 Canvas 不完整 | 核对 Meson8b 资源和冲突 owner |
| 固件加载失败 | 文件缺失、路径或摘要错误 | 核对 `meson8b_h264.bin` 来源与 manifest |
| CMA 分配失败 | CMA 太小或碎片化 | 检查 cmdline、CmaTotal/CmaFree 和缓冲数量 |
| 编码 timeout | 微码、HCODEC 时钟、电源、复位或 mailbox IRQ | 先核对 Hardkernel Meson8b dblk 微码来源/摘要，再检查命令和中断 |
| H.264 损坏 | Canvas/MFDIN、DMA、capture ring 或 header 状态错误 | 用独立工具缩小到首个失败帧 |
| One-KVM 不发现硬件后端 | 环境开关、设备权限或 V4L2 格式不匹配 | 独立探针通过后再显式启用 |
| `/dev/video*` 缺失 | 驱动未 probe 或采集卡未接 | 先用 `v4l2-ctl --list-devices` 区分设备 |

## 稳定构建排障

### 上游发现

先检查 `Check One-KVM release` 输出中的 tag、Deb 名称、版本、URL、digest、
`changed` 和构建身份。上游资产不唯一或没有 SHA-256 时必须失败，不能静默
选择近似包。

### rootfs 挂载

只在临时 Linux 构建目录执行：

```sh
findmnt -R "$WORK_DIR/rootfs.mnt"
mountpoint "$WORK_DIR/rootfs.mnt"
ps -ef | grep -E 'chroot|qemu-arm|apt-get' | grep -v grep
```

rootfs 仍挂载时不得运行 `e2fsck`。不要恢复忽略 `umount` 返回值或递归暴露
宿主 `/dev` 的旧实现。

### Amlogic 容器

```sh
"$AMLIMG_BIN" unpack image.burn.img verify-dir
cat verify-dir/commands.txt
sha1sum verify-dir/10.rootfs.PARTITION.sparse
cat verify-dir/11.rootfs.VERIFY
```

非 rootfs 条目变化表示构建越界。不能删除 VERIFY 或只检查外层 SHA-256。

### 发布资产

`SHA256SUMS` 只包含 basename。build 上传后、release 下载后和远端公开后都
必须复验 raw/xz 往返、manifest、报告和 GitHub asset digest。tag 冲突时
使用新 run 身份，不覆盖旧 Release。

## HCODEC 分层排障

### 1. 模块身份

```sh
file meson-venc.ko
modinfo meson-venc.ko
uname -m
uname -r
```

目标必须是 ARM 32-bit 并匹配候选内核 vermagic。资料中的 AArch64
`6.12.98-ipkvm-release` 模块不能用于当前系统。

### 2. 设备树和资源

```sh
tr '\0' '\n' </proc/device-tree/compatible
dmesg | grep -Ei 'meson-venc|hcodec|clock|syscon|canvas|irq|resource|probe'
```

重点检查：

- `amlogic,meson8b-hcodec` 节点已在 OneCloud 板级启用；
- `amlogic,hhi-sysctrl` 与实际 HHI syscon 一致；
- DOS 地址没有被其他节点重复占用；
- DOS/hcodec 时钟 ID 存在于 Meson8b provider；
- IRQ、AO syscon 和 Canvas phandle 有效。

补丁系列与最终驱动对这些属性要求不同，不能混合文件后判断 probe 失败。

### 3. 固件

```sh
find /lib/firmware/meson/venc -maxdepth 1 -type f -print
sha256sum /lib/firmware/meson/venc/meson8b_h264.bin
dmesg | grep -Ei 'firmware|imem|dma|hcodec'
```

候选固件必须来自固定 Hardkernel commit `5aed95d35d252cafc75ce613a3a0052285662de2`，
输入为 `drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h`，
输出 9536 字节，SHA-256 为
`2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368`。

### 4. CMA 与 DMA

```sh
cat /proc/cmdline
grep -E 'CmaTotal|CmaFree' /proc/meminfo
dmesg | grep -Ei 'cma|dma|allocation|contiguous|out of memory'
```

1080p 的编码工作区约 15.44 MiB，One-KVM 4 输入/4 输出缓冲使编码部分接近
64 MiB。64 MiB CMA 紧张时先验证实际分配；`cma=128M` 仍需重新启动候选并
记录结果。

### 5. 电源、时钟与 IRQ

`run-12-1` 的首帧记录为：`SEQUENCE`、`PICTURE` 成功，IDR 输出 7 字节后
返回 `-110`；按顺序确认 dblk 微码、AO power、隔离、DOS bus clock、HCODEC
内部 clock、reset、固件 DMA、mailbox mask/clear、命令完成 IRQ。
不能通过无限延长 timeout 隐藏硬件没有运行。

### 6. 码流

先用 640×480 单会话和 MMAP，随后再测试 DMABUF、720p 和 1080p。每次保存
完整参数、输出摘要和筛选后的 dmesg：

```sh
ffprobe -v error -show_streams candidate.h264
ffmpeg -v error -i candidate.h264 -f null -
```

缺少 SPS/PPS/IDR、分辨率或帧数错误、解码失败都表示探针失败。驱动没有 B
帧，软件 QP 反馈也不能描述为硬件 VBV。

### 7. One-KVM

独立码流通过后，临时执行：

```sh
ONE_KVM_V4L2M2M_ALLOW=1 /usr/bin/one-kvm
```

未发现 `h264_v4l2m2m` 时检查：V4L2 capability、H.264 capture format、
NV12/YUYV output format、设备权限和环境变量。不要先修改稳定 service。

## 已知基础限制

- HDMI 音频曾出现 `gx-sound-card` error -22；不影响视频/HID目标。
- GitHub runner 不能验证实体 HCODEC、HDMI、USB 采集或 HID。
- macOS 容器的特权 loop mount 可能不稳定，完整镜像构建使用 Linux runner。

历史 Linux 3.10 AMLENC 排障路线已废弃，原因和决策见
[ADR-0003](adr/0003-armbian-6.12-hcodec-route.md)。
