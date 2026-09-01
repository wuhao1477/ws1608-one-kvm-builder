# Linux 6.12 HCODEC 许可证与发布边界

## 当前路线

新的硬件编码研究只采用 Linux 6.12 `meson-venc` HCODEC V4L2 M2M。代码、
补丁、DT binding、设备树、固件和测试工具必须分别记录：

- 来源仓库和固定提交；
- 文件 SPDX 标识；
- 构建或提取输入 SHA-256；
- 最终产物 SHA-256；
- 是否允许源码发布、二进制发布和固件再分发。

## 驱动和补丁

参考驱动声明 GPL-2.0-only，并说明 SoC backend 源自 Amlogic GPL-2.0 Linux
4.9 编码协议。设备树和 binding 使用各自 SPDX 双许可证。后续集成必须保留
版权、SPDX 和源代码提供义务。

研究压缩包尚未映射到公开上游提交。建立可复现来源前：

- 只能用于本地分析；
- 不能直接发布其中的预编译 `.ko`、对象文件或测试程序；
- 不能把压缩包时间戳视为来源版本；
- 必须从固定源码重新构建 ARMv7 产物。

## HCODEC 固件

资料只包含 `extract-meson8b-ucode.py`，没有
`meson/venc/meson8b_h264.bin`。固件进入候选前必须同时满足：

1. 提取源具有明确来源和摘要；
2. 提取脚本提交与 SHA-256 已固定；
3. 输出固件 SHA-256 已写入 manifest；
4. 再分发条件允许进入对应 artifact；
5. 公开源码和许可证通知满足原项目要求。

任一条件缺失时，固件和包含它的内核包不得公开发布。

## 测试工具

MMAP、DMABUF、采集编码与设备信息工具必须从固定源码构建。资料中的现成
二进制仅供识别接口，不能作为可发布或可复现实验证据。

## 已废弃历史

旧 M8 私有 AMLENC ABI 不再作为未来交付依赖。完整再分发授权 was not found；
`libvpcodec.so` 和 `amlenc-m8-diag` 继续保持 `local-test-only` 历史分类，
不进入 Linux 6.12 HCODEC 候选。

完整第三方清单见 [THIRD_PARTY.md](../../../THIRD_PARTY.md)。
