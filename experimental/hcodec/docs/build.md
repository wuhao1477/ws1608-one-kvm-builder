# HCODEC ARMv7 构建

候选构建固定使用 Armbian build `fa7a7b2294d9e760a77630950afd460b7a0b2a26`、
Linux `f08cdc6cc92e3d23a05745f0f12f8caa348a27b4`、`6.12.28-current-meson` 和
Ubuntu 24.04 digest `sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316`。

GitHub Actions 工作流为 `.github/workflows/hcodec-candidate.yml`，响应
`codex/hcodec-*` 分支的 `push`、Pull Request 和 `workflow_dispatch`。`push`
触发只用于在创建 PR 前取得云构建证据，不创建 Release 或 tag。构建顺序为：

1. 运行仓库与 HCODEC 契约测试；
2. 从固定基础镜像提取配置、DTB、uImage 地址和签名策略；
3. 在 digest 固定容器中构建 ARMv7 zImage、uImage、DTB 和模块；
4. 构建 glibc 动态链接的 V4L2 MMAP/DMABUF 工具；
5. 生成并独立复验单一 `.tar.xz` artifact。

`meson-venc` 保持模块形式，不自动加载。`cma=128M` 只写入候选 manifest，
不修改稳定镜像。构建 manifest 的 `hardware_boot_tested` 和
`hardware_encoder_tested` 仍为 `false`；硬件结果另行记录，不能由静态 artifact
字段代替。

`run-12-1` 候选已在 WS1608 上完成启动验证并注册 `/dev/video0`。640×480 单帧
H.264 probe 确认 V4L2 队列、`start_streaming`、workspace 分配、硬件准备、
`SEQUENCE` 和 `PICTURE` 命令通过；IDR 输出 7 字节后超时并返回 `-110`。
CMA 充足，设备在失败后继续运行。offset VLC ring-base 修正已否定。

下一候选由 GitHub Actions 从 Hardkernel Linux
`5aed95d35d252cafc75ce613a3a0052285662de2` 的
`drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h` 生成
9536 字节 Meson8b dblk 微码，SHA-256 为
`2a5b578c4cbfe2f9b80c110825d61bc94eba97667639fc5bf5639f1b7eec4368`。

GitHub Actions run `33854312358`（分支 `codex/hcodec-meson8b-ucode`）已完成
contract、ARMv7 构建、artifact 上传/下载和独立复验。生成的
`ws1608-hcodec-armv7-run-13-1.tar.xz` 已在 WS1608 安装并重启成功；启动后
内核、`/dev/video0`、`cma=128M`、`/lib -> /usr/lib` 和微码摘要均正确。
唯一一次 640×480、MMAP、1 帧 probe 在 120 秒内超时，随后设备 SSH 失联，未得到
有效 Annex-B H.264。该候选标记为硬件编码失败，不继续其他分辨率或测试。

GitHub Actions run `33874935950`（提交 `e5750cf`）已完成 contract、ARMv7 构建、
artifact 上传/下载和独立复验。`run-15-1` 已安装并重启成功，内核、`/dev/video0`、
`cma=128M`、`/lib -> /usr/lib` 和 9536 字节微码摘要均正确；该候选补齐
Meson8b Assist `INT1=0x19`。唯一一次 640×480、MMAP、1 帧 probe 超过 120 秒未完成，
输出为 0 字节，设备随后失联；重启后 `pstore` 为空，标记为硬件编码失败，不继续
其他分辨率或测试，也不创建 PR。

GitHub Actions run `33893613040` 已完成 contract、ARMv7 构建、artifact 上传/下载
和独立复验。`run-16-1` 修复 Meson8b 微码长度门槛后已安装并重启成功；内核、
`/dev/video0`、`cma=128M`、模块 vermagic 和固件摘要均正确。唯一一次 640×480、
MMAP、1 帧 probe 已完成 `SEQUENCE`、`PICTURE`、`IDR`，生成 6547 字节 Annex-B
H.264；`ffprobe` 识别 1 帧 640×480 Baseline，`ffmpeg` 解码成功，输出 SHA-256
为 `af392c6132fb1b349c62a0609164a5d92fb5dbda0805709614e00dfa636f407a`。但工具
在 `STREAMOFF` 清理阶段未返回并导致 SSH 超时，重启后 `pstore` 为空；编码数据
路径已通过，清理路径仍失败，不创建 PR，也不继续更高分辨率或其他内存模式。

设备安装必须使用 `install-artifact.sh`：模块包先解到目标根分区 staging，再复制
目标版本目录；固件从 artifact 的 `firmware/meson8b_h264.bin` 直接安装。
不得把归档直接解到 `/`。640×480 实机通过前不创建 PR。
