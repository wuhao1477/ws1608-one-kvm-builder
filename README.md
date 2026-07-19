# WS1608 One-KVM builder

这个公开仓库自动把已在 OneCloud/WS1608 上验证过的 Armbian 基础镜像，封装为带 One-KVM Rust 的 Amlogic 直刷镜像。

## 自动更新规则

- 每周日 02:17 UTC（北京时间 10:17）查询 `mofeng-git/One-KVM` 的最新稳定 Release。
- 只有发现尚未构建的上游版本才下载 `armhf.deb`、构建并发布新 Release。
- `workflow_dispatch` 可手动运行；勾选 `force` 会为同一上游版本创建新的不可变 Release，不覆盖历史资产。
- 新 tag 格式为 `ws1608-one-kvm-<Deb版本>-<上游tag>-<UTC时分秒>`，例如 `ws1608-one-kvm-0.2.4-v260709-143015`。
- 预留 `repository_dispatch` 的 `one-kvm-release` 事件，但上游仓库目前不会向本仓库发送该事件，所以每周检查是实际触发方式。

当前已通过完整云端构建和发布检查的版本是 [`ws1608-one-kvm-0.2.4-v260709-173450`](https://github.com/wuhao1477/ws1608-one-kvm-builder/releases/tag/ws1608-one-kvm-0.2.4-v260709-173450)。构建证据和摘要见 [HANDOFF.md](docs/HANDOFF.md)；该成品仍需实体 WS1608 刷写验收，不能仅凭 CI 标记为硬件已通过。

## 基础镜像

稳定构建固定使用 `config/base.env` 指向的基础资产：Armbian 26.8 Trixie、`6.12.28-current-meson`、OneCloud HDMI-test 设备树和启动链。固定启动链是为了避免未经 WS1608 实机验证的内核或设备树更新进入稳定直刷包。更换基础镜像时，先更新 URL 和 SHA-256，再单独完成 WS1608 刷写验证。

## CI 验证

构建任务会重新解包成品并检查：输入摘要、Amlogic v2 CRC、12 个标准条目、非 rootfs 分区字节一致性、每个分区 VERIFY SHA1、`one-kvm` armhf 包与运行库、ARM 动态加载器、systemd 开机链接和 ExecStart、OneCloud OTG 配置、ext4 文件系统一致性。

压缩后还会验证 `SHA256SUMS`、manifest 全字段和 xz 解压字节往返；Actions artifact 上传后会下载到新目录再次执行资产与镜像验证。最终先上传 draft Release，GitHub 返回的四个 asset digest 与本地 SHA-256 全部一致后才公开。任一步非零都会使 build job 失败，不会公开该构建。

GitHub 托管 runner 没有连接实体 WS1608，因此 CI 不把结构验证写成硬件启动结论。Release 中同时提供未压缩 `.burn.img` 和 `.burn.img.xz`，以及 `SHA256SUMS`。

## 本地运行

推荐直接使用 GitHub Actions 云构建，不需要在本地保存解压后的大镜像。云 runner 会安装 root 权限所需的 `qemu-user-static`、Go、Node.js、`binutils` 和 `e2fsprogs`，完成构建与验证后只保留 Release 资产。

本地复现需要 Linux 主机、root 权限、`qemu-user-static`、Go、Node.js、`binutils`、`e2fsprogs` 和 Amlogic 基础镜像。先准备 `BASE_IMAGE_XZ`、`ONE_KVM_DEB`、`ONE_KVM_VERSION`、`UPSTREAM_TAG`、`BUILD_STAMP`、`BUILD_TAG`、`IMAGE_NAME` 和 `AMLIMG_BIN` 环境变量，再执行：

```sh
./scripts/build-image.sh
./scripts/verify-image.sh
node ./scripts/verify-artifacts.mjs "$OUTPUT_DIR" "$IMAGE_NAME" "$EXPECTED_MANIFEST_JSON"
```

`BUILD_TAG` 和 `IMAGE_NAME` 必须由 `scripts/lib/release-identity.mjs` 生成，不能手工拼接不一致的名称。

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
