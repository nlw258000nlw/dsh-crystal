# crystal-provision.ps1 - §10.5 一句话重建演练：从零在沙箱重建 dsh-crystal 骨架并验收全绿
# 只写 $ProRoot\，不碰现网六件、不创建任务、不重启任何进程
$ErrorActionPreference='Continue'
$ProRoot=Join-Path $env:LOCALAPPDATA '_crystal-sandbox\provision'
$RunDir=Join-Path $ProRoot ('run-'+$(Get-Date -Format 'yyyyMMdd-HHmmss'))
$PluginSrc=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$Build=Join-Path $PluginSrc 'scripts\crystal-build.ps1'
$Doctor=Join-Path $PluginSrc 'scripts\doctor.ps1'
$Enc=New-Object Text.UTF8Encoding($false)
$Log=Join-Path $RunDir 'provision.log'
function LogP([string]$s){
  $t=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  [IO.File]::AppendAllText($Log,("[PROVISION] "+$t+' '+$s+"`r`n"),$Enc)
  Write-Output ('[PROVISION] '+$t+' '+$s)
}
# 1 骨架目录
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
foreach($d in @('dsh-crystal\scripts','dsh-crystal\data\crystal','rendered')){ New-Item -ItemType Directory -Force -Path (Join-Path $RunDir $d) | Out-Null }
LogP ('骨架目录已建：'+$RunDir)
# 2 crystal.json 拷贝（provision 副本，不写回）
Copy-Item (Join-Path $PluginSrc 'crystal.json') (Join-Path $RunDir 'dsh-crystal\crystal.json') -Force
LogP ('crystal.json 拷贝完成（'+((Get-Item (Join-Path $RunDir 'dsh-crystal\crystal.json')).Length)+'B）')
# 3 生成物：六草稿+mirror 进沙箱 rendered
$rOut=Join-Path $RunDir 'rendered'
$null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Build -Render -OutDir $rOut 2>&1 | Out-String
$made=@(Get-ChildItem $rOut -File -ErrorAction SilentlyContinue)
LogP ('生成物：'+$made.Count+' 件（build exit='+$LASTEXITCODE+'）')
# 4 任务演练：只查询四任务在场，不创建
foreach($tn in @('CrystalL0-Stamp','CrystalDaily-Doctor','CrystalDaily-Scan','CrystalKillSwitch')){
  schtasks /Query /TN $tn 2>$null | Out-Null
  LogP ('任务 '+$tn+' 在场='+($LASTEXITCODE -eq 0)+'（只查询不装）')
}
# 5 doctor 真机只读验收
$dout=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Doctor 2>&1 | Out-String
$lines=@($dout -split "`r?`n" | Where-Object { $_.Trim() })
$sum=($lines | Where-Object { $_ -match '未解决红' } | Select-Object -Last 1) -replace 'doctor: ',''
$pricing=($lines | Where-Object { $_ -match 'PRICING' } | Select-Object -Last 1) -replace 'doctor: ',''
$ok=($LASTEXITCODE -eq 0)
LogP ('doctor exit='+$LASTEXITCODE+' 摘要：'+$sum+' | '+$pricing)
# 6 验收判定
$verdict=if($ok){'全绿 PASS'}else{'有红 FAIL'}
LogP ('provision 验收：'+$verdict)
Write-Output ('provision done: '+$verdict+' -> '+$RunDir)
if($ok){ exit 0 } else { exit 1 }
