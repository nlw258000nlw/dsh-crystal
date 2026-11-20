# doctor.ps1 - dsh-crystal P0 体检（段二版）
# 用法：默认只读体检；-Auto 允许修复 kind=auto 且未 frozen 的故障；-Fake bom|port|snowluma|stamp 只演示判定不落盘；-Quiet 只写日志不打印。
# 判据：GUI 端口 = GET /api/__probe__ 回 401 且正文纯文本含 unauthorized；OneBot = 127.0.0.1:3000。
# 规矩：同一故障只修一次，失败立即冻结（frozen）此后只诊断不修；修好也报一行。
param([string]$Fake='', [switch]$Auto, [switch]$Quiet, [switch]$PushQQ, [string]$PricingNow='')
$ErrorActionPreference='Stop'

$Base=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
# [fix-20261120-P7] 去本机化：缺省路径一律先读 data\detected.json（detect.ps1 产出），再回落本机习惯
$DetObj=$null
try{ $DetFile=Join-Path $Base 'data\detected.json'; if(Test-Path $DetFile){ $DetObj=Get-Content $DetFile -Raw -Encoding UTF8 | ConvertFrom-Json } }catch{}
$DetHome=Join-Path $env:LOCALAPPDATA 'crystal'
$DetKill=Join-Path $DetHome 'kill'
$DetL0=Join-Path $DetHome 'l0'
$DetBridge=''
$DetMaint=''
$DetUser=$env:USERPROFILE
$DetBackup=Join-Path $DetHome 'backup'
# 习惯路径兜底：探测常见安装位（跨机通用）
foreach($cand in @('F','D','C','E')){ $p=$cand+':\qq-dsh-bridge\qq-bridge'; if(Test-Path (Join-Path $p 'src\bridge.js')){ $DetBridge=$p; break } }
foreach($cand in @('F','D','C','E')){ $p=$cand+':\系统维护'; if(Test-Path $p){ $DetMaint=$p; break } }
if($DetObj){
  if($DetObj.crystalHome){ $DetHome=[string]$DetObj.crystalHome }
  if($DetObj.killRoot){ $DetKill=[string]$DetObj.killRoot }
  if($DetObj.l0Root){ $DetL0=[string]$DetObj.l0Root }
  if($DetObj.bridgeHome){ $DetBridge=[string]$DetObj.bridgeHome }
  if($DetObj.maintHome){ $DetMaint=[string]$DetObj.maintHome }
  if($DetObj.userHome){ $DetUser=[string]$DetObj.userHome }
  if($DetObj.backupRoot){ $DetBackup=[string]$DetObj.backupRoot }
}
$Data=Join-Path $Base 'data\crystal'
$Truth=Join-Path $Data 'truth.json'
$Faults=Join-Path $Data 'fault-dictionary.json'
$Alerts=''
$Errors=Join-Path $Data 'errors.log'
$Stamps=Join-Path $Data 'stamps'
try{ $cjSp=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjSp.paths -and $null -ne $cjSp.paths.stamps -and $cjSp.paths.stamps -ne ''){ $Stamps=[string]$cjSp.paths.stamps } }catch{}
$Snap=Join-Path $Data 'snapshots'
$Heart=Join-Path $DetHome 'data\heartbeat.json'
try{ $cjhb=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjhb.paths -and $null -ne $cjhb.paths.heartbeat -and $cjhb.paths.heartbeat -ne ''){ $Heart=[string]$cjhb.paths.heartbeat } }catch{}
$Fallback=Join-Path $Base 'data\fallback.json'
$Intercepts=Join-Path $DetHome 'data\intercepts.jsonl'
try{ $cjIc=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjIc.paths.intercepts -and $cjIc.paths.intercepts -ne ''){ $Intercepts=[string]$cjIc.paths.intercepts } }catch{}
function Add-ErrorLine([string]$text){
  try{
    $encE=New-Object Text.UTF8Encoding($false)
    if((Test-Path $Errors) -and ((Get-Item $Errors).Length -gt 1048576)){
      if(Test-Path ($Errors+'.1')){ Remove-Item ($Errors+'.1') -Force -ErrorAction SilentlyContinue }
      Move-Item $Errors ($Errors+'.1') -Force -ErrorAction SilentlyContinue
    }
    [IO.File]::AppendAllText($Errors,($text+"`r`n"),$encE)
  }catch{}
}
# —— CR-008 A 平价/高峰排期（P1）——
$PricingLib=Join-Path $Base 'scripts\crystal-pricing.ps1'
$QueueFile=Join-Path $DetHome 'data\queue.json'
$UsageFile=Join-Path $DetHome 'data\usage.log'
if(Test-Path $PricingLib){ try{ . $PricingLib }catch{} }
$FallbackLib=Join-Path $Base 'scripts\crystal-fallback.ps1'
if(Test-Path $FallbackLib){
  try{ . $FallbackLib }catch{
    try{ [IO.File]::AppendAllText($Alerts,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=fallback-lib msg=[FALLBACK-LIB-BROKEN] 兜底库加载失败：'+$_.Exception.Message+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
    Write-Output ('doctor: [FALLBACK-LIB-BROKEN] '+$_.Exception.Message)
  }
}else{
  try{ [IO.File]::AppendAllText($Alerts,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=fallback-lib msg=[FALLBACK-LIB-BROKEN] 兜底库缺失：'+$FallbackLib+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  Write-Output ('doctor: [FALLBACK-LIB-BROKEN] 缺失 '+$FallbackLib)
}

$script:lines=@()
$script:redCount=0; $script:yellowCount=0; $script:greenCount=0; $script:grayCount=0
$script:faultLevels=@{}

$KillFile=Join-Path $DetKill 'kill'
$KillBlock=Join-Path $Data 'kill-blocked'
$Runs=Join-Path $Data 'fault-runs.json'
$StartT=Get-Date
$DocState=Join-Path $Data 'doctor-state.json'
$script:lastRedAt=$null
if(Test-Path $DocState){ try{ $oldDoc=Get-Content $DocState -Raw | ConvertFrom-Json; if($null -ne $oldDoc -and $null -ne $oldDoc.lastRedAt -and $oldDoc.lastRedAt -ne ''){ $script:lastRedAt=[string]$oldDoc.lastRedAt } }catch{} }
$script:lastRedDisplay=if($null -eq $script:lastRedAt){'从未'}else{$script:lastRedAt}
$Cfg1=@{ timeoutSec=120; maxSameFault=3 }
$Cfg1Path=Join-Path $DetHome 'conf\lock1-selfstop.json'
try{
  $raw=[IO.File]::ReadAllBytes($Cfg1Path)
  if($raw.Length -ge 3 -and $raw[0]-eq 0xEF -and $raw[1]-eq 0xBB -and $raw[2]-eq 0xBF){ throw 'lock1 配置带 BOM' }
  $o=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json
  if($null -eq $o){ throw 'null' }
  if([int]$o.schemaVersion -ne 1){ try{ [IO.File]::AppendAllText($Alerts,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=conf-version msg=[CONF-VERSION-MISMATCH] 锁1 配置 schemaVersion='+$o.schemaVersion+'（当前支持 1），拒绝启动'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}; Write-Output ('doctor: [CONF-VERSION-MISMATCH] lock=1 schema='+$o.schemaVersion); exit 7 }
  if($null -ne $o.timeoutSec){ $Cfg1.timeoutSec=[int]$o.timeoutSec }
  if($null -ne $o.maxSameFault){ $Cfg1.maxSameFault=[int]$o.maxSameFault }
  if($null -ne $o.logPath -and $o.logPath -ne ''){ $script:confLogPath1=[string]$o.logPath; $Alerts=[string]$o.logPath }
  else{ $Alerts=Join-Path $Data 'alerts.log'; try{ if(Get-Command Write-CrystalFallback -ErrorAction SilentlyContinue){ Write-CrystalFallback -Module 'lock1-logpath' -Reason 'logPath 字段缺失' -FallbackTo $Alerts | Out-Null } }catch{}; $lineEarly='[YELLOW] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=lock1-logpath msg=lock1 conf 无 logPath 字段，退到默认路径 '+$Alerts; try{ [IO.File]::AppendAllText($Alerts,$lineEarly+"`r`n",(New-Object Text.UTF8Encoding($false))) }catch{}; $script:lines+=,$lineEarly; $script:faultLevels['lock1-logpath']='YELLOW' }
  $tL1=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  try{ [IO.File]::AppendAllText($Alerts,('[CONF-LOAD] '+$tL1+' lock=1 source=conf path='+$Cfg1Path+' schema='+$o.schemaVersion+' at='+$tL1+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
}catch{
  if($Alerts -eq ''){ $Alerts=Join-Path $Data 'alerts.log' }
  $lineEarly='[YELLOW] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=lock1-conf msg=lock1 配置不可用，退默认值：'+$_.Exception.Message
  try{ [IO.File]::AppendAllText($Alerts,$lineEarly+"`r`n",(New-Object Text.UTF8Encoding($false))) }catch{}
  $script:lines+=,$lineEarly
  $script:faultLevels['lock1-conf']='YELLOW'
  try{ [IO.File]::AppendAllText($Alerts,('[YELLOW] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=conf-lock1 msg=[CONF-FALLBACK] 锁1 配置不可用：'+$_.Exception.Message+'，已用默认值（timeoutSec=120 maxSameFault=3）'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  $tL1=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  try{ [IO.File]::AppendAllText($Alerts,('[CONF-LOAD] '+$tL1+' lock=1 source=default path='+$Cfg1Path+' schema=default at='+$tL1+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  try{ if(Get-Command Write-CrystalFallback -ErrorAction SilentlyContinue){ Write-CrystalFallback -Module 'doctor-lock1-conf' -Reason $_.Exception.Message -FallbackTo '默认值(timeoutSec=120 maxSameFault=3)' | Out-Null } }catch{}
}

# 总表派生路径（P12② 配置化：数据/外设路径一律从 crystal.json paths 读，缺键回落本机默认）
$CrystalHome=$DetHome
$DataHome=Join-Path $DetHome 'data'
$KillRoot=$DetKill
$L0Root=$DetL0
$BridgeHome=$DetBridge
$TogglesFile=Join-Path $DataHome 'plugin-toggles.json'
$PushState=Join-Path $DataHome 'alert-push-state.json'
$ConsoleTok=Join-Path $DetBridge 'state\console-token'
$ProfilePkg=Join-Path $DetUser '.dsh\profiles\desktop\package.json'
$SandboxHome=Join-Path $env:LOCALAPPDATA '_crystal-sandbox'
foreach($cand in @('F','D','C')){ $p=$cand+':\_crystal-sandbox'; if(Test-Path $p){ $SandboxHome=$p; break } }
$SysHome=$DetMaint
$BaselineF=Join-Path $DataHome 'render-baseline.json'
$UsageF=Join-Path $DataHome 'usage.jsonl'
$CostF=Join-Path $DataHome 'cost.jsonl'
$BStateF=Join-Path $DataHome 'budget-push-state.json'
$RcMirror=Join-Path $DataHome 'read-receipts.json'
$RcLog=Join-Path $DataHome 'read-receipts.jsonl'
$RestartGate=Join-Path $DetMaint '重启并接桥.ps1'
try{
  $cjP=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($cjP.paths.crystalHome){ $CrystalHome=[string]$cjP.paths.crystalHome }
  if($cjP.paths.dataHome){ $DataHome=[string]$cjP.paths.dataHome }
  if($cjP.paths.toggles){ $TogglesFile=[string]$cjP.paths.toggles }
  if($cjP.paths.pushState){ $PushState=[string]$cjP.paths.pushState }
  if($cjP.paths.consoleToken){ $ConsoleTok=[string]$cjP.paths.consoleToken }
  if($cjP.paths.profileHome){ $ProfilePkg=Join-Path ([string]$cjP.paths.profileHome) 'package.json' }
  if($cjP.paths.sandbox){ $SandboxHome=[string]$cjP.paths.sandbox }
  if($cjP.paths.sysHome){ $SysHome=[string]$cjP.paths.sysHome; $RestartGate=Join-Path $SysHome '重启并接桥.ps1' }
  if($cjP.paths.killRoot){ $KillRoot=[string]$cjP.paths.killRoot; $KillFile=Join-Path $KillRoot 'kill' }
  if($cjP.paths.l0Root){ $L0Root=[string]$cjP.paths.l0Root }
  if($cjP.paths.baseline){ $BaselineF=[string]$cjP.paths.baseline } elseif($DataHome){ $BaselineF=Join-Path $DataHome 'render-baseline.json' }
  if($cjP.paths.usage){ $UsageF=[string]$cjP.paths.usage }
  if($cjP.paths.cost){ $CostF=[string]$cjP.paths.cost }
  if($cjP.paths.budgetPush){ $BStateF=[string]$cjP.paths.budgetPush } elseif($DataHome){ $BStateF=Join-Path $DataHome 'budget-push-state.json' }
  if($cjP.paths.receipts){ $RcMirror=[string]$cjP.paths.receipts } elseif($DataHome){ $RcMirror=Join-Path $DataHome 'read-receipts.json' }
  if($cjP.paths.receiptLog){ $RcLog=[string]$cjP.paths.receiptLog } elseif($DataHome){ $RcLog=Join-Path $DataHome 'read-receipts.jsonl' }
}catch{}

# 锁一互斥：Global\crystal-lock 排队 90 秒，拿不到就跳过并留痕（§11）
$mu=New-Object Threading.Mutex($false,'Global\crystal-lock')
if(-not $mu.WaitOne(90000)){
  try{ [IO.File]::AppendAllText($Alerts,('[YELLOW] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=self fault=lock msg=排队 90 秒仍拿不到 Global\crystal-lock，本轮跳过（留痕）'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  Write-Output 'doctor: lock busy, skipped'
  exit 3
}
# 锁二停止开关检查：kill 文件在 → 拒绝干活；刚移除 → 写恢复痕
if(Test-Path $KillFile){
  if(-not(Test-Path $KillBlock)){ try{ [IO.File]::WriteAllText($KillBlock,'1',(New-Object Text.UTF8Encoding($false))) }catch{} }
  try{ [IO.File]::AppendAllText($Alerts,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=kill fault=kill-switch msg=结晶被停止开关拦住：'+$KillFile+' 存在，本轮拒绝运行，等待人工恢复（删 kill 文件）'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  Write-Output 'doctor: stopped by kill switch'
  exit 5
}
if(Test-Path $KillBlock){
  try{ [IO.File]::AppendAllText($Alerts,('[GREEN] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=kill fault=kill-switch msg=恢复：kill 文件已移除，crystal 恢复工作'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  try{ Remove-Item $KillBlock -Force }catch{}
}

# CR-008 B：三锁当前生效源 + truth.json activeConfig
$lockRows=@()
foreach($li in @(@{N='1';P=$Cfg1Path},@{N='2';P=(Join-Path $KillRoot 'conf\lock2-kill.json')},@{N='3';P=(Join-Path $L0Root 'conf\lock3-fallback.json')})){
  $src='default'; $sch='default'
  try{
    $rb=[IO.File]::ReadAllBytes($li.P)
    if(-not($rb.Length -ge 3 -and $rb[0]-eq 0xEF -and $rb[1]-eq 0xBB -and $rb[2]-eq 0xBF)){
      $oj=[Text.Encoding]::UTF8.GetString($rb) | ConvertFrom-Json
      if($null -ne $oj -and $null -ne $oj.schemaVersion){ $src='conf'; $sch=[string]$oj.schemaVersion }
    }
  }catch{}
  $lockRows += @{lock=('lock'+$li.N); source=$src; schema=$sch; path=$li.P; loadedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')}
}
$activeLine=('当前生效：'+((($lockRows | ForEach-Object { $_.lock+'='+$_.source+' v'+$_.schema }) -join ' / ')))
try{ [IO.File]::AppendAllText($Alerts,('[CONF-ACTIVE] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' '+$activeLine+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
Write-Output ('doctor: '+$activeLine)
try{
  $truthPath=Join-Path $Data 'truth.json'
  $traw=[IO.File]::ReadAllText($truthPath)
  $acJson=(@{locks=$lockRows; updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')} | ConvertTo-Json -Depth 6 -Compress)
  $traw=[regex]::Replace($traw,'(?s)"activeConfig"\s*:\s*\{.*?\},\s*(?=\r?\n\s*\})','')
  $traw=$traw.TrimEnd()
  if($traw.EndsWith('}')){
    $inner=$traw.Substring(0,$traw.Length-1).TrimEnd()
    if(-not $inner.EndsWith(',')){ $inner=$inner+',' }
    $traw=$inner+"`n  "+'"activeConfig": '+$acJson+"`n}"
    [IO.File]::WriteAllText($truthPath,$traw,(New-Object Text.UTF8Encoding($false)))
  }
}catch{ try{ [IO.File]::AppendAllText($Alerts,('[CONF-ACTIVE] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' truth.json activeConfig 写失败：'+$_.Exception.Message+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{} }

function Rotate-Log{
  if(Test-Path $Alerts){
    $len=(Get-Item $Alerts).Length
    if($len -gt 1MB){ $Alerts1=($Alerts -replace '\.log$','.1.log'); Copy-Item $Alerts $Alerts1 -Force; [IO.File]::WriteAllText($Alerts,'',(New-Object Text.UTF8Encoding($false))) }
  }
}
function Add-Line([string]$level,[string]$module,[string]$fault,[string]$msg){
  Rotate-Log
  $line='['+$level+'] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module='+$module+' fault='+$fault+' msg='+$msg+' 上次红：'+$script:lastRedDisplay
  $fl=Get-Fault $fault
  if($level -eq 'RED' -and $null -ne $fl -and $fl.loc){ $line+=(' loc='+[string]$fl.loc) }
  [IO.File]::AppendAllText($Alerts,$line+"`r`n",(New-Object Text.UTF8Encoding($false)))
  $script:lines+=,$line
  if($fault){ $script:faultLevels[$fault]=$level }
  switch($level){
    'RED'    { $script:redCount++ }
    'YELLOW' { $script:yellowCount++ }
    'GREEN'  { $script:greenCount++ }
    'GRAY'   { $script:grayCount++ }
  }
}
function Read-Json($p){
  if([IO.Directory]::Exists($p)){ return $null }
  try{ $raw=[IO.File]::ReadAllBytes($p) }catch{ return $null }
  if($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF){ return $null }
  $txt=[Text.Encoding]::UTF8.GetString($raw)
  try{ return ($txt | ConvertFrom-Json) }catch{ return $null }
}
function Write-Json($p,$obj){
  if([IO.Directory]::Exists($p)){ throw "目标路径是目录：$p" }
  $txt=($obj | ConvertTo-Json -Depth 10)
  $tmp=$p+'.tmp'
  [IO.File]::WriteAllText($tmp,$txt,(New-Object Text.UTF8Encoding($false)))
  try{ Move-Item -Force $tmp $p -ErrorAction Stop }catch{
    try{ [IO.File]::SetAttributes($p,[IO.FileAttributes]::Normal) }catch{}
    Move-Item -Force $tmp $p -ErrorAction Stop
  }
}
function Snap([string]$reason,[string]$state='red'){
  $ts=Get-Date -Format 'yyyyMMdd-HHmmss'
  $d=Join-Path $Snap $ts
  New-Item -ItemType Directory -Force $d | Out-Null
  foreach($f in @($Truth,$Faults,$Heart)){ if(Test-Path $f){ Copy-Item $f (Join-Path $d (Split-Path $f -Leaf)) -Force } }
  $note=@{state=$state;reason=$reason;time=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff');red=$script:redCount;yellow=$script:yellowCount;green=$script:greenCount;gray=$script:grayCount}
  [IO.File]::WriteAllText((Join-Path $d 'note.txt'),($note | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  $dirs=Get-ChildItem $Snap -Directory | Sort-Object Name -Descending
  if($dirs.Count -gt 10){ $dirs | Select-Object -Skip 10 | Remove-Item -Recurse -Force }
  return $d
}
function Get-Fault([string]$id){ foreach($f in $script:faultsObj.faults){ if($f.id -eq $id){ return $f } }; return $null }
function Is-Frozen($f){ return ($null -ne $f -and $f.frozen) }
function Set-Frozen([string]$id,[string]$reason){
  $rebuilt=@()
  foreach($f in $script:faultsObj.faults){
    if($f.id -eq $id){
      $new=[ordered]@{}
      foreach($prop in $f.PSObject.Properties){ $new[$prop.Name]=$prop.Value }
      $new['frozen']=$true
      $new['frozenAt']=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
      $new['frozenReason']=$reason
      $rebuilt+=,[pscustomobject]$new
    } else { $rebuilt+=,$f }
  }
  $script:faultsObj.faults=$rebuilt
  Write-Json $Faults $script:faultsObj
}
function Find-GuiPort([int]$prefer){
  $ports=@()
  if($prefer -gt 0){ $ports+=,$prefer }
  foreach($line in (netstat -ano 2>$null | Select-String -Pattern 'LISTENING')){
    foreach($part in ($line.ToString() -split '\s+')){
      if($part -match '^127\.0\.0\.1:(\d+)$'){ $ports+=,[int]$Matches[1] }
    }
  }
  $ports=$ports | Sort-Object -Unique | Select-Object -First 40
  foreach($p in $ports){
    if($p -le 0){ continue }
    $code=0; $body=''
    try{
      $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 1 ('http://127.0.0.1:{0}/api/__probe__' -f $p)
      $code=$r.StatusCode; $body=$r.Content
    }catch{
      $resp=$_.Exception.Response
      if($null -ne $resp){ $code=[int]$resp.StatusCode; try{ $sr=New-Object IO.StreamReader($resp.GetResponseStream()); $body=$sr.ReadToEnd(); $sr.Close() }catch{} }
    }
    if($code -eq 401 -and $body -match 'unauthorized'){ return $p }
  }
  return 0
}

try{
  $script:faultsObj=Read-Json $Faults
  if($null -eq $script:faultsObj){
    Add-Line 'RED' 'fault-dictionary.json' 'faults' 'fault-dictionary.json 带 BOM 或非法 JSON，体检无法进行'
    [IO.File]::WriteAllText($Heart,(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' doctor-fault',(New-Object Text.UTF8Encoding($false)))
    if(-not $Quiet){ Write-Output 'doctor: 1 未解决红 / 0 黄 / 0 绿 / 0 灰' }
    exit 2
  }

  # ---- bom-truth ----
  $truthErr=''; $script:truthObj=$null
  if($Fake -eq 'bom'){ $truthErr='truth.json 带 BOM（模拟）' } else { $script:truthObj=Read-Json $Truth; if($null -eq $script:truthObj){ $truthErr='truth.json 带 BOM 或非法 JSON' } }
  $f=Get-Fault 'bom-truth'
  if(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  elseif($truthErr -ne ''){
    $fixed=$false
    if($Auto -and $f.fix.kind -eq 'auto' -and $Fake -eq ''){
      try{
        Snap('bom-truth 修复前：'+$truthErr)
        $raw=[IO.File]::ReadAllBytes($Truth)
        $start=0
        if($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF){ $start=3 }
        $txt=[Text.Encoding]::UTF8.GetString($raw,$start,$raw.Length-$start)
        $obj=$txt | ConvertFrom-Json
        [IO.File]::WriteAllText($Truth,($obj | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
        $script:truthObj=Read-Json $Truth
        $fixed=($null -ne $script:truthObj)
      }catch{ $fixed=$false }
    }
    if($fixed){ Add-Line 'GREEN' $f.module $f.id '已自动修复，根因 id=bom-truth（去 BOM 重写，首字节回 123）' }
    else{
      Add-Line 'RED' 'truth.json' 'bom-truth' ('表不可用：'+$truthErr)
      if($Auto -and $Fake -eq '' -and $f.fix.kind -eq 'auto'){ Set-Frozen 'bom-truth' ('自动修复失败：'+$truthErr) }
    }
  } else { Add-Line 'GREEN' 'truth.json' 'bom-truth' 'truth.json 解析正常、无 BOM' }

  # ---- gui-port ----
  $f=Get-Fault 'gui-port'
  if(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  elseif($null -eq $script:truthObj){
    Add-Line 'RED' 'truth.health.guiPort' 'gui-port' '表不可用，无法核对 GUI 端口'
  } else {
    $cand=0
    try{ $cand=[int]$script:truthObj.health.guiPort }catch{ $cand=0 }
    if($Fake -eq 'port'){ $cand=59999 }
    $found=0
    $gpTries=0
    if($Fake -ne 'port'){
      $found=Find-GuiPort $cand
      if($found -le 0){
        # 探空短重试（DSH 忙/超时会让判据空回）：先 3 次×2 秒，仍空再来一轮 3 次×2 秒；两轮全空才按空判，防误红误熔断
        while($found -le 0 -and $gpTries -lt 6){
          Start-Sleep -Seconds 2
          $found=Find-GuiPort $cand
          $gpTries++
        }
      }
    }
    if($found -gt 0 -and $found -eq $cand){ Add-Line 'GREEN' 'truth.health.guiPort' 'gui-port' ('端口正常：127.0.0.1:'+$cand+' 符合判据（401 纯文本 unauthorized）') }
    elseif($found -gt 0){
      Add-Line 'RED' 'truth.health.guiPort' 'gui-port' ('端口不是 GUI：表里 guiPort='+$cand+'，实测 127.0.0.1:'+$found+' 符合判据（401 纯文本 unauthorized）')
      if($Auto -and $Fake -eq '' -and $f.fix.kind -eq 'auto'){
        $ok=$false
        try{
          Snap('gui-port 修复前：表值 '+$cand+' 实测 '+$found)
          $script:truthObj.health.guiPort=$found
          Write-Json $Truth $script:truthObj
          $check=Read-Json $Truth
          $ok=($null -ne $check -and [int]$check.health.guiPort -eq $found)
        }catch{ $ok=$false }
        if($ok){ Add-Line 'GREEN' $f.module $f.id ('已自动修复，根因 id=gui-port（guiPort 写回 '+$found+'）') }
        else{ Add-Line 'YELLOW' $f.module $f.id ('写回失败（truth.json 被占用或只读），不冻结，下轮再判再写') }
      }
    } else {
      $gpNote=''
      if($gpTries -gt 0){ $gpNote='（探空重试两轮共 6 次×2 秒仍空，判为连不上/忙，不自动改表）' }
      Add-Line 'RED' 'truth.health.guiPort' 'gui-port' ('端口不是 GUI：表里 guiPort='+$cand+'，实测 0 个端口符合判据（401 纯文本 unauthorized）'+$gpNote)
    }
  }

  # ---- snowluma-pipe ----
  $f=Get-Fault 'snowluma-pipe'
  if(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $qq=Get-Process -Name QQ -ErrorAction SilentlyContinue
    $onebot=Test-NetConnection -ComputerName 127.0.0.1 -Port 3000 -InformationLevel Quiet -WarningAction SilentlyContinue
    if($Fake -eq 'snowluma'){ $onebot=$false }
    if($null -eq $qq){ Add-Line 'YELLOW' 'snowluma-pipe' 'snowluma-pipe' 'QQ.exe 未运行，跳过注入检查' }
    elseif($onebot){ Add-Line 'GREEN' 'snowluma-pipe' 'snowluma-pipe' 'QQ.exe 在、OneBot 3000 在听，管道通' }
    else{
      Add-Line 'RED' 'snowluma-pipe' 'snowluma-pipe' ('进程在但管道不通：QQ.exe 在、OneBot 3000 不通；§16.5 人工口令=停 SnowLuma-Guard→杀重复实例→单实例重启→WebUI 5099 进程注入→加载→刷新（或跑 '+(Join-Path $DetMaint 'snowluma-reinject.vbs')+'），恢复后重跑 doctor 留痕')
      if($Auto -and $Fake -eq '' -and $f.fix.kind -eq 'manual'){ Add-Line 'YELLOW' $f.module $f.id 'fix.kind=manual，不自动修，按上行提示人工处理' }
    }
  }

  # ---- stamp-starvation ----
  $f=Get-Fault 'stamp-starvation'
  if(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $stampOk=$false; $lastTs=''
    if($Fake -ne 'stamp'){
      $sf=Get-ChildItem $Stamps -Filter '*.jsonl' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
      if($null -ne $sf){
        $lastLine=Get-Content $sf.FullName -Tail 1 -ErrorAction SilentlyContinue
        if($lastLine){
          try{ $o=$lastLine | ConvertFrom-Json; $lastTs=[string]$o.ts; if($o.ts){ $age=((Get-Date)-([datetime]::Parse($o.ts))).TotalHours; if($age -lt 30){ $stampOk=$true } } }catch{}
        }
      }
    }
    if($stampOk){ Add-Line 'GREEN' 'stamps' 'stamp-starvation' ('外盖戳正常：最后戳 '+$lastTs) }
    else{ Add-Line 'GRAY' 'stamps' 'stamp-starvation' ('外盖戳断供：今日戳缺失或超 30 小时未更新；禁止自补，由 CrystalL0-Stamp 写戳') }
  }

  # ---- heartbeat（§20.1：统一 heartbeat.json（$Heart）；阈值读 crystal.json checks.heartbeat.staleMinutes，缺省 30） ----
  $f=Get-Fault 'heartbeat'
  $hbThresh=30
  try{ if($null -ne $cjhb.checks -and $null -ne $cjhb.checks.heartbeat -and $null -ne $cjhb.checks.heartbeat.staleMinutes){ $hbThresh=[int]$cjhb.checks.heartbeat.staleMinutes } }catch{}
  $oldHb=Join-Path $Data 'heartbeat.txt'
  if(-not (Test-Path $Heart) -and (Test-Path $oldHb)){
    try{
      $hbMtime=(Get-Item $oldHb).LastWriteTime
      [IO.File]::WriteAllText($Heart,('{"by":"doctor","at":"'+$hbMtime.ToString('yyyy-MM-dd HH:mm:ss')+'"}'),(New-Object Text.UTF8Encoding($false)))
      (Get-Item $Heart).LastWriteTime=$hbMtime
      Rename-Item $oldHb ($oldHb+'.migrated-20261119') -ErrorAction SilentlyContinue
      [IO.File]::AppendAllText($Alerts,('[HEARTBEAT-MIGRATED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' from=data\crystal\heartbeat.txt to='+$Heart+' mtime='+$hbMtime.ToString('yyyy-MM-dd HH:mm:ss')+"`r`n"),(New-Object Text.UTF8Encoding($false)))
    }catch{}
  }
  if(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  elseif(-not (Test-Path $Heart)){ Add-Line 'YELLOW' 'heartbeat' 'heartbeat' '心跳未初始化（首次运行，本次已建立）' }
  else {
    $age=((Get-Date)-(Get-Item $Heart).LastWriteTime).TotalMinutes
    if($age -gt $hbThresh){ Add-Line 'RED' 'heartbeat' 'heartbeat' ('心跳超时未更新：上次 '+(Get-Item $Heart).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')+'（阈值 '+$hbThresh+' 分钟，见 crystal.json checks.heartbeat.staleMinutes）') }
    else{ Add-Line 'GREEN' 'heartbeat' 'heartbeat' '心跳正常' }
  }
  try{ [IO.File]::WriteAllText($Heart,('{"by":"doctor","at":"'+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+'"}'),(New-Object Text.UTF8Encoding($false))) }catch{}

  # ---- hand-edit（§10.1 六处生成物手改检测；只读，绝不写现网六件） ----
  $renders=@()
  try{ $cjObj=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjObj.renders){ $renders=@($cjObj.renders) } }catch{}
  $f=Get-Fault 'hand-edit'
  $RenderHashLib=Join-Path $Base 'scripts\crystal-renderhash.ps1'
  if(Test-Path $RenderHashLib){ try{ . $RenderHashLib }catch{} }
  $baselineMap=@{}
  try{
    $bj=Get-Content $BaselineF -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json
    if($null -ne $bj.entries){
      $bt=[string]$bj.builtAt
      foreach($be in @($bj.entries)){ if($null -ne $be.path){ $be | Add-Member -NotePropertyName builtAt -NotePropertyValue $bt -Force; $baselineMap[[string]$be.path]=$be } }
    }
  }catch{}
  if($Fake -eq 'handedit'){
    $demoTarget='<示例文件>'
    if($renders.Count -gt 0){ $demoTarget=[string]$renders[0].target }
    Write-Output ('doctor: [FAKE handedit] 演示（不落盘）：假设 '+$demoTarget+' 的 GENERATED 标记缺失')
    Write-Output ('doctor: [YELLOW] module=renders fault=hand-edit msg='+$demoTarget+'：生成物标记缺失，应为 GENERATED by crystal 头或 _generated/_crystal 键（生成段头部）')
  }
  elseif($Fake -eq 'handedit-content'){
    Write-Output ('doctor: [FAKE handedit-content] 演示（不落盘）：对沙箱篡改副本跑内容级比对')
    $demoPath=Join-Path $SandboxHome 'handedit\inject-table.json'
    if(Test-Path $demoPath){
      $facts=Get-RenderNormFacts -Path $demoPath -Kind 'inject-table'
      $be2=$null
      $injectKey=(Join-Path $DetBridge 'state\inject-table.json')
      if($baselineMap.ContainsKey($injectKey)){ $be2=$baselineMap[$injectKey] }
      if($null -ne $facts -and $null -ne $be2){
        if($facts.normHash -ne [string]$be2.normHash){ Write-Output ('doctor: [YELLOW] module=renders fault=hand-edit msg=r1 内容变了：'+$demoPath+'（归一化哈希不等，基线建于 '+$be2.builtAt+'）') }
        else{ Write-Output ('doctor: [GREEN] '+$demoPath+' 与基线一致') }
      } else { Write-Output ('doctor: [FAKE handedit-content] 请先建基线并在沙箱备好篡改副本') }
    } else { Write-Output ('doctor: [FAKE handedit-content] 沙箱副本缺失：'+$demoPath) }
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    foreach($r in $renders){
      $tp=[string]$r.target
      $files=@()
      if($tp -like '*\*'){ $files=@(Get-ChildItem -Path $tp -File -ErrorAction SilentlyContinue); if($files.Count -eq 0){ Add-Line 'RED' 'renders' 'hand-edit' ($r.id+' 通配无匹配：'+$tp) } }
      else{ if(Test-Path $tp){ $files=@(Get-Item $tp) } else { Add-Line 'RED' 'renders' 'hand-edit' ($r.id+' 文件缺失：'+$tp) } }
      foreach($fi in $files){
        $m=$null
        try{
          $txt=[IO.File]::ReadAllText($fi.FullName)
          $mm=[regex]::Match($txt,'GENERATED by crystal|"_generated"|"_crystal"')
          if($mm.Success){ $m=1+($txt.Substring(0,$mm.Index) -split "`n").Count-1 }
        }catch{}
        if($null -eq $m){ Add-Line 'YELLOW' 'renders' 'hand-edit' ($r.id+' 生成物标记缺失：'+$fi.FullName+'（应为 GENERATED by crystal 头或 _generated/_crystal 键）') }
        else{
          Add-Line 'GREEN' 'renders' 'hand-edit' ($r.id+' 生成标记在：'+$fi.FullName+' 第 '+$m+' 行')
          if($baselineMap.ContainsKey($fi.FullName)){
            $be3=$baselineMap[$fi.FullName]
            $facts2=Get-RenderNormFacts -Path $fi.FullName -Kind ([string]$r.kind)
            if($null -ne $facts2){
              if($facts2.headerText -ne [string]$be3.headerText){ Add-Line 'YELLOW' 'renders' 'hand-edit' ($r.id+' 头变了：'+$fi.FullName+' 第 '+$facts2.headerLine+' 行（基线建于 '+$be3.builtAt+'）') }
              elseif($facts2.sourceFingerprint -ne [string]$be3.sourceFingerprint){ Add-Line 'YELLOW' 'renders' 'hand-edit' ($r.id+' 来源行变了：'+$fi.FullName+' 第 '+$facts2.sourceLine+' 行（基线建于 '+$be3.builtAt+'）') }
              elseif($facts2.normHash -ne [string]$be3.normHash){ Add-Line 'YELLOW' 'renders' 'hand-edit' ($r.id+' 内容变了：'+$fi.FullName+'（归一化哈希不等，基线建于 '+$be3.builtAt+'）') }
            }
          }
        }
      }
    }
  }

  # ---- cookies-header-overflow（§16.1 只读：拷副本计数，阈值读 crystal.json checks） ----
  $f=Get-Fault 'cookies-header-overflow'
  if($Fake -eq 'cookies'){
    Write-Output 'doctor: [FAKE cookies] 演示（不落盘）：假设 dsh-auth- 计数=70'
    Write-Output ('doctor: [RED] module=cookies fault=cookies-header-overflow msg=实测 70 > 期望 <=68（crystal.json checks.cookies.errorCount），证据='+(Join-Path $ckDir 'Cookies')+'（副本）')
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $ckWarn=60; $ckErr=68
    $ckSrc=Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop\Network\Cookies'
    $ckDir=Join-Path $SandboxHome 'cookies'
    try{
      $cjObj2=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
      if($null -ne $cjObj2.checks -and $null -ne $cjObj2.checks.cookies){
        if($null -ne $cjObj2.checks.cookies.warnCount){ $ckWarn=[int]$cjObj2.checks.cookies.warnCount }
        if($null -ne $cjObj2.checks.cookies.errorCount){ $ckErr=[int]$cjObj2.checks.cookies.errorCount }
        if($null -ne $cjObj2.checks.cookies.copyDir -and $cjObj2.checks.cookies.copyDir -ne ''){ $ckDir=[string]$cjObj2.checks.cookies.copyDir }
      }
    }catch{}
    $ckCount=$null
    $ckCopy=Join-Path $ckDir 'Cookies'
    try{
      if(Test-Path $ckSrc){
        New-Item -ItemType Directory -Force -Path $ckDir | Out-Null
        Copy-Item $ckSrc $ckCopy -Force
        $b=[IO.File]::ReadAllBytes($ckCopy)
        $s=[Text.Encoding]::ASCII.GetString($b)
        $ckCount=[regex]::Matches($s,'dsh-auth-').Count
      }
    }catch{}
    if($null -eq $ckCount){ Add-Line 'GRAY' 'cookies' 'cookies-header-overflow' ('Cookies 运行时读不到（DSH 独占锁或副本失败）：'+$ckSrc+'；人工检查=关 DSH 后数 dsh-auth- 条数，>'+$ckErr+' 条再清') }
    elseif($ckCount -gt $ckErr){ Add-Line 'RED' 'cookies' 'cookies-header-overflow' ('实测 '+$ckCount+' 条 > 期望 <='+$ckErr+'（crystal.json checks.cookies.errorCount），证据='+$ckCopy+'（副本）；人工修法：关 DSH → 备份 Cookies → 删 dsh-auth-* → 重启') }
    elseif($ckCount -gt $ckWarn){ Add-Line 'YELLOW' 'cookies' 'cookies-header-overflow' ('实测 '+$ckCount+' 条 > 期望 <='+$ckWarn+'（crystal.json checks.cookies.warnCount），证据='+$ckCopy) }
    else{ Add-Line 'GREEN' 'cookies' 'cookies-header-overflow' ('实测 '+$ckCount+' 条 <= '+$ckWarn+'（crystal.json checks.cookies.warnCount），证据='+$ckCopy+'（副本）') }
  }

  # ---- config-version-mismatch（§16.2 只读：profile 依赖 vs 宿主注册表版本） ----
  $f=Get-Fault 'config-version-mismatch'
  if($Fake -eq 'version'){
    Write-Output 'doctor: [FAKE version] 演示（不落盘）：假设 dsh-token-meter=0.2.2-rc.1 与宿主 0.2.2-rc.3 不等'
    Write-Output ('doctor: [YELLOW] module=config fault=config-version-mismatch msg=实测 dsh-token-meter=0.2.2-rc.1、期望=0.2.2-rc.3、证据='+$ProfilePkg+'（dependencies.dsh-token-meter）')
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $hostVer=$null
    try{
      $reg=$null
      foreach($vh in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')){
        if($null -eq $reg){ $reg=Get-ItemProperty $vh -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'DeepSeek Harness' } | Select-Object -First 1 }
      }
      if($null -ne $reg){ $hostVer=[string]$reg.DisplayVersion }
    }catch{}
    if($null -eq $hostVer){ Add-Line 'YELLOW' 'config' 'config-version-mismatch' ('宿主版本读不到（注册表无 DeepSeek Harness）') }
    else {
      $pp=$ProfilePkg
      try{
        $pj=Get-Content $pp -Raw -Encoding UTF8 | ConvertFrom-Json
        $bad=@()
        if($null -ne $pj.dependencies){
          foreach($pn in $pj.dependencies.PSObject.Properties){
            if($pn.Name -like '@deepseek-ai/*'){
              $pv=[string]$pn.Value
              if($pv -ne $hostVer){ $bad += ($pn.Name+'='+$pv) }
            }
          }
        }
        if($bad.Count -gt 0){ foreach($b in $bad){ Add-Line 'YELLOW' 'config' 'config-version-mismatch' ('实测 '+$b+'、期望='+$hostVer+'、证据='+$pp+'（dependencies）') } }
        else{ Add-Line 'GREEN' 'config' 'config-version-mismatch' ('实测 @deepseek-ai/* 全部='+$hostVer+'、期望='+$hostVer+'、证据='+$pp+' + 注册表 DisplayVersion') }
      }catch{ Add-Line 'YELLOW' 'config' 'config-version-mismatch' ('读 '+$pp+' 失败：'+$_.Exception.Message) }
    }
  }

  # ---- mount-missing（§16.10 三处挂载：Junction/AGENTS 指向/bundles 登记，缺一红+给补命令） ----
  $f=Get-Fault 'mount-missing'
  if($Fake -eq 'mount'){
    Write-Output 'doctor: [FAKE mount] 演示（不落盘）：假设插件目录 Junction 缺失'
    Write-Output ('doctor: [RED] module=mount fault=mount-missing msg=实测 ReparsePoint=False、期望=True、证据='+(Join-Path $DetUser '.dsh\plugins\dsh-crystal'))
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $plgDir=$Base
    $att=(Get-Item $plgDir -Force).Attributes
    if($att -band [IO.FileAttributes]::ReparsePoint){ Add-Line 'GREEN' 'mount' 'mount-missing' ('实测 ReparsePoint=True（期望 True），证据='+$plgDir) }
    else{ Add-Line 'RED' 'mount' 'mount-missing' ('实测 ReparsePoint=False、期望=True（§14.1② Junction）、证据='+$plgDir+'；补：迁移目录后 mklink /J 指回（回滚见 '+$CrystalHome+'\迁移记录）') }
    $ag=Join-Path $DetUser '.dsh\AGENTS.md'
    try{
      $agHead=(Get-Content $ag -TotalCount 10 -Encoding UTF8) -join ' '
      if($agHead -match 'crystal'){ Add-Line 'GREEN' 'mount' 'mount-missing' ('实测 顶部含 crystal 字样（期望 True），证据='+$ag+' 第 1-10 行') }
      else{ Add-Line 'RED' 'mount' 'mount-missing' ('实测 顶部 10 行无 crystal 字样、期望有标记行（§14.1①）、证据='+$ag+' 第 1-10 行；补：顶部加 crystal 标记行（有 .bak-20261119 备份）') }
    }catch{ Add-Line 'YELLOW' 'mount' 'mount-missing' ('读 '+$ag+' 失败：'+$_.Exception.Message) }
    $pp=$ProfilePkg
    try{
      $pj=Get-Content $pp -Raw -Encoding UTF8 | ConvertFrom-Json
      $has=(($pj.dsh.profile.bundles -join ',') -match 'dsh-crystal')
      if($has){ Add-Line 'GREEN' 'mount' 'mount-missing' ('实测 bundles 含 dsh-crystal（期望 True），证据='+$pp+'（dsh.profile.bundles）') }
      else{ Add-Line 'RED' 'mount' 'mount-missing' ('实测 bundles 不含 dsh-crystal、期望含（§14.1③）、证据='+$pp+'（dsh.profile.bundles）；补：bundles 加登记后重启 DSH（有 .bak-20261119 备份）') }
    }catch{ Add-Line 'YELLOW' 'mount' 'mount-missing' ('读 '+$pp+' 失败：'+$_.Exception.Message) }
  }

  # ---- inventory（P3 第一段：旧插件纳管三源对账，只读绝不自动修、不计熔断） ----
  $invFile=Join-Path $DataHome 'plugins-inventory.json'
  if(-not (Test-Path $invFile)){
    Add-Line 'YELLOW' 'plugins' 'inventory' ('[INVENTORY-MISSING] 期望='+$invFile+' 实测=缺失；人工补跑 crystal-plugins.ps1 生成')
  } else {
    try{
      $inv=Get-Content $invFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $ageH=((Get-Date)-[datetime]::ParseExact([string]$inv.generatedAt,'yyyy-MM-dd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture)).TotalHours
      if($ageH -gt 24){ Add-Line 'YELLOW' 'plugins' 'inventory' ('[INVENTORY-STALE] generatedAt='+$inv.generatedAt+'（超 24 小时），人工补跑 crystal-plugins.ps1') }
      else {
        $invCov=@($inv.entries | Where-Object { $_.status -eq 'covered' }).Count
        $invReg=@($inv.entries | Where-Object { $_.status -eq 'registered' }).Count
        $invPend=@($inv.entries | Where-Object { $_.status -eq 'pending' }).Count
        $invUnk=@($inv.entries | Where-Object { $_.status -eq 'unknown' }).Count
        Add-Line 'GREEN' 'plugins' 'inventory' ('三源对账正常：covered='+$invCov+' registered='+$invReg+' pending='+$invPend+' unknown='+$invUnk+'（generatedAt='+$inv.generatedAt+'，差异=登记/纳管状态，非故障）')
      }
    }catch{
      Add-Line 'YELLOW' 'plugins' 'inventory' ('[INVENTORY-MISSING] 文件不可解析：'+$invFile+' '+$_.Exception.Message)
    }
  }

  # ---- automation（§12 自主执行：总表 8 条任务在场检测，只读不修） ----
  $f=Get-Fault 'automation-missing'
  if($Fake -eq 'automation'){
    Write-Output ('doctor: [FAKE automation] 演示（不落盘）：假设 任务 CrystalL0-Stamp 缺失 → YELLOW module=automation fault=automation-missing msg=任务缺失：CrystalL0-Stamp（schtasks /Query 未找到），人工复核')
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $autoMiss=@()
    try{
      $autoList=@($cjhb.automation)
      foreach($autoItem in $autoList){
        $aid=[string]$autoItem.id
        $ok=$false
        if([string]$autoItem.trigger -eq 'schtasks'){
          schtasks /Query /TN $aid /FO LIST 2>$null | Out-Null
          if($LASTEXITCODE -eq 0){ $ok=$true }
        } elseif([string]$autoItem.trigger -eq 'startup'){
          $su=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
          $desk=Join-Path $DetUser 'Desktop'
          if((Test-Path (Join-Path $desk $aid)) -or (Test-Path (Join-Path $DetMaint $aid)) -or (Test-Path (Join-Path $su $aid))){ $ok=$true }
        } elseif([string]$autoItem.trigger -eq 'file'){
          if($null -ne $autoItem.path -and (Test-Path ([string]$autoItem.path))){ $ok=$true }
        } else { $ok=$true }
        if(-not $ok){ $autoMiss+=$aid }
      }
    }catch{}
    if($autoMiss.Count -gt 0){ Add-Line 'YELLOW' 'automation' 'automation-missing' ('任务缺失：'+($autoMiss -join '、')+'（schtasks /Query 未找到或文件不在；只诊断不修，人工复核）') }
    else{ Add-Line 'GREEN' 'automation' 'automation-missing' ('总表 automation 任务全部在场') }
  }

  # ---- conflicts（§11.3：计划任务幂等+状态+锁文件；只读不修，不碰别人看门狗） ----
  $f=Get-Fault 'conflicts'
  if($Fake -eq 'conflicts'){
    Write-Output ('doctor: [FAKE conflicts] 演示（不落盘）：假设 CrystalDaily-Doctor 重复且被停 → RED module=self fault=conflicts msg=任务冲突：CrystalDaily-Doctor 重复 2 条（幂等破坏，人工复核）')
    Write-Output ('doctor: [YELLOW] module=self fault=conflicts msg=CrystalDaily-Doctor 状态=Disabled（停用不悄悄重建，人工处理）')
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $cfBad=@()
    $cfWarn=@()
    $crystalTasks=@()
    try{
      $cjcf=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach($at in @($cjcf.automation)){ if([string]$at.id -like 'Crystal*'){ $crystalTasks+=[string]$at.id } }
      foreach($tn in $crystalTasks){
        $qRaw=schtasks /query /fo csv /nh /tn $tn 2>&1
        $qCode=$LASTEXITCODE
        $rows=@($qRaw | Where-Object { $_ -is [string] -and $_.Trim() -ne '' })
        if($qCode -ne 0){ $errTxt=(($qRaw | Where-Object { $_ -isnot [string] } | ForEach-Object { $_.Exception.Message }) -join '；'); $cfWarn+=($tn+' 查询失败（原句='+$errTxt+'，如实报黄人工复核）') }
        elseif($rows.Count -eq 0){ $cfBad+=($tn+' 缺失（schtasks 查无此任务，人工复核）') }
        elseif($rows.Count -gt 1){ $cfBad+=($tn+' 重复 '+$rows.Count+' 条（幂等破坏，人工复核）') }
        elseif($rows[0] -notmatch [regex]::Escape($tn)){ $cfWarn+=($tn+' 输出异常（原句='+$rows[0].Trim()+ '，本地化/乱码如实报黄）') }
        else{
          $stLine=($rows[0] -split ',')[-1].Trim().Trim('"')
          if($stLine -match 'Ready|Running|就绪|正在运行'){ }
          else{ $cfWarn+=($tn+' 状态='+$stLine+'（停用不悄悄重建，人工处理）') }
        }
      }
    }catch{ $cfBad+=('crystal.json automation 读取失败：'+$_.Exception.Message) }
    $lockFile=Join-Path $DataHome 'lock'
    $lockInfo=('锁文件缺失：'+$lockFile+'（只记录不创建）')
    if(Test-Path $lockFile){ $li=Get-Item $lockFile; $lockInfo=('锁文件在场：'+$li.FullName+' 大小='+$li.Length+'B mtime='+$li.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) }
    if($cfBad.Count -gt 0){ Add-Line 'RED' 'self' 'conflicts' ('任务冲突：'+(($cfBad | ForEach-Object { $_ }) -join '、')) }
    elseif($cfWarn.Count -gt 0){ Add-Line 'YELLOW' 'self' 'conflicts' (($cfWarn | ForEach-Object { $_ }) -join '、') }
    else{ Add-Line 'GREEN' 'self' 'conflicts' (('计划任务幂等：'+($crystalTasks -join '/')+' 各 1 条且状态正常；'+$lockInfo)) }
  }

  # ---- autonomy（§12.5 自主执行表；只读，不补键、不计熔断） ----
  $f=Get-Fault 'autonomy-missing'
  if($Fake -eq 'autonomy'){
    Write-Output 'doctor: [FAKE autonomy] 演示（不落盘）：假设 crystal.json 缺 autonomy.reportMoney.daily'
    Write-Output 'doctor: [YELLOW] module=autonomy fault=autonomy-missing msg=autonomy.reportMoney.daily 缺失（只读不补）'
  }
  else{
    $aMiss=@(); $aBad=@(); $aOk=@()
    $tObj=$null
    try{ $tObj=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json }catch{}
    if($null -eq $tObj){ $aMiss+='autonomy（crystal.json 不可读）' }
    else{
      $au=$null
      try{ $au=$tObj.autonomy }catch{}
      if($null -eq $au){ $aMiss+='autonomy' }
      else{
        foreach($k in @('askDelete','askOutbound','askRoots','silentVerify')){
          $v=$null
          try{ $v=$au.$k }catch{}
          if($null -eq $v){ $aMiss+=('autonomy.'+$k) }
          elseif($v -isnot [bool]){ $aBad+=(('autonomy.'+$k)+' 原值='+$v+' 类型='+$v.GetType().Name) }
          else{ $aOk+=(($k+'=')+$v) }
        }
        $rm=$null
        try{ $rm=$au.reportMoney }catch{}
        if($null -eq $rm){ $aMiss+='autonomy.reportMoney' }
        else{
          foreach($k in @('perTurn','daily')){
            $v=$null
            try{ $v=$rm.$k }catch{}
            if($null -eq $v){ $aMiss+=(('autonomy.reportMoney.')+$k) }
            elseif($v -isnot [ValueType] -or $v -lt 0){ $aBad+=((('autonomy.reportMoney.')+$k)+' 原值='+$v) }
            else{ $aOk+=(('reportMoney.')+$k)+'='+$v }
          }
        }
      }
    }
    if($aMiss.Count -gt 0){ Add-Line 'YELLOW' 'autonomy' 'autonomy-missing' (('缺失键=')+($aMiss -join '、')+'（只读不补）') }
    if($aBad.Count -gt 0){ Add-Line 'YELLOW' 'autonomy' 'autonomy-missing' (('字段坏=')+($aBad -join '；')) }
    if($aMiss.Count -eq 0 -and $aBad.Count -eq 0){ Add-Line 'GREEN' 'autonomy' 'autonomy-missing' (('五项齐全：')+($aOk -join ' / ')) }
  }

  # ---- restart-gate（conflicts 第 4 条 + forbidden：重启只走一条通道；只读核验） ----
  $f=Get-Fault 'restart-gate'
  if($Fake -eq 'restartgate'){
    Write-Output ('doctor: [FAKE restartgate] 演示（不落盘）：假设 '+$RestartGate+' 缺失 → YELLOW module=self fault=restart-gate msg=重启通道缺失')
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $gate=$RestartGate
    $gateOk=(Test-Path $gate)
    $forbOk=($null -ne $cjhb.forbidden -and @($cjhb.forbidden).Count -ge 2)
    $tkHits=@()
    try{
      foreach($sf in @(Get-ChildItem (Join-Path $Base 'scripts') -File -Filter *.ps1 -ErrorAction SilentlyContinue)){
        $sfl=@(Get-Content $sf.FullName -Encoding UTF8)
        for($si=0; $si -lt $sfl.Count; $si++){
          if($sfl[$si] -match '(?i)(^|[;&|])\s*taskkill\s' -and $sfl[$si] -match '\/[TF]\b'){ $tkHits+=($sf.Name+':'+($si+1)) }
        }
      }
    }catch{}
    if(-not $gateOk){ Add-Line 'YELLOW' 'self' 'restart-gate' ('重启通道缺失：'+$gate) }
    elseif(-not $forbOk){ Add-Line 'YELLOW' 'self' 'restart-gate' 'forbidden 两条缺一（重启只走一条通道/禁 taskkill /T /F）' }
    elseif($tkHits.Count -gt 0){ Add-Line 'YELLOW' 'self' 'restart-gate' ('scripts 检出命令行位置 taskkill 用法：'+(($tkHits | ForEach-Object { $_ }) -join '、')+'（证据=文件:行号）') }
    else{ Add-Line 'GREEN' 'self' 'restart-gate' ('重启只走一条通道：'+$gate+'；scripts 无 taskkill /T /F') }
  }

  # ---- baseline（P3 第二段：render-baseline 保鲜；-Auto 只刷新自家数据文件，不碰现网） ----
  $f=Get-Fault 'baseline-stale'
  $baseLine=$BaselineF
  if($Fake -eq 'baseline'){
    Write-Output ('doctor: [FAKE baseline] 演示（不落盘）：假设 render-baseline.json builtAt 超 24 小时 → YELLOW module=renders fault=baseline-stale msg=基线过期')
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $bOk=$false; $bAgeH=999.0
    try{ $blj=Get-Content $baseLine -Raw -Encoding UTF8 | ConvertFrom-Json; $bOk=$true; $bAgeH=((Get-Date)-[datetime]::ParseExact([string]$blj.builtAt,'yyyy-MM-dd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture)).TotalHours }catch{}
    if(-not $bOk){ Add-Line 'YELLOW' 'renders' 'baseline-stale' ('基线缺失：'+$baseLine+'，人工跑 crystal-build.ps1 -Baseline') }
    elseif($bAgeH -gt 24){
      if($Auto){ try{ $sb=Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Base 'scripts\crystal-build.ps1'),'-Baseline' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue }catch{}; try{ [IO.File]::AppendAllText($Alerts,('[BASELINE-REFRESH] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' old='+[string]$blj.builtAt+' 超 24 小时，-Auto 已重刷'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{} }
      $blNote='，人工跑 crystal-build -Baseline'
      if($Auto){ $blNote='，-Auto 已重刷' }
      Add-Line 'YELLOW' 'renders' 'baseline-stale' ('基线过期：builtAt='+[string]$blj.builtAt+'（超 24 小时）'+$blNote)
    }
    else{ Add-Line 'GREEN' 'renders' 'baseline-stale' ('基线新鲜：builtAt='+[string]$blj.builtAt) }
  }

  # ---- budget-warn（§41 额度告警：只喊不拦，不计红黄绿灰、不熔断） ----
  $warnTok=1000000
  $warnCny=12.0
  $usageFileB=$UsageF
  $costFileB=$CostF
  try{
    $cjB=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($null -ne $cjB.checks -and $null -ne $cjB.checks.budget){
      try{ $warnTok=[int]$cjB.checks.budget.warnTokensDaily }catch{}
      try{ $warnCny=[double]$cjB.checks.budget.warnCnyDaily }catch{}
    }
    if($null -ne $cjB.paths){
      if($null -ne $cjB.paths.usage -and $cjB.paths.usage -ne ''){ $usageFileB=[string]$cjB.paths.usage }
      if($null -ne $cjB.paths.cost -and $cjB.paths.cost -ne ''){ $costFileB=[string]$cjB.paths.cost }
    }
  }catch{}
  $todayKeyB=(Get-Date -Format 'yyyy-MM-dd')
  $todayTokB=0; $todayCnyB=0.0
  if($Fake -eq 'budget'){
    Write-Output ('doctor: [FAKE budget] 演示（不落盘）：假设当日 token=1200000 超阈值 '+$warnTok+' → 应喊 [BUDGET-WARN]')
    Write-Output ('doctor: [BUDGET-WARN] '+$todayKeyB+' 当日累计 1200000 tokens / 0.00 元，超阈值（'+$warnTok+' tokens / '+$warnCny+' 元/日），只喊不拦')
  } else {
    try{
      foreach($ul in [IO.File]::ReadAllLines($usageFileB)){
        if($ul -notmatch '\{'){ continue }
        try{
          $uo=$ul | ConvertFrom-Json
          $lt=([datetime]::Parse([string]$uo.ts)).ToLocalTime().ToString('yyyy-MM-dd')
          if($lt -eq $todayKeyB){ $todayTokB+=[int64]$uo.inputTokens+[int64]$uo.outputTokens }
        }catch{}
      }
    }catch{}
    try{
      foreach($cl in [IO.File]::ReadAllLines($costFileB)){
        if($cl -notmatch '\{'){ continue }
        try{
          $co=$cl | ConvertFrom-Json
          $lt=([datetime]::Parse([string]$co.ts)).ToLocalTime().ToString('yyyy-MM-dd')
          if($lt -eq $todayKeyB){ $todayCnyB+=[double]$co.amountCny }
        }catch{}
      }
    }catch{}
    $bl='[BUDGET-OK] '+$todayKeyB+' 当日累计 '+$todayTokB+' tokens / '+([math]::Round($todayCnyB,2))+' 元（阈值 '+$warnTok+' tokens / '+$warnCny+' 元/日）'
    if($todayTokB -gt $warnTok -or $todayCnyB -gt $warnCny){
      $bl='[BUDGET-WARN] '+$todayKeyB+' 当日累计 '+$todayTokB+' tokens / '+([math]::Round($todayCnyB,2))+' 元，超阈值（'+$warnTok+' tokens / '+$warnCny+' 元/日），只喊不拦'
    }
    try{ [IO.File]::AppendAllText($Alerts,($bl+"`r`n"),$enc) }catch{}
    Write-Output ('doctor: '+$bl)
    if($todayCnyB -gt $warnCny){
      # 预算到顶报警（主人 2026-11-19 晚定）：钱线触顶→推 QQ 一条，只报警不打断工作；每天最多推一次
      try{
        $bstate=$BStateF
        $lastDay=''
        try{ $lastDay=[string]((Get-Content $bstate -Raw -Encoding UTF8 | ConvertFrom-Json).lastPushedDay) }catch{}
        if($lastDay -ne $todayKeyB){
          $tok=[IO.File]::ReadAllText($ConsoleTok).Trim()
          $bodyFile=Join-Path $env:TEMP ('crystal-budget-'+[guid]::NewGuid().ToString('N')+'.json')
          $msg='[crystal 预算] '+$todayKeyB+' 已花 '+([math]::Round($todayCnyB,2))+' 元，触顶预警线 '+$warnCny+' 元/日，只报警不打断'
          $bodyJson='{"userId":"","message":"'+($msg.Replace('"',''))+'"}'
          [IO.File]::WriteAllText($bodyFile,$bodyJson,(New-Object Text.UTF8Encoding($false)))
          $resp=& curl.exe -s -X POST 'http://127.0.0.1:3100/api/send/private' -H ('x-console-token: '+$tok) -H 'Content-Type: application/json' --data-binary ('@'+$bodyFile) 2>&1 | Out-String
          Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
          try{ [IO.File]::WriteAllText($bstate,('{"lastPushedDay":"'+$todayKeyB+'"}'),$enc) }catch{}
          try{ [IO.File]::AppendAllText($Alerts,('[BUDGET-PUSH] '+$todayKeyB+' '+(($resp -replace '\s+',' ').Trim())+"`r`n"),$enc) }catch{}
        }
      }catch{ try{ [IO.File]::AppendAllText($Alerts,('[BUDGET-PUSH-FAIL] '+$_.Exception.Message+"`r`n"),$enc) }catch{} }
    }
  }

  # ---- rules（§23 规则自填+开关：chat/work 各 10 槽，只读三态，不计熔断） ----
  $f=Get-Fault 'rules'
  if($Fake -eq 'rules'){
    Write-Output 'doctor: [FAKE rules] 演示（不落盘）：假设 crystal.json rules 表缺失 → YELLOW 指到 rules 键'
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $rulesObj=$null
    try{ $cjR=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $rulesObj=$cjR.rules }catch{}
    if($null -eq $rulesObj){ Add-Line 'YELLOW' 'crystal.json' 'rules' ('rules 表缺失：crystal.json 无 rules 键（应为 {chat:[10 槽],work:[10 槽]}，每槽 id/text/enabled）') }
    else {
      $chatA=@(); $workA=@()
      try{ $chatA=@($rulesObj.chat) }catch{}
      try{ $workA=@($rulesObj.work) }catch{}
      $chatFill=@($chatA | Where-Object { $null -ne $_.text -and $_.text -ne '' }).Count
      $workFill=@($workA | Where-Object { $null -ne $_.text -and $_.text -ne '' }).Count
      $badR=@()
      foreach($rr in @($chatA)+@($workA)){
        $rOk=($null -ne $rr.id -and $rr.id -ne '' -and $null -ne $rr.enabled)
        if(-not $rOk){ $badR+=([string]$rr.id) }
      }
      if($badR.Count -gt 0){ Add-Line 'YELLOW' 'crystal.json' 'rules' ('rules 有 '+$badR.Count+' 槽缺 id/enabled：'+($badR -join ',')) }
      elseif($chatA.Count -ne 10 -or $workA.Count -ne 10){ Add-Line 'YELLOW' 'crystal.json' 'rules' ('rules 槽数不对：chat='+$chatA.Count+' work='+$workA.Count+'（应各 10 槽）') }
      else{ Add-Line 'GREEN' 'crystal.json' 'rules' ('rules chat 10 槽填 '+$chatFill+' / work 10 槽填 '+$workFill+'，字段齐') }
    }
  }

  # ---- receipts（§24 已读凭证：只读三态，不计熔断） ----
  $f=Get-Fault 'receipts'
  if($Fake -eq 'receipts'){
    Write-Output ('doctor: [FAKE receipts] 演示（不落盘）：假设 read-receipts.json 缺失 → YELLOW 指到 '+$RcMirror)
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $rcMirror=$RcMirror
    $rcLog=$RcLog
    try{
      if(Test-Path $rcMirror){
        $rcAge=((Get-Date)-(Get-Item $rcMirror).LastWriteTime).TotalHours
        $rcN=0; try{ $rcN=@(Get-Content $rcLog -Encoding UTF8).Count }catch{}
        if($rcAge -le 24){ Add-Line 'GREEN' 'crystal' 'receipts' ('read-receipts.json 快照 '+[math]::Round($rcAge,1)+' 小时内，凭证 '+$rcN+' 行') }
        else{ Add-Line 'YELLOW' 'crystal' 'receipts' ('read-receipts.json 快照过期 '+[math]::Round($rcAge,1)+' 小时（应≤24h，跑 crystal receipts 刷新）') }
      } else { Add-Line 'YELLOW' 'crystal' 'receipts' ('read-receipts.json 缺失：'+$rcMirror+'（跑 crystal receipts 生成）') }
    }catch{ Add-Line 'YELLOW' 'crystal' 'receipts' ('read-receipts 检查异常：'+$_.Exception.Message) }
  }

  # ---- plugin-toggle（§24 插件开关台账：到期喊关，只读，不计熔断） ----
  $f=Get-Fault 'plugin-toggle'
  if($Fake -eq 'pluginctl'){
    Write-Output 'doctor: [FAKE pluginctl] 演示（不落盘）：假设某插件台账已到期 → YELLOW [PLUGIN-AUTO-OFF-DUE] 指到插件名与到期时间'
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $ptFile=$TogglesFile
    $due=@()
    $ptCnt=0
    try{
      if(Test-Path $ptFile){
        $ptO=[IO.File]::ReadAllText($ptFile,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if($null -ne $ptO -and $null -ne $ptO.entries){
          $ptCnt=@($ptO.entries).Count
          foreach($e in @($ptO.entries)){
            if($e.status -eq 'temp-enabled' -or $e.status -eq 'on'){
              try{
                $dl=[datetime]::ParseExact([string]$e.deadline,'yyyy-MM-dd HH:mm:ss',$null)
                if((Get-Date) -gt $dl){ $due+=('name='+$e.name+' deadline='+$e.deadline) }
              }catch{}
            }
          }
        }
      }
    }catch{}
    if($due.Count -gt 0){ Add-Line 'YELLOW' 'crystal' 'plugin-toggle' ('[PLUGIN-AUTO-OFF-DUE] '+($due -join '；')+' —— 用 pluginctl disable 关（改前自动备份留痕）') }
    else{ Add-Line 'GREEN' 'crystal' 'plugin-toggle' ('plugin-toggles 台账 '+$ptCnt+' 条登记，无到期未关') }
  }

  # ---- plugin-demand（主人 m03412 按需调度：demand 三档 vs 盘面 bundles vs 台账，只读，不计熔断） ----
  $f=Get-Fault 'plugin-demand'
  if($Fake -eq 'plugindemand'){
    Write-Output 'doctor: [FAKE plugindemand] 演示（不落盘）：假设 on-demand 插件 lease 过期 → YELLOW [PLUGIN-AUTO-OFF-DUE]；off 档被启用 → YELLOW 越权'
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $pdY=@()
    try{
      $cjPd=[IO.File]::ReadAllText((Join-Path $Base 'crystal.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
      $pkgPd=[IO.File]::ReadAllText($ProfilePkg,[Text.Encoding]::UTF8) | ConvertFrom-Json
      $bundles=@($pkgPd.dsh.profile.bundles)
      $ptPd=@()
      if(Test-Path $TogglesFile){
        $ptO=[IO.File]::ReadAllText($TogglesFile,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if($null -ne $ptO.entries){ $ptPd=@($ptO.entries) }
      }
      foreach($p in @($cjPd.plugins)){
        $nm=[string]$p.name
        $dm=[string]$p.demand
        $inBundles=($bundles -contains $nm)
        $ent=@($ptPd | Where-Object { $_.name -eq $nm })
        if($dm -eq 'off' -and $inBundles){ $pdY+=($nm+'=off 档被启用（越权）') }
        elseif($dm -eq 'on-demand' -and $inBundles){
          if($ent.Count -eq 0){ $pdY+=($nm+'=启用中但台账无记录') }
          else{
            $st=[string]$ent[0].status
            if($st -eq 'on' -or $st -eq 'temp-enabled'){
              try{
                $dl=[datetime]::ParseExact([string]$ent[0].deadline,'yyyy-MM-dd HH:mm:ss',$null)
                if((Get-Date) -gt $dl){ $pdY+=($nm+'=lease 已过期（deadline='+$ent[0].deadline+'）') }
              }catch{}
            }
          }
        }
        elseif($dm -eq 'on-demand' -and -not $inBundles -and $ent.Count -gt 0 -and [string]$ent[0].status -eq 'on'){
          $pdY+=($nm+'=台账说启用但不在 bundles（盘面不符）')
        }
      }
    }catch{}
    if($pdY.Count -gt 0){ Add-Line 'YELLOW' 'crystal' 'plugin-demand' ('按需调度异常：'+($pdY -join '；')+' —— 用 pluginctl enable/disable 校正') }
    else{ Add-Line 'GREEN' 'crystal' 'plugin-demand' '按需调度正常：demand 三档与 bundles、台账一致，无到期未关' }
  }

  # ---- disk（P9 ④磁盘管家：C/F 盘剩余+遗留目录大小，只报不动） ----
  $f=Get-Fault 'disk-low'
  if($Fake -eq 'disk'){
    Write-Output 'doctor: [FAKE disk] 演示（不落盘）：假设 F 盘剩余低于 10GB'
    Write-Output 'doctor: [YELLOW] module=self fault=disk-low msg=F 盘剩余 8.2GB 低于阈值 10GB（只报不动，人工清理）'
  }
  elseif(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $diskNotes=@()
    foreach($dv in @('C','F')){
      try{
        $drv=Get-PSDrive -Name $dv -ErrorAction Stop
        $freeGB=[math]::Round(($drv.Free/1GB),1)
        if($freeGB -lt 10){ $diskNotes+=($dv+': 剩余 '+$freeGB+'GB（低于 10GB）') }
        else{ $diskNotes+=($dv+': 剩余 '+$freeGB+'GB') }
      }catch{ $diskNotes+=($dv+': 不可读') }
    }
    try{
      $bakDirs=@(Get-ChildItem $CrystalHome -Directory -Filter 'dsh-crystal.bak-*' -ErrorAction SilentlyContinue)
      foreach($bd in $bakDirs){
        $sz=[math]::Round((((Get-ChildItem $bd.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)/1MB),1)
        $diskNotes+=($bd.Name+' 大小 '+$sz+'MB')
      }
      if(Test-Path $SandboxHome){
        $sz2=[math]::Round((((Get-ChildItem $SandboxHome -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)/1MB),1)
        $diskNotes+=( '_crystal-sandbox 大小 '+$sz2+'MB')
      }
    }catch{}
    $diskLow=@($diskNotes | Where-Object { $_ -match '低于' }).Count
    if($diskLow -gt 0){ Add-Line 'YELLOW' 'self' 'disk-low' ('磁盘：'+($diskNotes -join '；')) }
    else{ Add-Line 'GREEN' 'self' 'disk-low' ('磁盘：'+($diskNotes -join '；')) }
  }

  # ---- fallback ----
  $f=Get-Fault 'fallback'
  if(Is-Frozen $f){ Add-Line 'YELLOW' $f.module $f.id ('frozen at '+$f.frozenAt+'：'+$f.frozenReason+'，只诊断不修') }
  else {
    $fb=Read-Json $Fallback
    if($null -eq $fb){
      $fixed=$false
      if($Auto -and $Fake -eq '' -and $f.fix.kind -eq 'auto'){
        try{
          Snap('fallback 修复前：缺失或非法')
          $tpl='{"version":1,"chat":{"rules":["称呼一律「主人」","一句话一条，不堆信息","思考用最低档"],"tools":["qq_send_message","qq_reply","qq_send_voice","memory"]},"work":{"rules":["改前备份、改后写改动记录","干活档不拦","超钱只报不停工","动根基先问主人"],"tools":["*"]}}'
          [IO.File]::WriteAllText($Fallback,$tpl,(New-Object Text.UTF8Encoding($false)))
          $fb=Read-Json $Fallback
          $fixed=($null -ne $fb)
        }catch{ $fixed=$false }
      }
      if($fixed){ Add-Line 'GREEN' $f.module $f.id '已自动修复，根因 id=fallback（内置模板重写）' }
      else{
        Add-Line 'RED' 'fallback.json' 'fallback' 'fallback.json 缺失或非法 JSON'
        if($Auto -and $Fake -eq '' -and $f.fix.kind -eq 'auto'){ Set-Frozen 'fallback' '自动修复失败：模板重写后仍不可解析' }
      }
    } else { Add-Line 'GREEN' 'fallback.json' 'fallback' 'fallback.json 解析正常' }
  }

  $timeoutSec=$Cfg1.timeoutSec
if(((Get-Date)-$StartT).TotalSeconds -gt $timeoutSec){
  Add-Line 'RED' 'self' 'self-stop' ('[SELF-STOP] 超时：单次运行超过 '+$timeoutSec+' 秒，主动退出')
  if(-not $Quiet){ Write-Output ('doctor: [SELF-STOP] 超时 '+$timeoutSec+' 秒') }
  $icLine=@{ ts=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'); type='self-stop'; reason='timeout'; secs=$timeoutSec } | ConvertTo-Json -Compress
  try{ [IO.File]::AppendAllText($Intercepts,($icLine+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  exit 4
}
[IO.File]::WriteAllText($Heart,(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' doctor',(New-Object Text.UTF8Encoding($false)))

  if($Fake -eq ''){
  $runsObj=$null
  try{ $runsObj=Read-Json $Runs }catch{}
  if($null -eq $runsObj){ $runsObj=@{} }
  $melt=@()
  foreach($e in $script:faultLevels.GetEnumerator()){
    $fid=$e.Key; $lv=$e.Value
    if($lv -eq 'RED'){
      $c=0
      try{ $v=$runsObj.$fid; if($null -ne $v){ $c=[int]$v } }catch{}
      $c++
      $runsObj | Add-Member -NotePropertyName $fid -NotePropertyValue $c -Force
      if($c -ge $Cfg1.maxSameFault){ $melt+=,$fid }
    } else {
      try{ $names=$runsObj.PSObject.Properties.Name; if($names -contains $fid){ $runsObj | Add-Member -NotePropertyName $fid -NotePropertyValue 0 -Force } }catch{}
    }
  }
  try{ Write-Json $Runs $runsObj }catch{}
  if($melt.Count -gt 0){
    Add-Line 'RED' 'self' 'self-stop' ('[SELF-STOP] 熔断：fault='+($melt -join ',')+' 同处连红 ≥ '+$Cfg1.maxSameFault+' 次，停止接单，等待人工介入')
    if(-not $Quiet){
      $script:lines | Where-Object { $_ -like '[[]RED[]]*' } | ForEach-Object { Write-Output $_ }
      $meltRed=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'RED' })
      $meltYellow=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'YELLOW' })
      $meltGreen=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'GREEN' })
      $meltGray=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'GRAY' })
      Write-Output ('doctor: '+$meltRed.Count+' 未解决红 / '+$meltYellow.Count+' 黄 / '+$meltGreen.Count+' 绿 / '+$meltGray.Count+' 灰')
      Write-Output ('doctor: [SELF-STOP] 熔断 '+($melt -join ',')+'；复位=crystal.ps1 -Verb reset-melt -Arg1 <fault>')
    }
    $icLine=@{ ts=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'); type='self-stop'; reason='melt'; faults=($melt -join ',') } | ConvertTo-Json -Compress
    try{ [IO.File]::AppendAllText($Intercepts,($icLine+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
    exit 4
  }
}
$unresolvedRed=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'RED' })
  $finalYellow=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'YELLOW' })
  $finalGreen=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'GREEN' })
  $finalGray=@($script:faultLevels.GetEnumerator() | Where-Object { $_.Value -eq 'GRAY' })
  if($Fake -eq '' -and $unresolvedRed.Count -eq 0 -and $finalYellow.Count -eq 0){ Snap 'doctor 全绿快照' 'green' }
  # [fix-20261120-P2d] 桌宠提醒总线：有红就进 pet-inbox（30 分钟节流，独立于 -PushQQ）
  if($Fake -eq '' -and $unresolvedRed.Count -gt 0){
    try{
      $petSt=Join-Path $Data 'pet-tell.state.json'
      $nowMs=[DateTimeOffset]::Now.ToUnixTimeMilliseconds(); $lastMs=0
      try{ $ps2=Get-Content $petSt -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $ps2.lastAt){ $lastMs=[int64]$ps2.lastAt } }catch{}
      if($nowMs - $lastMs -ge 1800000){
        $tell=Join-Path $PSScriptRoot 'crystal-pet-tell.ps1'
        $first2=@($script:lines | Where-Object { $_ -like '[[]RED[]]*' } | Select-Object -First 1)[0]
        $pt=('doctor 有 '+$unresolvedRed.Count+' 个红项：'+$first2); if($pt.Length -gt 120){ $pt=$pt.Substring(0,120) }
        & $tell -Text $pt -Level 'red'
        try{ [IO.File]::WriteAllText($petSt, ('{"lastAt":'+$nowMs+'}'), (New-Object Text.UTF8Encoding($false))) }catch{}
      }
    }catch{}
  }
  if(-not $Quiet){
    $script:lines | Where-Object { $_ -like '[[]RED[]]*' } | ForEach-Object { Write-Output $_ }
    Write-Output ('doctor: '+$unresolvedRed.Count+' 未解决红 / '+$finalYellow.Count+' 黄 / '+$finalGreen.Count+' 绿 / '+$finalGray.Count+' 灰')
  }
  if($PushQQ -and $unresolvedRed.Count -gt 0){
  try{
    $pushState=$PushState
    $nowMs=[DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $lastMs=0
    try{ $ps=Get-Content $pushState -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $ps.lastPushedAt){ $lastMs=[int64]$ps.lastPushedAt } }catch{}
    if($nowMs - $lastMs -lt 1800000){ if(-not $Quiet){ Write-Output 'doctor: 红警推送节流（30 分钟内已推过），跳过' } }
    else {
    $tok=(Get-Content $ConsoleTok -Raw).Trim()
    $first=@($script:lines | Where-Object { $_ -like '[[]RED[]]*' } | Select-Object -First 1)[0]
    $msg='[crystal 红警] doctor：'+$unresolvedRed.Count+' 个未解决红；首条：'+$first
    if($msg.Length -gt 480){ $msg=$msg.Substring(0,480) }
    $body=@{userId=''; message=$msg} | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:3100/api/send/private' -Headers @{'x-console-token'=$tok} -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 10
    Add-Line 'GREEN' 'self' 'push-qq' 'QQ 红警已推送 private:'
    try{ $respTxt=($resp | ConvertTo-Json -Compress); if($respTxt.Length -gt 300){ $respTxt=$respTxt.Substring(0,300) } }catch{ $respTxt='(无响应体)' }
    try{ [IO.File]::AppendAllText($Alerts,('[PUSH] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' to=owner channel=qq result=ok resp='+$respTxt+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
    try{ [IO.File]::WriteAllText($pushState, ('{"lastPushedAt":'+$nowMs+'}'), (New-Object Text.UTF8Encoding($false))) }catch{}
    }
  }catch{
    try{ Add-Line 'YELLOW' 'self' 'push-qq' ('QQ 红警推送失败：'+$_.Exception.Message) }catch{}
    try{ [IO.File]::AppendAllText($Alerts,('[PUSH] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' to=owner channel=qq result=fail resp='+$_.Exception.Message+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  }
}
# —— CR-008 A：平价/高峰行 + 队列评估（不参与红黄绿计数）——
if($Fake -eq ''){
  try{
    $pi=Get-CrystalPricing -OverrideNow $PricingNow
    $pline='[PRICING] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' tier='+$pi.tier+' 当前='+$pi.label+' 下一窗口='+$pi.nextLabel+' '+$pi.nextMinutes+' 分钟 usage-source=none（真实 usage 写入端待授权，见 '+$CostF+'）'
    if($pi.fallback){ $pline+=' [CONF-FALLBACK]'; try{ if(Get-Command Write-CrystalFallback -ErrorAction SilentlyContinue){ Write-CrystalFallback -Module 'doctor-pricing' -Reason 'crystal.json pricing 段缺失或非法' -FallbackTo '默认窗口 09:00-12:00/14:00-18:00' | Out-Null } }catch{} }
    try{ [IO.File]::AppendAllText($Alerts,($pline+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
    if(-not $Quiet){ Write-Output ('doctor: '+$pline) }
    $q=Read-Json $QueueFile
    if($null -ne $q -and $null -ne $q.items){
      foreach($it in @($q.items | Where-Object { $_.status -eq 'pending' })){
        $force=$false; try{ if($it.force -eq $true){ $force=$true } }catch{}
        if($pi.tier -eq 'peak' -and -not $force){
          $qline='[QUEUE-WAIT] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' item='+$it.id+' tier=peak 高峰等待（主人喊「现在做」即插队）'
          try{ [IO.File]::AppendAllText($Alerts,($qline+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
          if(-not $Quiet){ Write-Output ('doctor: '+$qline) }
          continue
        }
        $cmd=''; try{ $cmd=[string]$it.command }catch{}
        $okPath=($cmd -like ($CrystalHome+'\*') -or $cmd -like ($Base+'\*'))
        if($cmd -eq '' -or -not $okPath){
          $qline='[QUEUE-REFUSED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' item='+$it.id+' 命令为空或路径越界，跳过'
          try{ [IO.File]::AppendAllText($Alerts,($qline+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
          if(-not $Quiet){ Write-Output ('doctor: '+$qline) }
          continue
        }
        $tier=$pi.tier
        $st=Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$cmd -WindowStyle Hidden -PassThru
        $qline='[QUEUE-RUN] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' item='+$it.id+' tier='+$tier+$(if($force){' force=现在做'}else{''})+' pid='+$st.Id
        try{ [IO.File]::AppendAllText($Alerts,($qline+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
        if(-not $Quiet){ Write-Output ('doctor: '+$qline) }
        $it | Add-Member -NotePropertyName 'status' -NotePropertyValue 'running' -Force
        $it | Add-Member -NotePropertyName 'startedAt' -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') -Force
        $amt='0.00'; try{ if($null -ne $it.estCNY){ $amt=[string]$it.estCNY } }catch{}
        $note2=''; try{ $note2=[string]$it.notes }catch{}
        $uline=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'|'+[string]$it.title+'|'+$note2+'|'+$amt+'|'+$tier
        try{ [IO.File]::AppendAllText($UsageFile,($uline+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
      }
      try{ Write-Json $QueueFile $q }catch{}
    }
  }catch{
    Add-ErrorLine ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' [PRICING] 异常：'+$_.Exception.Message)
  }
}
$nowDoc=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
$DocSt=@{lastChecked=$nowDoc}
if(Test-Path $DocState){ try{ $oldDoc2=Get-Content $DocState -Raw | ConvertFrom-Json; if($null -ne $oldDoc2){ $DocSt.lastRedAt=$oldDoc2.lastRedAt; $DocSt.lastGreenAt=$oldDoc2.lastGreenAt } }catch{} }
if($unresolvedRed.Count -gt 0){ $DocSt.lastRedAt=$nowDoc } else { $DocSt.lastGreenAt=$nowDoc }
try{ [IO.File]::WriteAllText($DocState,($DocSt | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false))) }catch{}
if($unresolvedRed.Count -gt 0){ exit 1 } else { exit 0 }
}catch{
  Add-ErrorLine ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' 顶层异常：'+$_.Exception.Message)
  if(-not $Quiet){ Write-Output ('doctor 顶层异常：'+$_.Exception.Message) }
  exit 2
}
