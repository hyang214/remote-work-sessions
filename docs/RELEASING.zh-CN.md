# 发布流程

[English](RELEASING.md) | 中文

本项目从公开 GitHub 仓库发布到公共 npm registry。不要发布内部 clone，也不要
把内部 Git 历史带到公开仓库。

## 首次创建公开仓库

1. 从已经脱敏的 working tree 生成 clean public export：

   ```bash
   scripts/export-public-repo.sh /absolute/path/to/empty/export-directory
   ```

   命令会创建一个新的 `main` Git 仓库，只用通用 contributor identity 提交当前
   公开快照，配置公开 GitHub URL，扫描导出后的完整历史，并验证 npm tarball。
   命令不会 push。

2. 创建名为 `remote-work-sessions` 的空公开 GitHub 仓库，不要让平台生成初始化
   文件，然后 push 导出仓库的 `main` 分支。
3. 把 `main` 设为默认分支，并要求 pull-request review 以及 `Quality`、
   `ShellCheck`、`Public history`、`Podman E2E` checks 通过。
4. 开启 private vulnerability reporting、dependency graph、Dependabot alerts
   和 security updates；在仓库套餐支持时开启 secret scanning 和 push protection。
5. 确认 `.github/workflows/` 下的 workflows 可以运行。workflow 权限只保留各 job
   显式声明的最小权限。

源码仓库可以保留原 remote。不要把它的已有历史镜像到公开仓库；如果需要重新
初始化公开仓库，再执行一次 clean export。

## 首次发布 npm package

npm package 名称是 `remote-work-sessions`。发布前再次确认该名称仍可用，并确认
目标 npm 账号或 organization 会持有它。

npm trusted publisher 需要配置在已经存在的 package 上，因此首个版本需要
maintainer 手动 bootstrap：

1. 在 clean public repository 运行 `npm run test:release` 和
   `npm run test:e2e`。
2. 登录开启双因素认证的 npm 账号。
3. 使用 `npm publish --access public` 发布已经 review 的准确 tarball。
4. 在 npm package settings 中为此仓库添加 GitHub Actions trusted publisher，
   workflow 填 `publish.yml`，environment 填 `npm`。
5. 在 GitHub 创建 `npm` environment，并按需要限制为 protected tags 或要求
   maintainer approval。
6. 删除 bootstrap 期间使用的 npm automation token 或 GitHub `NPM_TOKEN`
   secret。正常发布使用 OIDC，不依赖长期 npm token。

参见 npm 官方的 [trusted publishing](https://docs.npmjs.com/trusted-publishers/)
和 [provenance](https://docs.npmjs.com/generating-provenance-statements/) 文档。

## 常规发布

1. 从公开仓库干净的 `main` checkout 开始。
2. 选择 SemVer 版本，同步更新 `package.json`、`package-lock.json`、
   `bin/rws` 中的 `RWS_VERSION`、setup-version 示例以及 `CHANGELOG.md`。
3. 运行：

   ```bash
   npm ci --ignore-scripts
   npm run test:release
   npm run test:e2e
   scripts/verify-public-release.sh --history
   ```

4. 所有 required checks 通过后，合并已经 review 的 release change。
5. 只对已经进入受保护公开 `main` 分支的 commit 创建 GitHub release，并使用与
   `v<package-version>` 完全一致的 tag。例如 package version 是 `1.2.3`，tag
   必须是 `v1.2.3`。
6. `Publish npm` workflow 会验证 tag、运行测试、扫描公开历史，并通过 npm
   trusted publishing 发布；npm 会为 package 生成 provenance。
7. 在 npm 确认 package version 和 provenance，在干净环境安装并运行
   `rws --version`。

发布失败后，不要修改已经使用过的 npm version 内容再重试。如果该 version 已被
npm 接受，应修复原因并选择新版本；发布证据保留在公开 Actions run 中。
