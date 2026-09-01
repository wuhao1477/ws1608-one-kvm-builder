# WS1608 AMLENC 下一版本计划（已废弃）

- 状态：Superseded
- 原计划日期：2026-08-14
- 废弃日期：2026-09-01
- 替代决策：[ADR-0003](../../adr/0003-armbian-6.12-hcodec-route.md)
- 当前规格：[Armbian HCODEC 路线设计](../specs/2026-09-01-armbian-hcodec-route-design.md)

## 原目标

该计划延续独立 AMLENC 实验链，准备 ARMv7 One-KVM 包、私有 H.264 编码
后端、USB Gadget 和实验直刷包，同时保护稳定 One-KVM 自动发布链。

## 可继续使用的历史结论

- 稳定 Armbian 系统与实验硬件工作必须隔离；
- One-KVM H.264/H.265/VP8/VP9 软件编码是可用后备路径；
- 硬件能力只能由实体码流和内核证据确认；
- CI 必须保留不可变输入、摘要、artifact 下载后复验和未验证状态；
- 硬件失败不得修改稳定 Release。

## 不再继续的内容

私有 AMLENC ABI、旧用户态编码库、旧内核、双启动和对应 prerelease 不再
开发。新的实现使用 Armbian/Linux 6.12 `meson-venc` V4L2 M2M，并通过
One-KVM `h264_v4l2m2m` 后端接入。

## 保留范围

旧提交与计划只用于理解历史决策。该文件不包含当前执行清单，后续实现不得
从旧分支复制启动链或预编译二进制。
