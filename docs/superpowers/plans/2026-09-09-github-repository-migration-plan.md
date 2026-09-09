# GitHub Repository Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将仓库 Git 主入口迁移到 GitHub，保留 CNB 配置为停用历史文件，并阻止凭据进入仓库或 GitHub Actions。

**Architecture:** GitHub SSH 远端成为唯一 `origin`，当前所有本地分支和标签以非强制方式同步。CNB 配置和脚本保留但只作历史参考；GitHub Actions 承担测试、构建和制品流程。一个无第三方依赖的 secret-scan 脚本检查 Git 跟踪文件，并由 GitHub Actions 每次运行。

**Tech Stack:** Git、GitHub Actions、Node.js 内置模块、pnpm、Bash。

**Spec:** `docs/superpowers/specs/2026-09-09-github-repository-migration-design.md`

## Global Constraints

- GitHub SSH 远端：`git@github.com:wuhao1477/ws1608-one-kvm-builder.git`。
- GitHub 是唯一受支持的 Git 远端；CNB 配置保留但停用。
- 禁止提交 token、密码、私钥、完整 `Authorization` 值和包含凭据的 URL。
- 不使用 force push；GitHub 已存在且不同的 ref 必须停止迁移并报告。
- 不修改 HCODEC 驱动、镜像内容或设备验收状态。
- 不提交 `Downloads/`、构建产物、设备日志或凭据。

---

### Task 1: Add repository secret scanning

**Files:**
- Create: `scripts/verify-secrets.mjs`
- Create: `tests/secret-scan.test.mjs`
- Modify: `.gitignore`

**Interfaces:**
- `node scripts/verify-secrets.mjs` scans `git ls-files` and exits `0` when no high-confidence credential pattern is found; exits `1` with file and pattern names on a match.

- [ ] **Step 1: Write the failing test**

  Add tests that run the scanner against a temporary Git repository containing a private-key header and a GitHub token, and assert both are rejected. Add a safe fixture containing `CNB_TOKEN` variable references and public SHA-256 values and assert it passes.

- [ ] **Step 2: Run the test to verify it fails**

  Run: `node --test tests/secret-scan.test.mjs`
  Expected: FAIL because `scripts/verify-secrets.mjs` does not exist.

- [ ] **Step 3: Implement the scanner**

  Use `child_process.spawnSync('git', ['ls-files', '-z'])` and `fs.readFileSync`. Skip binary files. Reject private-key headers, GitHub token prefixes (`ghp_`, `gho_`, `ghs_`, `ghr_`, `github_pat_`), AWS access-key IDs, literal Bearer credentials, and credential-bearing URLs. Do not reject variable names such as `CNB_TOKEN` or public test placeholders.

- [ ] **Step 4: Run the test to verify it passes**

  Run: `node --test tests/secret-scan.test.mjs`
  Expected: PASS.

- [ ] **Step 5: Add local ignore rules**

  Add `.env`, `.env.*`, `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, and `credentials.json` patterns to `.gitignore` without changing existing build-output rules.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/verify-secrets.mjs tests/secret-scan.test.mjs .gitignore
  git commit -S -m "chore(security): 增加仓库凭据扫描"
  ```

### Task 2: Make GitHub Actions the supported CI entry

**Files:**
- Create: `.github/workflows/security.yml`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/build-pipeline.md`
- Modify: `docs/maintenance.md`
- Modify: `docs/superpowers/specs/2026-09-09-github-repository-migration-design.md`

**Interfaces:**
- GitHub workflow runs `node scripts/verify-secrets.mjs`, `pnpm test`, and `bash -n` for all tracked shell scripts.
- CNB files remain present but documentation labels them as stopped historical configuration.

- [ ] **Step 1: Write the failing workflow/documentation assertions**

  Extend `tests/cnb-migration-contract.test.mjs` with assertions that the security workflow exists, invokes `verify-secrets.mjs`, and that current docs state GitHub is the only supported entry while `.cnb.yml` is historical.

- [ ] **Step 2: Run the assertions to verify they fail**

  Run: `node --test tests/cnb-migration-contract.test.mjs`
  Expected: FAIL because the workflow and archival wording are absent.

- [ ] **Step 3: Add the GitHub security workflow and update docs**

  Pin `actions/checkout`, use `persist-credentials: false`, set `permissions: contents: read`, and run the scanner, `pnpm test`, and shell syntax checks. Update current docs without deleting historical CNB references.

- [ ] **Step 4: Run the assertions to verify they pass**

  Run: `node --test tests/cnb-migration-contract.test.mjs`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add .github/workflows/security.yml README.md docs/README.md docs/build-pipeline.md docs/maintenance.md docs/superpowers/specs/2026-09-09-github-repository-migration-design.md tests/cnb-migration-contract.test.mjs
  git commit -S -m "chore(ci): 切换 GitHub 为唯一支持入口"
  ```

### Task 3: Verify and migrate Git refs to GitHub

**Files:**
- No repository files; operate on Git remotes and refs only.

**Interfaces:**
- Source remote before migration: `github-archive` at `git@github.com:wuhao1477/ws1608-one-kvm-builder.git`.
- Target remote after migration: `origin` at the same GitHub URL.

- [ ] **Step 1: Run secret scan and full local gates**

  Run:
  ```bash
  node scripts/verify-secrets.mjs
  pnpm test
  for script in $(git ls-files '*.sh'); do bash -n "$script"; done
  ```
  Expected: all commands exit `0`; `Downloads/` remains untracked and is not staged.

- [ ] **Step 2: Record ref maps and check GitHub refs**

  Run:
  ```bash
  git for-each-ref --format='%(refname:short) %(objectname)' refs/heads refs/tags > /tmp/ws1608-ref-map.before
  git ls-remote github-archive 'refs/heads/*' 'refs/tags/*' > /tmp/ws1608-github-ref-map.before
  ```
  Stop if any target ref is non-fast-forward or contains a different object.

- [ ] **Step 3: Push refs without force**

  Run:
  ```bash
  git push github-archive --all
  git push github-archive --tags
  ```

- [ ] **Step 4: Make GitHub the only local origin**

  Run:
  ```bash
  git remote remove origin
  git remote rename github-archive origin
  git remote -v
  ```
  Expected: only GitHub `origin` remains; no CNB URL is configured locally.

- [ ] **Step 5: Verify remote refs and branch tracking**

  Run:
  ```bash
  git fetch origin --prune
  git ls-remote origin 'refs/heads/*' 'refs/tags/*' > /tmp/ws1608-github-ref-map.after
  git status --short --branch
  ```
  Expected: current branch tracks `origin/codex/hcodec-cnb-stability`, all pushed refs match the pre-migration map, and no tracked secret or build output appears.

- [ ] **Step 6: Commit migration evidence**

  If documentation or tests changed after the gates, commit them with a signed migration commit. Do not create or merge a PR in this task.

### Task 4: Final verification

**Files:**
- Review: `docs/superpowers/specs/2026-09-09-github-repository-migration-design.md`
- Review: current README and maintenance docs

- [ ] **Step 1: Run all gates again**

  Run: `node scripts/verify-secrets.mjs && pnpm test && git diff --check`
  Expected: all exit `0`.

- [ ] **Step 2: Verify GitHub-only remotes**

  Run: `git remote -v`
  Expected: only GitHub `origin` appears.

- [ ] **Step 3: Report migration status**

  Report the GitHub branch/ref verification, scanner result, test count, preserved CNB files, and any remaining untracked `Downloads/` directory. State explicitly that no PR was created or merged.
