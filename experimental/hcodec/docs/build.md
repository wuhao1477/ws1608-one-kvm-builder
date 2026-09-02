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
不修改稳定镜像。所有候选的 `hardware_boot_tested` 和
`hardware_encoder_tested` 均为 `false`。

run-9 候选已在 WS1608 上完成启动验证并注册 `/dev/video0`。640×480 单帧
H.264 probe 已确认 V4L2 队列、`start_streaming`、workspace 分配、硬件准备、
`SEQUENCE` 和 `PICTURE` 命令通过；失败点是 `IDR` 命令在 SPS/PPS 后的
VLC offset 续写阶段超时。run-10 只调整 Meson8b offset 帧写入时的 VLC
ring base，继续由 GitHub Actions 构建 artifact 后再刷机验证。
