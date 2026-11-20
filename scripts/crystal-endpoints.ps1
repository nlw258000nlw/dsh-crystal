# crystal-endpoints.ps1 - 服务发现：按 dsh-gui-port.js 判据（/api/__probe__ 回 401 且纯文本 unauthorized）探真 GUI 端口，落 $Ep（§10.2）
# -Probe：探测并写 endpoints.json（默认）；-Check：复探对比，漂移写 [ENDPOINTS-DRIFT] 行到 alerts.log
# 令牌自愈本段只做检测：bridge baseUrl 与 GUI 端口不一致时 mismatch=true 并建议留痕，不自动改桥配置（待主人授权）
param([string]$Verb='Probe', [switch]$Check)
$ErrorActionPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'crystal-lock.ps1')
$Plugin=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$MaintHome=Join-Path $env:LOCALAPPDATA 'crystal\sys'
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
$BridgeHome=Join-Path $env:LOCALAPPDATA 'crystal\bridge'
$DetF=Join-Path $Plugin 'data\detected.json'
if(Test-Path $DetF){
  try{
    $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json
    if($det.dataRoot){ $DataHome=[string]$det.dataRoot }
    if($det.bridgeHome){ $BridgeHome=[string]$det.bridgeHome }
    if($det.maintHome){ $MaintHome=[string]$det.maintHome }
  }catch{}
}
$GuiJs=Join-Path $MaintHome 'dsh-gui-port.js'
$Ep=Join-Path $DataHome 'endpoints.json'
$Alerts=''
try{ $cjep=Get-Content (Join-Path $Plugin 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjep.paths.alerts -and $cjep.paths.alerts -ne ''){ $Alerts=[string]$cjep.paths.alerts } }catch{}
if($Alerts -eq ''){ . (Join-Path $PSScriptRoot 'crystal-fallback.ps1'); $Alerts=Get-CrystalAlertsPath }
$BridgeCfg=Join-Path $BridgeHome 'config.json'
$enc=New-Object Text.UTF8Encoding($false)
function Get-GuiPort{
  try{
    $node=Get-Command node -ErrorAction Stop | Select-Object -ExpandProperty Source
    $out=& $node $GuiJs 2>$null | Out-String
    $port=[int]($out.Trim())
    if($port -gt 0 -and $port -lt 65536){ return $port }
  }catch{}
  return 0
}
function Test-Tcp([int]$p){
  try{
    $c=New-Object Net.Sockets.TcpClient
    $iar=$c.BeginConnect('127.0.0.1',$p,$null,$null)
    if($iar.AsyncWaitHandle.WaitOne(800)){ $c.EndConnect($iar); $c.Close(); return $true }
    $c.Close(); return $false
  }catch{ return $false }
}
$now=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
$gui=Get-GuiPort
$ob3000=Test-Tcp 3000
$ob3001=Test-Tcp 3001
$bw=''
if(Test-Path $BridgeCfg){
  $raw=[IO.File]::ReadAllText($BridgeCfg)
  $m=[regex]::Match($raw,'"baseUrl"\s*:\s*"([^"]+)"')
  if($m.Success){ $bw=$m.Groups[1].Value }
}
$obj=@{ checkedAt=$now; gui=@{ port=$gui; baseUrl=('http://127.0.0.1:'+$gui); source='dsh-gui-port.js 判据（401+纯文本 unauthorized）' }; onebot=@{ http3000=$ob3000; ws3001=$ob3001 }; bridgeBaseUrl=$bw }
if($gui -gt 0 -and $bw -ne '' -and $bw -match (':'+$gui+'/?$')){ $obj.mismatch=$false }
elseif($gui -gt 0 -and $bw -ne ''){ $obj.mismatch=$true }
else { $obj.mismatch=$null }
if(($Verb -eq 'Probe') -and -not $Check){
  $lkep=Get-CrystalWriteLock -Target $Ep -TimeoutSec 90
  if($null -eq $lkep){ Write-Output ('[ENDPOINTS-SKIP] '+$now+' guiPort='+$gui+'（锁被占，已留痕）'); exit 0 }
  try{
    try{ [IO.File]::WriteAllText($Ep,($obj | ConvertTo-Json -Depth 5),$enc) }catch{}
    Write-Output ('[ENDPOINTS] '+$now+' guiPort='+$gui+' onebot3000='+$ob3000+' onebot3001='+$ob3001+' bridgeBaseUrl='+$bw+' mismatch='+$obj.mismatch)
    if($gui -eq 0){ exit 3 }
    exit 0
  }finally{
    Release-CrystalWriteLock $lkep
  }
}
# -Check：与落盘 endpoints.json 对比，漂移写 alerts.log
$old=$null
try{ $old=Get-Content $Ep -Raw -Encoding UTF8 | ConvertFrom-Json }catch{}
if($null -ne $old){
  if([int]$old.gui.port -ne $gui -or [bool]$old.onebot.http3000 -ne $ob3000 -or [bool]$old.onebot.ws3001 -ne $ob3001){
    $line='[ENDPOINTS-DRIFT] '+$now+' old='+$old.gui.port+'/3000:'+$old.onebot.http3000+'/3001:'+$old.onebot.ws3001+' new='+$gui+'/3000:'+$ob3000+'/3001:'+$ob3001
    try{ [IO.File]::AppendAllText($Alerts,($line+"`r`n"),$enc) }catch{}
    $lkdrift=Get-CrystalWriteLock -Target $Ep -TimeoutSec 90
    if($null -eq $lkdrift){ Write-Output $line; Write-Output ('[ENDPOINTS-SKIP] '+$now+'（锁被占，漂移行照报、endpoints.json 未更新）'); exit 1 }
    try{
      try{ [IO.File]::WriteAllText($Ep,($obj | ConvertTo-Json -Depth 5),$enc) }catch{}
      Write-Output $line
      exit 1
    }finally{
      Release-CrystalWriteLock $lkdrift
    }
  }
}
$lkep2=Get-CrystalWriteLock -Target $Ep -TimeoutSec 90
if($null -eq $lkep2){ Write-Output ('[ENDPOINTS-SKIP] '+$now+'（锁被占，已留痕）'); exit 0 }
try{
  try{ [IO.File]::WriteAllText($Ep,($obj | ConvertTo-Json -Depth 5),$enc) }catch{}
  Write-Output ('[ENDPOINTS-OK] '+$now+' guiPort='+$gui+' 无漂移')
  exit 0
}finally{
  Release-CrystalWriteLock $lkep2
}
