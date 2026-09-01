# WS1608 S805 AMLENC 实验计划（已废弃）

- 状态：Superseded
- 原计划日期：2026-08-13
- 废弃日期：2026-09-01
- 替代决策：[ADR-0003](../../adr/0003-armbian-6.12-hcodec-route.md)
- 当前规格：[Armbian HCODEC 路线设计](../specs/2026-09-01-armbian-hcodec-route-design.md)

## 原目标

该计划试图在不改变稳定镜像链的前提下，使用 S805 厂商编码内核、M8
用户态编码库和 One-KVM 私有 AMLENC 适配恢复 H.264 硬件编码。

## 已获得的历史成果

- 建立了稳定链摘要保护和独立实验工作流；
- 固定了内核、编码库、One-KVM 和工具链来源；
- 研究了 Meson8b 编码节点、连续内存和用户态 ABI；
- 建立了 H.264 码流、SPS/PPS/IDR、帧数、解码和内核错误门禁；
- 证明 One-KVM 四种软件编码路径可以继续作为可靠基础；
- 积累了 Amlogic 镜像、SSH 首启、rootfs 容量和发布复验经验。

## 废弃原因

旧系统没有达到可靠启动和用户态门槛，私有字符设备 ABI 与用户态库增加了
维护和许可证风险。新的 Linux 6.12 V4L2 M2M 资料提供 Meson8b HCODEC
后端，并能保留已经验证的 Armbian 系统、USB Gadget/OTG 和 One-KVM。

## 保留范围

Git 历史、旧 tag、源锁和失败证据保留审计用途。该文件不再是实施计划，
不得据此构建、刷写或启动旧系统。后续工作只遵循 ADR-0003 和当前路线规格。
