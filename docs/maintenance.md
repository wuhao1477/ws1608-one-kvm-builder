# 维护手册

## 日常检查

每周检查不需要人工操作。查看 [Actions](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions)：

- `Check One-KVM release` 成功，说明上游 API、资产命名和本仓库 Release 查询都正常。
- 有新 tag 时必须看到 `Build and verify image`。
- 没有新 tag 时必须看到 `No new One-KVM release`，且 build job 是 skipped。
- Build 成功后，查看新时间戳 Release 的四个资产均为 `uploaded`，并核对 `manifest.json`、`SHA256SUMS` 和 GitHub asset digest。

当前已验证的参考运行：

- 成功构建、验证并首次发布：[29692047384](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29692047384)。
- 无更新跳过构建：[29692347031](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29692347031)。
- 旧流程强制覆盖同一 Release：[29692576405](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29692576405)，只作迁移前历史证据。

新不可变 Release 流程的参考运行在完成首次云端验收后记录到 [HANDOFF.md](HANDOFF.md)。

## 手动触发

普通检查：

```sh
gh workflow run build.yml \
  --repo wuhao1477/ws1608-one-kvm-builder \
  --ref main \
  -f force=false
```

只有以下情况使用强制模式：

- 修复了构建/验证脚本，需要重新生成同一上游版本。
- 上游在同一个 tag 下替换了 Deb 资产。
- 需要修复 Release 上传的文件或校验和。

```sh
gh workflow run build.yml \
  --repo wuhao1477/ws1608-one-kvm-builder \
  --ref main \
  -f force=true
```

强制模式会创建新的 `ws1608-one-kvm-<version>-<upstream-tag>-<UTC-HHMMSS>` Release，旧 tag 和资产保持不变。由于 apt 仓库和 ext4 时间戳是动态的，不同构建的 SHA-256 可以不同；分别以各自 manifest 和 `SHA256SUMS` 为准。

## 更新 One-KVM 版本

通常不需要改代码：

1. 等待周检，或手动运行 `force=false`。
2. `discover-release.sh` 会从上游最新 Release 选择唯一 armhf Deb。
3. 构建会从包 metadata 检查版本和架构。
4. 新 Release tag 格式为 `ws1608-one-kvm-<Deb版本>-<上游tag>-<UTC-HHMMSS>`。

如果上游改变资产命名、同时发布多个 armhf 变体或不再提供 digest，先在 `scripts/discover-release.sh` 增加明确规则和测试；不要把“取第一个资产”作为临时修复。

## 更新稳定基础镜像

基础镜像包含启动链、内核、DTB 和 HDMI 参数，是最高风险的输入。流程如下：

1. 在独立工作目录生成候选 Amlogic `.burn.img`，不要覆盖 `base-20260719`。
2. 在实体 WS1608 上刷写，按 [hardware-validation.md](hardware-validation.md) 完成启动、HDMI、网络、One-KVM、OTG、视频和 HID 测试。
3. 将候选镜像压缩为 `.img.xz`，计算 SHA-256。
4. 创建新的不可变基础 Release，例如 `base-YYYYMMDD`，上传压缩资产和测试说明。
5. 修改 `config/base.env` 的四个字段：`BASE_RELEASE_TAG`、`BASE_IMAGE_NAME`、`BASE_IMAGE_SHA256`、`BASE_IMAGE_URL`。
6. 搜索并检查硬编码的版本文字：

```sh
rg -n 'Armbian_|6\.12\.28|HDMI-test|Onecloud_trixie' .
```

7. 先运行 `npm test`、`bash -n` 和 `actionlint`，再用 `force=true` 构建候选 Release。
8. 候选包完成实体刷写后，才把它作为稳定基础继续使用。

不要直接把 Armbian 每日构建 URL 写入稳定通道。若要追踪最新内核，应另建 candidate 流程，成功后再人工提升基础 tag。

## 更新 AmlImg 工具

`config/tool-versions.env` 固定了仓库和提交：

```text
AMLIMG_REPOSITORY=https://github.com/rmoyulong/AmlImg.git
AMLIMG_COMMIT=311cd4b892023bcb3cf6661698f5ab685e34a7f8
```

更新时必须：

- 检查上游许可证和 CLI 行为仍支持 `unpack`、`pack`。
- 在测试中验证 Amlogic v2 CRC 和条目布局。
- 用同一个基础包做一次完整云构建。
- 比较 boot、bootloader、resource 和 rootfs VERIFY 行为。

不要把未固定的 `main` 或 `latest` 直接用于生产构建。

## Release 维护

Release tag 是不可变构建身份，不要删除旧版本来“清理列表”。发布失败时：

1. 查看构建 job 的失败步骤和 artifact 是否存在。
2. 修复代码并提交到 `main`。
3. 对同一上游 tag 使用 `force=true`，生成新的时间戳身份。
4. 重新检查 Release 是否为非 draft、四个资产是否 uploaded，且 digest 与 `SHA256SUMS` 相符。

发布步骤先创建 draft。远端摘要或状态不匹配时，脚本会删除本次 draft/tag 并让 job 失败。发现残留 draft 时先确认对应 run 已失败，再删除该 draft；不能修改已有公开 Release 来冒充重建结果。

基础 Release 应使用新 tag，不要覆盖已有基础资产；覆盖基础包会让历史 manifest 的 URL 指向不同内容。

## 依赖和权限

- GitHub Actions 使用 `contents: write` 发布 Release；不要扩大到 `pull-requests: write` 或在 PR 事件上复用该权限。
- `actions/checkout@v7`、`actions/setup-go@v7`、`actions/upload-artifact@v7` 当前使用官方 major 版本；升级时查看 action 的 Node/runtime 兼容性。
- `qemu-user-static`、`e2fsprogs`、Go 和 Node 是构建环境依赖，不要把二进制提交到仓库。
- 不把设备密码、SSH key、token、局域网 IP 或物理测试机信息加入 workflow、manifest 或 docs。

## 发布前清单

仓库级检查：

```sh
npm test
for script in scripts/*.sh; do bash -n "$script"; done
git diff --check
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/build.yml
```

Release 下载后检查：

```sh
gh release download "$BUILD_TAG" --repo wuhao1477/ws1608-one-kvm-builder --dir release-check
node scripts/verify-artifacts.mjs release-check "$IMAGE_NAME" "$EXPECTED_MANIFEST_JSON"
```

manifest 字段来源与不变量见 [manifest-schema.md](manifest-schema.md)。

- [ ] `config/base.env` 的 URL 可下载，SHA-256 与 Release asset digest 一致。
- [ ] 上游 armhf Deb 包名、版本、架构和 digest 已检查。
- [ ] `npm test` 与所有 `bash -n` 通过。
- [ ] Amlogic 条目、非 rootfs 分区和 VERIFY SHA1 通过。
- [ ] rootfs 已严格卸载后再运行 `e2fsck`。
- [ ] `SHA256SUMS` 使用 basename，不能含 runner 绝对路径。
- [ ] 本地成品和重新下载的 Actions artifact 均通过 `verify-artifacts.mjs`。
- [ ] 下载后的 burn 镜像再次通过 `verify-image.sh`。
- [ ] Release 四个资产均为 uploaded，raw/xz manifest hash 与 GitHub asset digest 相同。
- [ ] Release 非 draft/non-prerelease，tag 中的 Deb 版本、上游 tag 和 UTC 时分秒正确。
- [ ] 实机刷写结果单独记录，不能用 CI 结构验证替代。
