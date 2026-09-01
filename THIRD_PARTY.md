# Third-party components

## Stable image components

- [One-KVM Rust](https://github.com/mofeng-git/One-KVM)：GPL-3.0。
- [Armbian build](https://github.com/armbian/build)：GPL-2.0。
- Linux kernel：GPL-2.0，具体版本与配置由基础镜像提供。
- Debian packages：适用各软件包随附许可证。
- [AmlImg](https://github.com/rmoyulong/AmlImg)：BSD-3-Clause，提交由
  `config/tool-versions.env` 固定。

## Linux 6.12 HCODEC research material

2026-09-01 核对的研究资料包含：

- Linux 6.12 `meson-venc` V4L2 M2M 驱动；
- 18 个内核补丁；
- `amlogic,meson8b-hcodec` DT binding 与 Meson8b 节点；
- H.264 固件提取脚本；
- MMAP、DMABUF、采集编码和设备信息测试工具。

资料压缩包 SHA-256：
`4422aa4c8d9f3f18cc6220ec3c0da056ed5979fdddeaad1b6b09166edf80e0a6`。

驱动文件声明 GPL-2.0-only，设备树文件声明 GPL-2.0-only OR MIT，binding
声明 GPL-2.0-only OR BSD-2-Clause。每个后续文件仍以自身 SPDX 标识为准。

该资料当前只作参考实现，不能直接进入公开构建：

- 压缩包来源与上游提交尚未建立可复现映射；
- 预编译模块是 AArch64 6.12.98，不适用于 WS1608 ARMv7；
- 预编译测试程序不进入仓库或 Release；
- `meson8b_h264.bin` 未随资料提供，提取后的固件需要单独记录来源、输入摘要、
  输出摘要和再分发条件；
- 18 个补丁与最终驱动源码存在修订差异，不能混合作为许可证或构建来源。

## Superseded AMLENC research

历史研究使用过 Hardkernel Linux、Khadas `libencoder` 和 One-KVM AMLENC
适配。该路线已由
[ADR-0003](docs/adr/0003-armbian-6.12-hcodec-route.md) 废弃。
其中 `libvpcodec` 与诊断二进制缺少完整再分发授权，只保留历史来源信息，
不得进入新 HCODEC 候选或公开资产。
