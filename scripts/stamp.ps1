# stamp.ps1 - 外盖戳：L0 计划任务 CrystalL0-Stamp 调用，每天向 stamps\<yyyyMMdd>.jsonl 追加一行。
# crystal/doctor 只读戳、禁止自补；断供超时自报灰行（见 doctor.ps1 的 stamp-starvation）。
# §11.3：写前拿 Global\crystal-lock + 数据目录 lock，排队 90 秒超时跳过并写 [LOCK-SKIP]（不杀持锁进程）。
$ErrorActionPreference='Stop'
$Base=Split-Path -Parent $PSScriptRoot
. (Join-Path $Base 'scripts\crystal-lock.ps1')
$Stamps=Join-Path $Base 'data\crystal\stamps'
try{ $cjS=Get-Content (Join-Path $Base 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjS.paths -and $null -ne $cjS.paths.stamps -and $cjS.paths.stamps -ne ''){ $Stamps=[string]$cjS.paths.stamps } }catch{}
if(-not (Test-Path $Stamps)){ New-Item -ItemType Directory -Force -Path $Stamps | Out-Null }
$file=Join-Path $Stamps ((Get-Date -Format 'yyyyMMdd') + '.jsonl')
$lk=Get-CrystalWriteLock -Target $file -TimeoutSec 90
if($null -eq $lk){ Write-Output 'stamp: 锁被占，本次跳过（[LOCK-SKIP] 已留痕）'; exit 0 }
try{
  $line='{"ts":"' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz') + '","by":"L0"}'
  [IO.File]::AppendAllText($file, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
  Write-Output ("stamp: " + $file)
}finally{
  Release-CrystalWriteLock $lk
}
