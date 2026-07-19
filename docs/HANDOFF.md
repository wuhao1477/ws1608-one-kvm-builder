# WS1608 One-KVM 构建器交接

更新时间：2026-07-20

## 当前结论

公开仓库已经建立并可独立运行：

- 仓库：[wuhao1477/ws1608-one-kvm-builder](https://github.com/wuhao1477/ws1608-one-kvm-builder)
- 当前 Release：[ws1608-one-kvm-0.2.4-v260709-173450](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.4-v260709-173450)
- 完整构建与发布：[Actions run 29697101081](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697101081)，结论 `success`
- 新格式识别与跳过：[Actions run 29697714162](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697714162)，识别当前 Release 后完整构建 job 为 skipped
- 迁移前 Release：[ws1608-one-kvm-v260709](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-v260709)
- 上游版本：One-KVM `0.2.4`，tag `v260709`
- 基础：Armbian 26.8 Trixie，`6.12.28-current-meson`，OneCloud/WS1608 HDMI-test
- 触发：每周日 02:17 UTC；无新上游 tag 时只检查、不构建

完整运行从提交 `32eb3c38e4f284e8dfe5de047dc56a236c970461` 构建。输出目录和重新下载的 Actions artifact 均通过资产与镜像检查，draft Release 的四个远端 digest 全部匹配后才公开。当前 Release 为非 draft、非 prerelease，四个资产均为 uploaded；查询全部 Releases 未发现残留 draft。

## 当前发布数据

| 资产 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `One-KVM_0.2.4_v260709_173450_Onecloud_trixie_6.12.28_HDMI-test.burn.img` | 1,188,645,868 | `ca311861c7f2a55a5f7b2cacc8f8e092ee6b2a08af755797ac287b78b3fc3c4a` |
| `One-KVM_0.2.4_v260709_173450_Onecloud_trixie_6.12.28_HDMI-test.burn.img.xz` | 339,180,856 | `9184adedd6781dad93f18879a18be6284b6d63feafb55b77f8ea591836321358` |
| `manifest.json` | 1,393 | `cd2e11de5219a7a8910e9cd70513d0bd121cbdc3eb6c0392e5471f49485b48ce` |
| `SHA256SUMS` | 279 | `e9437befe11595f560a13e37962e8492ff0d69225d4a034695d32381690ba707` |

manifest 的关键输入数据：

| 项目 | 值 |
| --- | --- |
| 构建时间 | `2026-07-19T17:35:01Z` |
| GitHub run / attempt | `29697101081` / `1` |
| One-KVM Deb | `one-kvm_0.2.4_armhf.deb` |
| One-KVM Deb SHA-256 | `52f9035f4949bc9a63d2c763eaced21dce7c99d8f547e1465691674f9bd0b82a` |
| 基础镜像 xz SHA-256 | `f0bde03edd12022db41a53c546b1b16b7e49ddecbd39121f3e8c0086f700de82` |
| AmlImg commit | `311cd4b892023bcb3cf6661698f5ab685e34a7f8` |

2026-07-20 的独立复核只下载了小型 `manifest.json` 和 `SHA256SUMS`，并把其摘要、manifest 中的 raw/xz 摘要、上游 Deb digest、基础资产 digest 与 GitHub API 逐项比较，结果全部匹配。由于维护者本地空间有限，没有再次下载两个大镜像；完整大文件的上传后重新下载、xz 字节往返和镜像复验已在 run `29697101081` 的云 runner 完成。

## 已实现的范围

仓库现在可以在 GitHub hosted Ubuntu runner 中完成：

1. 查询上游最新稳定 One-KVM Release。
2. 严格选择唯一 armhf Deb 并验证 digest、版本和架构。
3. 下载固定基础 burn 包并验证 SHA-256。
4. 解包 Amlogic v2，展开 rootfs，使用 qemu 在 armhf chroot 中安装包。
5. 安装 One-KVM 开机服务、WS1608 OTG unit/drop-in、`libcomposite` 和版本 metadata。
6. 严格卸载 rootfs 后运行 e2fsck，重建 sparse 并验证往返一致性。
7. 更新 sparse rootfs 的 Amlogic VERIFY SHA-1，重打包容器。
8. 独立解包成品，比较非 rootfs 分区、检查所有 VERIFY、Deb/systemd/OTG/ext4。
9. 在输出目录和重新下载的 Actions artifact 上验证 `.burn.img`、`.burn.img.xz`、`SHA256SUMS` 和 `manifest.json`。
10. 创建 draft Release，比较四个远端 asset digest，成功后才公开不可变 Release/tag。

具体实现不要从本文件复制，直接以 [build-pipeline.md](build-pipeline.md)、[scripts/build-image.sh](../scripts/build-image.sh) 和 [scripts/verify-image.sh](../scripts/verify-image.sh) 为准。

## 最重要的边界

- 稳定通道只自动更新 One-KVM，不自动滚动 Armbian、内核、DTB 或 U-Boot。
- CI 结构、rootfs、artifact 和远端摘要验证通过不等于实体 WS1608 已启动；每个新 Release 仍需要一次实机刷写验收。
- 之前已验证基础镜像能启动、HDMI 显示、联网、使用 eMMC 并承受短时负载；已运行系统中的 One-KVM `0.2.4` health/service 也曾通过。
- HDMI 音频存在已知 `gx-sound-card` error -22；USB 视频/HID、实际采集卡和被控机 HID 仍需现场验证。
- 设备 IP、SSH 密码、token、私钥和物理测试机信息不在公开仓库中。

## 接手后的第一步

1. 阅读 [docs/README.md](README.md)、[build-pipeline.md](build-pipeline.md) 和 [troubleshooting.md](troubleshooting.md)。
2. 阅读 [image-lineage.md](image-lineage.md)，不要把历史 Jammy 或官方 Bookworm 参考包误当成当前稳定基础。
3. 打开 [Actions](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions)，确认最近一次完整运行和 skipped 运行的每个验证步骤。
4. 实机刷写前下载当前 Release 的 xz 镜像并核对 `SHA256SUMS`；需要审计全部四个资产时，在有足够空间的 Linux runner 上使用 `verify-artifacts.mjs`。
5. 同一上游版本需要重建时使用 `force=true`；它会生成新的 UTC 时分秒 tag，不会修改旧 Release。
6. 如要改基础镜像，先阅读 [hardware-validation.md](hardware-validation.md)，完成实体刷写后再改 `config/base.env`。

## 已知维护风险

### 1. 不能忽略卸载错误

此前使用递归 `/dev` bind mount 并忽略 `umount` 返回值，导致 e2fsck 在仍挂载的 raw 文件上运行。日志出现 journal recovery、orphan inode 和 free block/inode 错误，OTG 文件在成品中消失。当前代码使用普通 `/dev` bind、复制/恢复 DNS、严格卸载和 mountpoint 门禁。修改这些代码时必须保留门禁。

### 2. force 重建不是字节级复现

rootfs 安装使用动态 apt 源，ext4 时间戳和构建时间也会变化。同一上游 tag force 重建可能得到不同 SHA-256；这是当前设计已知限制，不要把旧 hash 硬编码成测试期望。

### 3. 上游同 tag 替换资产或 tag 碰撞

当前 discover 以完整公开 Release 的资产集合作为状态，并兼容旧 tag；两种格式同时存在时优先报告新格式。上游重写同一个 tag 时普通周检不会重建；使用 force，并检查新 manifest 的 package digest。UTC 时分秒重复会在发布前直接失败，不能通过覆盖旧 tag 解决。

### 4. GitHub 资产大小

当前未压缩镜像约 1.19 GB，低于 GitHub Release 单文件限制；rootfs 增长后要重新评估。不能为了绕过限制而删除直刷 `.img`，因为用户需要直接刷写包。

## 后续优先级

1. 用 `ws1608-one-kvm-0.2.4-v260709-173450` 在实体 WS1608 完成一次完整刷写、断电重启和 One-KVM/OTG/视频/HID 验收。
2. 将不含敏感信息的硬件结论记录到私有测试记录；公开仓库只记录结论和 Release tag。
3. 若需要最新内核，建立 candidate 基础镜像流程，先通过硬件验收再提升稳定基础。
4. 若需要严格可复现，固定 Debian snapshot、依赖版本、时间戳，并继续保留 manifest 的 builder commit。

## 建议的后续技能

- GitHub Actions 失败：`github:gh-fix-ci`。
- 复杂构建/挂载问题：`systematic-debugging`。
- 交付前证据检查：`verification-before-completion`。
- 实体板卡和接口验收：`hardware-solution`，但不要跳过 [hardware-validation.md](hardware-validation.md) 的现场步骤。
- 再次交接：`handoff`，输出必须脱敏。
