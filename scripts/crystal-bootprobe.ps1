# crystal-bootprobe.ps1 - 开机清单只读探活（§44）：只读判断「接回小鱼」与「小鱼自检」两条开机链，绝不启停任何进程
# 用法：powershell -File crystal-bootprobe.ps1   （探一次，贴 [BOOT-*] 行与末行，exit=缺件数）
# 每 2 分钟一探的调度不建新任务：doctor 每次体检都会探一次（automation 检查已含在场），本脚本供人工/演练单独探活。
$ErrorActionPreference='SilentlyContinue'
$cj=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path (Split-Path -Parent $PSScriptRoot) 'crystal.json'))) | ConvertFrom-Json
$boot=@($cj.automation | Where-Object { $_.trigger -eq 'startup' -or $_.id -eq '接回小鱼' })
$StartupDir=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
try{ if($cj.paths.startupDir -and $cj.paths.startupDir -ne ''){ $StartupDir=[string]$cj.paths.startupDir } }catch{}
$BootData=Join-Path $env:LOCALAPPDATA 'crystal\data'
try{
  $detBP=Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\detected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($detBP.dataRoot){ $BootData=[string]$detBP.dataRoot }
}catch{}
$log=Join-Path $BootData 'boot-probe.log'
try{ $cjBP=(Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json); if($cjBP.paths.bootProbe -and $cjBP.paths.bootProbe -ne ''){ $log=[string]$cjBP.paths.bootProbe } }catch{}
$enc=New-Object Text.UTF8Encoding($false)
$miss=0
foreach($b in $boot){
  $ok=$false
  $extra=''
  if([string]$b.trigger -eq 'file'){
    $ok=(Test-Path ([string]$b.path))
    if(-not $ok){ $extra='（文件不在：'+$b.path+'）' }
  } else {
    $ok=(Test-Path (Join-Path $StartupDir ([string]$b.id)))
    if(-not $ok){ $extra='（Startup 文件夹无此文件）' }
  }
  if($ok){
    $line='[BOOT-OK] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' id='+$b.id+' 开机链文件在场（只读探活，未启停任何进程）'
  } else {
    $line='[BOOT-MISSING] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' id='+$b.id+' 缺失'+$extra+'（只读报缺，不自动创建）'
    $miss++
  }
  try{ [IO.File]::AppendAllText($log,($line+"`r`n"),$enc) }catch{}
  Write-Output $line
}
$sum='[BOOT-PROBE] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' 共 '+$boot.Count+' 条开机链，缺 '+$miss+' 条'
try{ [IO.File]::AppendAllText($log,($sum+"`r`n"),$enc) }catch{}
Write-Output $sum
exit $miss
