# crystal-backup.ps1 - 一键回滚现行备份刷新（P7 大管家创意⑤配套）：重建 $BakRoot\现行-<yyyyMMdd-HHmm>
# 用法：crystal-backup.ps1（缺省刷新一份现行备份；只保留最新 2 份，其余 现行-* 删除）
# 口径与 $BakRoot\..\一键回滚\一键回滚.ps1 的 BackupNote 一致=七件（桥接-bridge/维护脚本/工作区/插件配置-profile/插件-plugins/记忆/会话-今天）
# 安全边界：只写 $BakRoot\现行-*；不碰其它目录；不杀进程；会话只补今天（/MAXAGE:1）
param([switch]$KeepAll)
$ErrorActionPreference='SilentlyContinue'
$BakRoot=Join-Path $env:LOCALAPPDATA 'crystal\backup'
$Bridge=Join-Path $env:LOCALAPPDATA 'crystal\bridge'
$Sys=Join-Path $env:LOCALAPPDATA 'crystal\sys'
$Work=Join-Path $env:USERPROFILE 'Documents\deepseek-harness'
$Profile=Join-Path $env:USERPROFILE '.dsh\profiles\desktop'
$Plugins=Join-Path $env:USERPROFILE '.dsh\plugins'
$Memories=Join-Path $env:USERPROFILE '.dsh\memories'
$Sessions=Join-Path $env:USERPROFILE '.dsh\sessions'
$DetF=Join-Path (Split-Path -Parent $PSScriptRoot) 'data\detected.json'
if(Test-Path $DetF){
  try{
    $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json
    if($det.backupRoot){ $BakRoot=[string]$det.backupRoot }
    if($det.bridgeHome){ $Bridge=[string]$det.bridgeHome }
    if($det.maintHome){ $Sys=[string]$det.maintHome }
    if($det.userHome){
      $u=[string]$det.userHome
      $Work=Join-Path $u 'Documents\deepseek-harness'
      $Profile=Join-Path $u '.dsh\profiles\desktop'
      $Plugins=Join-Path $u '.dsh\plugins'
      $Memories=Join-Path $u '.dsh\memories'
      $Sessions=Join-Path $u '.dsh\sessions'
    }
  }catch{}
}
try{
  $cjBk=Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($cjBk.paths.bakRoot){ $BakRoot=[string]$cjBk.paths.bakRoot }
  if($cjBk.paths.bridgeHome){ $Bridge=[string]$cjBk.paths.bridgeHome }
  if($cjBk.paths.sysHome){ $Sys=[string]$cjBk.paths.sysHome }
  if($cjBk.paths.workHome){ $Work=[string]$cjBk.paths.workHome }
  if($cjBk.paths.profileHome){ $Profile=[string]$cjBk.paths.profileHome }
  if($cjBk.paths.pluginsHome){ $Plugins=[string]$cjBk.paths.pluginsHome }
  if($cjBk.paths.memories){ $Memories=[string]$cjBk.paths.memories }
  if($cjBk.paths.sessionsHome){ $Sessions=[string]$cjBk.paths.sessionsHome }
}catch{}
$stamp=Get-Date -Format 'yyyyMMdd-HHmm'
$dest=Join-Path $BakRoot ('现行-'+$stamp)
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$sets=@(
  @($Bridge,(Join-Path $dest '桥接-bridge')),
  @($Sys,(Join-Path $dest '维护脚本')),
  @($Work,(Join-Path $dest '工作区')),
  @($Profile,(Join-Path $dest '插件配置-profile')),
  @($Plugins,(Join-Path $dest '插件-plugins')),
  @($Memories,(Join-Path $dest '记忆'))
)
$fail=0
foreach($s in $sets){
  & robocopy $s[0] $s[1] /MIR /R:2 /W:2 /NFL /NDL /NP /NJH /NJS | Out-Null
  $c=$LASTEXITCODE
  if($c -ge 8){ $fail++; Write-Output ('[BACKUP-FAIL] '+(Split-Path $s[1] -Leaf)+' robocopy exit='+$c) }
}
& robocopy $Sessions (Join-Path $dest '会话-今天') /E /MAXAGE:1 /R:2 /W:2 /NFL /NDL /NP /NJH /NJS | Out-Null
$note='本备份为「现行」环境快照。生成时间：2026-11-19 '+$stamp+'（crystal backup 自动刷新）内容：六套+会话-今天。用途：一键回滚.ps1 还原源。'
[IO.File]::WriteAllText((Join-Path $dest '备份说明.md'),$note,(New-Object Text.UTF8Encoding($true)))
if(-not $KeepAll){
  $olds=@(Get-ChildItem $BakRoot -Directory | Where-Object { $_.Name -match '^现行-\d{8}-\d{4}$' } | Sort-Object Name -Descending | Select-Object -Skip 2)
  foreach($o in $olds){ Remove-Item $o.FullName -Recurse -Force -ErrorAction SilentlyContinue; Write-Output ('[BACKUP-PRUNE] 删除旧备份 '+$o.Name) }
}
$total=(Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum/1GB
Write-Output ('[BACKUP] 完成：'+$dest+' 合计 {0:N2} GB' -f $total)
if($fail -gt 0){ Write-Output ('[BACKUP] '+$fail+' 套失败，需人工检查'); exit 1 }
exit 0
