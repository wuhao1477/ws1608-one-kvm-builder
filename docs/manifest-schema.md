# manifest 数据契约

新格式 Release 的 `manifest.json` 是构建来源和成品身份的机器可读事实记录。生成逻辑位于 [build.yml](../.github/workflows/build.yml)，校验逻辑位于 [verify-artifacts.mjs](../scripts/verify-artifacts.mjs)。

## 字段

| 字段 | 类型 | 来源 | 验证 |
| --- | --- | --- | --- |
| `board` | string | 固定为 `WS1608 / OneCloud` | artifact verifier 精确比较 |
| `base` | string | 固定基础镜像名称 | artifact verifier 精确比较 |
| `kernel` | string | 固定为 `6.12.28-current-meson` | artifact verifier 精确比较 |
| `build_tag` | string | release identity formatter | build script、artifact verifier、远端 Release |
| `build_stamp` | string | discovery 的 UTC `HHMMSS` | identity formatter、镜像 metadata |
| `built_at` | string | runner UTC ISO-8601 时间 | artifact verifier 精确比较 |
| `one_kvm_version` | string | Deb 文件名和 Package metadata | dpkg、identity、artifact verifier |
| `one_kvm_release` | string | 上游 Release tag | discovery、镜像 metadata |
| `image` | string | 未压缩成品 basename | 文件集合、SHA256SUMS、manifest |
| `image_sha256` | string | 未压缩成品实际 SHA-256 | 流式重算、SHA256SUMS、GitHub digest |
| `image_xz` | string | 压缩成品 basename | 文件集合、SHA256SUMS、manifest |
| `image_xz_sha256` | string | 压缩成品实际 SHA-256 | 流式重算、SHA256SUMS、GitHub digest |
| `package_url` | string | 上游 armhf Deb asset URL | artifact verifier 精确比较 |
| `package_sha256` | string | GitHub digest 或下载后实算 | 下载检查、artifact verifier |
| `base_image_url` | string | `config/base.env` | artifact verifier 精确比较 |
| `base_sha256` | string | `config/base.env` | 下载检查、artifact verifier |
| `builder_commit` | string | `github.sha` | artifact verifier 精确比较 |
| `github_run_id` | string | `github.run_id` | artifact verifier 精确比较 |
| `github_run_attempt` | string | `github.run_attempt` | artifact verifier 精确比较 |
| `amlimg_repository` | string | `config/tool-versions.env` | artifact verifier 精确比较 |
| `amlimg_commit` | string | `config/tool-versions.env` | build-tools 固定提交、artifact verifier |

## 不变量

- `build_tag` 必须是 `ws1608-one-kvm-<version>-<upstream-tag>-<HHMMSS>`。
- `image` 必须是 `One-KVM_<version>_<upstream-tag>_<HHMMSS>_Onecloud_trixie_6.12.28_HDMI-test.burn.img`。
- `image_xz` 必须等于 `image + .xz`。
- `SHA256SUMS` 只能有两行，使用 basename，分别对应 raw 和 xz。
- xz 解压后的文件必须与 raw 镜像逐字节相同。
- 发布目录只能包含 raw、xz、`SHA256SUMS` 和 `manifest.json`。
- GitHub draft Release 的四个 asset digest 必须与本地文件完全一致。

## 兼容性

迁移前 Release `ws1608-one-kvm-v260709` 的 manifest 没有完整构建身份和工具字段，因此不能直接通过新 `verify-artifacts.mjs` 的完整 expected JSON。它只用于历史恢复和迁移状态判断；新的 force 构建会产生完整 schema，不修改旧 manifest。

维护者增加字段时，应先更新 synthetic artifact 测试、workflow 的 `EXPECTED_MANIFEST_JSON` 和本文档，再运行完整云构建。

