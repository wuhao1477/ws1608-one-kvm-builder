# 构建与发布流程

## 触发方式

工作流文件是 [.github/workflows/build.yml](../.github/workflows/build.yml)。

| 触发器 | 行为 |
| --- | --- |
| `schedule` | 每周日 `02:17 UTC` 检查一次，约北京时间周日 `10:17` |
| `pull_request` | 对构建相关文件执行完整云构建与验证，不发布 |
| `workflow_dispatch`，`force=false` | 与定时检查相同；已有相同上游 tag 和 Deb digest 时跳过 |
| `workflow_dispatch`，`force=true` | 为同一 One-KVM 输入创建独立 `bRRRAAA` 构建 |
| `workflow_dispatch`，`publish=false` | 上传短期 Actions artifact，但不创建 tag 或 Release |
| `repository_dispatch: one-kvm-release` | 预留接口；上游当前不会主动发送 |

工作流默认只有 `contents: read`。只有依赖完整构建成功的 `release` job
获得 `contents: write`；该 job 不会在 pull request 或 `publish=false` 时运行。
每个强制 dispatch 使用包含 run ID 的独立 concurrency group；普通周检共享串行组。

## 阶段一：发现上游输入

`scripts/discover-release.sh` 查询上游 latest Release，以及本仓库全部 Release 和 tag ref：

1. 只接受非 draft、非 prerelease 的上游 Release。
2. 必须且只能找到一个 `one-kvm_*_armhf.deb`。
3. GitHub API 必须提供有效的 SHA-256 digest；缺失或格式错误时检查失败。
4. 包文件名提供 One-KVM Rust Deb 版本，上游 Release 提供 tag。
5. 构建 tag 为 `ws1608-one-kvm-<deb-version>-<upstream-tag>-bRRRAAA`；后缀由 workflow run number 和 attempt 组成。
6. 只有公开 Release 同时匹配上游 tag、package digest、五个资产名称、上传状态和 Release body 中的资产摘要时才输出 `changed=false`，后续 build job 不启动。
7. `force=true` 或 digest 变化时使用当前 workflow 的唯一构建号；已有 tag ref
   会阻止复用失败 draft 或其他运行已经占用的身份。

Release body 的输入身份、五个资产名称和摘要是更新判定的机器可读标记。这里不使用可被并发覆盖的 state 文件。

## 阶段二：准备云 runner

构建 job 使用 `ubuntu-24.04`，安装 `binutils`、`e2fsprogs`、`qemu-user-static`、`util-linux`、`file` 和 `xz-utils`。Go `1.24.x` 只用于从固定提交构建 AmlImg。
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
3. 在任何覆盖操作前拒绝残留挂载，展开 sparse，先执行只读 `e2fsck`，再挂载 rootfs 和临时 `/dev`。
4. 保存 DNS 状态，在隔离的 mount/PID namespace 中挂载 proc，通过 qemu armhf chroot 安装 Deb 和依赖；不向 chroot 暴露宿主 `/dev` 或 sysfs。
5. 删除 Deb、qemu、systemctl stub 和 apt lists，恢复 DNS。
6. 安装 One-KVM service、WS1608 OTG unit/drop-in、helper 和 `libcomposite`。
7. 写入 Deb 版本、上游 tag、package digest、build tag/number 和 builder
   commit 到 `/etc/ws1608-one-kvm-release`。
8. 严格卸载所有挂载点；rootfs 仍挂载时禁止继续。
9. 执行修复性 `e2fsck`、raw/sparse 往返 `cmp`，更新 sparse SHA-1 VERIFY。
10. 重打包 Amlogic 容器，文件名包含 `version-tag-bRRRAAA`，生成初始 manifest。

## 阶段五：独立镜像验证

`scripts/verify-image.sh` 只读取最终成品和基础包，重新解包并检查：

- AmlImg 解包及 Amlogic CRC；
- 12 行 `commands.txt` 和全部分区 VERIFY SHA-1；
- boot、bootloader、resource 等非 rootfs 条目逐字节不变；
- rootfs 已改变、sparse 可展开、ext4 `e2fsck -fn` 通过；
- `one-kvm` 为指定版本的 armhf 包，二进制为 32-bit ARM ELF，动态加载器和全部运行库存在；
- 主服务链接、`ExecStart` 和 `User=root` 精确匹配，OTG 四个配置文件与仓库源文件逐字节一致；
- 镜像 metadata 的版本、tag、摘要、序号和 builder commit 完全匹配；
- Deb、qemu 和 build-only systemctl stub 不存在于成品。

全部检查完成后才写出 `validation-report.json`。报告明确记录
`hardware_boot_tested=false`，不能替代实体 WS1608 验收。

## 阶段六：发布资产验证

`scripts/package-release.sh` 生成 `.burn.img.xz`，然后 finalizer 写入：

- One-KVM 包名、URL、package SHA-256、版本和上游 tag；
- base tag、文件名、URL、SHA-256，build tag/revision/number、builder commit、Actions run ID/number/attempt 和固定 AmlImg commit；
- raw、xz 和 validation report 的文件名、大小与 SHA-256；
- 构建时间和 `validation=passed`。

`scripts/verify-release-assets.sh` 先由 Node 验证器检查 basename、符号链接、
manifest、报告、文件白名单和所有摘要，再执行 `xz -t`、流式解压比较和
`sha256sum --check`。`SHA256SUMS` 只允许 basename，且包含 raw、xz、
manifest 和 validation report。

build job 上传 Actions artifact 后会立即下载副本，重复资产校验和完整镜像校验。独立 `release` job 再次下载并验证资产，原子创建指向 builder commit 的 tag 并核对 SHA，然后创建 draft Release 并上传五项资产：

1. `.burn.img`
2. `.burn.img.xz`
3. `SHA256SUMS`
4. `manifest.json`
5. `validation-report.json`

全部上传完成后才把 draft 公开；Latest 由 GitHub 按发布记录自动选择，
避免并发强制构建互相回退指针。任何检查、上传或发布步骤失败都会使
workflow 失败；旧 Release 不会被覆盖。

## 本地验证

不需要 root 或大镜像的检查：

```sh
npm test
for script in scripts/*.sh; do bash -n "$script"; done
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/build.yml
```

完整镜像构建需要 Linux root、loop mount、qemu-user-static 和足够磁盘。
macOS 上优先使用 pull request 或 `publish=false` 的 GitHub Actions 构建。
