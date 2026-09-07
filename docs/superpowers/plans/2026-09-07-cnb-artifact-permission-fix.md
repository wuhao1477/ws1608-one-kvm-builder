# CNB 制品与 PR 权限修复实施计划

> **For agentic workers:** 按任务逐项执行；每项先写失败测试，再实现，再运行对应验证。

**Goal:** 使用 CNB 官方制品附件机制恢复 GitHub Actions 的上传、下载和复验语义，同时保留 PR 事件的最小权限安全边界。

**Architecture:** 构建脚本只负责发现输入、构建、打包和验证；候选制品存储交给 `cnbcool/attachments:latest`，Release 创建继续使用项目已有的不可覆盖 tag、草稿 Release 和摘要复验逻辑。PR 事件先在云端验证附件插件是否真的拥有官方文档所述的上传能力；若平台实际拒绝写入，则停止并报告 CNB 能力冲突，不用本地复制伪装成上传下载。

**Tech Stack:** CNB `.cnb.yml`、`cnbcool/attachments:latest`、Bash、Node.js 内置测试、CNB OpenAPI/CLI。

**Spec:** `docs/build-pipeline.md`、`docs/superpowers/specs/2026-07-20-versioned-releases-design.md`、官方迁移和附件文档。

## Global Constraints

- `pull_request` 仍使用 CNB 的不可信事件权限，不导入可写 PAT 或 Release 密钥。
- 稳定 Release 只允许可信的定时、API Trigger 和 Web Trigger 路径创建。
- 稳定产物必须保持五项文件、SHA-256、manifest 和 validation report 不变。
- HCODEC、AMLENC 候选继续只保留 14 天，不创建稳定 Release。
- 每次修改 `.cnb.yml` 或 `.cnb/web_trigger.yml` 都必须通过 CNB validator。

### Task 1: 固化官方映射契约

**Files:**
- Modify: `tests/workflow-policy.test.mjs`
- Modify: `experimental/hcodec/tests/artifact-contract.test.mjs`
- Modify: `experimental/amlenc/tests/burn-image-contract.test.mjs`

- [ ] **Step 1: 写失败测试**

断言候选流程使用 `image: cnbcool/attachments:latest`，上传设置 `ttl: 14`，并存在下载后独立复验；断言 PR 路径不调用 `scripts/cnb-upload-commit-assets.sh` 的写入接口，也不把本地 `cp` 当成上传下载。

- [ ] **Step 2: 运行测试确认失败**

```sh
node --test tests/workflow-policy.test.mjs experimental/hcodec/tests/artifact-contract.test.mjs experimental/amlenc/tests/burn-image-contract.test.mjs
```

预期：当前自定义 commit asset 路径不满足官方插件契约。

### Task 2: 分离构建与制品存储

**Files:**
- Modify: `scripts/cnb-run-stable.sh`
- Modify: `scripts/cnb-run-hcodec.sh`
- Modify: `scripts/cnb-run-amlenc.sh`
- Modify: `.cnb.yml`
- Create: `scripts/cnb-download-commit-assets.sh`
- Delete: `scripts/cnb-upload-commit-assets.sh`

- [ ] **Step 1: 让三个 runner 只生成并验证输出**

稳定流程继续在 `PUBLISH=true` 时调用 `scripts/cnb-publish-release.sh`；候选流程只留下已验证的输出目录，不在构建脚本中直接调用 commit asset 写 API。

- [ ] **Step 2: 在 CNB Pipeline 中加入官方附件插件**

按官方迁移教程把候选输出接入 `cnbcool/attachments:latest`，上传使用 14 天 TTL；稳定使用 `./out/cnb-stable/*/*`，HCODEC 使用 `./out/hcodec/artifact/*`，AMLENC 使用 `./out/amlenc/burn/*`。每个 runner 先生成独立的构建上下文文件，供后续稳定复验 Stage 恢复身份字段。

```yaml
- name: upload candidate artifact
  image: cnbcool/attachments:latest
  settings:
    attachments:
      - ./out/hcodec/artifact/*
    ttl: 14
```

- [ ] **Step 3: 加入下载后复验**

使用 `scripts/cnb-download-commit-assets.sh` 通过 CNB 只读下载接口获取刚上传的文件，写入全新目录，再运行现有 `verify-release-assets.sh`、`verify-artifact.sh` 或 `verify-burn-release.sh`。该入口只执行 GET，不执行上传、确认或删除；禁止复制原目录作为下载替代。

### Task 3: 云端权限探针与根因确认

**Files:**
- Modify: `.cnb.yml` only as part of Task 2
- Test: CNB PR build for PR `#1`

- [ ] **Step 1: 先运行契约流水线**

确认 `contract` 成功，且稳定 PR 构建在镜像和五项资产复验之后进入附件上传阶段。

- [ ] **Step 2: 读取完整 Stage 日志**

使用 `cnb pulls check-status`、`cnb build get-build-status` 和 `cnb build get-build-stage`，记录附件插件的 HTTP 状态、目标 Commit 和最终下载复验结果，不隐藏错误输出。

- [ ] **Step 3: 验证真实对象**

使用 `CNB_COMMIT` 对应的预合并 Commit，查询 commit asset 列表，下载每个文件并与构建目录逐字节比较。若插件仍因 `repo-code:r` 或预合并对象限制失败，停止实现并将其记录为 CNB 平台能力冲突，不提交本地复制方案。

### Task 4: 恢复全部触发行为

**Files:**
- Modify: `.cnb.yml`
- Modify: `.cnb/web_trigger.yml`
- Test: `tests/cnb-migration-contract.test.mjs`
- Test: `tests/workflow-policy.test.mjs`

- [ ] **Step 1: 核对 GitHub 到 CNB 映射**

逐项验证 schedule、PR path filter、workflow dispatch 四个输入、repository dispatch、并发锁、HCODEC/AMLENC 分支规则和稳定 Release 条件。

- [ ] **Step 2: 验证可信与不可信事件边界**

PR 只构建和产出候选制品；定时、API Trigger 和 Web Trigger 才能写 Release 或可信候选附件。`force`、`publish`、`prerelease`、`acknowledge_experimental` 的默认值和作用保持不变。

### Task 5: 本地与云端验收

**Files:**
- Verify all changed files and generated checksum manifests

- [ ] **Step 1: 运行本地门禁**

```sh
pnpm test
for script in scripts/*.sh experimental/amlenc/scripts/*.sh experimental/hcodec/scripts/*.sh; do bash -n "$script"; done
node /Users/wuhao/.codex/skills/cnb-pipeline/validator/validate.js .cnb.yml
node /Users/wuhao/.codex/skills/cnb-pipeline/validator/validate.js .cnb/web_trigger.yml
git diff --check
```

- [ ] **Step 2: 运行 CNB 契约和稳定 PR 构建**

两条流水线都必须成功；稳定 PR 必须显示镜像构建、五项输出、附件上传、下载和独立复验均成功。

- [ ] **Step 3: 合并后验证主分支**

验证 `main` 指向迁移提交，重新运行 migration contract、稳定 API Trigger、稳定 Web Trigger 配置、HCODEC 和 AMLENC 触发配置，并核对 10 个 Release、40 个附件、latest 指向和下载摘要。

## Official References

- [从 GitHub Actions 迁移到 CNB](https://docs.cnb.cool/zh/build/migrate-to-cnb/migrate-from-github-actions.html)
- [附件插件](https://cnb.cool/cnb/plugins/cnbcool/attachments)
- [默认环境变量与 CNB_TOKEN 权限](https://docs.cnb.cool/zh/build/build-in-env.html)
- [触发规则](https://docs.cnb.cool/zh/build/trigger-rule.html)
- [手动触发流水线](https://docs.cnb.cool/zh/build/web-trigger.html)
- [权限说明](https://docs.cnb.cool/zh/build/permission.html)
