# 镜像来源与选型

## 当前稳定基础

唯一稳定输入由 [`config/base.env`](../config/base.env) 定义：

```text
BASE_RELEASE_TAG=base-20260804-consolefix
BASE_IMAGE_NAME=Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-consolefix.burn.img.xz
BASE_KERNEL=6.12.28-current-meson
```

该镜像来自 Armbian 26.8 / Debian Trixie，并修复 U-Boot 文本环境中的 console
引号。稳定系统已有实体启动、HDMI、网络、SSH、eMMC 和 One-KVM 运行证据。
自动构建只修改 rootfs；DDR、U-Boot、bootloader、内核、DTB、resource 和
HDMI 参数保持不变。

## HCODEC 候选来源

硬件编码继续使用 Armbian/Linux 6.12 系统，不建立旧内核用户空间。候选必须
固定以下输入：

- 与稳定基础匹配的 Linux 6.12 ARMv7 源码与 `.config`；
- 选定的 `meson-venc` 驱动基线及完整摘要；
- Meson8b 时钟、HHI、Canvas、DOS、IRQ 和 OneCloud DT 改动；
- 可追溯的 `meson/venc/meson8b_h264.bin` 来源和 SHA-256；
- 由同一源码构建的 ARMv7 V4L2 测试工具。

研究资料包含 18 个补丁和一个更新的最终驱动，两者不是同一修订。实施时只能
选择一个一致基线；不能把 AArch64 6.12.98 预编译模块复制进当前镜像。

HCODEC 候选改变内核或 DTB，因此必须使用独立 prerelease 身份，并重新完成
启动、HDMI、网络、eMMC、OTG、视频和编码验收。

## 已废弃历史

Linux 3.10.107、Debian Bullseye、私有 AMLENC 字符设备、双内核和 kexec
实验未达到可靠启动门槛，已由 [ADR-0003](adr/0003-armbian-6.12-hcodec-route.md)
废弃。历史 tag 和提交保留审计用途，但不再作为构建输入。

## 其他参考镜像

- Armbian Jammy 6.1.9：只作恢复和差异参考，未进入当前固定输入。
- 官方 One-KVM Bookworm 5.9.0-rc7：只用于理解 OneCloud 封装，不能拆取
  bootloader、DTB 或 rootfs 混入当前基础。

任何新的 Armbian、内核、DTB 或 U-Boot 组合都先作为候选完成实体测试，再
通过新 ADR 决定是否提升。仅有文件名、CI 或其他 SoC 结果不能证明可用。
