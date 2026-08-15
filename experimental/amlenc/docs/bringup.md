# WS1608 S805 AMLENC 实机启动与编码门禁

当前状态：**未通过实机验证**。本流程不得写入 eMMC，不得接入 One-KVM、USB Gadget 或稳定发布链路。

## 1. 可恢复启动

1. 使用可移除介质或可恢复的临时启动方式加载 `out/amlenc/kernel/` 中的 Linux 3.10.107 内核、WS1608 DTB 和模块。
2. 保留当前已验证镜像和 USB Burning Tool 恢复路径。
3. 启动后确认 `uname -r` 为 `3.10.107`，且 `/dev/amvenc_avc` 存在。当前稳定版 6.12 内核不能作为本门禁的测试环境。

在设备上采集不含网络地址、密码和序列号的只读信息：

```bash
mkdir -p amlenc-evidence/system
uname -a > amlenc-evidence/system/uname.txt
tr '\0' '\n' </proc/device-tree/compatible > amlenc-evidence/system/dt-compatible.txt
cat /proc/iomem > amlenc-evidence/system/iomem.txt
cat /proc/meminfo > amlenc-evidence/system/meminfo.txt
ls -l /dev/amvenc_avc > amlenc-evidence/system/device-node.txt
dmesg | grep -Ei 'amvenc|encoder|codec_mm|cma|ion|oops|panic|timeout|corrupt' > amlenc-evidence/system/kernel-boot.log
```

## 2. 固定探针

把 `libvpcodec.so`、`amlenc-m8-diag`、`validate-h264.sh`、`hardware-limits.json` 和单帧 NV12 测试图放在设备的临时目录。依次执行：

```bash
export LD_LIBRARY_PATH=$PWD
./amlenc-m8-diag --input frame-640x480.nv12 --width 640 --height 480 --fps 30 --bitrate 1000000 --frames 300 --output 640x480-300f.h264
dmesg > 640x480-300f.dmesg
./validate-h264.sh --probe 640x480-300f --input 640x480-300f.h264 --kernel-log 640x480-300f.dmesg --output-dir amlenc-evidence/640x480-300f

./amlenc-m8-diag --input frame-1280x720.nv12 --width 1280 --height 720 --fps 30 --bitrate 4000000 --frames 1800 --output 1280x720-1800f.h264
dmesg > 1280x720-1800f.dmesg
./validate-h264.sh --probe 1280x720-1800f --input 1280x720-1800f.h264 --kernel-log 1280x720-1800f.dmesg --output-dir amlenc-evidence/1280x720-1800f

./amlenc-m8-diag --input frame-1280x720.nv12 --width 1280 --height 720 --fps 30 --bitrate 4000000 --frames 864000 --output 1280x720-8h.h264
dmesg > 1280x720-8h.dmesg
./validate-h264.sh --probe 1280x720-8h --input 1280x720-8h.h264 --kernel-log 1280x720-8h.dmesg --output-dir amlenc-evidence/1280x720-8h
```

长时探针开始前应保证输出介质空间足够。每项探针必须在编码结束后采集新的完整 `dmesg`，再交给验证器；验证器只把筛选后的编码相关行写入证据目录。裸 Annex-B H.264 不携带容器时间戳，因此验证器按固定探针的 30 fps 解复用，并用提交帧数计算持续时间。每项验证独立要求 H.264、正确分辨率、精确帧数、SPS/PPS/IDR、零解码错误，以及无 kernel oops、CMA failure、编码超时或损坏码流。

## 3. 停止条件

任一命令非零退出即停止后续开发。只有三项 `validation.json` 都为 `passed`，并经人工核对系统信息与哈希后，才能把 `hardware-limits.json` 更新为已验证并开始 One-KVM 集成。提交证据前删除 IP、密码、序列号和未经筛选的原始日志。
