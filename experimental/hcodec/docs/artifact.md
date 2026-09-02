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

run-8 已证明候选内核可启动并注册 HCODEC V4L2 设备，但首帧编码会硬锁。下一版
artifact 的目的不是声明编码成功，而是通过默认开启的 `trace_runtime` 日志记录
`queue_setup`、`buf_prepare`、`buf_queue` 和 `start_streaming` 阶段。
