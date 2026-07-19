# One-KVM 构建身份与发布门槛设计

日期：2026-07-20  
状态：已确认，待实施

## 目标

调整 WS1608 One-KVM 云构建，使同一个 One-KVM Rust 版本可以安全地产生多个不可变构建，同时让 Release/tag 在名称中直接显示 One-KVM 版本，并把成品检查作为发布前的硬门槛。

## 标签与 Release 命名

采用短格式：

```text
ws1608-one-kvm-<one-kvm-deb-version>-<upstream-tag>-<utc-hhmmss>
```

示例：

```text
ws1608-one-kvm-0.2.4-v260709-143015
```

- `0.2.4` 是 `one-kvm_*_armhf.deb` 的实际 Deb 版本。
- `v260709` 是上游 One-KVM Release tag，保留上游日期标识。
- `143015` 是构建开始时的 UTC 时分秒，不使用本地时区。
- `manifest.json` 保存完整 ISO-8601 `built_at`、GitHub run ID、run attempt、上游 tag、包摘要、基础摘要和 builder commit，tag 保持短而不丢失追溯信息。

成品文件名使用相同身份，例如：

```text
One-KVM_0.2.4_v260709_143015_Onecloud_trixie_6.12.28_HDMI-test.burn.img
```

## 多次构建与碰撞策略

- 普通周检以“是否已经存在该上游 tag 的成功构建”为状态；已有构建时只检查并跳过完整镜像构建。
- 迁移时，现有旧格式 `ws1608-one-kvm-v260709` 继续被识别为 `v260709` 的成功构建，普通周检不会因命名规则变化而重复构建。
- `workflow_dispatch` 的 `force=true` 总是创建新的时间戳 tag 和独立 Release，不覆盖旧 Release 资产。
- workflow 继续使用串行 concurrency，避免同时生成相同秒数的 tag。
- 创建构建 tag 前检查远端 tag 和 Release 是否已存在；发生碰撞时直接失败并输出明确原因，不自动覆盖或静默改名。
- 构建失败或验证失败时不创建 Release；后续重试会产生新的时间戳。
- 发布使用 `gh release create`，不使用 `--clobber` 或 `release edit` 覆盖历史构建。

## 构建后验证门槛

发布步骤必须依赖所有验证步骤成功。验证分为四层：

1. **输入层**：基础镜像 SHA-256、One-KVM Deb digest、Package/Version/Architecture 和 AmlImg commit。
2. **容器层**：成品独立解包、Amlogic v2 CRC、12 条 commands 顺序、非 rootfs 分区逐字节不变、所有 VERIFY SHA-1。
3. **rootfs 层**：严格卸载后 `e2fsck`、sparse 往返字节一致、Deb 状态/版本/架构、ARM ELF、systemd enable/drop-in、OTG unit/helper/module、版本 metadata。
4. **发布资产层**：重新读取最终 `.burn.img`、压缩后解压并与最终 raw 镜像比较、`SHA256SUMS` 自校验、manifest 字段与实际文件和环境一致。

任一命令非零、文件缺失、摘要不匹配或字段不一致都必须使 build job 失败；Release 创建步骤不能通过 `always()` 绕过失败依赖。

最终资产先上传为 Actions artifact，再下载到全新目录重新执行发布资产层检查。通过后创建 draft Release，比较 GitHub 返回的每个 asset digest 与本地 SHA-256；全部一致才将 Release 从 draft 改为公开。draft 校验失败时删除该 draft，job 保持失败状态，不产生公开 Release 或正式 tag。

## 触发与追踪

- schedule 仍每 7 天检查上游最新稳定 Release。
- 新上游 tag 触发一次正常构建；同一上游 tag 的 force 构建产生新的构建身份。
- Release 标题、tag、资产文件名、manifest 和 release notes 使用同一 One-KVM Deb 版本；上游 tag 与构建时间在 Release notes/manifest 中保留。
- 不把基础 Armbian、内核、DTB 或 U-Boot 的滚动更新混入稳定通道。

## 非目标与边界

GitHub hosted runner 不能连接 USB Burning Tool，也不能模拟 HDMI、USB 视频采集或 HID。因此云端验证只能证明镜像结构和 rootfs 内容；实体 WS1608 刷写、断电重启和 One-KVM 外设验收仍是发布后的硬件步骤，不能伪装成 CI 结果。

## 验收标准

- 同一上游 tag 的两次 force 构建拥有不同 tag/Release，旧资产仍可下载。
- 任意验证失败时不存在对应的已发布 Release。
- 从 Release 下载的压缩包解压后 SHA-256 与 `SHA256SUMS` 和 manifest 一致。
- Release/tag/manifest 能直接识别 One-KVM Deb 版本，且能追溯上游 tag、构建时间和 builder commit。
- 普通周检在已有成功构建时不启动完整镜像 job。
