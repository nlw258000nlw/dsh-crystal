# crystal-pack.ps1 —— P8 打包：把 dsh-crystal 源码 + 文档压成 release zip
# 用法：powershell -File crystal-pack.ps1 [-OutDir <目录>] [-Version <版本号>]
# 打包口径：排除 data 运行数据（只留 fault-dictionary.json）、node_modules、.git、.bak*、pet 诊断临时件
param(
  [string]$OutDir = '',
  [string]$Version = 'v1001'
)
$ErrorActionPreference = 'Stop'
$Pkg = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
if ($OutDir -eq '') { $OutDir = Join-Path ([Environment]::GetFolderPath('Desktop')) '' }
$stage = Join-Path $env:TEMP ("crystal-pack-" + $Version)
$dst = Join-Path $stage 'dsh-crystal'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $dst -Force | Out-Null

# 1) 主目录拷贝（排除运行时数据与临时件）
$rob1 = robocopy $Pkg $dst /E /XD data node_modules .git docs release screenshots /XF '*.bak*' '*.tmp' 'pet-diag*' 'smoke-*' '*.1.log' '*.generic' /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "robocopy 主目录失败 code=$LASTEXITCODE" }
# 2) 只带 fault-dictionary.json（体检字典=源码级数据）
$srcData = Join-Path $Pkg 'data\crystal\fault-dictionary.json'
if (Test-Path $srcData) {
  New-Item -ItemType Directory -Path (Join-Path $dst 'data\crystal') -Force | Out-Null
  Copy-Item $srcData (Join-Path $dst 'data\crystal\fault-dictionary.json') -Force
}
# 3) docs：只发公开文档（能力页/原理页/preview.svg），内部交接/验收单不发
$dstDocs = Join-Path $dst 'docs'
New-Item -ItemType Directory -Path $dstDocs -Force | Out-Null
foreach ($d in @('能力页.md','原理页.md','preview.svg')) {
  $srcD = Join-Path $Pkg ("docs\" + $d)
  if (Test-Path $srcD) { Copy-Item $srcD (Join-Path $dstDocs $d) -Force }
}
# 4) screenshots 目录（存在才带）
$shotSrc = Join-Path $Pkg 'screenshots'
if (Test-Path $shotSrc) {
  $rob3 = robocopy $shotSrc (Join-Path $dst 'screenshots') /E /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -ge 8) { throw "robocopy screenshots 失败 code=$LASTEXITCODE" }
}

# 5) 用通用 crystal.json 覆盖 staged（不发布现网私人配置）；删掉 .generic 中间件
Copy-Item (Join-Path $Pkg 'crystal.json.generic') (Join-Path $dst 'crystal.json') -Force
Remove-Item (Join-Path $dst 'crystal.json.generic') -Force -ErrorAction SilentlyContinue

$zip = Join-Path $OutDir ("dsh-crystal-" + $Version + "-" + (Get-Date -Format 'yyyyMMdd') + '.zip')
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $dst -DestinationPath $zip -CompressionLevel Optimal
$files = @(Get-ChildItem $dst -Recurse -File)
$bytes = ($files | Measure-Object -Property Length -Sum).Sum
Write-Host ('[PACK] ' + $zip)
Write-Host ('[PACK] files=' + $files.Count + ' bytes=' + $bytes)
