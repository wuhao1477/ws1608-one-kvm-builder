# 构建与发布流程

## 触发方式

工作流文件是 [.github/workflows/build.yml](../.github/workflows/build.yml)。

| 触发器 | 行为 |
| --- | --- |
| `schedule` | 每周日 `02:17 UTC` 检查一次，约北京时间周日 `10:17` |
| `workflow_dispatch`，`force=false` | 与定时检查相同；已有相同构建 tag 时跳过 |
| `workflow_dispatch`，`force=true` | 忽略已有 tag，重新构建并覆盖同名 Release 资产 |
| `repository_dispatch: one-kvm-release` | 预留接口；上游 One-KVM 当前不会主动发送，因此不能依赖它及时触发 |

工作流的 `contents: write` 权限只用于发布 Release。当前没有 `pull_request` 构建路径，不要在未来引入未审查的 PR 代码并保留同样的写权限。

## 阶段一：发现上游版本

`scripts/discover-release.sh` 使用 `gh api repos/mofeng-git/One-KVM/releases/latest`：

1. 只接受非 draft、非 prerelease 的最新 Release。
2. 必须找到且只能找到一个名称以 `one-kvm_` 开头、以 `_armhf.deb` 结尾的资产。
3. 从文件名取得包版本，从 GitHub API 取得下载 URL 和 digest。
4. 把上游 tag 清理成 `ws1608-one-kvm-<tag>` 作为本仓库构建 tag。
5. 查询本仓库是否已经存在该 tag。存在则输出 `changed=false`，构建 job 条件为 false。
6. API 没有提供 digest 时，下载步骤会自行计算并写入后续 manifest。

这里没有单独的 state 文件，Release tag 就是“已构建版本”的事实来源。上游若在同一个 tag 下替换资产，普通周检不会发现，需人工使用 `force=true`，或将发现逻辑改为同时比较 asset digest。

## 阶段二：准备云 runner

构建 job 使用 `ubuntu-24.04`，安装：

- `e2fsprogs`：`e2fsck`、文件系统检查。
- `qemu-user-static`：在 x86/arm64 runner 中执行 armhf rootfs 的命令。
- `file`、`jq`、`xz-utils`。
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
- One-KVM 开机链接、OTG vendor unit、drop-in、`libcomposite`、OTG helper 和 metadata 存在且内容正确。

## 阶段六：打包和发布

构建输出目录先生成未压缩 `.burn.img`，再用 `xz -T0 -9e` 生成压缩包。`SHA256SUMS` 在输出目录内执行，因此只包含 basename。manifest 追加：

- 上游 One-KVM URL 和 digest。
- 固定基础 xz digest。
- 构建时间。

发布逻辑：

- 不存在构建 tag：`gh release create`。
- 已存在构建 tag（只有 `force=true` 才会进入）：`gh release upload --clobber` 后 `gh release edit`。
- Release 同时上传 `.burn.img`、`.burn.img.xz`、`SHA256SUMS`、`manifest.json`。
- Actions artifact 保留 14 天，便于失败后短期下载检查。

## 本地复现边界

本地纯格式测试：

```sh
npm test
for script in scripts/*.sh; do bash -n "$script"; done
```

完整镜像构建需要 Linux root、loop mount、qemu-user-static 和大量空间。macOS OrbStack 的特权 loop mount 在本次验证中两次导致 Docker daemon `unexpected EOF`，所以维护者应优先使用 GitHub Actions；不要为了本地复现删除或重置用户现有 Docker 数据。
