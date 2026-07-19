# WS1608 One-KVM builder

这个公开仓库自动把已在 OneCloud/WS1608 上验证过的 Armbian 基础镜像，封装为带 One-KVM Rust 的 Amlogic 直刷镜像。

## 自动更新规则

- 每周日 02:17 UTC（北京时间 10:17）查询 `mofeng-git/One-KVM` 的最新稳定 Release。
- 只有发现尚未发布的上游 tag 与 Deb SHA-256 组合才下载 `armhf.deb`、构建并发布新 Release。
- Release/tag 格式为 `ws1608-one-kvm-<one-kvm-rust-version>-<upstream-tag>-bRRRAAA`，例如 `ws1608-one-kvm-0.2.4-v260709-b014001`；`RRR` 是 Actions run number，`AAA` 是 run attempt，均至少保留三位。
- `workflow_dispatch` 可手动运行；`force=true` 创建独立构建，`publish=false` 只做云端构建和验证，不发布。
- Pull request 会执行完整构建，但不会获得发布权限。
- 预留 `repository_dispatch` 的 `one-kvm-release` 事件，但上游仓库目前不会向本仓库发送该事件，所以每周检查是实际触发方式。

当前已通过完整云端构建和发布检查的版本是 [`ws1608-one-kvm-0.2.4-v260709-b016001`](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.4-v260709-b016001)。完整发布见 [run 29703507602](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29703507602)，无更新跳过构建见 [run 29703930315](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29703930315)。构建证据和摘要见 [HANDOFF.md](docs/HANDOFF.md)；该成品仍需实体 WS1608 刷写验收，不能仅凭 CI 标记为硬件已通过。

## 基础镜像

稳定构建固定使用 `config/base.env` 指向的基础资产：Armbian 26.8 Trixie、`6.12.28-current-meson`、OneCloud HDMI-test 设备树和启动链。固定启动链是为了避免未经 WS1608 实机验证的内核或设备树更新进入稳定直刷包。更换基础镜像时，先更新 URL 和 SHA-256，再单独完成 WS1608 刷写验证。

## CI 验证

构建任务会重新解包成品并检查：Amlogic v2 CRC、12 个标准条目、非 rootfs 分区字节一致性、每个分区 VERIFY SHA1、`one-kvm` armhf 包和依赖、systemd 开机链接、OneCloud OTG 配置、ext4 文件系统一致性、构建来源 metadata 和临时文件清理。

GitHub 托管 runner 没有连接实体 WS1608，因此 CI 不把结构验证写成硬件启动结论。发布前会验证 xz 解压后与原始镜像摘要一致、manifest、`SHA256SUMS` 和 validation report。Release 提供未压缩 `.burn.img`、`.burn.img.xz`、`SHA256SUMS`、`manifest.json` 和 `validation-report.json`。

## 本地运行

推荐直接使用 GitHub Actions 云构建，不需要在本地保存解压后的大镜像。云 runner 会安装 root 权限所需的 `qemu-user-static`、Go、Node.js、`binutils` 和 `e2fsprogs`，完成构建与验证后只保留 Release 资产。

本地复现需要 Linux 主机、root 权限、`qemu-user-static`、Go、Node.js、`e2fsprogs` 和 Amlogic 基础镜像。准备 `BASE_IMAGE_XZ`、`ONE_KVM_DEB`、`AMLIMG_BIN`、`ONE_KVM_VERSION`、`UPSTREAM_TAG`、`PACKAGE_NAME`、`PACKAGE_DIGEST`、`PACKAGE_URL`、`BUILD_TAG`、`BUILD_NUMBER`、`BUILD_REVISION`、`BUILDER_COMMIT`、`GITHUB_RUN_ID`、`GITHUB_RUN_ATTEMPT`、`GITHUB_RUN_NUMBER`、`OUTPUT_DIR`、`WORK_DIR`、`IMAGE_NAME` 和 `VALIDATION_REPORT` 后执行：

```sh
./scripts/build-image.sh
./scripts/verify-image.sh
./scripts/package-release.sh
```

`BUILD_TAG`、`BUILD_REVISION` 和 `IMAGE_NAME` 必须使用 `discover-release` 输出的同一构建身份；脚本会拒绝不一致的名称。

纯格式测试不需要镜像或 root 权限：

```sh
npm test
```

## 文档与交接

- [维护文档索引](docs/README.md)：按构建、排障、实机验收等任务导航。
- [当前交接状态](docs/HANDOFF.md)：当前 Release、验证边界、已知问题和后续优先级。
- [镜像来源与选型](docs/image-lineage.md)：当前稳定基础、历史 Jammy 镜像和官方 One-KVM 镜像的关系。
- [构建与发布流程](docs/build-pipeline.md)：GitHub Actions 从发现上游版本到发布直刷包的完整过程。
- [排障手册](docs/troubleshooting.md)：Amlogic、sparse、挂载、e2fsck、OTG 和云构建已知坑。
- [WS1608 实机验收](docs/hardware-validation.md)：不能由 CI 替代的刷写、启动、视频和 HID 检查。

## 许可证

本仓库脚本使用 MIT 许可证。生成的镜像包含 Armbian、Debian、One-KVM Rust 和 Amlogic 工具的第三方组件，各组件继续适用其原许可证；来源链接见 `THIRD_PARTY.md`。
