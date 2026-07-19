# 维护文档索引

本文档面向接手仓库的维护者。先阅读 [HANDOFF.md](HANDOFF.md) 了解当前状态，再按任务进入对应文档。

## 文档导航

- [HANDOFF.md](HANDOFF.md)：当前 Release、已验证范围、未完成事项和下一步。
- [image-lineage.md](image-lineage.md)：当前基础镜像、历史参考镜像及选型依据。
- [architecture.md](architecture.md)：稳定构建的边界、镜像分层和启动/OTG设计。
- [build-pipeline.md](build-pipeline.md)：GitHub Actions 从上游 Release 到直刷包的逐步流程。
- [manifest-schema.md](manifest-schema.md)：成品身份、输入摘要和发布资产的数据契约。
- [maintenance.md](maintenance.md)：日常更新、基础镜像更换、强制重建和 Release 维护。
- [troubleshooting.md](troubleshooting.md)：已发生故障、症状、原因和修复方法。
- [hardware-validation.md](hardware-validation.md)：WS1608 实机刷写、One-KVM、视频采集和 HID 验收表。
- [adr/0001-pinned-base-weekly-check.md](adr/0001-pinned-base-weekly-check.md)：固定稳定基础镜像并每周检查上游的决策记录。
- [adr/0002-immutable-verified-releases.md](adr/0002-immutable-verified-releases.md)：同版本多次构建、不可变 tag 和 draft 验证发布的决策记录。
- [superpowers/specs/2026-07-20-one-kvm-release-identity-design.md](superpowers/specs/2026-07-20-one-kvm-release-identity-design.md)：本次发布加固设计。
- [superpowers/plans/2026-07-20-one-kvm-cloud-release-hardening.md](superpowers/plans/2026-07-20-one-kvm-cloud-release-hardening.md)：实现与云端验收计划。

## 当前基线

| 项目 | 当前值 |
| --- | --- |
| 板卡 | OneCloud / WS1608，Amlogic S805，armhf |
| 稳定基础 | Armbian 26.8 Trixie，`6.12.28-current-meson` |
| One-KVM | `0.2.4`，上游 Release `v260709` |
| 当前 Release | [`ws1608-one-kvm-v260709`](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-v260709) |
| 成品 SHA-256 | 见 Release 的 `SHA256SUMS`，不要从聊天记录复制 |
| 自动检查 | 每周日 02:17 UTC，即北京时间周日 10:17 |

## 最短操作路径

1. 查看 [Actions](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions) 最近一次运行。
2. 没有新上游版本时，`Check One-KVM release` 成功且 `Build and verify image` 应为 skipped。
3. 只有需要修复同一版本或验证流程变更时，才在 `workflow_dispatch` 中勾选 `force`。
4. 下载 Release 的 `.burn.img` 或 `.burn.img.xz`，先核对 `SHA256SUMS`，再进行实体刷写。
5. 实机结果填写到 [hardware-validation.md](hardware-validation.md) 的验收表；云端结构测试不能替代实体刷写。

## 事实来源优先级

当文档和现场状态不一致时，按下面顺序判断：

1. `config/base.env`、`.github/workflows/build.yml` 和脚本当前内容。
2. Release 的 `manifest.json`、`SHA256SUMS` 和 GitHub Actions 日志。
3. 本目录的维护文档和历史交接记录。
4. 聊天记录中的临时路径、临时哈希或手工命令只作历史参考。

## 公开仓库安全边界

不要把设备局域网 IP、SSH 密码、GitHub token、私钥、USB 测试机信息写入仓库。实机测试需要的连接信息应留在维护者本地或组织的 Secret/密码管理器中。公开 Release 中只放镜像、校验和、构建来源摘要和许可证信息。
