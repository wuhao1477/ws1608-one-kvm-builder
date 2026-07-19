# ADR-0002：不可变多次构建与验证后发布

- 状态：Accepted
- 日期：2026-07-20
- 范围：WS1608 One-KVM 成品 Release

## 背景

旧流程把一个上游 tag 映射为一个固定的本仓库 tag，`force=true` 使用 `--clobber` 覆盖同名 Release。这样无法同时保留同一 One-KVM Rust 版本的多次构建，也难以从文件名判断具体构建身份；Release 上传后的远端资产没有在公开前再次核对。

## 决策

1. 成品 tag 使用 `ws1608-one-kvm-<Deb版本>-<上游tag>-<UTC-HHMMSS>`。
2. 成品文件名使用相同的 Deb 版本、上游 tag 和 UTC 时分秒。
3. `force=true` 创建新的 tag 和 Release，历史 Release 永不覆盖。
4. 普通周检把旧格式 tag 和带四个已上传资产的新格式 tag 都视为成功构建，迁移不会触发无意义重建。
5. 同名 tag/Release 碰撞时直接失败，不能自动覆盖或静默改名。
6. 发布前依次验证本地成品、重新下载的 Actions artifact 和解包后的 burn 镜像。
7. Release 先创建为 draft；四个远端 asset digest 与本地 SHA-256 一致后才公开。失败时删除本次新建的 draft/tag。
8. `manifest.json` 保存完整构建时间、run ID、run attempt、builder commit、输入来源和摘要。

## 结果

- 同一个 One-KVM Rust 版本可以保留多个独立构建。
- tag 和文件名可以直接识别 Deb 版本与上游 Release。
- 任一验证失败都会使云构建失败，且不会留下公开的错误 Release。
- UTC 时分秒可能在不同日期发生同名碰撞；串行 concurrency 降低概率，远端预检负责阻止覆盖，重新触发会取得新的时间。
- GitHub hosted runner 仍不能证明实体 WS1608 已启动，实机刷写验收继续独立执行。

## 实际验收

- Release [`ws1608-one-kvm-0.2.4-v260709-173450`](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.4-v260709-173450) 已公开，旧 Release 未被修改。
- [run 29697101081](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697101081) 通过输入、镜像、artifact、draft 和远端 digest 检查。
- [run 29697714162](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697714162) 证明新格式 Release 能被发现并跳过完整构建。
- 当前没有残留 draft；raw/xz、manifest 和 `SHA256SUMS` 摘要见 [HANDOFF.md](../HANDOFF.md)。
