# detect.ps1 - dsh-crystal 环境探测（去本机化 P7）
# 探测 crystalHome / bridgeHome / maintHome / backupRoot / dshRoot / 端口，写 data\detected.json
# 优先级：环境变量 > crystal.json.paths 已有值 > 本机习惯路径探测 > 默认值。
param([switch]$Quiet, [switch]$Force)
$ErrorActionPreference = 'Stop'

$Pkg = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$CjPath = Join-Path $Pkg 'crystal.json'
$Det = Join-Path $Pkg 'data\detected.json'
$cj = $null
try { $cj = Get-Content $CjPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
$paths = $null
if ($cj -and $cj.paths) { $paths = $cj.paths }

function Get-Home([string]$envName, [string]$cfgVal, [string]$defaultVal) {
  if ($envName) {
    $e = [Environment]::GetEnvironmentVariable($envName)
    if ($e) { return $e }
  }
  if ($cfgVal -and $cfgVal -ne '') { return $cfgVal }
  return $defaultVal
}
function Get-PathVal([string]$key, [string]$defaultVal) {
  $v = ''
  try { if ($paths -and ($paths.PSObject.Properties[$key])) { $v = [string]$paths.$key } } catch {}
  if ($v -and $v -ne '') { return $v }
  return $defaultVal
}

$userHome = $env:USERPROFILE
$desktop = [Environment]::GetFolderPath('Desktop')

# crystalHome：env CRYSTAL_HOME > crystal.json.paths.crystalHome > %LOCALAPPDATA%\crystal
$crystalHome = Get-Home 'CRYSTAL_HOME' (Get-PathVal 'crystalHome' '') (Join-Path $env:LOCALAPPDATA 'crystal')

# 兼容现网：如果 F:\crystal 存在而探测值不存在，宁可沿用现网目录（数据不搬家）
if (-not (Test-Path $crystalHome) -and (Test-Path 'F:\crystal')) { $crystalHome = 'F:\crystal' }

$dataRoot = Join-Path $crystalHome 'data'
$killRoot = Get-Home 'CRYSTAL_KILL' (Get-PathVal 'killRoot' '') (Join-Path $crystalHome 'kill')
$l0Root = Get-Home 'CRYSTAL_L0' (Get-PathVal 'l0Root' '') (Join-Path $crystalHome 'l0')
$backupRoot = Get-Home 'CRYSTAL_BACKUP' (Get-PathVal 'backupRoot' '') 'F:\备份'
# 现网兼容：习惯目录在就沿用（数据不搬家）
if (-not (Test-Path $killRoot)) { foreach ($c in @('F:\crystal-kill', 'D:\crystal-kill', 'C:\crystal-kill')) { if (Test-Path $c) { $killRoot = $c; break } } }
if (-not (Test-Path $l0Root)) { foreach ($c in @('F:\crystal-l0', 'D:\crystal-l0', 'C:\crystal-l0')) { if (Test-Path $c) { $l0Root = $c; break } } }
if (-not (Test-Path $backupRoot)) { foreach ($c in @('F:\备份', 'D:\备份', 'C:\备份')) { if (Test-Path $c) { $backupRoot = $c; break } } }

# bridgeHome：env QQ_DSH_BRIDGE > crystal.json.paths.bridgeHome > 常见目录探测
$bridgeHome = Get-Home 'QQ_DSH_BRIDGE' (Get-PathVal 'bridgeHome' '') ''
if ($bridgeHome -eq '' -or -not (Test-Path (Join-Path $bridgeHome 'src\bridge.js'))) {
  foreach ($cand in @('F:\qq-dsh-bridge\qq-bridge', 'D:\qq-dsh-bridge\qq-bridge', 'C:\qq-dsh-bridge\qq-bridge')) {
    if ($cand -and (Test-Path (Join-Path $cand 'src\bridge.js'))) { $bridgeHome = $cand; break }
  }
}

# maintHome：env CRYSTAL_MAINT > crystal.json.paths.maintHome > 常见目录探测（可空）
$maintHome = Get-Home 'CRYSTAL_MAINT' (Get-PathVal 'maintHome' '') ''
if ($maintHome -eq '') {
  foreach ($cand in @('F:\系统维护', 'D:\系统维护', 'C:\系统维护')) {
    if (Test-Path $cand) { $maintHome = $cand; break }
  }
}

# dshRoot：env DSH_HOME > 常见目录探测 > 运行进程反推
$dshRoot = Get-Home 'DSH_HOME' (Get-PathVal 'dshRoot' '') ''
if ($dshRoot -eq '' -or -not (Test-Path (Join-Path $dshRoot 'resources\app.asar'))) {
  foreach ($cand in @('F:\新建文件夹', 'D:\新建文件夹', 'F:\DSH', 'D:\DSH', 'F:\DeepSeek', 'D:\DeepSeek')) {
    if ($cand -and (Test-Path (Join-Path $cand 'resources\app.asar'))) { $dshRoot = $cand; break }
  }
}
if ($dshRoot -eq '') {
  try {
    $procs = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path })
    if ($procs.Count -gt 0) {
      $p = $procs[0].Path
      $d = Split-Path $p -Parent
      while ($d -and $d -ne (Split-Path $d -Parent)) {
        if ((Split-Path $d -Leaf) -eq 'resources') { $dshRoot = Split-Path $d -Parent; break }
        $d = Split-Path $d -Parent
      }
    }
  } catch {}
}

# 端口：bridge 3100 / onebot 3000 / snowluma 5099 / gui 从 dsh-gui-port.js
$ports = [ordered]@{ bridge = 3100; onebot = 3000; snowluma = 5099; gui = 0 }
$guiPort = 0
try {
  if ($maintHome -and (Test-Path (Join-Path $maintHome 'dsh-gui-port.js'))) {
    $gp = & node (Join-Path $maintHome 'dsh-gui-port.js') 2>$null
    if ($gp -match '^\d+$') { $guiPort = [int]$gp }
  }
} catch {}
$ports.gui = $guiPort

$tz = ''
try { $tz = [TimeZoneInfo]::Local.Id } catch { $tz = 'Asia/Shanghai' }

$out = [ordered]@{
  detectedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  pluginHome = $Pkg
  userHome = $userHome
  desktop = $desktop
  crystalHome = $crystalHome
  dataRoot = $dataRoot
  killRoot = $killRoot
  l0Root = $l0Root
  backupRoot = $backupRoot
  bridgeHome = $bridgeHome
  maintHome = $maintHome
  dshRoot = $dshRoot
  ports = $ports
  tz = $tz
}

New-Item -ItemType Directory -Path (Split-Path $Det) -Force | Out-Null
$enc = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($Det, ($out | ConvertTo-Json), $enc)
if (-not $Quiet) {
  Write-Host ('detect: crystalHome=' + $crystalHome)
  Write-Host ('detect: bridgeHome=' + $bridgeHome)
  Write-Host ('detect: maintHome=' + $maintHome)
  Write-Host ('detect: backupRoot=' + $backupRoot + ' dshRoot=' + $dshRoot + ' tz=' + $tz)
  Write-Host ('detect: ports bridge=' + $ports.bridge + ' onebot=' + $ports.onebot + ' snowluma=' + $ports.snowluma + ' gui=' + $ports.gui)
  Write-Host ('detect: wrote ' + $Det)
}
