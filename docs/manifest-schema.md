# manifest 数据契约

## 稳定 Release schema

稳定 `manifest.json` 由 `scripts/write-image-manifest.mjs` 和
`scripts/finalize-release.mjs` 生成，当前 `schema_version=2`。

主要字段：

| 字段 | 来源 |
| --- | --- |
| `board` / `base` / `kernel` | `config/base.env` |
| `one_kvm_version` / `one_kvm_release` | 上游 armhf Deb 与 Release tag |
| `package_name` / `package_url` / `package_sha256` | 上游资产 |
| `base_release_tag` / `base_image_name` / `base_sha256` | 固定基础 |
| `build_tag` / `build_revision` / `build_number` | discovery 与 Actions |
| `builder_commit` | 构建提交 |
| `github_run_id` / `github_run_number` / `github_run_attempt` | Actions |
| `amlimg_repository` / `amlimg_commit` | 固定工具来源 |
| raw、xz、validation report 的名称、大小和 SHA-256 | 最终资产 |
| `validation` | 固定为 `passed` |

不变量：

- tag 与镜像文件名使用同一 `bRRRAAA` 身份；
- 所有资产名是 basename，且不是符号链接；
- xz 解压结果与 raw image 完全相同；
- 发布目录恰好包含五项资产；
- GitHub 远端 digest 与本地摘要一致；
- validation report 为 `result=passed` 且 `hardware_boot_tested=false`。

## HCODEC 候选证据

未来 HCODEC 工作流必须在独立候选 manifest 中增加以下 schema 约束。当前
稳定工作流尚未生成这些字段：

```json
{
  "kernel_base": { "const": "6.12.28-current-meson" },
  "encoder_backend": { "const": "h264_v4l2m2m" },
  "driver_source_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
  "patch_series_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
  "firmware_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
  "dtb_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
  "cma_mib": { "type": "integer", "minimum": 1 },
  "hardware_boot_tested": { "type": "boolean" },
  "hardware_encoder_tested": { "type": "boolean" }
}
```

候选实例必须填写实际摘要和 CMA 数值，并记录：

- 内核源码提交、配置摘要、编译器和 vermagic；
- 驱动使用补丁系列还是最终源码，不允许混合；
- Meson8b 固件来源、许可证和提取输入；
- OneCloud DT 时钟、HHI、DOS、IRQ 和 Canvas 资源；
- V4L2 输入格式、分辨率、帧率、码率、缓冲数量和探针结果；
- 独立解码、内核错误扫描、温度与运行时长；
- One-KVM 是否仅通过临时环境开关运行。

新候选生成时两个硬件字段必须从 `false` 开始。静态构建和其他 SoC 测试
不能把它们改为 `true`。

## 兼容性

旧格式 Release 不满足 schema 2 的跳过条件。已废弃 H.264 实验 tag 保留
历史用途，不作为 HCODEC 新候选的输入或成功证据。

增加字段时先更新测试、生成器、验证器和本文档，再运行完整云构建与实体
验收。
