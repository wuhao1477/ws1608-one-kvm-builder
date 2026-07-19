# 构建与发布流程

## 触发方式

工作流文件是 [.github/workflows/build.yml](../.github/workflows/build.yml)。

| 触发器 | 行为 |
| --- | --- |
| `schedule` | 每周日 `02:17 UTC` 检查一次，约北京时间周日 `10:17` |
| `workflow_dispatch`，`force=false` | 与定时检查相同；该上游 tag 已有完整公开 Release 时跳过 |
| `workflow_dispatch`，`force=true` | 忽略版本级检查，创建新的 UTC 时分秒 tag 和独立 Release |
| `repository_dispatch: one-kvm-release` | 预留接口；上游 One-KVM 当前不会主动发送，因此不能依赖它及时触发 |

工作流的 `contents: write` 权限只用于发布 Release。当前没有 `pull_request` 构建路径，不要在未来引入未审查的 PR 代码并保留同样的写权限。

## 阶段一：发现上游版本

`scripts/discover-release.sh` 使用 `gh api repos/mofeng-git/One-KVM/releases/latest`：

1. 只接受非 draft、非 prerelease 的最新 Release。
2. 必须找到且只能找到一个名称以 `one-kvm_` 开头、以 `_armhf.deb` 结尾的资产。
3. 从文件名取得包版本，从 GitHub API 取得下载 URL 和 digest。
4. 以 Deb 版本、上游 tag 和当前 UTC 时分秒生成构建身份，例如 `ws1608-one-kvm-0.2.4-v260709-143015`。
5. 查询全部公开 Release。旧格式 tag 或匹配新格式、且四个必要资产均为 uploaded 的 Release 才算成功构建。
6. 已有成功构建且不是 force 时输出 `changed=false`；draft、prerelease 或资产不完整不会阻止重建。
7. API 没有提供 digest 时，下载步骤自行计算实际 Deb SHA-256 并写入 manifest。

这里没有单独的 state 文件，完整公开 Release 是“已构建版本”的事实来源。上游若在同一个 tag 下替换资产，普通周检仍不会自动重建；使用 `force=true` 生成新构建，并比较新旧 manifest 的 `package_sha256`。

## 阶段二：准备云 runner

构建 job 使用 `ubuntu-24.04`，安装：

- `e2fsprogs`：`e2fsck`、文件系统检查。
- `qemu-user-static`：在 x86/arm64 runner 中执行 armhf rootfs 的命令。
- `binutils`、`file`、`jq`、`xz-utils`。
- Go `1.24.x`，用于构建固定提交的 AmlImg。

标准 runner 当前足够容纳约 1.19 GB 未压缩成品、约 339 MB xz 成品、308 MB 基础 xz、rootfs raw 和验证副本。若 rootfs 或 Release 资产继续增长，先检查 runner 磁盘和 GitHub 单文件 2 GiB 限制。

## 阶段三：下载和校验输入

基础包从本仓库的 `base-20260719` Release 下载，URL 和 xz SHA-256 固定在 `config/base.env`。One-KVM 包从上游 URL 下载，并检查：

```text
Package = one-kvm
Architecture = armhf
Version = discover-release 输出的版本
```

任何摘要、包名或架构不匹配都会停止，不会发布不确定来源的镜像。

## 阶段四：解包和修改 rootfs

`scripts/build-image.sh` 的实际顺序：

1. 解压基础 `.img.xz`。
2. 使用固定提交的 AmlImg 解包 Amlogic v2 容器。
3. 从 `commands.txt` 找到 `rootfs` sparse 项和对应 VERIFY 项，不硬编码偏移。
4. `sparse-to-raw.mjs` 将 Android sparse 展开为 ext4 raw；逻辑大小约为 342016 个 4096 字节块。
5. 先运行 `e2fsck -fn`，确认基础 rootfs 可读。
6. 以 loop 方式挂载 raw，绑定 `/dev`，挂载 proc 和 sysfs。
7. 临时保存 rootfs 的 `resolv.conf`，复制 runner DNS；不使用文件级 bind mount。
8. 复制 qemu、Deb 包和 build-only `systemctl` stub，进入 armhf chroot。
9. 在 chroot 中运行 `apt-get update`，再安装 One-KVM Deb 和依赖；删除 apt 列表、临时包、qemu 和 stub。
10. 恢复 `resolv.conf`，写入 OTG 文件和版本 metadata。
11. 严格卸载 proc、sys、dev 和 rootfs；卸载失败或 rootfs 仍是挂载点时停止。
12. `e2fsck -fy` 修复并检查 raw，转回 sparse，再做 raw→sparse→raw 的 `cmp`。
13. 对 sparse rootfs 计算 SHA-1，写成无换行的 `sha1sum <40hex>` VERIFY 文件。
14. 使用 AmlImg 按原 `commands.txt` 重打包，生成新的容器 CRC 和分区 VERIFY。
15. 删除中间 raw/package，保留输出和 manifest。

## VERIFY 和 sparse 的关键规则

- Amlogic `VERIFY` 的内容是 48 字节：`sha1sum ` 加 40 位十六进制摘要，不带换行。
- 摘要对象是 Amlogic 容器中的 sparse 文件字节，不是展开后的 ext4 raw。
- 普通 `img2simg` 可能产生过大的 RAW chunk；`raw-to-sparse.mjs` 把单个 RAW chunk 的总大小限制在约 2 MiB 以内，保留 WS1608/Amlogic 刷写兼容性。
- 稀疏转换必须保持总块数、非零块和文件系统逻辑大小；测试和构建都执行往返比较。

## 阶段五：独立验证

`scripts/verify-image.sh` 不信任构建目录中的中间结果，而是重新解包成品和基础包，然后检查：

- AmlImg 解包成功，间接验证 Amlogic v2 CRC。
- `commands.txt` 与 `config/commands.expected` 完全一致。
- 除 rootfs 和 rootfs VERIFY 外，所有分区文件与基础包逐字节相同。
- 每个 PARTITION 后的 VERIFY SHA-1 正确。
- rootfs sparse 与基础包不同。
- raw ext4 的 `e2fsck -fn` 通过。
- `one-kvm` 状态为 `install ok installed`、版本匹配、架构为 armhf。
- `libdrm2` 已安装，`/usr/bin/one-kvm` 是 32-bit ARM ELF。
- `libc6`、`libgcc-s1`、`libstdc++6`、ALSA 和 ELF NEEDED 运行库均存在，动态加载器为 armhf。
- One-KVM service symlink 指向精确目标，`ExecStart=/usr/bin/one-kvm`、`User=root`。
- OTG vendor unit、drop-in、`libcomposite` 和 helper 与仓库配置逐字节一致。
- 镜像 metadata 的 One-KVM 版本、build tag 和 UTC 构建时分秒匹配工作流。

## 阶段六：打包与 artifact 回读

构建输出目录先生成未压缩 `.burn.img`，再用 `xz -T0 -9e` 生成压缩包。`SHA256SUMS` 在输出目录内执行，因此只包含 basename。manifest 追加：

- 上游 One-KVM URL 和 digest。
- 固定基础 xz digest。
- 完整构建时间、build tag/stamp、run ID/attempt 和 builder commit。
- AmlImg 仓库与固定提交、成品 raw/xz 文件名和摘要。

`verify-artifacts.mjs` 要求输出目录恰好只有四个发布文件，严格解析两行 `SHA256SUMS`，流式计算 raw/xz 摘要，核对 manifest 全字段，并把 xz 解压到临时文件与 raw 逐字节比较。

通过后上传 Actions artifact，再使用 `actions/download-artifact` 下载到新的目录。下载副本再次执行 `verify-artifacts.mjs`，并对下载后的 `.burn.img` 完整执行 `verify-image.sh`。任一步失败时不会进入 Release 步骤。

## 阶段七：draft Release 与远端摘要

发布逻辑：

- 发布前再次确认 build tag 的 Release 和 Git ref 均不存在；存在即失败。
- 从已下载并验证的 Actions artifact 创建 draft Release，不使用原始输出目录。
- 查询 draft 的四个 asset digest/state，与本地文件逐项比较。
- 只有全部为 uploaded 且摘要完全一致时才执行 `--draft=false` 公开。
- 公开后再次核对 Release 状态和远端摘要。
- 公开前任一步失败会删除本次新建的 draft/tag；历史 Release 永不修改。
- Actions artifact 保留 14 天，便于失败后短期下载检查。

## 本地复现边界

本地纯格式测试：

```sh
npm test
for script in scripts/*.sh; do bash -n "$script"; done
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/build.yml
```

完整本地构建还必须设置与 discovery 输出一致的 `BUILD_STAMP`、`BUILD_TAG`、`IMAGE_NAME`，并在压缩后执行：

```sh
node scripts/verify-artifacts.mjs "$OUTPUT_DIR" "$IMAGE_NAME" "$EXPECTED_MANIFEST_JSON"
```

`verify-image.sh` 同样要求 `BUILD_TAG` 和 `BUILD_STAMP`，以防把未标识或身份错配的镜像当作成品。

完整镜像构建需要 Linux root、loop mount、qemu-user-static 和大量空间。macOS OrbStack 的特权 loop mount 在本次验证中两次导致 Docker daemon `unexpected EOF`，所以维护者应优先使用 GitHub Actions；不要为了本地复现删除或重置用户现有 Docker 数据。
