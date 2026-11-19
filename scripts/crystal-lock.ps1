# crystal-lock.ps1 - §11.3 写路径互斥共用库：Global\crystal-lock 全局互斥 + F:\crystal\data\lock 文件锁
# 用法：. '路径\crystal-lock.ps1' 后
#   $lk=Get-CrystalWriteLock -Target '<目标文件>' -TimeoutSec 90
#   if($null -eq $lk){ <跳过：库已自动写 [LOCK-SKIP] 留痕> }
#   else { try{ <写操作> } finally { Release-CrystalWriteLock $lk } }
# 只许「排队→超时→跳过并留痕」，绝不杀持锁进程；取锁与释放全包 try/finally，异常路径也释放。
$script:CLockFallbacks='F:\crystal\data\fallbacks.log'
try{ $cjf=Get-Content 'C:\Users\丽微\.dsh\plugins\dsh-crystal\crystal.json' -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cjf.paths.fallbacks -and $cjf.paths.fallbacks -ne ''){ $script:CLockFallbacks=[string]$cjf.paths.fallbacks } }catch{}
function Write-CrystalLockTrace([string]$Tag,[string]$Target,[string]$Reason,[double]$WaitedSec){
  $enc=New-Object Text.UTF8Encoding($false)
  $line=$Tag+' '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' lock=Global\crystal-lock|F:\crystal\data\lock target='+$Target+' waitedSec='+([math]::Round($WaitedSec,2))+' reason='+$Reason
  try{ [IO.File]::AppendAllText($script:CLockFallbacks,($line+"`r`n"),$enc) }catch{}
  Write-Host $line
}
function Get-CrystalWriteLock{
  param([string]$Target='',[int]$TimeoutSec=90)
  $mx=$null; $fs=$null; $started=[datetime]::Now
  try{
    $mx=[System.Threading.Mutex]::new($false,'Global\crystal-lock')
    $acquired=$false
    try{ $acquired=$mx.WaitOne($TimeoutSec*1000) }
    catch [System.Threading.AbandonedMutexException]{ $acquired=$true }
    if(-not $acquired){
      $w=([datetime]::Now-$started).TotalSeconds
      Write-CrystalLockTrace '[LOCK-SKIP]' $Target ('互斥排队超时（他人持锁，跳过本次写入）') $w
      try{ $mx.Dispose() }catch{}
      return $null
    }
    try{
      $fs=[IO.File]::Open('F:\crystal\data\lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    }catch{
      $w=([datetime]::Now-$started).TotalSeconds
      Write-CrystalLockTrace '[LOCK-SKIP]' $Target ('文件锁被占：'+$_.Exception.Message) $w
      try{ $mx.ReleaseMutex() }catch{}
      try{ $mx.Dispose() }catch{}
      return $null
    }
    return [pscustomobject]@{ mutex=$mx; fileStream=$fs; target=$Target; acquiredAt=[datetime]::Now }
  }catch{
    $w=([datetime]::Now-$started).TotalSeconds
    Write-CrystalLockTrace '[LOCK-FAIL]' $Target ([string]$_.Exception.Message) $w
    if($null -ne $fs){ try{ $fs.Dispose() }catch{} }
    if($null -ne $mx){ try{ $mx.ReleaseMutex() }catch{}; try{ $mx.Dispose() }catch{} }
    return $null
  }
}
function Release-CrystalWriteLock($Lk){
  if($null -eq $Lk){ return }
  try{ $Lk.fileStream.Dispose() }catch{}
  try{ $Lk.mutex.ReleaseMutex() }catch{}
  try{ $Lk.mutex.Dispose() }catch{}
}
