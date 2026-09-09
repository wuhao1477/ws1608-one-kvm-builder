# HCODEC Artifact

候选工作流上传一个 `ws1608-hcodec-armv7-run-<run>-<attempt>.tar.xz`，并同时
上传顶层 `manifest.json` 与 `SHA256SUMS`。artifact 保留 14 天，不创建 tag 或
Release。

归档内容固定为：

- `kernel/`：zImage、uImage、OneCloud DTB、模块包、配置、符号表、源码摘要、签名报告；
- `tools/`：两个 ARMv7 V4L2 工具、工具摘要和固件来源摘要；
- 根目录 probe 脚本、manifest 与归档内部 `SHA256SUMS`。

`verify-artifact.sh` 会检查摘要、tar.xz 解包、文件白名单、符号链接、固件二进制、
内核版本和硬件状态字段。artifact 明确包含由固定源码生成的
`firmware/meson8b_h264.bin` 与 `firmware-manifest.json`，其输出为 9536 字节，
SHA-256 为 `2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368`。
该 artifact 仍是静态构建候选，不代表实体 WS1608 已完成编码。

历史 run `33854312358` 的 artifact `ws1608-hcodec-armv7-run-13-1.tar.xz` 已通过本地
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

run `33987050987` 的 `run-29-1` 已完成 640×480 MMAP 30 帧实机编码，生成 1 个 IDR、
29 个 P 帧和 6866 字节码流；独立 `ffprobe`/`ffmpeg` 验证通过，摘要为
`7d50f102b6405fcc637467a61a8c5ef62ef0c90f2af88136a2f9f9ae97f6413f`。编码结束和
`power_off end` 正常，但设备随后失联，`hardware_encoder_tested` 仍为 `false`。

下一候选新增 `capture-stability-probe.sh`。该脚本先调用 `capture-probe.sh` 保存
内核日志、命令和退出码，再持久化 60 条每秒健康记录：uptime、eth0 状态、carrier
和 IP。它只用于一次候选测试，不能替代硬件稳定性验收。

CNB 构建 `cnb-iso-1k218vadk`（提交
`11a490631aaff658b8d590c87a6576a232488d3f`）的 `run-30-1` artifact
`ws1608-hcodec-armv7-run-996855724-1.tar.xz` 已完成下载、独立复验、刷写和重启，
artifact SHA-256 为
`6881000c3bd150a52bd0f77e76b51c31a2f918862caa17fd2fda7cd00ff27f17`。
640×480 MMAP motion probe 退出码为 `0`，生成 44137 字节 Annex-B H.264，包含
1 个 IDR 和 29 个 P 帧；独立 `ffprobe`/`ffmpeg` 通过，码流 SHA-256 为
`334a7bca58cda061d28ddaf4410bfebec79c0e50d0cd09466ab2929ad288a9a2`。保存的
`kernel.live.log` 记录 30 帧、两个 `stop_streaming` 和 `power_off end`，60 条
健康记录全部保持 eth0/carrier 在线，HCODEC 错误、panic 和 oops 为 0。探针后
设备仍需重启恢复 SSH，因此该 artifact 仍是实机研究候选，不代表稳定验收或可创建
PR。

之后将同一 artifact 安装到稳定 One-KVM 用户空间进行 `results-stable-30f` 复验：
退出码为 `0`，输出 44127 字节 Annex-B H.264，包含 1 个 IDR 和 29 个 P 帧；独立
`ffprobe`/`ffmpeg` 通过，码流 SHA-256 为
`d1daed2cda6353b1b7d2f692abcf3803ef9076b6e0dc550652bafd66b97e818a`。60 条健康记录
完整，内核日志无 HCODEC 错误、panic 或 oops，但探针后设备仍需重启恢复 SSH，
所以该 artifact 仍未达到稳定验收或 PR 条件。
