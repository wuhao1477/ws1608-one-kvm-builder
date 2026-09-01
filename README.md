# WS1608 One-KVM builder

本仓库把已在 OneCloud/WS1608 上验证过的 Armbian 基础镜像封装为带
One-KVM Rust 的 Amlogic 直刷镜像，并为 S805 H.264 硬件编码维护独立的
Linux 6.12 HCODEC 研究路线。

## 当前状态

- 唯一稳定底座：Armbian `26.8.0-trunk.413`、Debian Trixie、
  Linux `6.12.28-current-meson`、`base-20260804-consolefix`。
- 当前稳定 Release：
  [`ws1608-one-kvm-0.2.6-v260802-b028001`](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.6-v260802-b028001)。
- 稳定底座已经具备实体启动、HDMI、网络、SSH、eMMC 和 One-KVM 运行证据。
- H.264 HCODEC 候选尚未通过 WS1608 实机编码测试；不得把资料或 CI 结果
  写成硬件已经可用。

## 自动更新规则

- 每周日 02:17 UTC 查询 `mofeng-git/One-KVM` 最新稳定 Release。
- 只有出现尚未发布的上游 tag 与 Deb SHA-256 组合才构建新镜像。
- Release/tag 使用
  `ws1608-one-kvm-<one-kvm-version>-<upstream-tag>-bRRRAAA`。
- `workflow_dispatch` 支持 `force=true` 独立重建和 `publish=false` 仅验证。
- Pull request 执行完整构建，但不获得发布权限。
- 每个 Release 提供 `.burn.img`、`.burn.img.xz`、`SHA256SUMS`、
  `manifest.json` 和 `validation-report.json`。

稳定通道只更新 One-KVM rootfs 内容，不自动替换内核、DTB、U-Boot 或
Armbian 基础。完整流程见[构建与发布流程](docs/build-pipeline.md)。

## 硬件编码研发路线

当前唯一有效方向是在已验证 Armbian/Linux 6.12 基础上移植
`meson-venc` HCODEC 驱动，通过标准 V4L2 M2M 输出 Annex-B H.264，再由
One-KVM 使用 `h264_v4l2m2m` 后端。

新证据包含 18 个 Linux 6.12 补丁、Meson8b 后端、V4L2 MMAP/DMABUF
工具和固件提取脚本。它证明方向具备较高可行性，但尚不能直接交付：

- 附带模块是 AArch64 `6.12.98-ipkvm-release`，不能加载到 ARMv7
  `6.12.28-current-meson`；
- 补丁与最终驱动不是同一修订，Meson8b 时钟和 HHI 资源仍需修正；
- 缺少可追溯的 `meson8b_h264.bin` 固件；
- `cma=128M` 是基于 1080p 缓冲预算的候选值，不是实机结论；
- One-KVM 实验探测需要 `ONE_KVM_V4L2M2M_ALLOW=1`，通过独立编码测试前
  不写入稳定服务配置。

Linux 3.10、Bullseye、`/dev/amvenc_avc`、`libvpcodec`、双内核和 kexec
路线已经废弃，仅作为历史研究记录保留。正式决策见
[ADR-0003](docs/adr/0003-armbian-6.12-hcodec-route.md)。

## CI 与实机边界

CI 会重新解包成品并验证 Amlogic v2 CRC、boot FAT、Linux console、12 个
标准条目、分区 VERIFY、非 rootfs 分区一致性、One-KVM armhf 包、systemd、
OTG、ext4、manifest、压缩往返和所有摘要。

GitHub 托管 runner 没有实体 WS1608、采集卡或被控机 USB。加入新内核或
设备树的 HCODEC 候选必须保持 `hardware_boot_tested=false` 和
`hardware_encoder_tested=false`，直到对应实机验收完成。

## 本地检查

纯仓库测试不需要镜像或 root 权限：

```sh
pnpm test
```

完整镜像构建需要 Linux、root、qemu-user-static、Go、Node.js、e2fsprogs、
mtools 和固定 AmlImg 工具；macOS 上优先使用 GitHub Actions。

## 文档

- [维护文档索引](docs/README.md)
- [当前交接状态](docs/HANDOFF.md)
- [架构与稳定性边界](docs/architecture.md)
- [HCODEC 实机验收](docs/hardware-validation.md)
- [排障手册](docs/troubleshooting.md)
- [Armbian HCODEC 路线规格](docs/superpowers/specs/2026-09-01-armbian-hcodec-route-design.md)

## 许可证

本仓库脚本使用 MIT 许可证。生成镜像及 HCODEC 研究资料中的第三方组件继续
适用各自许可证；来源和固件发布边界见 [THIRD_PARTY.md](THIRD_PARTY.md)。
