# ADR-0001：固定已验证基础镜像并每周检查 One-KVM

- 状态：Accepted
- 日期：2026-07-19
- 范围：WS1608 稳定直刷镜像

## 背景

One-KVM 的上游 Release 位于另一个 GitHub 仓库。GitHub Actions 没有通用的“订阅另一个公开仓库 Release 并自动触发本仓库 workflow”机制；除非上游主动发送 `repository_dispatch` 或外部 webhook，否则只能由本仓库定时查询。

WS1608 的启动可靠性同时依赖 DDR、U-Boot、bootloader、内核、DTB、HDMI 参数和 rootfs。仅在云 runner 中构建和检查文件，不能证明新的 Armbian 内核/设备树能在实体板卡启动。

## 决策

1. 稳定通道固定使用已在 WS1608 实机验证的 Armbian 26.8 Trixie HDMI-test 基础资产。
2. 每周日 02:17 UTC 查询 `mofeng-git/One-KVM` 最新稳定 Release。
3. 只有尚未存在对应构建 tag 时才下载 Deb、构建和发布。
4. `workflow_dispatch` 的 `force=true` 用于脚本修复、上游同 tag 资产替换或 Release 资产修复。
5. `repository_dispatch: one-kvm-release` 只作为预留入口，不能假设上游会发送。
6. 基础镜像、内核或设备树更新必须先通过实体 WS1608 验收，再进入稳定通道。

成品的 tag、多次 force 构建和发布验证规则由 [ADR-0002](0002-immutable-verified-releases.md) 补充；本 ADR 的固定基础与周检决策保持有效。

## 结果

优点：

- 保留已知启动链和 HDMI 行为，One-KVM 更新不会自动改变 bootloader/DTB。
- 无更新时不消耗完整云构建时间和 Release 存储。
- 每次成品都有上游 Deb、基础 xz 和输出镜像摘要。

代价：

- 稳定通道不是“最新 Armbian 内核”通道。
- 上游同 tag 替换资产时普通周检不会发现，需要 force 或增加 digest 比较。
- GitHub runner 不能完成实体硬件验收。
- apt 和 ext4 时间戳使 force 重建不保证字节级相同。

当前证据：固定基础 `base-20260719` 被用于 Release `ws1608-one-kvm-0.2.4-v260709-173450`；完整云构建见 [run 29697101081](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697101081)，后续周检在 [run 29697714162](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697714162) 识别已有新格式 Release 并跳过镜像构建。实体板卡验收仍不由 Actions 代替。

## 后续变更条件

下列任一项发生时，应新建 ADR 或更新本文档，而不是只改 workflow：

- 上游 One-KVM 开始主动发送 dispatch/webhook。
- 建立 candidate 基础镜像和自动硬件测试 runner。
- 改用 Debian snapshot 以实现字节级复现。
- Release 资产超过 GitHub 单文件限制，需要外部对象存储。
