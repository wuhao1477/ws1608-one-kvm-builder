# WS1608 实机验收

## 当前证据边界

| 项目 | 状态 | 证据/备注 |
| --- | --- | --- |
| 固定 Armbian 基础镜像启动 | 已验证 | WS1608 实机能启动并正常 HDMI 显示 |
| HDMI 1080p、千兆网络、eMMC | 已验证 | 基础镜像现场测试通过 |
| 四核 60 秒负载 | 已验证 | 基础镜像现场测试通过 |
| HDMI 音频 | 已知问题 | `gx-sound-card` 注册出现 error -22，当前不影响 One-KVM 的 USB 视频/HID目标 |
| One-KVM `0.2.4` 运行 | 已验证过 | 在已启动系统中安装，systemd active，health API 返回 ok |
| 当前 Release `ws1608-one-kvm-v260709` 实体刷写 | 未验证 | GitHub runner 没有 WS1608、USB Burning Tool 或显示器 |
| USB HDMI 采集卡 | 未验证 | 之前测试时未连接实际采集卡 |
| 被控机 USB HID | 未验证 | 之前测试时未连接被控机 USB 线 |

因此，CI 的“通过”只表示镜像容器和 rootfs 内容通过检查，不能写成“这个 Release 已在 WS1608 启动”。

## 测试前准备

- 一台可恢复的 WS1608/OneCloud，建议保留已知可启动基础包。
- Amlogic USB Burning Tool 和对应 USB 数据线。
- HDMI 显示器，用于确认启动和分辨率。
- 网络线或已知 DHCP 环境。
- USB HDMI 采集卡和被控机 USB 连接线，用于 One-KVM 功能测试。
- 测试主机上的 SSH、浏览器和 `curl`；连接地址、密码和设备序列号只保存在本地，不写入仓库。

## 刷写与启动

1. 从 Release 下载 `.burn.img` 或解压 `.burn.img.xz`。
2. 用 `SHA256SUMS` 核对文件；GitHub API 的 asset digest 也应与 manifest 一致。
3. 使用 Amlogic USB Burning Tool 刷写，确认工具报告完成后断电重启。
4. 记录 HDMI 是否有画面、首次启动耗时和是否自动取得网络地址。
5. 通过 SSH 登录后立即检查版本文件和服务状态。

建议命令：

```sh
cat /etc/ws1608-one-kvm-release
uname -a
systemctl is-enabled one-kvm.service
systemctl is-active one-kvm.service
systemctl status one-kvm-otg.service --no-pager
curl -fsS http://127.0.0.1:8080/api/health
```

预期：版本文件包含 `one_kvm_version=0.2.4`、`one_kvm_release=v260709`、对应 `build_tag=...-bRRRAAA` 和 package SHA-256；health API 返回状态 ok；One-KVM 服务为 enabled/active。具体版本应以实际 Release manifest 为准。

## OTG、视频和 HID

```sh
cat /sys/devices/platform/soc/c9040000.usb/usb_role/*/role
lsmod | grep -E 'libcomposite|configfs' || true
find /dev -maxdepth 1 -type c -name 'video*' -print
systemctl status one-kvm-otg.service --no-pager
journalctl -u one-kvm-otg.service -b --no-pager
```

检查点：

- USB role 最终为 `device`，而不是 `host`。
- `libcomposite` 已加载，OTG unit 没有 timeout 或 sysfs path 错误。
- 接入 HDMI 采集卡后出现 `/dev/video*`，One-KVM Web 页面能看到视频流。
- 接入被控机 USB 后，键盘、鼠标和必要的存储/虚拟介质操作能在 BIOS 和操作系统阶段工作。
- 断开并重新接入采集卡/USB 线后服务能恢复，不需要手动重启。

如果设备树或内核更新了 USB role 路径，`config/one-kvm-enable-otg` 的固定路径可能失效；这属于基础镜像候选升级的硬件验收项。

## 重启和稳定性

```sh
systemctl reboot
```

重启后重复检查：

- HDMI 仍有画面。
- 网络和 SSH 可用。
- One-KVM service enabled/active。
- health API 可访问。
- OTG role、视频设备和 HID 仍可用。

有 `stress-ng` 时可进行短时四核负载测试：

```sh
stress-ng --cpu 4 --timeout 60s --metrics-brief
```

记录温度、重启、服务崩溃和 USB 断连；不要在没有散热和供电条件确认时长时间满载。

## 验收记录模板

把每次实体测试复制到维护者的私有记录中，公开仓库只提交不含地址、密码和序列号的结论：

```text
Release tag:
burn.img SHA-256:
测试日期:
板卡/硬件版本（不含序列号）:
刷写结果:
HDMI 启动与分辨率:
网络/SSH:
one-kvm service:
health API:
OTG role/libcomposite:
视频采集:
键盘 HID:
鼠标 HID:
重启后复测:
负载/温度:
结论: pass / fail / blocked
失败日志位置（私有）:
```

## 稳定发布门槛

只有以下条件都满足，才可以把新的基础镜像或内核标为稳定输入：

- 至少一次完整刷写和断电重启。
- HDMI、网络、eMMC 和 One-KVM Web/health 正常。
- OTG role、视频采集和 HID 通过，或明确记录为该硬件变体不支持。
- 至少一次重启后复测。
- 失败日志和 SHA-256 已保存。

未通过实体测试的基础更新只能作为候选，不得替换 `config/base.env` 指向的稳定资产。
