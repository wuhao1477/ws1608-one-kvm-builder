# GitHub Repository Migration Design

## Goal

将 `wuhao1477/ws1608-one-kvm-builder` 的 Git 托管主入口从 CNB 迁移到 GitHub，保留 CNB 配置作为历史参考，并确保仓库与 GitHub Actions 不包含明文凭据。

## Scope

- GitHub SSH 远端作为唯一 `origin`：`git@github.com:wuhao1477/ws1608-one-kvm-builder.git`。
- 将当前 `main`、功能分支、标签和当前 HCODEC 分支推送到 GitHub；不覆盖已有 GitHub 提交。
- 删除本地 CNB `origin` 配置；不删除仓库中的 `.cnb.yml`、`.cnb/` 或 `scripts/cnb-*`。
- CNB 文件标记为历史参考，不再作为受支持的构建入口或凭据来源。
- 后续构建、PR 检查和制品流程只使用 `.github/workflows/`。

## Credential policy

- 禁止提交 token、密码、私钥、完整 `Authorization` 值和包含凭据的 URL。
- CNB 脚本可以保留无默认值的运行时变量读取，但不得在 GitHub Actions 中注入 CNB secret。
- 增加仓库级 secret-scan 契约，扫描受跟踪文件并排除历史说明中的变量名、测试占位符和公开摘要。
- `.gitignore` 增加本地 `.env`、凭据文件和 SSH 私钥模式；设备密码、IP、日志不进入仓库。

## Workflow policy

- 保留 `.cnb.yml` 和 `.cnb/web_trigger.yml`，但在文档中明确其为停用的历史配置。
- GitHub Actions 保留稳定构建、HCODEC/AMLENC 实验和测试工作流。
- 删除或禁用 GitHub Actions 对 CNB API、CNB token 和 CNB 附件接口的调用；GitHub secret 仅保留实际使用的 GitHub 服务凭据。
- 不在本次迁移中改变 HCODEC 驱动、镜像内容或硬件验收状态。

## Migration sequence

1. 执行 secret-scan 和完整测试，确认工作树只有预期迁移变更。
2. 将 GitHub 远端设置为 `origin`，CNB 远端改名为本地备份后移除。
3. 推送 `main`、当前分支、其他本地分支和标签到 GitHub；遇到已存在且不同的 GitHub ref 时停止，不强制覆盖。
4. 更新维护文档中的托管、构建和凭据说明，保留 CNB 历史链接但标记停用。
5. 在 GitHub Actions 上运行仓库测试和 secret-scan；不创建或合并 PR。

## Acceptance criteria

- `git remote -v` 仅显示 GitHub `origin`。
- GitHub 包含当前分支、`main`、所有本地分支和标签，且推送未使用 force。
- secret-scan 对所有受跟踪文件通过，没有明文凭据或 CNB secret 注入。
- `pnpm test` 和所有 shell 语法检查通过。
- 文档明确 GitHub 是唯一受支持入口，CNB 仅为停用历史配置。
- HCODEC 设备状态、artifact 和现有硬件证据不被本次迁移改变。

## Rollback

迁移前记录 GitHub/CNB ref 映射和远端 URL。若 GitHub 推送或扫描失败，不删除任何远端对象；恢复本地 remote 配置即可继续现有分支工作。凭据泄露疑似发生时立即停止推送并轮换对应 secret。
