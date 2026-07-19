# 排障手册与已知坑

## 快速判断

| 症状 | 常见原因 | 处理 |
| --- | --- | --- |
| build job skipped | 同一上游 tag 已有 Release | 这是正常行为；修复代码或资产被上游替换时用 `force=true` |
| discover 失败，找到 0 或多个 armhf 包 | 上游资产命名或发布策略改变 | 先查看上游 Release JSON，再修改选择规则；不要静默选第一个 |
| 基础包 SHA-256 不匹配 | URL 指向了被替换的资产、下载损坏或 `base.env` 未更新 | 比较 GitHub asset digest，创建新基础 tag，不覆盖旧 tag |
| Deb 架构不是 armhf | 误选 arm64/amd64 包 | 检查 `dpkg-deb -f`，保持 WS1608 的 armhf 约束 |
| `qemu-arm-static` 缺失 | runner 依赖未安装 | 检查 workflow 的 apt 安装步骤；不要把宿主 qemu 二进制提交到仓库 |
| apt update 失败 | Armbian/Debian 镜像短时不可用、网络或日期问题 | 重试并查看源；必要时为 apt 源增加稳定备用方案，不能跳过依赖校验 |
| `systemctl` 在 chroot 报 running in chroot | One-KVM postinst 尝试 start 服务 | 这是预期现象；构建脚本随后手工保证 enable link，不能在 chroot 启动真实服务 |
| e2fsck 报 journal recovery/orphan | rootfs 仍处于挂载状态就运行 e2fsck，或嵌套 mount 未卸载 | 先检查 `cleanup_mounts`；必须确认 `mountpoint "$MOUNT_DIR"` 为 false 后再 e2fsck |
| OTG 文件在挂载时存在、成品中消失 | 旧版递归 `/dev` bind 卸载失败，脚本忽略错误 | 使用当前非递归 bind、严格卸载逻辑；不要恢复 `umount -R` 后忽略返回值的实现 |
| OTG unit 找不到 | 检查了错误目录或基础文件没有持久化 | 当前 unit 在 `/usr/lib/systemd/system`，drop-in 在 `/etc/systemd/system/one-kvm.service.d/otg.conf` |
| rootfs VERIFY mismatch | 对 raw ext4 而不是 sparse 文件计算 SHA1，或 VERIFY 有换行 | 重新用 `sha1sum` 计算 sparse 文件，写入固定 48 字节格式 |
| Amlogic CRC/条目失败 | 手工改了容器布局、使用错误版本工具或截断文件 | 用固定 AmlImg commit，先 `unpack` 再独立 `verify-image.sh` |
| 刷写工具拒绝 sparse | RAW chunk 过大或总块数变化 | 使用仓库的 `raw-to-sparse.mjs`，不要替换成未验证的 `img2simg` |
| `SHA256SUMS` 含 `/home/runner/...` | 在输出目录外调用 sha256sum | 使用 `(cd "$OUTPUT_DIR" && sha256sum ...)`，当前 workflow 已修复 |
| force 构建在发布前 tag 冲突 | 两次构建取得同一个 UTC 时分秒，或 tag 被手工创建 | 这是防覆盖门槛；确认旧资产不动，重新触发取得新时分秒，不能使用 `--clobber` |
| `verify-artifacts` 报额外文件 | 输出目录残留 `.sha256` 或其他中间文件 | 发布目录必须恰好四个文件；修复构建脚本，不要放宽检查 |
| xz round-trip mismatch | 压缩资产截断、上传/下载损坏或文件被替换 | 重新计算 raw/xz 摘要并检查 Actions artifact；不得继续创建 Release |
| manifest field mismatch | 构建身份、输入摘要或 runner metadata 与 manifest 不一致 | 检查 `EXPECTED_MANIFEST_JSON` 的来源，不能以修改 manifest 掩盖输入差异 |
| draft asset digest mismatch | GitHub 返回摘要与本地文件不同或上传未完成 | 发布脚本会删除本次 draft/tag 并失败；检查网络/API 后创建新的时间戳构建 |
| GitHub Release 资产超过 2 GiB | 未压缩镜像或 rootfs 持续变大 | 保留 xz 资产并评估拆分/外部存储；不要静默省略直刷 `.img` |
| OrbStack Docker daemon `unexpected EOF` | macOS 特权 loop mount 在本次测试中不稳定 | 使用 GitHub Actions 云 runner 或原生 Linux；不要删除用户 Docker 卷来解决 |
| HDMI 有画面但没有音频 | 基础内核的 `gx-sound-card` 注册错误，已观测到 error -22 | 记录为已知基础镜像限制；One-KVM 的 USB 视频/HID 功能不以 HDMI 音频为前置条件 |
| `/dev/video0` 或 HID 不存在 | 测试机没有接 HDMI 采集卡/USB 控制线，或 OTG 角色未切到 device | 按硬件验收文档接线、检查 sysfs role、`libcomposite` 和采集卡驱动 |

## 挂载排障命令

这些命令只应在受控 Linux runner/临时工作目录执行，不能对正在使用的设备分区执行：

```sh
findmnt -R "$WORK_DIR/rootfs.mnt"
mountpoint "$WORK_DIR/rootfs.mnt"
ps -ef | grep -E 'chroot|qemu-arm|apt-get' | grep -v grep
```

如果 rootfs 仍挂载，先停止当前构建并卸载所有子挂载；不要直接对设备节点运行 `e2fsck -fy`。

## Amlogic 数据排查

先看容器条目，不要先改脚本：

```sh
"$AMLIMG_BIN" unpack image.burn.img verify-dir
cat verify-dir/commands.txt
sha1sum verify-dir/10.rootfs.PARTITION.sparse
cat verify-dir/11.rootfs.VERIFY
```

如果非 rootfs 分区有差异，优先检查是否误修改了 boot、bootloader、resource 或 `commands.txt` 顺序。若只有 rootfs 差异，继续检查 ext4 和包安装；不要通过删掉 VERIFY 项来绕过检查。

## Actions 排障顺序

1. 先看 `Check One-KVM release` 的输出，确认 `changed`、上游 tag、资产 URL 和 digest。
2. 再看 `Download and verify inputs`，确认基础包、Deb metadata 和 SHA-256。
3. `Build burn image` 失败时看 mount、chroot、apt 和 e2fsck；这时不应有 Release 资产。
4. `Verify burn image` 失败时看命名的 `verified:` 行，最后一行就是第一项失败的检查。
5. `Verify packaged artifact` 失败时检查四文件集合、两行 SHA256SUMS、manifest 和 xz 往返。
6. `Verify downloaded artifact` 或 `Re-verify downloaded burn image` 失败说明上传后的 artifact 不可发布。
7. draft 发布失败时检查远端 asset digest/state 和 cleanup 日志；公开 Release 不应存在。
8. 修复后提交到 `main`，再用 `force=true` 创建新的 tag，并保存新的 manifest/hash。

## 历史故障记录

首次镜像封装经历了多次云端验证失败；迁移前修复结果见 [29692576405](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29692576405)，当前不可变发布流程的最终证据以 [29697101081](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions/runs/29697101081) 为准：

- 初版验证没有打印具体断言，无法定位失败项。
- 包状态、ARM ELF 和主服务链接先后被证明正确；OTG 独立 wants link 并非必要依赖。
- 改成 vendor unit 后仍发现 unit 消失，随后 `e2fsck` 日志显示 journal recovery、orphan inode 和 free block/inode 计数错误。
- 根因是嵌套 bind mount 未严格卸载，脚本却继续对仍挂载的 raw 文件执行 e2fsck。
- 当前实现改为普通 `/dev` bind、DNS 文件复制/恢复、严格逐项卸载和 mountpoint 门禁；之后构建与独立验证通过。
- 新流程随后增加 Actions artifact 重新下载、完整镜像复验、draft Release 远端 digest 比较和不可变 tag；这些步骤均在 `29697101081` 通过。

这些修复不是可有可无的风格调整。修改 mount、chroot、e2fsck 或 sparse 转换时，必须保留同等级别的门禁和独立验证。
