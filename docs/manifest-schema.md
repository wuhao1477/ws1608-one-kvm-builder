# manifest 数据契约

新格式 Release 的 `manifest.json` 是构建来源和成品身份的机器可读记录。生成逻辑位于 `scripts/write-image-manifest.mjs` 与 `scripts/finalize-release.mjs`，验证逻辑位于 `scripts/verify-release-assets.mjs`。

## 字段

| 字段 | 类型 | 来源 |
| --- | --- | --- |
| `schema_version` | number | 固定为 `2` |
| `board` / `base` / `kernel` | string | `config/base.env` |
| `one_kvm_version` / `one_kvm_release` | string | armhf Deb 文件名和上游 tag |
| `package_name` / `package_url` / `package_sha256` | string | 上游 Release asset |
| `base_release_tag` / `base_image_name` / `base_image_url` / `base_sha256` | string | `config/base.env` |
| `build_tag` / `build_revision` / `build_number` | string / string / number | discovery 和 Actions run number/attempt |
| `builder_commit` | 40 字符十六进制 | `github.sha` |
| `github_run_id` / `github_run_number` / `github_run_attempt` | string | GitHub Actions |
| `amlimg_repository` / `amlimg_commit` | string | `config/tool-versions.env` |
| `built_at` | ISO-8601 string | finalizer 完成时间 |
| `image` / `image_size` / `image_sha256` | string / number / string | raw burn image |
| `compressed_image` / `compressed_image_size` / `compressed_image_sha256` | string / number / string | xz asset |
| `validation_report` / `validation_report_size` / `validation_report_sha256` | string / number / string | validation report |
| `validation` | string | 固定为 `passed` |

## 不变量

- `build_tag` 必须为 `ws1608-one-kvm-<Deb版本>-<上游tag>-bRRRAAA`；`build_revision` 是末段，且与 `build_number` 一致。
- `image` 必须为 `One-KVM_<Deb版本>-<上游tag>-bRRRAAA_<BASE_FLAVOR>.burn.img`，`compressed_image` 等于 `image + .xz`。
- 所有 manifest、报告和 `SHA256SUMS` 中的文件名都是 basename，不能是符号链接。
- `SHA256SUMS` 恰好四行，覆盖 raw image、xz image、`manifest.json` 和 `validation-report.json`。
- xz 解压后的字节必须与 raw image 完全相同。
- 发布目录恰好包含五个文件：raw image、xz image、`SHA256SUMS`、`manifest.json`、`validation-report.json`。
- draft 和公开 Release 的五个 GitHub asset 都必须是 `uploaded`，远端 `sha256:` digest 必须与本地文件一致。
- Release body 同时记录五个资产的名称和摘要；周检只有在这些标记完整一致时才跳过构建。
- `validation-report.json` 必须有 `result=passed` 且 `hardware_boot_tested=false`。这不代表实体 WS1608 已刷写启动。

## 兼容性

迁移前的 `ws1608-one-kvm-v260709` 和旧 HHMMSS Release 只作为历史资产，不满足 schema 2 的跳过条件。新的 force 构建会产生完整五资产 schema，不修改旧 Release。

维护者增加字段时，应先更新 synthetic artifact 测试、发布/验证脚本和本文档，再运行完整云构建。
