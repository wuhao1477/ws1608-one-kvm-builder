# 维护手册

## 稳定周检

查看 [Actions](https://github.com/wuhao1477/ws1608-one-kvm-builder/actions)：

- 新 One-KVM tag 或 Deb digest 出现时，必须运行 build 和 release；
- 输入未变化时，必须进入 `No new One-KVM input`，build/release 为 skipped；
- Release 必须包含五项资产，且 manifest、报告、`SHA256SUMS` 与远端 digest
  一致。

普通检查：

```sh
gh workflow run build.yml --repo wuhao1477/ws1608-one-kvm-builder \
  --ref main -f force=false -f publish=true
```

同一输入独立重建：

```sh
gh workflow run build.yml --repo wuhao1477/ws1608-one-kvm-builder \
  --ref main -f force=true -f publish=true
```

只验证不发布时使用 `publish=false`。强制重建创建新 `bRRRAAA`，不覆盖旧
Release；动态 apt 和 ext4 时间戳意味着成品 SHA-256 可以变化。

## One-KVM 更新

通常不修改代码。`discover-release.sh` 选择上游唯一 armhf Deb，并验证版本、
架构和 GitHub digest。若上游改变资产命名或不提供 digest，先增加精确规则和
测试，不能选择第一个近似资产。

## HCODEC 候选维护

HCODEC 工作遵循 [ADR-0003](adr/0003-armbian-6.12-hcodec-route.md)：

1. 从匹配稳定基础的 Linux 6.12 ARMv7 源码开始；
2. 固定驱动、补丁、固件、工具链和测试工具摘要；
3. 静态验证后只生成候选 artifact；
4. 先执行独立 V4L2 码流测试；
5. 再临时启用 One-KVM V4L2 M2M；
6. 综合实机验收后才允许 prerelease。

维护禁区：

- 不恢复已废弃的 Linux 3.10 构建或试启动分支；
- 不加载资料中的 AArch64 `meson-venc.ko`；
- 不混用 18 个补丁和最终驱动源码；
- 不在稳定服务中默认设置 `ONE_KVM_V4L2M2M_ALLOW=1`；
- 不发布来源或许可证不明的 HCODEC 固件；
- 不把教程中的 1080p30/20 视为 WS1608 实测；
- 不因 HCODEC 候选失败修改稳定 Release。

## 稳定基础升级

稳定基础包含启动链、内核、DTB 和 HDMI 参数。升级流程：

1. 创建新的不可变 candidate 基础资产；
2. 验证 Amlogic 容器和所有分区摘要；
3. 在实体 WS1608 完成刷写、断电重启、HDMI、网络、eMMC、One-KVM、OTG、
   视频和 HID；
4. 保存不含敏感信息的测试结论与 SHA-256；
5. 新建 ADR，批准后才修改 `config/base.env`；
6. 使用 `force=true` 构建 One-KVM 候选并再次实机验收。

不把 Armbian 每日构建 URL 写入稳定配置。

## AmlImg 与 Actions 依赖

- AmlImg 仓库和提交固定在 `config/tool-versions.env`；升级时验证 v2 CRC、
  item table、pack/unpack 和分区 VERIFY。
- Actions 固定完整 commit SHA；升级前检查 runtime 和权限变化。
- 默认权限保持 `contents: read`，只有 release job 使用写权限。
- qemu、Go、Node、交叉编译器和预编译模块不提交仓库。

## 发布前检查

```sh
pnpm test
for script in scripts/*.sh; do bash -n "$script"; done
git diff --check
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/build.yml
```

发布后重新下载五项资产并运行 `scripts/verify-release-assets.sh`。实体结果单独
记录，不能用 CI 结构验证替代。

Release tag 和基础资产不可覆盖。失败后修复并创建新构建身份，不删除历史
Release 来复用名称。
