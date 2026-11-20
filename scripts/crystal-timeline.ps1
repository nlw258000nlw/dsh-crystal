# crystal-timeline.ps1 - 系统大事记（P7 大管家创意④）：只读汇总各日志的显著事件成时间线
# 用法：crystal-timeline.ps1 [-Count 20]（缺省最近 20 条；-Count 0=全量）
# 事件源：alerts.log（[SELF-STOP]/[CONF-*]/[ROLLBACK-*]/[MOUNT-FIXED]/[PUSH] 等）、fallbacks.log（[LOCK-SKIP]/[LOCK-FAIL]/[FALLBACK*]）、
#         daily-scan.log（[DAILY-SCAN]/[PRICING]/[BUDGET-WARN]/[RECEIPTS]）、plugin-toggles.jsonl（[PLUGIN-TOGGLE]）、
#         read-receipts.jsonl（[RECEIPT]）、usage.jsonl（bridge-start）
# 只读、绝不写任何被读文件；产出 $Out（重生成，非追加）
param([int]$Count=20)
$ErrorActionPreference='SilentlyContinue'
$Plugin=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$Data=Join-Path $env:LOCALAPPDATA 'crystal\data'
try{
  $detT=Get-Content (Join-Path $Plugin 'data\detected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($detT.dataRoot){ $Data=[string]$detT.dataRoot }
}catch{}
$PluginData=Join-Path $Plugin 'data\crystal'
$Out=Join-Path $Data 'timeline.txt'
$enc=New-Object Text.UTF8Encoding($false)
$events=@()
function Add-Source([string]$path,[string[]]$pats){
  if(-not (Test-Path $path)){ return }
  $lines=@(Get-Content $path -Encoding UTF8)
  $n=$lines.Count
  $from=[Math]::Max(0,$n-600)
  for($i=$n-1; $i -ge $from; $i--){
    $l=[string]$lines[$i]
    $hit=$false
    foreach($p in $pats){ if($l -match $p){ $hit=$true; break } }
    if(-not $hit){ continue }
    $l2=$l
    if($l2.Length -gt 160){ $l2=$l2.Substring(0,159) }
    $script:events+=($l2+'  <- '+[IO.Path]::GetFileName($path))
  }
}
Add-Source (Join-Path $PluginData 'alerts.log') @('\[SELF-STOP\]','\[CONF-VERSION-MISMATCH\]','\[CONF-FALLBACK\]','\[CONF-ACTIVE\]','\[ROLLBACK-CHECK\]','\[ROLLBACK-REFUSED\]','\[MOUNT-FIXED\]','\[HEARTBEAT-MIGRATED\]','\[BASELINE-REFRESH\]','\[PUSH\]')
Add-Source (Join-Path $Data 'fallbacks.log') @('\[LOCK-SKIP\]','\[LOCK-FAIL\]','\[FALLBACK-YELLOW\]','\[FALLBACK-RED\]','\[TOKEN-SELFHEAL\]')
Add-Source (Join-Path $Data 'daily-scan.log') @('\[DAILY-SCAN\]','\[BUDGET-WARN\]','\[RECEIPTS\]')
Add-Source (Join-Path $Data 'plugin-toggles.jsonl') @('\[PLUGIN-TOGGLE\]')
Add-Source (Join-Path $Data 'read-receipts.jsonl') @('\[RECEIPT\]')
Add-Source (Join-Path $Data 'usage.jsonl') @('"module":"bridge-start"')
$events=@($events | Select-Object -Last $Count)
[IO.File]::WriteAllText($Out,(($events -join "`r`n")+"`r`n"),$enc)
Write-Output ('[TIMELINE] 最近 '+$events.Count+' 条（全量落 '+$Out+'）')
foreach($e in $events){ Write-Output $e }
exit 0
