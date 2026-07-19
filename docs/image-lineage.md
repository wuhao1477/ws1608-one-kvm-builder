# 镜像来源与选型

## 当前稳定基础

稳定构建使用：

```text
Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test.burn.img
```

该镜像已经在 OneCloud/WS1608 实机完成直刷、启动和 HDMI 显示验证。仓库把它压缩后作为不可变资产保存在 `base-20260719` Release，下载 URL 和 SHA-256 固定在 [`config/base.env`](../config/base.env)。自动构建只修改它的 rootfs；DDR、U-Boot、bootloader、boot 分区、内核、DTB、resource 和 HDMI 启动参数保持不变。

“稳定基础已启动验证”不代表仓库生成的每个 One-KVM Release 已完成实体刷写。当前成品的验证边界见 [hardware-validation.md](hardware-validation.md)。

## 历史参考镜像

### Armbian Jammy 6.1.9

本次工作曾比较过以下本地镜像：

```text
Armbian_23.02.0-trunk_Onecloud_jammy_edge_6.1.9.burn.img
```

仅按文件名可以确定，它属于较早的 Armbian 23.02 trunk、Ubuntu Jammy 用户空间和 6.1.9 edge 内核；当前稳定基础是 Armbian 26.8 trunk、Debian Trixie 用户空间和 6.12.28 current-meson 内核。该旧包没有作为当前仓库的固定输入，也没有记录与当前 Release 等价的摘要和完整硬件验收，因此只保留为恢复或对比参考，不能在维护时直接替换 `config/base.env`。

### 官方 One-KVM Bookworm 5.9.0-rc7

上游曾发布以下 OneCloud 直刷包：

[One-KVM_24.5.0_Onecloud_bookworm_5.9.0-rc7.burn.img.xz](https://github.com/mofeng-git/One-KVM/releases/download/v260329/One-KVM_24.5.0_Onecloud_bookworm_5.9.0-rc7.burn.img.xz)

它是官方预封装参考包，文件名表明其用户空间为 Debian Bookworm、内核为 5.9.0-rc7。它适合用于理解 OneCloud 的直刷封装方式，但不是当前仓库的基础：本仓库保留已经在目标 WS1608 上验证过的 Trixie 6.12.28 HDMI 启动链，并从上游最新稳定 Release 安装唯一的 `armhf.deb`。

不要从官方参考包中单独复制 bootloader、DTB、rootfs 或 VERIFY 文件到当前基础。这些组件必须作为一个组合完成实体启动、HDMI、网络和 OTG 验收。

## 选型结论

当前唯一稳定方案是“固定已验证的 Trixie 6.12.28 HDMI-test 基础，只自动更新 One-KVM armhf 包”。它满足三个约束：

- 可由 Amlogic USB Burning Tool 直接刷写。
- 保留已验证的 WS1608 启动链和 HDMI 行为。
- 无上游更新时每周只检查，不进行大镜像构建。

每个成品使用 `ws1608-one-kvm-<Deb版本>-<上游tag>-<UTC-HHMMSS>` 的不可变身份；同一版本的重复构建不会覆盖旧 Release。

Jammy 6.1.9 和官方 Bookworm 5.9.0-rc7 均为历史参考，不进入稳定流水线。新的 Armbian、内核、DTB 或 U-Boot 只能先进入候选测试，按 [hardware-validation.md](hardware-validation.md) 完成实体验收后，再创建新的不可变基础 Release。

## 来源与事实边界

- 当前基础文件名、URL 和摘要以 [`config/base.env`](../config/base.env) 为准。
- 当前 One-KVM 版本和输入摘要以对应 Release 的 `manifest.json` 为准。
- 旧本地镜像路径属于维护者环境，不写入公开仓库；文档只保留不含用户名的文件名。
- 没有实机记录的镜像不得标注为“确定能启动”。
