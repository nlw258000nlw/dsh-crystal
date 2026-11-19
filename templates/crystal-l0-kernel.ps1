param([string]$Mode='Stamp', [switch]$Install)
$ErrorActionPreference='SilentlyContinue'
$L0Dir='<CRYSTAL_HOME>-l0'
$L0Log=Join-Path $L0Dir 'l0.log'
$StatusFile=Join-Path ([Environment]::GetFolderPath('Desktop')) '结晶状态.txt'
$CrystalData='<PLUGIN_HOME>\data\crystal'
$Heart='<CRYSTAL_HOME>\data\heartbeat.json'
$HeartTxt=Join-Path $CrystalData 'heartbeat.txt'
$Stamps=Join-Path $CrystalData 'stamps'
$Alerts=Join-Path $CrystalData 'alerts.log'
$Doctor='<PLUGIN_HOME>\scripts\doctor.ps1'
function Log0([string]$line){
  [IO.File]::AppendAllText($L0Log,('[L0] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' '+$line+"`r`n"),(New-Object Text.UTF8Encoding($false)))
}
$Cfg3=@{ heartbeatStaleMin=30; minRules='chat:称呼脑公|短句口语|低档思考; work:改前备份|改后留痕|花销先说|干活档不许拦' }
$Cfg3Path=Join-Path $L0Dir 'conf\lock3-fallback.json'
try{
  $raw=[IO.File]::ReadAllBytes($Cfg3Path)
  if($raw.Length -ge 3 -and $raw[0]-eq 0xEF -and $raw[1]-eq 0xBB -and $raw[2]-eq 0xBF){ throw 'lock3 配置带 BOM' }
  $o=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json
  if($null -eq $o){ throw 'null' }
  if([int]$o.schemaVersion -ne 1){ Log0 ('[RED] module=l0 fault=conf-version msg=[CONF-VERSION-MISMATCH] 锁3 配置 schemaVersion='+$o.schemaVersion+'（当前支持 1），拒绝启动'); Write-Output ('l0: [CONF-VERSION-MISMATCH] lock=3 schema='+$o.schemaVersion); exit 7 }
  if($null -ne $o.heartbeatStaleMin){ $Cfg3.heartbeatStaleMin=[int]$o.heartbeatStaleMin }
  if($null -ne $o.minRules -and $o.minRules -ne ''){ $Cfg3.minRules=[string]$o.minRules }
  $tL=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  Log0 ('[CONF-LOAD] '+$tL+' lock=3 source=conf path='+$Cfg3Path+' schema='+$o.schemaVersion+' at='+$tL)
  if($null -ne $o.logPath -and $o.logPath -ne ''){ $L0Log=[string]$o.logPath }
  else{
    $fbLib=Join-Path $CrystalData '..\..\scripts\crystal-fallback.ps1'
    $fbOk=$false
    if(Test-Path $fbLib){ try{ . $fbLib; $fbOk=$true }catch{} }
    if($fbOk -and (Get-Command Write-CrystalFallback -ErrorAction SilentlyContinue)){ try{ Write-CrystalFallback -Module 'l0-logpath' -Reason 'logPath 字段缺失' -FallbackTo $L0Log | Out-Null }catch{} }
    else{ Log0 ('[FALLBACK] lock3 conf 无 logPath 字段，退到默认路径 '+$L0Log) }
  }
}catch{
  Log0 ('[CONF-FALLBACK] 锁3 配置不可用：'+$_.Exception.Message+'，已用默认值')
  $tL=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  Log0 ('[CONF-LOAD] '+$tL+' lock=3 source=default path='+$Cfg3Path+' schema=default at='+$tL)
  $fbLib2=Join-Path $CrystalData '..\..\scripts\crystal-fallback.ps1'
  if(Test-Path $fbLib2){ try{ . $fbLib2 }catch{} }
  if(Get-Command Write-CrystalFallback -ErrorAction SilentlyContinue){ try{ Write-CrystalFallback -Module 'l0-conf' -Reason ('配置不可用：'+$_.Exception.Message) -FallbackTo ('默认值+默认日志 '+$L0Log) | Out-Null }catch{} }
  else{ Log0 ('[FALLBACK] lock3 配置不可用，退默认值（fallbacks 库不可用，只留本日志）') }
}
if($Install){
  schtasks /Create /TN CrystalL0-Stamp /SC HOURLY /MO 6 /TR ("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $L0Dir 'crystal-l0.ps1') + "`" -Mode Stamp") /F | Out-Null
  schtasks /Create /TN CrystalDaily-Doctor /SC DAILY /ST 08:10 /TR ("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + $Doctor + "`"") /F | Out-Null
  Log0 ('install：两个任务已建/刷新')
  exit 0
}
if($Mode -eq 'Stamp'){
  if(-not (Test-Path $Stamps)){ New-Item -ItemType Directory -Force -Path $Stamps | Out-Null }
  $file=Join-Path $Stamps ((Get-Date -Format 'yyyyMMdd') + '.jsonl')
  $line='{"ts":"' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz') + '","by":"L0"}'
  [IO.File]::AppendAllText($file, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
  Log0 ('stamp：'+$file)
}
$status='正常'
$hbF=$Heart
if(-not (Test-Path $hbF) -and (Test-Path $HeartTxt)){ $hbF=$HeartTxt }
if(-not (Test-Path $hbF)){
  Log0 '接管：crystal 停了（无心跳文件）'
  try{ [IO.File]::AppendAllText($Alerts,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=l0 fault=heartbeat msg=crystal 停了（无心跳文件），锁三兜底'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  $status='停了（无心跳文件）'
} else {
  $age=((Get-Date)-(Get-Item $hbF).LastWriteTime).TotalMinutes
  if($age -gt $Cfg3.heartbeatStaleMin){
    Log0 ('接管：crystal 停了（心跳超时 '+[int]$age+' 分钟）')
    try{ [IO.File]::AppendAllText($Alerts,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=l0 fault=heartbeat msg=crystal 停了（心跳超时 '+[int]$age+' 分钟），锁三兜底'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
    $status='停了（心跳超时 '+[int]$age+' 分钟）'
  } else {
    Log0 ('正常：心跳 '+[int]$age+' 分钟前')
  }
}
$txt='crystal='+$status+'; 重启=跑 doctor.ps1 刷新心跳; 急救=双击 停结晶.cmd; 恢复=删 <CRYSTAL_HOME>-kill\kill 再跑 doctor'
try{ [IO.File]::WriteAllText($StatusFile,$txt,(New-Object Text.UTF8Encoding($false))) }catch{}
Log0 ('状态文件已写：'+$status)
$L0State=Join-Path $L0Dir 'l0-state.json'
$now0=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
$st0=@{lastChecked=$now0}
if(Test-Path $L0State){ try{ $old0=Get-Content $L0State -Raw | ConvertFrom-Json; if($null -ne $old0){ $st0.lastRedAt=$old0.lastRedAt; $st0.lastGreenAt=$old0.lastGreenAt } }catch{} }
if($status -like '停了*'){ $st0.lastRedAt=$now0 } else { $st0.lastGreenAt=$now0 }
try{ [IO.File]::WriteAllText($L0State,($st0 | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false))) }catch{}
exit 0
