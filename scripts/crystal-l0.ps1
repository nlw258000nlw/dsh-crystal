# 薄包装：真正的 L0 在 F:\crystal-l0\crystal-l0.ps1（锁三家当目录）。此文件只为兼容旧路径。
param([string]$Mode='Stamp',[switch]$Install)
$ErrorActionPreference='SilentlyContinue'
$l0Args = @{ }
$PSBoundParameters.GetEnumerator() | ForEach-Object { $l0Args[$_.Key] = $_.Value }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'F:\crystal-l0\crystal-l0.ps1' @l0Args