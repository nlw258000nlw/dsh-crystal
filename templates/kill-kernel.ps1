# kill.ps1 - 锁二 CrystalKillSwitch：纯 PowerShell、不依赖 node、不 import crystal 代码、不读 truth、不读 crystal 日志。
# 只判 <CRYSTAL_HOME>-kill\kill 文件在不在：在 → 停掉所有 crystal 进程（命令行含 dsh-crystal 的 powershell）并写 [KILL] 一行到 kill.log；不在 → 静默退出。
# kill 文件由桌面「停结晶.cmd」写入；恢复 = 人工删除 kill 文件（恢复动作由 crystal 侧留痕）。
$ErrorActionPreference='SilentlyContinue'
$KillFile='<CRYSTAL_HOME>-kill\kill'
$Log='<CRYSTAL_HOME>-kill\kill.log'
$Cfg2Path='<CRYSTAL_HOME>-kill\conf\lock2-kill.json'
try{
  $raw=[IO.File]::ReadAllBytes($Cfg2Path)
  if($raw.Length -ge 3 -and $raw[0]-eq 0xEF -and $raw[1]-eq 0xBB -and $raw[2]-eq 0xBF){ throw 'lock2 配置带 BOM' }
  $o=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json
  if($null -eq $o){ throw 'null' }
  if([int]$o.schemaVersion -ne 1){ try{ [IO.File]::AppendAllText($Log,('[RED] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=kill fault=conf-version msg=[CONF-VERSION-MISMATCH] 锁2 配置 schemaVersion='+$o.schemaVersion+'（当前支持 1），拒绝启动'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}; Write-Output ('kill: [CONF-VERSION-MISMATCH] lock=2 schema='+$o.schemaVersion); exit 7 }
  if($null -ne $o.killFile -and $o.killFile -ne ''){ $KillFile=[string]$o.killFile }
  if($null -ne $o.logPath -and $o.logPath -ne ''){ $Log=[string]$o.logPath }
  if($null -ne $o.intervalSec){ $script:intervalSec=[int]$o.intervalSec }
  $tL=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  try{ [IO.File]::AppendAllText($Log,('[CONF-LOAD] '+$tL+' lock=2 source=conf path='+$Cfg2Path+' schema='+$o.schemaVersion+' at='+$tL+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
}catch{
  try{ [IO.File]::AppendAllText($Log,('[YELLOW] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' module=kill fault=conf-lock2 msg=[CONF-FALLBACK] 锁2 配置不可用：'+$_.Exception.Message+'，已用默认值（killFile=<CRYSTAL_HOME>-kill\kill）'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
  $tL=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  try{ [IO.File]::AppendAllText($Log,('[CONF-LOAD] '+$tL+' lock=2 source=default path='+$Cfg2Path+' schema=default at='+$tL+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
}
if(-not (Test-Path $KillFile)){
  $KSt=Join-Path '<CRYSTAL_HOME>-kill' 'kill-state.json'
  $nowK=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  $stK=@{lastChecked=$nowK}
  try{ $oldK=Get-Content $KSt -Raw | ConvertFrom-Json; if($null -ne $oldK){ $stK.lastRedAt=$oldK.lastRedAt; $stK.lastGreenAt=$oldK.lastGreenAt } }catch{}
  $stK.lastGreenAt=$nowK
  try{ [IO.File]::WriteAllText($KSt,($stK | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false))) }catch{}
  exit 0
}
$trigger=''
try{ $trigger=(Get-Content $KillFile -Raw).Trim() }catch{}
$procs = Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'dsh-crystal' }
$killed=0
foreach($pr in $procs){
  try{ Stop-Process -Id $pr.ProcessId -Force -ErrorAction Stop; $killed++ }catch{}
}
$line='[KILL] ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' trigger=' + $trigger + ' killed=' + $killed
[IO.File]::AppendAllText($Log, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
$KSt=Join-Path '<CRYSTAL_HOME>-kill' 'kill-state.json'
$nowK=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
$stK=@{lastChecked=$nowK; lastRedAt=$nowK}
try{ [IO.File]::WriteAllText($KSt,($stK | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false))) }catch{}
Write-Output $line
