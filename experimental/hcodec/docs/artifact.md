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
