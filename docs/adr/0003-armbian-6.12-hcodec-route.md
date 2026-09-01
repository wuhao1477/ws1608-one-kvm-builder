# ADR-0003：放弃 Linux 3.10，采用 Armbian Linux 6.12 HCODEC

- 状态：Accepted
- 日期：2026-09-01
- 范围：WS1608/S805 H.264 硬件编码研发

## 背景

稳定 Armbian 26.8 / Trixie / Linux `6.12.28-current-meson` 已在 WS1608
证明能够启动、显示、联网、使用 eMMC 并运行 One-KVM。此前为了恢复
S805 厂商编码能力，仓库研究过 Linux 3.10 私有 AMLENC 字符设备路线，
但长期未能获得可靠的旧内核启动与用户态证据。

## 新证据

新的参考实现把 Amlogic HCODEC 改写为 Linux 6.12 V4L2 M2M 驱动，资料
包含 18 个补丁、Meson8b/GXL/GXM 后端、设备树绑定、固件提取脚本和
MMAP/DMABUF 测试工具。One-KVM `0.2.6` 已包含 `h264_v4l2m2m` 后端。

该资料证明路线具备较高可行性，但不是可直接交付的 S805 版本：现成模块是
AArch64 6.12.98，补丁与最终源码存在分叉，Meson8b 时钟和 HHI 资源不完整，
H.264 固件没有可追溯成品，公共节点仍默认禁用。

1080p 的驱动工作区、4 个输入和 4 个输出缓冲使编码内存接近 64 MiB；加上
USB 采集及其他 DMA 后，`cma=128M` 是合理候选，但仍需实机验证。

## 决策

1. 唯一系统底座继续使用 `base-20260804-consolefix` 和 Linux 6.12.28。
2. H.264 硬件编码只采用 `meson-venc` HCODEC V4L2 M2M。
3. 内核候选必须为 ARMv7 目标重新构建模块、DTB 和固件。
4. 独立 V4L2 码流通过后，才以 `ONE_KVM_V4L2M2M_ALLOW=1` 临时验证
   One-KVM；稳定服务保持关闭。
5. 新内核候选不得修改或覆盖稳定 Release。
6. 实机验收前保持 `hardware_boot_tested=false` 和
   `hardware_encoder_tested=false`。

## 已废弃内容

Linux 3.10.107、Debian Bullseye 实验底座、`/dev/amvenc_avc`、
`libvpcodec`、AMLENC ABI v1、双内核、recovery-first、kexec、U-Boot 冷启动
试验和对应实验 Release 全部停止开发。相关文件只保留不可执行的历史说明。

## 验证边界

CI 可以证明补丁应用、ARMv7 编译、模块依赖、DT schema、固件摘要和产物
结构；只有实体 WS1608 可以证明 HCODEC 启动、DMA/CMA、IRQ、码流、性能、
温度、USB 采集、HID 和重启稳定性。

外部 1080p30 与 One-KVM 1080p20 数据只作为测试目标，不作为验收结果。

## 结果

优点：保留已验证系统和现代 USB Gadget/OTG，使用标准 V4L2 API，移除旧
私有 ABI 与授权不明确用户态库依赖。

代价：需要为当前 ARMv7 内核完成驱动、时钟、DT、固件和 CMA 集成，并重新
进行完整实机验收。

## 后续变更条件

只有出现可复现 ARMv7 构建、完整来源摘要和 WS1608 实机证据时，才可以
更新 HCODEC 候选状态。提升为稳定输入需要新的 ADR，不通过修改本文完成。
