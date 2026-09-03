# HCODEC Artifact

候选工作流上传一个 `ws1608-hcodec-armv7-run-<run>-<attempt>.tar.xz`，并同时
上传顶层 `manifest.json` 与 `SHA256SUMS`。artifact 保留 14 天，不创建 tag 或
Release。

归档内容固定为：

- `kernel/`：zImage、uImage、OneCloud DTB、模块包、配置、符号表、源码摘要、签名报告；
- `tools/`：两个 ARMv7 V4L2 工具、工具摘要和固件来源摘要；
- 根目录 manifest 与归档内部 `SHA256SUMS`。

`verify-artifact.sh` 会检查摘要、tar.xz 解包、文件白名单、符号链接、固件二进制、
内核版本和硬件状态字段。固件只保留固定源码、提取脚本和摘要，
`binary_included=false`。该 artifact 是静态构建候选，不代表实体 WS1608 已启动或完成编码。

run-9 已证明候选内核可启动并注册 HCODEC V4L2 设备，并把最小 probe 失败点
定位到 `IDR` 命令：`queue_setup`、`buf_prepare`、`buf_queue`、
`start_streaming`、workspace、硬件准备、`SEQUENCE` 和 `PICTURE` 均已通过。
run-10 artifact 的目的不是声明编码成功，而是验证 Meson8b 在 SPS/PPS 后
执行 IDR 时是否需要把 VLC ring base 移到 offset 写入起点。

安装候选内核时必须使用 `experimental/hcodec/scripts/install-artifact.sh`。
该脚本先将模块包解到临时目录，再只复制
`lib/modules/<kernel_release>`；禁止直接用 `tar -xJf ... -C /`，因为归档
顶层包含 `lib/`，会覆盖 Armbian 的 `/lib -> /usr/lib` 符号链接并导致
动态程序无法启动。安装前要求根分区至少保留 4 GiB 可用空间。
