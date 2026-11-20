# crystal-mem.ps1 - 记忆三件：3 天体检 / 建议箱 / 月度账本（只读体检+追加建议，永不自动删记忆）
# 用法：powershell -File crystal-mem.ps1 [-Verb check|inbox|month|add] [-Arg1 文字] [-Quiet]；输出 <=6 行；缓存数据目录 mem-check.json
param([string]$Verb='check',[string]$Arg1='',[switch]$Quiet)
$ErrorActionPreference='SilentlyContinue'
$enc=New-Object Text.UTF8Encoding($false)
$Base=Split-Path -Parent $PSScriptRoot
$CrystalJson=Join-Path $Base 'crystal.json'
$MemDir=$null
if(Test-Path $CrystalJson){
  try{
    $cj=[IO.File]::ReadAllText($CrystalJson,$enc)|ConvertFrom-Json
    $MemDir=$cj.paths.memories
  }catch{}
}
if(-not $MemDir -or -not (Test-Path $MemDir)){
  $MemDir=Join-Path $env:USERPROFILE '.dsh\.dsh\memories'
}
if(-not (Test-Path $MemDir)){ if(-not $Quiet){ Write-Host 'mem: source=none 找不到记忆目录' }; exit 0 }
$DataHome=Join-Path $Base 'data'
if(-not (Test-Path $DataHome)){ [IO.Directory]::CreateDirectory($DataHome)|Out-Null }

switch -Exact ($Verb.ToLower()) {
 'check' {
   $files=@(Get-ChildItem $MemDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\.' })
   $totalN=0; $totalB=0; $fresh=@(); $stale=@()
   $cut=(Get-Date).AddDays(-3)
   foreach($f in $files){
     $totalN++; $totalB+=$f.Length
     $line=$f.FullName.Substring($MemDir.Length).TrimStart('\','/')
     if($f.LastWriteTime -ge $cut){ $fresh+=$line } else { $stale+=$line }
   }
   $sugg=0; $sp=Join-Path $MemDir 'SUGGESTIONS.jsonl'
   if(Test-Path $sp){ $sugg=@([IO.File]::ReadAllLines($sp,$enc)|Where-Object {$_ -match '\S'}).Count }
   $out=[ordered]@{ checkedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); windowDays=3; files=$totalN; bytes=$totalB; active=(@($fresh|Where-Object {$_}).Count); stale=(@($stale|Where-Object {$_}).Count); suggestions=$sugg; staleList=(@($stale|Where-Object {$_})|Select-Object -First 20); dir=$MemDir }
   [IO.File]::WriteAllText((Join-Path $DataHome 'mem-check.json'), (ConvertTo-Json $out -Depth 4), $enc)
   if(-not $Quiet){
     Write-Host ('mem: 3天窗 | 共 '+$totalN+' 件 / '+[Math]::Round($totalB/1KB,1)+' KB | 3天内动过 '+$out.active+' | 没动过 '+$out.stale+' | 建议箱 '+$sugg)
     if($out.stale -gt 0){ Write-Host ('mem: 没动过的(只标不删): '+((@($stale|Where-Object {$_})|Select-Object -First 8) -join '、')) }
    # [fix-20261120-P2d] 桌宠提醒总线：三天没动过的记忆只标不删，也进 pet-inbox
    if($out.stale -gt 0){
      try{ $tell=Join-Path $PSScriptRoot 'crystal-pet-tell.ps1'; & $tell -Text ('记忆有 '+$out.stale+' 件三天没动过，等主人点头再删') -Level 'mem' }catch{}
    }
   }
 }
 'inbox' {
   $sp=Join-Path $MemDir 'SUGGESTIONS.jsonl'
   if(-not (Test-Path $sp)){ Write-Host 'mem: inbox=empty'; exit 0 }
   $lines=@([IO.File]::ReadAllLines($sp,$enc)|Where-Object {$_ -match '\S'})
   Write-Host ('mem: 建议箱共 '+$lines.Count+' 条，最近 '+[Math]::Min(8,$lines.Count)+' 条:')
   $lines | Select-Object -Last 8 | ForEach-Object { Write-Host ('  '+$_) }
 }
 'add' {
   $text=($Arg1|Out-String).Trim()
   if(-not $text){ Write-Host 'mem: add 需要文字'; exit 2 }
   $sp=Join-Path $MemDir 'SUGGESTIONS.jsonl'
   $row=[ordered]@{ at=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); from='panel'; text=$text }
   [IO.File]::AppendAllText($sp, ((ConvertTo-Json $row -Compress)+"`n"), $enc)
   Write-Host 'mem: 建议已收'
 }
 'month' {
   $d=Join-Path $MemDir 'daily'
   $m=@()
   if(Test-Path $d){
     foreach($f in @(Get-ChildItem $d -File -Filter '*.md' -ErrorAction SilentlyContinue)){
       $m+=[pscustomobject]@{ day=$f.Name; bytes=$f.Length; last=$f.LastWriteTime.ToString('MM-dd HH:mm') }
     }
   }
   $m=@($m|Sort-Object day)
   $tot=($m|Measure-Object bytes -Sum).Sum
   if(-not $Quiet){
     Write-Host ('mem: 月度账 | daily '+$m.Count+' 篇 / '+[Math]::Round($tot/1KB,1)+' KB')
     $m | Select-Object -Last 5 | ForEach-Object { Write-Host ('  '+$_.day+' '+[Math]::Round($_.bytes/1KB,1)+'KB 改于 '+$_.last) }
   }
 }
 default { Write-Host 'mem: 用法 check|inbox|month|add' }
}
