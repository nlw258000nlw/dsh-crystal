# dsh-crystal 安装指南（开源版）

> 大管家插件：体检、自愈、按需插件调度、记账、回滚、升级参谋。本机实测 PS5.1 + Windows 10/11 + DSH + qq-dsh-bridge。

## 一、依赖版本

| 依赖 | 要求 | 说明 |
|---|---|---|
| Windows | 10 / 11 | PowerShell 5.1（内置） |
| DSH（DeepSeek Harness） | 0.2.2-rc.3 及以上 | profiles\desktop 的 @deepseek-ai/* 依赖需与宿主注册表 DisplayVersion 对齐 |
| qq-dsh-bridge | 本仓库同期版本 | 桥侧注入段（usage 记账/令牌自愈/按需联动）随桥源码走 |
| Node.js | 16+（桥） | 仅桥需要 |
| 磁盘 | ≥5GB | 数据目录 + 备份目录 |

## 二、安装三步

1. **放好目录**：把本包放进 `%USERPROFILE%\.dsh\plugins\dsh-crystal\`。
2. **渲染总表**：从 `crystal.json.template` 生成 `crystal.json`——把 `<CRYSTAL_HOME>`（数据目录，如 `F:\crystal`）、`<USER_HOME>`、`<BRIDGE_HOME>`、`<SYS_HOME>` 换成你自己的路径；或用 `install.ps1 -HomeDir <数据目录>` 自动渲染（路径里的反斜杠写双份 `\\`）。
3. **跑安装脚本**：`powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-DryRun]`——预检→登记 bundles→（可选）junction→doctor 终检；失败自动逆序回滚。

## 三、卸载 / 回滚三步

1. `crystal rollback -To <版本tag>` 回退版本（版本包在数据目录 `versions\`，回退前自动再拍一份保险包）。
2. 删 `%USERPROFILE%\.dsh\plugins\dsh-crystal\` 与数据目录、junction。
3. 从 profile 的 `package.json` 的 `dsh.profile.bundles` 里去掉 `dsh-crystal`（install.ps1 的备份 `package.json.bak-install-*` 可直接盖回）。

## 四、doctor 红黄对照（体检口径）

- 红（当场拦/熔断）：bom-truth、snowluma-pipe、stamp-starvation、heartbeat、fallback、mount-missing（授权修复后）、conf-version 三锁、restart-gate、rules/receipts/plugin-toggle/plugin-demand 越权、baseline 超期（-Auto 自动刷新）、budget 超红线（只喊不拦，不计熔断）。
- 黄（提醒/待办）：frozen（只诊断不修）、cookies 运行时锁（GRAY+人工命令）、mount 三点待授权（判黄期间）、[PLUGIN-AUTO-OFF-DUE]、patch 漂移（只报不改）。
- 灰（设计内）：cookies 运行时独占锁——如实报灰 + 人工检查命令。
- 全绿口径：`0 未解决红 / 0 黄 / N 绿 / 0-1 灰`。

## 五、数据目录统一

| 内容 | 路径 |
|---|---|
| 账本/队列/日志/版本/备份台账 | `<CRYSTAL_HOME>\data\` |
| CLI 日志 | `<CRYSTAL_HOME>\data\logs\` |
| 现行环境备份（回滚源） | `F:\备份\现行-*`（`crystal backup` 刷新，只留 2 份） |
| 沙箱（演练/假测产物） | `F:\_crystal-sandbox\` |
