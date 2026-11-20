# 薄包装：真正的 L0 在 $l0Real（锁三家当目录）。此文件只为兼容旧路径。
param([string]$Mode='Stamp',[switch]$Install)
$ErrorActionPreference='SilentlyContinue'
$l0Real=''
try{
  $detL0=Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\detected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($detL0.l0Root){ $l0Real=Join-Path ([string]$detL0.l0Root) 'crystal-l0.ps1' }
}catch{}
if($l0Real -eq '' -or -not (Test-Path $l0Real)){ $l0Real=Join-Path $env:LOCALAPPDATA 'crystal\l0\crystal-l0.ps1' }
$l0Args = @{ }
$PSBoundParameters.GetEnumerator() | ForEach-Object { $l0Args[$_.Key] = $_.Value }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $l0Real @l0Args