# dsh-crystal — DSH 自愈与总表守护插件

一句话：一张总表（crystal.json）驱动生成与校验，一名医生（doctor.ps1）二十检体检，三把锁（自停/断电/兜底）保底，一个 CLI 十一个动词。

## 三个入口
1. 总表：`F:\crystal\dsh-crystal\crystal.json`（schemaVersion 2；renders/checks/automation/plugins/pricing/autonomy/forbidden/_ignore 全在这）
2. 体检：`F:\crystal\dsh-crystal\scripts\doctor.ps1`（16 检，默认只读；`-Auto` 只修 fix.kind=auto 且未冻结项；`-Fake <fault>` 假测不落盘；`-PricingNow` 假时间测档期）
3. CLI：`F:\crystal\dsh-crystal\scripts\crystal.ps1`

## CLI 动词（各一行示例；stdout 每条 ≤12 行，全文落 F:\crystal\data\logs\）
- status：`powershell -NoProfile -ExecutionPolicy Bypass -File F:\crystal\dsh-crystal\scripts\crystal.ps1 -Verb status`（体检摘要+autonomy 读数）
- doctor：`… -Verb doctor`（转发 doctor.ps1 默认只读；`-Arg1 Auto` = -Auto）
- build：`… -Verb build`（= crystal-build -Check，只读核对现网六件在场与编码）
- rollback：`… -Verb rollback`（rollback.ps1 只认全绿快照+回滚后复检 [ROLLBACK-CHECK]）
- where：`… -Verb where`（数据与脚本落位表）
- count：`… -Verb count`（alerts/fallbacks/usage/cost/快照 行数）
- plugins：`… -Verb plugins`（三源对账→F:\crystal\data\plugins-inventory.json）
- reset-melt：`… -Verb reset-melt -Arg1 <fault>`（熔断复位，alerts.log 写 [MELT-RESET] 留痕）

## 四色含义（doctor 每行与汇总）
- 红 RED：会崩/坏（未解决红>0 时 exit 1；同一 fault 连 3 红=熔断 exit 4，先打全部红行+汇总+复位提示）
- 黄 YELLOW：坏但只诊断不修（frozen/停用/缺键/待授权项）
- 绿 GREEN：正常（现行常态=0 红 / 0 黄 / 15 绿 / 1 灰）
- 灰 GRAY：无法判定（如 Cookies 被运行中的 DSH 独占锁，给人工检查口令）

## 熔断复位
- 症状：doctor exit=4，汇总只两行（[SELF-STOP] 熔断，诊断被吞）
- 复位：`crystal.ps1 -Verb reset-melt -Arg1 <fault名>`（清 fault-runs.json 该 fault 计数+[MELT-RESET] 留痕），再跑 doctor 复查
- 常见场景=DSH 重启后 GUI 端口漂移：`crystal-endpoints.ps1 -Probe` 写新端口 → `doctor.ps1 -Auto` 写回 truth.json → 已熔断先 reset-melt truth.health.guiPort

## 三把锁（互相独立，各在各家，配置坏了用各自默认值继续并写 [CONF-FALLBACK] 黄行）
- 锁一 自停熔断：`F:\crystal\conf\lock1-selfstop.json`（doctor 120s 超时/连 3 红自停；Global\crystal-lock 排队 90s）
- 锁二 断电开关：`F:\crystal-kill\conf\lock2-kill.json` + `F:\crystal-kill\kill.ps1`（真杀进程；桌面 停结晶.cmd；任务 CrystalKillSwitch 每 2 分钟）
- 锁三 L0 兜底：`F:\crystal-l0\conf\lock3-fallback.json` + `F:\crystal-l0\crystal-l0.ps1`（每 6 小时盖戳；桌面 结晶状态.txt；任务 CrystalL0-Stamp）
- 日报：`F:\crystal\scripts\scan.ps1`（任务 CrystalDaily-Scan 每天 09:10，写 daily-scan.log）

## 备份与回滚（分步）
1. 改任何脚本/配置前：落 `.bak-<日期>-<时刻>` 备份并逐件点名写尺寸（同名备份会误读成旧备份，禁止）
2. 改完立即：补 BOM（.ps1 首三字节 239,187,191）+ ParseFile 0 错 + PS5.1 真机跑贴 exit 码与末行
3. 回滚：`.bak` 覆盖回去 → 重跑 doctor 复检全绿才算回退成功
4. 数据回滚：`rollback.ps1` 只认全绿快照（data\crystal\snapshots\，留 10 个，日志与戳不倒退）
5. 迁移旧目录 `dsh-crystal.bak-20261119` 留 24 小时，清前问脑公

## 红线（写死）
- 现网六件（inject-table.json / qq-tool-restrict.mjs / bridge.js / presets\*.patch.yml / AGENTS.md / config.json）未经脑公亲口授权一字节不写，连瞬时改都不许
- 不重启 DSH/桥（重启由脑公本人动手）、不碰 SnowLuma-Guard、不动宿主 app.asar、口令/令牌不落文件
- 出岔：先写 [SELF-STOP] 到 alerts.log，再一行回信等人工，不硬扛


---

## P4 附录（2026-11-19 脑公亲指新阶段）
### 依赖版本
- PowerShell 5.1+（doctor/CLI/三锁全部 ps1；**所有 .ps1 必须 UTF-8 带 BOM**，PS5.1 才不把中文当 GBK 读）
- node v20+（F:\系统维护\dsh-gui-port.js 端口判据、bridge.js 用 node --check 验语法）
- DSH ≥ 0.2.2-rc.3（profiles\desktop\package.json 的 dsh.profile.bundles 登记 dsh-crystal）
- JSON 一律无 BOM 且首字节 123；crystal.json 是 PS5.1 宽松 JSON（路径内单反斜杠在字符串里必须写成 \\）

### 装卸载回滚三步
- 装：`install.ps1 -DryRun` 预演 → `install.ps1 [-HomeDir <数据目录>]`（登记 bundles→可选 Junction→从 crystal.json.template 渲染总表→doctor 上报；已装=校验模式幂等）→ 重启 DSH 生效
- 卸：`schtasks /Delete /TN CrystalL0-Stamp|CrystalDaily-Doctor|CrystalDaily-Scan|CrystalKillSwitch /F` → 从 bundles 摘掉 dsh-crystal → `cmd /c rmdir C:\Users\<你>\.dsh\plugins\dsh-crystal`（只删 Junction 不删目标）→ 数据目录 <home> 保留归档
- 回滚：`crystal.ps1 -Verb rollback -Arg1 status` 看版本 → `-Arg1 vNNNN` 回退（版本包 F:\crystal\data\versions\<tag>\，回退前自动存保险包）；应急=盖回当天 `.bak-20261119-<时刻>`（每段收工必点名备份）

### doctor 红黄对照（20 检；常态 0红0黄18绿1灰）
- **红**=坏了或违红线（会熔断计数）：bom-truth 编码坏 / gui-port 端口漂（DSH 重启必漂，`crystal-endpoints -Probe`+`doctor -Auto` 自愈）/ snowluma-pipe 掉线 / stamp-starvation 戳断供 / heartbeat 心跳停 / fallback 缺 / hand-edit 六处标记被手改 / config-version-mismatch / mount-missing / conf-version 锁配置版本 / restart-gate 源码现 taskkill /T /F / automation 任务缺失 / inventory 缺失或过期 / baseline 缺失 / rules 缺键 / autonomy 缺键 / receipts 缺 / plugin-toggle 台账到期 / conflicts 任务幂等破坏
- **黄**=提醒不熔断：mount 待授权段判黄、台账到期、版本不符（拒启由锁侧 exit 7 执行）
- **灰**=如实不可判：cookies（DSH 独占锁→按黄行给的人工命令数条数）、stamps 断供（不自杀只报灰）
- 熔断与复位：同 fault 连 3 红 → [SELF-STOP] exit 4（先打完诊断行）；`crystal.ps1 -Verb reset-melt -Arg1 <fault>` 复位
- 预算：checks.budget{warnTokensDaily:1000000,warnCnyDaily:12}，超额 doctor 出 [BUDGET-WARN] 直写行（不计熔断）

### 数据目录统一
- 运行数据：F:\crystal\data\（endpoints/queue/usage/usage.jsonl/fallbacks/fallback-state/render-baseline/heartbeat/versions/cost/daily-scan/logs/install）
- 插件根 data\crystal\：doctor 运行文件（truth/fault-dictionary/alerts/errors/stamps/snapshots/evidence）
- 三锁：F:\crystal\conf、F:\crystal-kill、F:\crystal-l0；演练 F:\crystal-drill；沙箱 F:\_crystal-sandbox

---

作者：QQ 2870864194（脑公）｜开源：MIT License
