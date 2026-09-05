# HCODEC Artifact

候选工作流上传一个 `ws1608-hcodec-armv7-run-<run>-<attempt>.tar.xz`，并同时
上传顶层 `manifest.json` 与 `SHA256SUMS`。artifact 保留 14 天，不创建 tag 或
Release。

归档内容固定为：

- `kernel/`：zImage、uImage、OneCloud DTB、模块包、配置、符号表、源码摘要、签名报告；
- `tools/`：两个 ARMv7 V4L2 工具、工具摘要和固件来源摘要；
- 根目录 manifest 与归档内部 `SHA256SUMS`。

`verify-artifact.sh` 会检查摘要、tar.xz 解包、文件白名单、符号链接、固件二进制、
内核版本和硬件状态字段。artifact 明确包含由固定源码生成的
`firmware/meson8b_h264.bin` 与 `firmware-manifest.json`，其输出为 9536 字节，
SHA-256 为 `2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368`。
该 artifact 仍是静态构建候选，不代表实体 WS1608 已完成编码。

run `33854312358` 的 artifact `ws1608-hcodec-armv7-run-13-1.tar.xz` 已通过本地
和 GitHub Actions 的完整摘要复验，并在 WS1608 完成安装与启动验证。唯一一次
640×480、MMAP、1 帧 probe 超时，随后设备网络失联；输出未形成有效 Annex-B
码流，因此 `hardware_encoder_tested` 仍为 `false`，不得创建 PR。

run `33874935950` 的 artifact `ws1608-hcodec-armv7-run-15-1.tar.xz` 已通过本地
和 GitHub Actions 的完整摘要复验，并在 WS1608 完成安装与启动验证。该候选补齐
Meson8b Assist `INT1=0x19`，但唯一一次 640×480、MMAP、1 帧 probe 超过 120 秒
未完成，输出为 0 字节，随后设备网络失联；重启后 `pstore` 为空，
`hardware_encoder_tested` 仍为 `false`，不得创建 PR。

run `33893613040` 的 artifact `ws1608-hcodec-armv7-run-16-1.tar.xz` 已通过本地
和 GitHub Actions 的完整摘要复验，并在 WS1608 完成安装、重启和启动检查。唯一
一次 640×480、MMAP、1 帧 probe 的内核日志确认 `SEQUENCE`、`PICTURE`、`IDR`
完成，生成 6547 字节 Annex-B H.264；`ffprobe` 读到 1 帧 640×480，`ffmpeg`
解码成功，输出 SHA-256 为
`af392c6132fb1b349c62a0609164a5d92fb5dbda0805709614e00dfa636f407a`。工具随后
在 `STREAMOFF` 清理阶段阻塞并使 SSH 超时，重启后 `pstore` 为空。因此编码数据
路径已获得实机证据，但探针未完整退出，`hardware_encoder_tested` 仍为 `false`，
不得创建 PR。

`run-12-1` 已证明候选内核可启动并注册 HCODEC V4L2 设备，并把最小 probe 失败点
定位到 `IDR` 命令：`queue_setup`、`buf_prepare`、`buf_queue`、
`start_streaming`、workspace、硬件准备、`SEQUENCE` 和 `PICTURE` 均已通过；
IDR 输出 7 字节后超时并返回 `-110`。新候选改用 Hardkernel Meson8b dblk 微码，
640×480（640x480）实机通过前不得创建 PR。

安装候选内核时必须使用 `experimental/hcodec/scripts/install-artifact.sh`。
该脚本先将模块包解到临时目录，再只复制
`lib/modules/<kernel_release>`；禁止直接用 `tar -xJf ... -C /`，因为归档
顶层包含 `lib/`，会覆盖 Armbian 的 `/lib -> /usr/lib` 符号链接并导致
动态程序无法启动。安装前要求根分区至少保留 4 GiB 可用空间。

模块包同时包含构建时生成的 `modules.order`、`modules.dep`、`modules.dep.bin`、
`modules.alias` 和 `modules.alias.bin`。安装脚本会先验证 `zram.ko` 到
`zsmalloc.ko`/842 模块的依赖记录，再原样复制索引；不要在设备上再次运行无参数
`depmod`，因为该设备环境会把这组 ARM 模块的依赖重算为空，导致
`armbian-zram-config.service` 报 `Unknown symbol`。

run `33967514846` 的 `run-24-1` 已在 WS1608 修复上述 zram 启动故障。相同最小
probe 返回 `0`，写出 6547 字节、SHA-256 为
`af392c6132fb1b349c62a0609164a5d92fb5dbda0805709614e00dfa636f407a` 的有效 H.264，
但设备在工具退出后失联，仍不得创建 PR。

artifact 根目录的 `capture-probe.sh` 会把 probe 命令、标准输出/错误、退出码和
`kernel.before.log`、`kernel.live.log`、`kernel.after.log` 保存到指定的根文件系统
目录。它只用于每个候选的一次最小 probe：

```sh
./capture-probe.sh results ./tools/meson-venc-smoke \
  /dev/video0 results/stream.h264 640 480 1
```

run `33973657980` 的 `run-25-1` 证明该包装器能在设备失联前保存完整结束边界：
码流 6547 字节、退出码 `0`、两个 `STREAMOFF` 和 `power_off end` 均已完成。
该证据将下一候选限定为 Meson8b `full_power_reset` 试验，仍不得创建 PR。
