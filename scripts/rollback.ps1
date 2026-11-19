# rollback.ps1 - 只回滚 crystal 自己的 data\crystal 数据文件（truth/faults/heartbeat），不倒退日志与戳。
# 快照只认「doctor 全绿快照」：note.txt 里 state=green 才可回滚；没有全绿快照 → 拒绝并写 [ROLLBACK-REFUSED]。
# 回滚后自动跑一次 doctor 复检，结论写 [ROLLBACK-CHECK] 行；复检有红/黄 → 报红并建议再退上一份。
# 用法：-List 列快照与状态；-To <ts> 恢复指定全绿快照；缺省恢复最新全绿快照；-DryRun 只演示不落地。
param([string]$To='',[switch]$List,[switch]$DryRun)
$ErrorActionPreference='Stop'
$Base=Split-Path -Parent $PSScriptRoot
$Data=Join-Path $Base 'data\crystal'
$Snap=Join-Path $Data 'snapshots'
$Alerts=Join-Path $Data 'alerts.log'
$Doctor=Join-Path $Base 'scripts\doctor.ps1'
function Log-R([string]$level,[string]$msg){
  try{ [IO.File]::AppendAllText($Alerts,('['+$level+'] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' '+$msg+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
}
function Get-State($d){
  $n=Join-Path $d 'note.txt'
  if(-not (Test-Path $n)){ return 'none' }
  try{
    $raw=[IO.File]::ReadAllBytes($n)
    if($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF){ $txt=[Text.Encoding]::UTF8.GetString($raw,3,$raw.Length-3) } else { $txt=[Text.Encoding]::UTF8.GetString($raw) }
    $o=$txt | ConvertFrom-Json
    if($null -ne $o -and $null -ne $o.state){ return [string]$o.state }
  }catch{}
  return 'unknown'
}
if(-not (Test-Path $Snap)){ Write-Output 'rollback: 没有快照目录'; exit 0 }
$snaps = Get-ChildItem $Snap -Directory | Sort-Object Name -Descending
if($List){
  $snaps | ForEach-Object { Write-Output ($_.Name+'  state='+(Get-State $_.FullName)) }
  exit 0
}
$greens=@($snaps | Where-Object { (Get-State $_.FullName) -eq 'green' })
if($To -ne ''){
  $target = $greens | Where-Object { $_.Name -eq $To } | Select-Object -First 1
  if($null -eq $target){
    $exists = $snaps | Where-Object { $_.Name -eq $To } | Select-Object -First 1
    if($null -ne $exists){
      Log-R 'RED' ('[ROLLBACK-REFUSED] '+$To+' 不是全绿快照（state='+(Get-State $exists.FullName)+'）')
      Write-Output ('rollback: 拒绝回滚到 '+$To+'（非全绿快照）')
      exit 1
    }
    Log-R 'RED' ('[ROLLBACK-REFUSED] '+$To+' 不存在')
    Write-Output ('rollback: 找不到快照 '+$To)
    exit 1
  }
} else {
  $target = $greens | Select-Object -First 1
  if($null -eq $target){
    Log-R 'RED' '[ROLLBACK-REFUSED] no-green-snapshot：没有 doctor 全绿快照，拒绝回滚（不许退到红/黄状态）'
    Write-Output 'rollback: 没有全绿快照，拒绝回滚'
    exit 1
  }
}
Write-Output ('rollback: 目标快照 '+$target.Name+'（全绿）'+$(if($DryRun){'（DryRun，不落地）'}else{''}))
foreach($f in (Get-ChildItem $target.FullName -File | Where-Object { $_.Name -ne 'note.txt' })){
  $dst = Join-Path $Data $f.Name
  if($DryRun){ Write-Output ('  将恢复 '+$dst); continue }
  Copy-Item $f.FullName $dst -Force
}
if(-not $DryRun){
  Log-R 'GREEN' ('[ROLLBACK] 从快照 '+$target.Name+' 恢复 data\crystal 数据文件（alerts/errors/stamps 不倒退，回滚事件向前记）')
  $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Doctor
  $code = $LASTEXITCODE
  $sum = ($out | Where-Object { $_ -like 'doctor: *未解决红*' } | Select-Object -Last 1)
  Log-R 'GREEN' ('[ROLLBACK-CHECK] 快照='+$target.Name+' 复检='+$sum+' exit='+$code)
  if($code -ne 0){
    Log-R 'RED' '[ROLLBACK-CHECK] 未过：复检有红/黄，建议再退上一份全绿快照或人工介入'
    Write-Output 'rollback: 完成，但复检未过（见 alerts.log [ROLLBACK-CHECK]）'
    exit 1
  }
  Write-Output 'rollback: 完成，复检全绿'
  exit 0
}
Write-Output 'rollback: DryRun 完成'