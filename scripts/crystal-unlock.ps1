# crystal-unlock.ps1 - 解冻只认人工口令（CR-005）。口令比对 data\crystal\unlock.hash（SHA256），口令本身不落任何文件。
# 用法：crystal-unlock.ps1 -Fault <id> -Pass <口令>；无 -Pass 或口令错 → 拒绝并写 alerts.log 一行；成功清 frozen 三字段并写解冻痕。
param([string]$Fault='',[string]$Pass='')
$ErrorActionPreference='Stop'
$Base=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$Data=Join-Path $Base 'data\crystal'
$Faults=Join-Path $Data 'fault-dictionary.json'
$Alerts=Join-Path $Data 'alerts.log'
$Hash=Join-Path $Data 'unlock.hash'
function Log-A([string]$level,[string]$msg){
  [IO.File]::AppendAllText($Alerts, ("["+$level+"] "+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' '+$msg+"`r`n"), (New-Object Text.UTF8Encoding($false)))
}
if($Fault -eq ''){ Log-A 'RED' 'unlock 拒绝：未指定 -Fault'; Write-Output 'refused: no fault'; exit 1 }
if($Pass -eq ''){ Log-A 'RED' ('unlock 拒绝：fault='+$Fault+' 未提供 -Pass'); Write-Output 'refused: no pass'; exit 1 }
if(-not (Test-Path $Hash)){ Log-A 'RED' ('unlock 拒绝：fault='+$Fault+' 口令文件不存在'); Write-Output 'refused: no hash file'; exit 1 }
$expect=(Get-Content $Hash -Raw).Trim()
$sha=[Security.Cryptography.SHA256]::Create()
$given=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Pass)))).Replace('-','')
if($given.ToUpper() -ne $expect.ToUpper()){
  Log-A 'RED' ('unlock 拒绝：fault='+$Fault+' 口令错误'); Write-Output 'refused: wrong pass'; exit 1
}
$f=Get-Content $Faults -Raw -Encoding UTF8 | ConvertFrom-Json
$hit=$null
foreach($x in $f.faults){ if($x.id -eq $Fault){ $hit=$x } }
if($null -eq $hit){ Log-A 'YELLOW' ('unlock：fault='+$Fault+' 不存在'); Write-Output 'no such fault'; exit 1 }
if(-not $hit.frozen){ Log-A 'YELLOW' ('unlock：fault='+$Fault+' 本来就没冻结'); Write-Output 'not frozen'; exit 0 }
foreach($x in $f.faults){ if($x.id -eq $Fault){ $x.frozen=$false; $x.frozenAt=''; $x.frozenReason='' } }
$txt=($f | ConvertTo-Json -Depth 10)
$tmp=$Faults+'.tmp'
[IO.File]::WriteAllText($tmp,$txt,(New-Object Text.UTF8Encoding($false)))
Move-Item -Force $tmp $Faults
Log-A 'GREEN' ('unlock 成功：fault='+$Fault+' 人工解冻，由 human 执行，已清 frozen 三字段')
Write-Output ('unlocked: '+$Fault)
exit 0