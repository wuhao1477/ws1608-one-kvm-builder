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
| `armbian-zram-config.service` 报 `Unknown symbol` | 设备上的 `depmod` 覆盖了制品依赖索引 | 重新安装包含完整 `modules.*` 索引的候选 artifact；不要在设备上重跑无参数 `depmod` |
| HCODEC probe 失败 | DT 时钟、HHI、DOS、IRQ 或 Canvas 不完整 | 核对 Meson8b 资源和冲突 owner |
| 固件加载失败 | 文件缺失、路径或摘要错误 | 核对 `meson8b_h264.bin` 来源与 manifest |
| CMA 分配失败 | CMA 太小或碎片化 | 检查 cmdline、CmaTotal/CmaFree 和缓冲数量 |
| 编码 timeout | 微码、HCODEC 时钟、电源、复位或 mailbox IRQ | 先核对 Hardkernel Meson8b dblk 微码来源/摘要，再检查命令和中断 |
| probe 超时后 SSH 失联 | HCODEC 访问可能触发系统级挂起或复位 | 停止所有后续编码测试；等待一次网络恢复窗口，保存结果后再分析，不重复刷写或延长 timeout |
| H.264 损坏 | Canvas/MFDIN、DMA、capture ring 或 header 状态错误 | 用独立工具缩小到首个失败帧 |
| 编码完成但 STREAMOFF 阻塞 | V4L2 队列清理、硬件电源关闭或停止 CPU 路径未完成 | 保留已生成码流和上一启动日志；不重试 probe，先修复清理路径 |
| probe 返回 `0` 后设备失联 | HCODEC 关电后的异步系统影响，且 zram 上的 journal 不持久 | 用 artifact 的 `capture-stability-probe.sh` 保存根文件系统 dmesg 和 60 秒健康记录，再进行唯一一次候选 probe |
| One-KVM 不发现硬件后端 | 环境开关、设备权限或 V4L2 格式不匹配 | 独立探针通过后再显式启用 |
| Web UI 升级报取清单失败 | 镜像故意关闭了在线升级 | 预期行为；改为重刷本仓库 Release 镜像，不要清除 `no-online-update.conf` |
| 设备上 `/usr/bin/one-kvm` 与 manifest 摘要不符 | 曾执行过上游在线升级，二进制被 `rename()` 覆盖且 dpkg 无记录 | 重刷镜像；升级会静默丢掉 Meson8b 补丁 |
| 安装候选报空间不足 | 目标根分区可用空间低于本候选实际需要 | 门槛按解包后模块树与备份计算；清理 `/root/hcodec/backups` 下旧备份，不要删解包目录 |
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

`run-13-1` 已确认安装和启动路径正确：内核为 `6.12.28-current-meson`，
`/dev/video0` 已注册，Meson8b 微码为 9536 字节且摘要正确，`cma=128M` 生效。
唯一一次 640×480、MMAP、1 帧 probe 在 120 秒内超时，之后设备 SSH 返回
`Host is down`。没有有效码流时必须停止测试，不创建 PR，不继续更高分辨率或
One-KVM 集成。

`run-15-1` 在补齐 Meson8b Assist `INT1=0x19` 后重复了同一最小边界：安装、重启、
固件、CMA 和 `/dev/video0` 均正常，唯一一次 640×480、MMAP、1 帧 probe 超过
120 秒未完成，输出为 0 字节，设备随后失联；重启后的 `pstore` 为空。该修复
未解决 IDR 阶段的硬件挂起，必须停止测试并继续完整协议对照，不得重复 probe、
延长 timeout 或创建 PR。

`run-16-1` 在修复 Meson8b 微码长度门槛后完成了同一最小边界的硬件工作：内核日志
记录 `SEQUENCE`、`PICTURE`、`IDR` 完成，生成 6547 字节码流；离线校验确认
Annex-B、SPS/PPS/IDR、640×480、1 帧和完整 FFmpeg 解码均通过，输出 SHA-256
为 `af392c6132fb1b349c62a0609164a5d92fb5dbda0805709614e00dfa636f407a`。但工具在
完成数据读取后的 `STREAMOFF` 清理阶段未返回，SSH 随后超时，重启后的 `pstore`
为空。该候选证明编码数据路径可用，但清理路径仍失败；不得把它标为完整验收通过，
不得重试 probe、延长 timeout、测试更高分辨率或创建 PR。

`run-24-1` 修复了候选模块安装重跑 `depmod` 导致 zram 依赖为空的问题，
`armbian-zram-config.service` 已正常启动。相同最小 probe 返回 `0` 并写出经
FFmpeg 解码的 6547 字节码流，但设备仍在工具退出后失联；zram 上的 journal 随重启
丢失，`pstore` 为空。下个候选必须通过 `capture-probe.sh` 把实时和结束后的 dmesg
写入 `/root/hcodec/.../results`，且仍只执行一次最小 probe。

`run-25-1` 的持久化 trace 已确认两个 `STREAMOFF` 以及 `power_off end` 在工具
退出前完成，且无 DMA idle timeout；失联发生在其后。Hardkernel Meson8b 参考驱动
在相同阶段保留 HCODEC `DOS_GCLK_EN0` 内部门控，下一候选只对 Meson8b 保留这些
gate，保留原有 CPU 停止、隔离、内存断电与时钟释放。

`run-29-1` 已完成 640×480 MMAP 30 帧编码，生成 1 个 IDR、29 个 P 帧和 6866 字节
码流；`ffprobe` 识别 30 帧 Baseline H.264，`ffmpeg` 解码成功。测试后的设备仍失联，
因此下一构建增加 `capture-stability-probe.sh`，在复用 `capture-probe.sh` 的内核日志
之外持续写入 60 秒的 uptime、网卡 carrier 和 IP 记录。该证据完成前不得创建 PR。

CNB `run-30-1` 已使用该包装器完成 640×480 MMAP motion 30 帧编码：退出码 `0`，
1 个 IDR、29 个 P 帧，输出 44137 字节；`ffprobe`/`ffmpeg` 通过，摘要为
`334a7bca58cda061d28ddaf4410bfebec79c0e50d0cd09466ab2929ad288a9a2`。实时内核日志
记录 30 帧、两个 `stop_streaming` 和 `power_off end`；HCODEC 错误、panic 和 oops
筛查均为 0，60 条健康记录保持 eth0/carrier 在线。探针后设备仍需重启恢复 SSH，
因此该候选仍未完成稳定性验收，不重复 probe，也不创建 PR。

将同一 CNB artifact 安装到稳定 One-KVM 用户空间后的 `results-stable-30f` 复验
同样返回 `0`：1 个 IDR、29 个 P 帧、44127 字节码流，SHA-256 为
`d1daed2cda6353b1b7d2f692abcf3803ef9076b6e0dc550652bafd66b97e818a`；
`ffprobe`/`ffmpeg` 通过，60 条健康记录完整，HCODEC 错误、panic 和 oops 为 0。
探针后 SSH 再次失联，重启后 One-KVM 服务恢复；这说明问题仍位于探针结束后的
设备稳定性边界，不应通过重复探针或提高分辨率掩盖。

GitHub Actions run `34345081710` 的 `run-32-1` 继续使用同一包装器完成验证：
退出码 `0`，30 次 `device_run`、32 次 IRQ、1 个 IDR、29 个 P 帧和 1 次
`power_off deferred` 均已记录；`kernel.health.log` 为空，60 条健康记录完整，
码流经本地 `ffprobe`/`ffmpeg` 验证通过。探针结束后仍需重启恢复 SSH，说明
`power_off deferred` 已被观测到，但尚未证明设备能在探针后持续可访问；不得创建
PR 或扩大到更高分辨率、DMABUF、One-KVM 集成。

GitHub Actions run `34441199008` 的 `run-39-1` 在确认新 `meson-venc.ko` 已加载后完成
唯一一次正式探针：退出码 `0`，30 次 `device_run`、32 次 IRQ、1 个 IDR、29 个 P 帧，
并记录 1 次 `power_off deferred`。码流为 44137 字节，`ffprobe`/`ffmpeg` 通过；60 条
健康记录的 eth0/carrier/IP 全部在线，探针结束后 SSH 未失联。该结果说明延迟关电路径
通过 640×480 独立稳定性验证，后续仍不得在未单独验证前扩大到 DMABUF、720p、1080p
或 One-KVM 集成。

### 6. 码流

当前候选只用 640×480 单会话和 MMAP；DMABUF、720p 和 1080p 在稳定性验收前
不测试。每次保存完整参数、输出摘要和筛选后的 dmesg：

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
