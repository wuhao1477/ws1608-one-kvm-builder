# 构建与发布流程

## 稳定工作流

现有稳定流程定义在 [.cnb.yml](../.cnb.yml)。它负责 One-KVM rootfs 自动更新，
不负责 HCODEC 内核研发。

| 触发器 | 行为 |
| --- | --- |
| `crontab` | 每周日 02:17 UTC 检查上游 |
| `pull_request` | 完整构建与验证，不发布 |
| `api_trigger_one-kvm-release` | 发布稳定 Release |
| `web_trigger_stable force=false` | 相同输入已发布时跳过 |
| `web_trigger_stable force=true` | 为同一输入创建新 `bRRRAAA` 构建 |
| `web_trigger_stable publish=false` | 上传 14 天 commit asset，不创建 Release |

稳定 Release 使用 CNB 仓库 token；候选构建只上传当前提交附件。

### 1. 发现输入

`scripts/cnb-discover-release.sh` 只接受上游非 draft、非 prerelease Release
中唯一的 `one-kvm_*_armhf.deb`。上游 GitHub API 必须提供 SHA-256 digest；
当前 CNB 仓库的 Release 和 tag 通过 CNB API 查询。只有公开 Release 的 tag、
Deb digest、五项资产、上传状态及 body 摘要全部一致，才输出 `changed=false`。

### 2. 固定输入

基础来自 `config/base.env`：

```text
BASE_RELEASE_TAG=base-20260804-consolefix
BASE_KERNEL=6.12.28-current-meson
```

工作流验证基础 xz SHA-256、One-KVM 包名、版本、`armhf` 架构和 Deb 摘要。
AmlImg 从 `config/tool-versions.env` 的固定提交构建。

### 3. 修改 rootfs

`scripts/build-image.sh` 解包 Amlogic v2，展开 rootfs sparse，在隔离的
mount/PID namespace 和 qemu armhf chroot 中安装 One-KVM。随后安装
systemd、OTG、`libcomposite` 和来源 metadata，严格卸载文件系统，执行
`e2fsck`、raw/sparse 往返和 VERIFY 更新。

稳定工作流不改变 boot、内核、DTB、U-Boot 或 resource。

### 4. 独立镜像验证

`scripts/verify-image.sh` 重新解包成品并检查：

- Amlogic CRC、12 个条目和所有 VERIFY；
- boot console 参数；
- 非 rootfs 分区逐字节不变；
- ext4 一致性；
- One-KVM ARM ELF、动态加载器、依赖、systemd 和 OTG；
- 版本、tag、Deb/base 摘要和 builder commit；
- 构建临时文件已移除。

验证报告保持 `hardware_boot_tested=false`，表示该次成品未由 CI 实体刷写。

### 5. 五资产发布

构建生成：

1. `.burn.img`
2. `.burn.img.xz`
3. `SHA256SUMS`
4. `manifest.json`
5. `validation-report.json`

稳定构建通过 CNB commit asset 上传后立即下载复验；发布路径创建指向 builder
commit 的 tag 和 draft Release。五项资产全部上传并核对远端 digest 后才公开。

## HCODEC 候选流程

HCODEC 候选流程由 `.cnb.yml` 实现。它只允许 `codex/hcodec-*` 分支 push、
Pull Request 和 Web Trigger，不加入 schedule，也不得调用稳定发布 job。新分支应先取得云构建 artifact 并完成实体刷写验证，
之后才创建 PR。实施顺序固定为：

1. 固定与 Armbian 6.12.28 基础匹配的 ARMv7 内核源码和 `.config`；
2. 固定一致的 `meson-venc` 源码、补丁摘要和固件提取输入；
3. 构建内核、模块、DTB、`meson8b_h264.bin` 和 ARMv7 测试工具；
4. 验证补丁应用、DT schema、ELF 架构、vermagic、符号、固件摘要；
5. 生成不自动发布的候选 artifact；
6. 实体板先完成独立 V4L2 M2M 码流测试；
7. 独立探针通过后，以 `ONE_KVM_V4L2M2M_ALLOW=1` 临时验证 One-KVM；
8. 综合验收通过后再创建 prerelease。

AMLENC 候选流程也由 `.cnb.yml` 的 `codex/amlenc-*` PR 和 Web Trigger 实现；
它仍保持 Linux 3.10 实验链与稳定通道隔离，不得调用稳定发布流程。

## 本地仓库检查

```sh
pnpm test
for script in scripts/*.sh; do bash -n "$script"; done
node /Users/wuhao/.codex/skills/cnb-pipeline/validator/validate.js .cnb.yml
node /Users/wuhao/.codex/skills/cnb-pipeline/validator/validate.js .cnb/web_trigger.yml
```

完整镜像或内核构建需要 Linux runner、root 权限和足够磁盘；macOS 只运行
不需要挂载、chroot 或目标交叉编译器的检查。
