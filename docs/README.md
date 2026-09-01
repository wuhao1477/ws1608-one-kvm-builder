# 维护文档索引

本文档面向仓库维护者。当前唯一系统底座是 Armbian 26.8 / Trixie /
Linux `6.12.28-current-meson`；H.264 硬件编码只走 Linux 6.12 HCODEC
V4L2 M2M 路线。

## 当前入口

- [HANDOFF.md](HANDOFF.md)：当前 Release、路线状态、证据边界和下一步。
- [architecture.md](architecture.md)：稳定构建与 HCODEC 候选的架构关系。
- [build-pipeline.md](build-pipeline.md)：现有稳定工作流和候选流程边界。
- [image-lineage.md](image-lineage.md)：稳定基础来源和候选内核选型。
- [manifest-schema.md](manifest-schema.md)：稳定资产及未来 HCODEC 候选证据字段。
- [maintenance.md](maintenance.md)：日常更新、候选升级和维护禁区。
- [hardware-validation.md](hardware-validation.md)：V4L2 M2M、码流、One-KVM、HID 验收。
- [troubleshooting.md](troubleshooting.md)：HCODEC、DT、固件、CMA 和发布排障。
- [ADR-0001](adr/0001-pinned-base-weekly-check.md)：固定已验证基础并每周检查。
- [ADR-0002](adr/0002-immutable-versioned-rebuilds.md)：不可变版本化 Release。
- [ADR-0003](adr/0003-armbian-6.12-hcodec-route.md)：放弃 3.10，采用 Armbian 6.12 HCODEC。
- [路线设计](superpowers/specs/2026-09-01-armbian-hcodec-route-design.md)：证据、限制和文档规则。
- [文档迁移计划](superpowers/plans/2026-09-01-armbian-hcodec-documentation-plan.md)：本次迁移步骤。

## 当前基线

| 项目 | 当前值 |
| --- | --- |
| 板卡 | OneCloud / WS1608，Amlogic S805，ARMv7 |
| 稳定基础 | `base-20260804-consolefix` |
| 系统 | Armbian `26.8.0-trunk.413` / Debian Trixie |
| 内核 | `6.12.28-current-meson` |
| 稳定 One-KVM | `0.2.6` / `v260802` |
| 稳定 Release | `ws1608-one-kvm-0.2.6-v260802-b028001` |
| 自动检查 | 每周日 02:17 UTC |
| HCODEC 候选 | 尚未实机验证 |
| 候选后端 | `h264_v4l2m2m` |

## 最短维护路径

1. 先读 [HANDOFF.md](HANDOFF.md) 和 [ADR-0003](adr/0003-armbian-6.12-hcodec-route.md)。
2. 稳定 One-KVM 更新继续使用 `.github/workflows/build.yml`。
3. 没有新上游 tag 与 Deb 摘要时，build/release 必须跳过。
4. HCODEC 工作先验证 ARMv7 内核、DTB、固件和独立 V4L2 码流，不修改稳定资产。
5. 独立探针通过后，才以 `ONE_KVM_V4L2M2M_ALLOW=1` 临时验证 One-KVM。
6. 实机结果按 [hardware-validation.md](hardware-validation.md) 记录。

## 已废弃历史

- [2026-08-13 S805 AMLENC 计划](superpowers/plans/2026-08-13-ws1608-s805-amlenc-experimental-plan.md)
- [2026-08-14 AMLENC 下一版本计划](superpowers/plans/2026-08-14-ws1608-amlenc-next-version-plan.md)

这两份文件只保存历史结论，不再包含可执行的旧内核开发步骤。

## 事实来源优先级

1. 当前配置、工作流和脚本。
2. Release 的 manifest、validation report、`SHA256SUMS` 和 Actions 日志。
3. ADR、路线规格和本目录维护文档。
4. 外部教程与研究资料只作候选证据，不能替代 WS1608 实测。

公开仓库不得包含设备 IP、密码、私钥、token 或序列号。
