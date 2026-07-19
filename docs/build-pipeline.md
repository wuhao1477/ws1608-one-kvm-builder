# 构建与发布流程

## 触发方式

工作流文件是 [.github/workflows/build.yml](../.github/workflows/build.yml)。

| 触发器 | 行为 |
| --- | --- |
| `schedule` | 每周日 `02:17 UTC` 检查一次，约北京时间周日 `10:17` |
| `pull_request` | 对构建相关文件执行完整云构建与验证，不发布 |
| `workflow_dispatch`，`force=false` | 与定时检查相同；已有相同上游 tag 和 Deb digest 时跳过 |
| `workflow_dispatch`，`force=true` | 为同一 One-KVM 输入创建下一个 `bNNN` 构建 |
| `workflow_dispatch`，`publish=false` | 上传短期 Actions artifact，但不创建 tag 或 Release |
| `repository_dispatch: one-kvm-release` | 预留接口；上游当前不会主动发送 |

工作流默认只有 `contents: read`。只有依赖完整构建成功的 `release` job
获得 `contents: write`；该 job 不会在 pull request 或 `publish=false` 时运行。

## 阶段一：发现上游输入

`scripts/discover-release.sh` 查询上游 latest Release 和本仓库全部 Release：

1. 只接受非 draft、非 prerelease 的上游 Release。
2. 必须且只能找到一个 `one-kvm_*_armhf.deb`。
3. GitHub API 必须提供有效的 SHA-256 digest；缺失或格式错误时检查失败。
4. 包文件名提供 One-KVM Rust Deb 版本，上游 Release 提供 tag。
5. 构建 tag 为 `ws1608-one-kvm-<deb-version>-<upstream-tag>-bNNN`。
6. 已有公开 Release 同时匹配上游 tag 和 package digest 时输出
   `changed=false`，后续 build job 不启动。
7. `force=true` 或 digest 变化时，序号在已有公开、draft 和 prerelease
   记录之后递增，防止失败遗留 draft 复用同一身份。

Release body 的 `one_kvm_release=` 和 `package_sha256=` 是更新判定的
机器可读标记。这里不使用可被并发覆盖的 state 文件。

## 阶段二：准备云 runner

构建 job 使用 `ubuntu-24.04`，安装 `e2fsprogs`、`qemu-user-static`、
`file` 和 `xz-utils`。Go `1.24.x` 只用于从固定提交构建 AmlImg。
`checkout`、`setup-go`、artifact upload/download 都固定到完整 commit SHA。

标准 runner 当前可以容纳约 1.19 GB 未压缩成品、约 339 MB xz 成品、
308 MB 基础 xz、rootfs raw 和验证副本。artifact 上传关闭二次压缩。

## 阶段三：校验不可变输入

基础包从 `base-20260719` Release 下载，URL、名称、平台字段和 xz
SHA-256 固定在 `config/base.env`。One-KVM Deb 必须同时满足：

```text
Package = one-kvm
Architecture = armhf
Version = discover-release 输出的版本
SHA-256 = GitHub Release asset digest
```

任何输入摘要或 Deb metadata 不匹配都会停止构建。

## 阶段四：构建 rootfs

`scripts/build-image.sh` 的顺序：

1. 解压并用固定 AmlImg 解包基础 Amlogic v2 容器。
2. 从 `commands.txt` 找到 rootfs sparse 和 VERIFY，不硬编码条目偏移。
3. 展开 sparse，先执行只读 `e2fsck`，再挂载 rootfs、`/dev`、proc、sysfs。
4. 保存 DNS 状态，通过 qemu armhf chroot 安装 Deb 和依赖。
5. 删除 Deb、qemu、systemctl stub 和 apt lists，恢复 DNS。
6. 安装 One-KVM service、WS1608 OTG unit/drop-in、helper 和 `libcomposite`。
7. 写入 Deb 版本、上游 tag、package digest、build tag/number 和 builder
   commit 到 `/etc/ws1608-one-kvm-release`。
8. 严格卸载所有挂载点；rootfs 仍挂载时禁止继续。
9. 执行修复性 `e2fsck`、raw/sparse 往返 `cmp`，更新 sparse SHA-1 VERIFY。
10. 重打包 Amlogic 容器，文件名包含 `version-tag-bNNN`，生成初始 manifest。

## 阶段五：独立镜像验证

`scripts/verify-image.sh` 只读取最终成品和基础包，重新解包并检查：

- AmlImg 解包及 Amlogic CRC；
- 12 行 `commands.txt` 和全部分区 VERIFY SHA-1；
- boot、bootloader、resource 等非 rootfs 条目逐字节不变；
- rootfs 已改变、sparse 可展开、ext4 `e2fsck -fn` 通过；
- `one-kvm` 为指定版本的 armhf 包，二进制为 32-bit ARM ELF；
- 主服务链接为精确目标，OTG 四个配置文件与仓库源文件逐字节一致；
- 镜像 metadata 的版本、tag、摘要、序号和 builder commit 完全匹配；
- Deb、qemu 和 build-only systemctl stub 不存在于成品。

全部检查完成后才写出 `validation-report.json`。报告明确记录
`hardware_boot_tested=false`，不能替代实体 WS1608 验收。

## 阶段六：发布资产验证

`scripts/package-release.sh` 生成 `.burn.img.xz`，然后 finalizer 写入：

- One-KVM URL、package SHA-256、版本和上游 tag；
- base SHA-256、build tag/number、builder commit 和 Actions run ID；
- raw、xz 和 validation report 的文件名、大小与 SHA-256；
- 构建时间和 `validation=passed`。

`scripts/verify-release-assets.sh` 执行 `xz -t`，流式解压并比较 raw
SHA-256，核对 `SHA256SUMS`，再由 Node 验证器检查 manifest、报告、文件
白名单和所有摘要。`SHA256SUMS` 只允许 basename，且包含 raw、xz、
manifest 和 validation report。

验证后的目录通过 Actions artifact 传给独立 `release` job。该 job 下载后
再次运行同一个资产验证器，先以 draft 上传五项资产：

1. `.burn.img`
2. `.burn.img.xz`
3. `SHA256SUMS`
4. `manifest.json`
5. `validation-report.json`

全部上传完成后才把 draft 公开并标记 latest。任何检查、上传或发布步骤
失败都会使 workflow 失败；旧 Release 不会被覆盖。

## 本地验证

不需要 root 或大镜像的检查：

```sh
npm test
for script in scripts/*.sh; do bash -n "$script"; done
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/build.yml
```

完整镜像构建需要 Linux root、loop mount、qemu-user-static 和足够磁盘。
macOS 上优先使用 pull request 或 `publish=false` 的 GitHub Actions 构建。
