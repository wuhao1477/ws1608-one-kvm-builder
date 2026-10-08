# WS1608 One-KVM 构建器交接

更新时间：2026-10-08

## 当前结论

仓库只维护一条稳定固件链，硬件编码已放弃（[ADR-0004](adr/0004-drop-hardware-h264.md)）：

- 仓库：[wuhao1477/ws1608-one-kvm-builder](https://github.com/wuhao1477/ws1608-one-kvm-builder)
- 当前 Release：[ws1608-one-kvm-0.2.6-v260802-b028001](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.6-v260802-b028001)
- 完整构建与发布：[Actions run 30917486241](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/30917486241)，结论 `success`，builder commit `8447674df6536f7b4fd2c58031d00de039169273`
- 最近一次无更新检查：[Actions run 34745400800](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/34745400800)（2026-09-13），build 和 release job 均为 skipped
- 上游版本：One-KVM `0.2.6`，tag `v260802`
- 基础：`base-20260804-consolefix`，Armbian 26.8 Trixie，`6.12.28-current-meson`
- 实机：consolefix 底座已验证启动、HDMI、网络、SSH、eMMC；One-KVM 服务和 health API 正常，视频使用软件编码
- 触发：每周日 02:17 UTC；无新的上游 tag + Deb digest 时只检查、不构建

稳定构建链（workflow、`config/`、`scripts/`、`tests/`）与发布 `b028001` 的 builder commit 一致，只额外增加了 `Repository security` 密钥扫描。

## 已实现的范围

仓库现在可以在 GitHub hosted Ubuntu runner 中完成：

1. 查询上游最新稳定 One-KVM Release。
2. 严格选择唯一 armhf Deb 并验证 digest、版本和架构。
3. 下载固定基础 burn 包并验证 SHA-256。
4. 解包 Amlogic v2，展开 rootfs，使用 qemu 在 armhf chroot 中安装包。
5. 安装 One-KVM 开机服务、WS1608 OTG unit/drop-in、`libcomposite` 和版本 metadata。
6. 严格卸载 rootfs 后运行 e2fsck，重建 sparse 并验证往返一致性。
7. 更新 sparse rootfs 的 Amlogic VERIFY SHA-1，重打包容器。
8. 独立解包成品，比较非 rootfs 分区、检查所有 VERIFY、Deb/systemd/OTG/ext4。
9. 生成并验证 versioned image、xz、`SHA256SUMS`、`manifest.json` 和 `validation-report.json`。
10. 下载 artifact 后再次验证，再公开不可变 Release。

具体实现不要从本文件复制，直接以 [build-pipeline.md](build-pipeline.md)、[scripts/build-image.sh](../scripts/build-image.sh) 和 [scripts/verify-image.sh](../scripts/verify-image.sh) 为准。

## 最重要的边界

- 稳定通道只自动更新 One-KVM，不自动滚动 Armbian、内核、DTB 或 U-Boot。
- CI 结构、rootfs、artifact 和远端摘要验证通过不等于实体 WS1608 已启动；每个新 Release 仍需要一次实机刷写验收。
- 已验证基础镜像能启动、HDMI 显示、联网、使用 eMMC 并承受短时负载；One-KVM `0.2.6` health/service 已在实机通过。
- HDMI 音频存在已知 `gx-sound-card` error -22；USB 视频/HID、实际采集卡和被控机 HID 仍需现场验证。
- 设备 IP、SSH 密码、token、私钥和物理测试机信息不在公开仓库中。

## 接手后的第一步

1. 阅读 [docs/README.md](README.md)、[build-pipeline.md](build-pipeline.md) 和 [troubleshooting.md](troubleshooting.md)。
2. 阅读 [image-lineage.md](image-lineage.md)，不要把历史 Jammy 或官方 Bookworm 参考包误当成当前稳定基础。
3. 打开 [Actions](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions)，确认最近一次完整运行和 skipped 运行的每个验证步骤。
4. 实机刷写前下载当前 Release 的 xz 镜像并核对 `SHA256SUMS`；需要审计全部五个资产时，在有足够空间的 Linux runner 上使用 `scripts/verify-release-assets.sh`。
5. 同一上游版本需要重建时使用 `force=true`；它会生成新的 `bRRRAAA` tag，不会修改旧 Release。
6. 如要改基础镜像，先阅读 [hardware-validation.md](hardware-validation.md)，完成实体刷写后再改 `config/base.env`。

## 已知维护风险

### 1. 不能忽略卸载错误

此前使用递归 `/dev` bind mount 并忽略 `umount` 返回值，导致 e2fsck 在仍挂载的 raw 文件上运行。日志出现 journal recovery、orphan inode 和 free block/inode 错误，OTG 文件在成品中消失。当前代码改用临时 `/dev`、隔离的 mount/PID namespace、复制/恢复 DNS、残留挂载检查和严格卸载。修改这些代码时必须保留这些检查。

### 2. force 重建不是字节级复现

rootfs 安装使用动态 apt 源，ext4 时间戳和构建时间也会变化。同一上游 tag force 重建可能得到不同 SHA-256；这是当前设计已知限制，不要把旧 hash 硬编码成测试期望。

### 3. 上游同 tag 替换资产或 tag 碰撞

当前 discover 同时比较上游 tag 和 package digest。如果上游重写同一个 tag，下一次周检会使用新的 `bRRRAAA`；仍应检查新 manifest 的 package digest。

### 4. GitHub 资产大小

当前未压缩镜像约 1.19 GB，低于 GitHub Release 单文件限制；rootfs 增长后要重新评估。不能为了绕过限制而删除直刷 `.img`，因为用户需要直接刷写包。

## 后续优先级

1. 2026-09-13 之后每周调度没有再触发，而上游已发布 One-KVM `0.2.7`（`v260926`）和 `0.2.8`（`v261001`）。先在 Actions 页面确认调度状态，必要时用 `workflow_dispatch` 构建；新 Release 刷写后按 [hardware-validation.md](hardware-validation.md) 复测。
2. 采集卡视频和被控机 USB HID 仍需现场验证；不含敏感信息的结论记录到私有测试记录，公开仓库只记录结论和 Release tag。
3. 若需要最新内核，建立 candidate 基础镜像流程，先通过硬件验收再提升稳定基础。
4. 若需要严格可复现，固定 Debian snapshot、依赖版本、时间戳，并保留 manifest 中的 builder commit。

## 建议的后续技能

- GitHub Actions 失败：`github:gh-fix-ci`。
- 复杂构建/挂载问题：`systematic-debugging`。
- 交付前证据检查：`verification-before-completion`。
- 实体板卡和接口验收：`hardware-solution`，但不要跳过 [hardware-validation.md](hardware-validation.md) 的现场步骤。
- 再次交接：`handoff`，输出必须脱敏。
