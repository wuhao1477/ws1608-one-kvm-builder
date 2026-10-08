# ADR-0004：放弃 H.264 硬件编码，仓库只维护稳定固件

- 状态：Accepted
- 日期：2026-10-08
- 范围：取代 [ADR-0003](0003-armbian-6.12-hcodec-route.md)

## 背景

稳定固件（`base-20260804-consolefix` + One-KVM `0.2.6`）已在 WS1608 实机启动、
显示、联网并正常运行 One-KVM，视频使用 One-KVM 自带的软件编码。

S805 H.264 硬件编码先后尝试了 Linux 3.10 AMLENC 与 Linux 6.12 HCODEC 两条路线。
6.12 路线能在独立探针中输出有效码流，但探针后的设备稳定性和 One-KVM 反复开流
始终没有完成实机验收，继续投入与“固件能用 One-KVM”的目标不成比例。

## 决策

1. 放弃 H.264 硬件编码目标；One-KVM 使用软件编码。
2. 仓库只保留稳定固件构建链：`.github/workflows/build.yml`、`config/`、
   `scripts/`、`tests/` 和安全扫描。
3. 删除 `experimental/amlenc`、`experimental/hcodec`、对应 workflow，以及已停用的
   CNB 配置与脚本。
4. 稳定构建链恢复到发布 `ws1608-one-kvm-0.2.6-v260802-b028001` 的提交
   `8447674`：去掉 CNB 迁移带入的 FUSE/loop 分支，基础镜像改回 GitHub Release
   下载（SHA-256 不变）。
5. 硬件编码研究只以 git tag 保留：`archive/hcodec-meson8b-rearm`、
   `archive/amlenc-mainline`、`archive/amlenc-legacy-bringup`、
   `archive/amlenc-kexec-2.0.18-fix`。

## 结果

- 维护面缩小到一条已在实机证明可用的构建链。
- 已发布的 3.10 实验预发布 Release 保留原状，不再更新。
- 需要恢复硬件编码研究时，从 archive tag 建分支并新建 ADR。
