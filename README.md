# dsh-crystal

DSH 大管家全能插件：体检、记账、备份、按需调度、桌宠、记忆三件套、QQ 桥联动，一个插件全包。让小鱼看得见自己、救得了自己、管得住自己。

## 使用说明

1. 安装：把本包丢给小鱼，让它用 DSH CLI 装：`dsh plugin --profile desktop add link:<本目录>`（它会自己处理 dependencies 和 bundles）。
2. 体检：`powershell -File scripts\crystal.ps1 -Verb doctor` —— 目标状态 `0 未解决红 / 0 黄 / 20 绿 / 1 灰`。
3. 面板：DSH 侧边栏「结晶」——能力台账、体检明细、模式档位、记忆、QQ 联动都在里面。
4. 桌宠：`scripts\crystal.ps1 -Verb pet -Arg1 start`，右键有九项菜单。
5. 排障：看 `data\crystal\alerts.log`，红了跑 `-Verb doctor -Auto`；真救不动再喊小鱼。

## 配置参数（crystal.json，改前自动备份）

| 段 | 参数 | 含义 |
|---|---|---|
| modes | chat / work | 双档触发词、注入规则、工具拦截 |
| pet | size / intervalMin / voice / silent | 桌宠大小、说话间隔、语音开关、静默时段 |
| rules | review.every | 每 N 条强制复习规则（默认 3） |
| plugins | 13 个插件需求档 | always / on-demand / off |
| budget | 12 元 / 5 亿 token 日预算 | 顶格桌宠冒泡提醒 |
| paths | 各数据路径 | 覆盖自动探测结果（优先级最高） |

## 报告 bug
在仓库开 issue，附上 `data\crystal\alerts.log` 的 [RED]/[YELLOW] 行与 `doctor-state.json`；能附 `crystal.ps1 -Verb status -Arg1 json` 输出更好。

## 包结构
```
dsh-crystal/
├─ crystal.json          总表（一表生成，不许第二作者）
├─ lib/                  index.js 面板服务端 + client.js 面板前端
├─ scripts/              35 个 PowerShell（doctor/backup/daily/pet/mem/…）
├─ data/                 运行数据（体检字典、记账、台账）
├─ docs/                 能力页、原理页、验收与交接文档
└─ screenshots/          面板与桌宠截图（打包时生成）
```

## 许可证
MIT，见 LICENSE。
