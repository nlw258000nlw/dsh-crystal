# dsh-crystal 结晶大管家

DSH 的全能管家插件：21 项系统体检（doctor.ps1）、三把自愈锁、按需插件调度、用量记账与预算报警、每日早报（QQ 推送）、升级参谋、一键备份回滚、桌面大肥鱼桌宠。

## 一句话
装上之后你什么都不用管——它每小时体检，红了自愈，坏了熔断，钱花到顶会喊你，晚上九点给你发早报。

## 核心能力
- **doctor 体检**：21 项检查，红黄绿灰四色报告，-Auto 自动修、-Fake 假测不落盘
- **三把锁**：doctor 自停熔断 / kill 开关 / L0 兜底盖戳，互不依赖
- **按需调度**：插件三档 demand（always/on-demand/off），72 小时租约自动关
- **记账与预算**：每轮 token 用量落 usage.jsonl，日钱线触顶只报警不打断
- **总表驱动**：crystal.json 一表生成六处配置，改一处全跟着变
- **CLI**：`crystal status|doctor|build|rollback|bill|dues|fortune|keywords|pet …`
- **面板**：侧栏「结晶」红黄绿灰四卡 + 开关表单
- **桌宠**：透明置顶大肥鱼小窗，会说体检结果和早安晚安

## 安装
双击 `install.ps1`（DryRun 先演练），或 DSH CLI：`dsh plugin --profile desktop add link:<插件目录>`。

## 常见问题
- 白屏？先看 README「排障」节；日志在 `data\crystal\alerts.log`
- 想换配置？面板「结晶」或直接改 `crystal.json`（改前自动备份）

详细文档见 README.md 与 docs\交接单.md。
