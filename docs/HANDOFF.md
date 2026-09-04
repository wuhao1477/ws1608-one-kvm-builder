# WS1608 One-KVM 构建器交接

更新时间：2026-09-04

## 当前结论

稳定构建和发布链已经建立，系统与硬件编码路线现已明确分离：

- 稳定基础为 `base-20260804-consolefix`、Armbian `26.8.0-trunk.413`、
  Debian Trixie、Linux `6.12.28-current-meson`。
- 当前稳定 Release 为
  [`ws1608-one-kvm-0.2.6-v260802-b028001`](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.6-v260802-b028001)。
- 稳定底座已有实体启动、HDMI、网络、SSH、eMMC 和 One-KVM 运行证据。
- H.264 硬件编码改走 Linux 6.12 `meson-venc` HCODEC V4L2 M2M。
- Linux 3.10、私有 AMLENC ABI、双内核和 kexec 已废弃，不再构建或刷写。
- HCODEC 尚未通过 WS1608 实机编码验证，当前不能发布硬件成功结论。
- `codex/hcodec-armv7-cloud-verify` 的 `run-12-1` 候选已实机启动，`cma=128M`
  生效且 `/dev/video0` 注册成功；640×480 单帧 probe 记录到
  `SEQUENCE`、`PICTURE` 成功，`IDR` 输出 7 字节后超时并返回 `-110`。
  CMA 仍有余量，设备在失败后继续正常运行。
- ARMv7 静态候选构建已完成，分支为 `codex/hcodec-armv7`，实现提交为
  `1b87398e5393bf465a36cef7388f684a718c7fc7` 与 `6215ec6`；artifact 仅由独立 workflow
  生成并保留 14 天，不创建 Release。

正式决策见 [ADR-0003](adr/0003-armbian-6.12-hcodec-route.md)，技术边界见
[路线设计](superpowers/specs/2026-09-01-armbian-hcodec-route-design.md)。

## 稳定通道

`.github/workflows/build.yml` 每周日 02:17 UTC 查询 One-KVM 最新稳定
Release。只有新的上游 tag 与 armhf Deb SHA-256 组合才触发镜像构建；同一
输入可通过 `force=true` 生成新的不可变 `bRRRAAA` Release。

稳定构建只修改 rootfs 中的 One-KVM、systemd、OTG 和来源 metadata，不
替换 boot、内核、DTB、U-Boot 或 resource。CI 验证镜像容器、分区、ext4、
包身份、服务、压缩往返、manifest 和五项发布资产，但不能代替实体硬件验收。

## HCODEC 新证据

已核对的研究资料包含 18 个 Linux 6.12 补丁、最终 `meson-venc` 驱动、
Meson8b 绑定、V4L2 MMAP/DMABUF 工具和固件提取脚本。编码链为：

```text
NV12/YUYV → V4L2 OUTPUT → DMA/CMA → Canvas/MFDIN
→ HCODEC 固件与 IRQ → V4L2 CAPTURE → Annex-B H.264
```

One-KVM `0.2.6` 已有 `h264_v4l2m2m` 后端，Amlogic 实验探测需要
`ONE_KVM_V4L2M2M_ALLOW=1`。

## 尚未解决

- 资料中的 `meson-venc.ko` 是 AArch64 `6.12.98-ipkvm-release`，不能用于
  当前 ARMv7 内核。
- 18 个补丁已针对锁定的 `6.12.28` 基线顺序应用，并追加 OneCloud 节点修正；
  run-8 已验证实体 probe 可注册 `/dev/video0`。
- run-9 已确认 V4L2 队列、`start_streaming`、workspace 分配、硬件准备和
  `SEQUENCE/PICTURE` 命令可通过；当前失败点是 Meson8b `IDR` 命令。
- `run-12-1` 已否定 Meson8b offset VLC ring-base 假设；IDR 仍在 7 字节后超时。
- 新候选使用 Hardkernel Linux `5aed95d35d252cafc75ce613a3a0052285662de2` 的
  `drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h`，生成
  9536 字节固件，SHA-256 为
  `2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368`。
- 1080p 编码缓冲预算约 59.30 MiB（NV12）至 63.26 MiB（YUYV），
  `cma=128M` 只是候选设置。
- 1080p30 和 One-KVM 1080p20 来自外部实测描述，不是当前板卡证据。

## 接手后的顺序

1. 推送 `codex/hcodec-meson8b-ucode`，等待 GitHub Actions 生成并复验 artifact。
2. 刷入新候选，只运行 640×480 单帧探针；通过前不继续 720p/1080p。
3. 只有 640×480 生成有效 Annex-B H.264 后才创建 PR。
4. 独立码流通过后临时接入 One-KVM，不修改稳定服务配置。
5. 完成启动、视频、HID、虚拟介质、重启和长时间运行后再讨论候选发布。

## 维护边界

- 不把外部教程、其他 SoC 或 CI 编译结果写成 WS1608 硬件通过。
- 不提交 `Downloads/`、预编译模块、固件或本机测试数据。
- 不在稳定服务中默认启用 V4L2 M2M 实验开关。
- 不改变稳定基础，除非新候选完成单独实机验收与决策。
- 不创建或合并 PR，除非新候选完成 640×480 单帧实机编码验收。
- 设备连接信息和原始日志保持在维护者的私有测试记录中。

实机步骤见 [hardware-validation.md](hardware-validation.md)，故障定位见
[troubleshooting.md](troubleshooting.md)。
