# ADR-0002：使用不可变版本化 Release 保留重复构建

- 状态：Accepted
- 日期：2026-07-20
- 范围：WS1608 One-KVM 构建和发布

## 背景

旧流程使用 `ws1608-one-kvm-<upstream-tag>`，强制构建会覆盖同名 Release
资产。这样无法保留同一 One-KVM 版本的多次构建，也无法从 tag 直接看出
One-KVM Rust Deb 版本。旧流程只按 tag 判断是否更新，上游同 tag 替换 Deb
时普通周检不会发现。

## 决策

1. tag 使用 `ws1608-one-kvm-<deb-version>-<upstream-tag>-bRRRAAA`；构建号由 Actions run number 和 run attempt 组成。
2. 普通检查同时比较 upstream tag 和 package SHA-256。
3. `force=true`、上游 tag 变化或 package digest 变化都会使用当前 workflow 的唯一构建号。
4. 每个构建创建新的 Release，不覆盖旧 tag 或旧资产。
5. 发布 job 与 build job 分离，默认权限为 `contents: read`。
6. Release 先保持 draft，五项资产上传完成后才公开。
7. build job 和 release job 都验证 manifest、报告、xz 往返和校验和。
8. draft/prerelease 不算成功输入，其 tag ref 仍视为已占用。
9. 强制 dispatch 使用独立 concurrency group；普通检查保持串行，防止并发请求丢失或争用 tag。

## 结果

- tag、标题、文件名、镜像 metadata 和 manifest 都能直接识别 Deb 版本。
- 同一上游版本可保留多次构建及各自摘要。
- 上游同 tag 替换资产会自动触发新构建。
- 未完成上传的 draft 不会抑制后续构建，也不会公开为成功 Release。
- Release 数量会增加；维护时不得通过覆盖旧资产减少数量。

该决策不改变 ADR-0001 的硬件边界。Armbian、内核、DTB 和 U-Boot 仍只
在完成 WS1608 实机验收后更新稳定基础。
