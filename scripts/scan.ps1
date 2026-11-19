param([switch]$Quiet)
$ErrorActionPreference='SilentlyContinue'
$PkgRoot=Split-Path -Parent $PSScriptRoot
$ScanDir=$Env:CRYSTAL_HOME
if(-not $ScanDir){ try{ $cjSc=Get-Content (Join-Path $PkgRoot 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($cjSc.paths.crystalHome){ $ScanDir=[string]$cjSc.paths.crystalHome } }catch{} }
if(-not $ScanDir){ $ScanDir='F:\crystal' }
$Log=Join-Path $ScanDir 'data\daily-scan.log'
$State=Join-Path $ScanDir 'data\scan-state.json'
$CrystalData=Join-Path $PkgRoot 'data\crystal'
$Truth=Join-Path $CrystalData 'truth.json'
$Faults=Join-Path $CrystalData 'fault-dictionary.json'
$Heart=Join-Path $CrystalData 'heartbeat.txt'
# P6 完美化：心跳路径统一读 crystal.json paths.heartbeat（缺键回落旧路径）
try{ $cjSc=(Get-Content (Join-Path $PkgRoot 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json); if($null -ne $cjSc.paths.heartbeat -and $cjSc.paths.heartbeat -ne ''){ $Heart=[string]$cjSc.paths.heartbeat } }catch{}
$AlertsLog=Join-Path $CrystalData 'alerts.log'
$Cfg1=Join-Path $ScanDir 'conf\lock1-selfstop.json'
$Cfg2=Join-Path ($ScanDir+'-kill') 'conf\lock2-kill.json'
$Cfg3=Join-Path ($ScanDir+'-l0') 'conf\lock3-fallback.json'
$St1=Join-Path $CrystalData 'doctor-state.json'
$St2=Join-Path ($ScanDir+'-kill') 'kill-state.json'
$St3=Join-Path ($ScanDir+'-l0') 'l0-state.json'
$DrillLog=Join-Path ($ScanDir+'-drill') 'drill.log'
function Read-Json($p){ if([IO.Directory]::Exists($p)){return $null}; try{$raw=[IO.File]::ReadAllBytes($p)}catch{return $null}; if($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF){return $null}; try{ return ([Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json) }catch{ return $null } }
$script:ok=0; $script:warn=0; $script:fail=0; $script:worst='无'
function Add([string]$kind,[string]$name,[string]$note){
  if($kind -eq 'fail'){ $script:fail++; if($script:worst -eq '无'){ $script:worst=$name } }
  elseif($kind -eq 'warn'){ $script:warn++ } else { $script:ok++ }
  if($kind -ne 'ok'){ Write-Output ("  ["+$kind+"] "+$name+' '+$note) }
}
if(Test-Path $Truth){ $b=[IO.File]::ReadAllBytes($Truth); if($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF){ Add 'fail' 'truth.json' ('首字节='+$b[0]+','+$b[1]+','+$b[2]+'（带 BOM）') } elseif($b.Length -ge 1 -and $b[0] -eq 123){ Add 'ok' 'truth.json' '首字节 123' } else { Add 'fail' 'truth.json' ('首字节='+$b[0]) } } else { Add 'fail' 'truth.json' '文件缺失' }
if(Test-Path $Faults){ $b=[IO.File]::ReadAllBytes($Faults); if($b.Length -ge 1 -and $b[0] -eq 123){ Add 'ok' 'fault-dictionary.json' '首字节 123' } else { Add 'fail' 'fault-dictionary.json' ('首字节='+$b[0]) } } else { Add 'fail' 'fault-dictionary.json' '文件缺失' }
foreach($p in @($Cfg1,$Cfg2,$Cfg3)){ $o=Read-Json $p; if($null -eq $o){ Add 'warn' (Split-Path $p -Leaf) '配置不可读（各锁用默认值继续）' } else { Add 'ok' (Split-Path $p -Leaf) '可读' } }
foreach($t in @('CrystalL0-Stamp','CrystalDaily-Doctor','CrystalKillSwitch','CrystalDaily-Scan')){ schtasks /Query /TN $t 2>$null | Out-Null; if($LASTEXITCODE -eq 0){ Add 'ok' ('任务 '+$t) '在' } else { Add 'warn' ('任务 '+$t) '不在' } }
$gui=0; $to=Read-Json $Truth; if($null -ne $to -and $null -ne $to.health -and $null -ne $to.health.guiPort){ $gui=[int]$to.health.guiPort }
if($gui -gt 0){ $c=Test-NetConnection -ComputerName 127.0.0.1 -Port $gui -InformationLevel Quiet -WarningAction SilentlyContinue; if($c){ Add 'ok' ('端口 '+$gui) '在听' } else { Add 'warn' ('端口 '+$gui) '没探到' } } else { Add 'warn' 'guiPort' '表里没有端口' }
$c=Test-NetConnection -ComputerName 127.0.0.1 -Port 3000 -InformationLevel Quiet -WarningAction SilentlyContinue; if($c){ Add 'ok' 'OneBot 3000' '在听' } else { Add 'warn' 'OneBot 3000' '不通' }
if(Test-Path $Heart){ $age=((Get-Date)-(Get-Item $Heart).LastWriteTime).TotalMinutes; if($age -gt 30){ Add 'warn' 'heartbeat' ('超时 '+[int]$age+' 分钟') } else { Add 'ok' 'heartbeat' ([int]$age.ToString()+' 分钟前') } } else { Add 'warn' 'heartbeat' '无文件' }
$lastScan=$null; $st0=Read-Json $State; if($null -ne $st0 -and $st0.lastScanAt){ $lastScan=[datetime]::Parse($st0.lastScanAt) }
$newRed=0
if(Test-Path $AlertsLog){ $lines=[IO.File]::ReadAllLines($AlertsLog,[Text.Encoding]::UTF8); foreach($l in $lines){ if($l -like '[RED]*'){ $ts=$l.Substring(6,23); $d=[datetime]::ParseExact($ts,'yyyy-MM-dd HH:mm:ss.fff',$null); if($null -eq $lastScan -or $d -gt $lastScan){ $newRed++ } } } }
if($newRed -gt 0){ Add 'warn' 'alerts 新红行' ([string]$newRed) } else { Add 'ok' 'alerts 新红行' '0' }
$drive=$Env:SystemDrive+'\'
$free=(Get-PSDrive -Name ($drive.Substring(0,1)) -ErrorAction SilentlyContinue).Free
if($null -ne $free -and $free -gt 2GB){ Add 'ok' '盘剩余' ([string][int]($free/1GB)+'GB') } else { Add 'warn' '盘剩余' '<2GB 或未知' }
$def1=3600; $def2=360; $def3=64800
$c1=Read-Json $Cfg1; if($null -ne $c1 -and $null -ne $c1.staleTimes -and $null -ne $c1.staleTimes.selfstop){ $def1=[int]$c1.staleTimes.selfstop }
$c2=Read-Json $Cfg2; if($null -ne $c2 -and $null -ne $c2.staleTimes -and $null -ne $c2.staleTimes.kill){ $def2=[int]$c2.staleTimes.kill }
$c3=Read-Json $Cfg3; if($null -ne $c3 -and $null -ne $c3.staleTimes -and $null -ne $c3.staleTimes.l0){ $def3=[int]$c3.staleTimes.l0 }
foreach($pair in @(@('锁一 doctor',$St1,$def1),@('锁二 kill',$St2,$def2),@('锁三 L0',$St3,$def3))){
  $nm=$pair[0]; $sf=$pair[1]; $thr=$pair[2]; $s=Read-Json $sf
  if($null -eq $s -or $null -eq $s.lastChecked){ Add 'warn' $nm 'state.json 缺失' }
  else { $age=((Get-Date)-[datetime]::Parse($s.lastChecked)).TotalSeconds; if($age -gt $thr){ Add 'warn' ($nm+' 哑了') ('[SUSPECT-DEAD] lastChecked '+[int]($age/60)+' 分钟前 > 阈值 '+$thr+'s') } else { Add 'ok' $nm ([int]($age/60).ToString()+' 分钟前') } }
}
if(Test-Path $DrillLog){ $da=((Get-Date)-(Get-Item $DrillLog).LastWriteTime).TotalHours; if($da -gt 72){ Add 'warn' '演练' ('很久没演练：'+[int]$da+' 小时') } else { Add 'ok' '演练' ([int]$da.ToString()+' 小时前') } } else { Add 'warn' '演练' '从未演练（drill.log 缺失）' }
try{
  . (Join-Path $PSScriptRoot 'crystal-pricing.ps1')
  $pi=Get-CrystalPricing
  $pline='[PRICING] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' tier='+$pi.tier+' 当前='+$pi.label+' 下一窗口='+$pi.nextLabel+' '+$pi.nextMinutes+' 分钟'
  if($pi.fallback){ $pline+=' [CONF-FALLBACK]' }
  try{ [IO.File]::AppendAllText($Log,($pline+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  if(-not $Quiet){ Write-Output $pline }
}catch{
  try{ [IO.File]::AppendAllText($Log,('[PRICING-ERR] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' '+$_.Exception.Message+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
}
# ---- budget（§41 额度告警：只喊不拦） ----
try{
  $bCfg=$null
  $cjS=Get-Content (Join-Path $PkgRoot 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $cjS.checks -and $null -ne $cjS.checks.budget){ $bCfg=$cjS.checks.budget }
  $warnTokS=1000000
  if($null -ne $bCfg){ try{ $warnTokS=[int]$bCfg.warnTokensDaily }catch{} }
  $usageFileS=Join-Path $ScanDir 'data\usage.jsonl'
  try{ $cjSc2=(Get-Content (Join-Path $PkgRoot 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json); if($null -ne $cjSc2.paths.usage -and $cjSc2.paths.usage -ne ''){ $usageFileS=[string]$cjSc2.paths.usage } }catch{}
  if($null -ne $cjS.paths -and $null -ne $cjS.paths.usage -and $cjS.paths.usage -ne ''){ $usageFileS=[string]$cjS.paths.usage }
  $todayKeyS=(Get-Date -Format 'yyyy-MM-dd')
  $todayTokS=0
  foreach($ul in [IO.File]::ReadAllLines($usageFileS)){
    if($ul -notmatch '\{'){ continue }
    try{
      $uo=$ul | ConvertFrom-Json
      $lt=([datetime]::Parse([string]$uo.ts)).ToLocalTime().ToString('yyyy-MM-dd')
      if($lt -eq $todayKeyS){ $todayTokS+=[int64]$uo.inputTokens+[int64]$uo.outputTokens }
    }catch{}
  }
  $bl='[BUDGET-OK] '+$todayKeyS+' 当日累计 '+$todayTokS+' tokens（阈值 '+$warnTokS+'）'
  if($todayTokS -gt $warnTokS){ $bl='[BUDGET-WARN] '+$todayKeyS+' 当日累计 '+$todayTokS+' tokens 超阈值 '+$warnTokS+'，只喊不拦' }
  try{ [IO.File]::AppendAllText($Log,($bl+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  if(-not $Quiet){ Write-Output $bl }
}catch{}
# 已读凭证快照（§24）
try{
  $rp=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-receipts.ps1') 2>&1 | Out-String
  try{ [IO.File]::AppendAllText($Log,($rp.Trim()+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
}catch{}
# P7 每日体检日报（只落盘不推送；手动推送=crystal daily push）
try{
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-daily.ps1') -Quiet -Push 2>&1 | Out-Null
}catch{}
$line='[DAILY-SCAN] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' ok='+$script:ok+' warn='+$script:warn+' fail='+$script:fail+' 最差项='+$script:worst
try{ [IO.File]::AppendAllText($Log,$line+"`r`n",(New-Object Text.UTF8Encoding($false))) }catch{}
try{ [IO.File]::WriteAllText($State,('{"lastScanAt":"'+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+'"}'),(New-Object Text.UTF8Encoding($false))) }catch{}
Write-Output $line
if($script:fail -gt 0){ exit 2 } elseif($script:warn -gt 0){ exit 1 } else { exit 0 }