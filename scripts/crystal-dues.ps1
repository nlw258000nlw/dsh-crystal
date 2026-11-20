# crystal-dues.ps1 - 今日欠债：只读汇总 dtodo 三轨（life/work/daily）的未完成与逾期件数
# 数据源=记忆目录（缺省 $env:USERPROFILE\.dsh\memories，可用 crystal.json paths.memories 覆盖）
# 条目格式（dsh-memory-evolve lib\todo.js）：§ 分隔，首行 [时间] [id: x] [q1-4]? [due: YYYY-MM-DD]? [status: ...]
# 输出 ≤5 行；源文件缺失=source:none 不算错；缓存 $cache
param([switch]$Quiet)
$ErrorActionPreference='SilentlyContinue'
$mem=Join-Path $env:USERPROFILE '.dsh\.dsh\memories'
$Plugin=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
$DetF=Join-Path $Plugin 'data\detected.json'
if(Test-Path $DetF){
  try{ $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json; if($det.dataRoot){ $DataHome=[string]$det.dataRoot } }catch{}
}
$cache=Join-Path $DataHome 'dues.json'
$enc=New-Object Text.UTF8Encoding($false)
try{
  $t=Get-Content (Join-Path $Plugin 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $t.paths -and $null -ne $t.paths.memories -and $t.paths.memories -ne ''){ $mem=[string]$t.paths.memories }
}catch{}
$today=Get-Date -Format 'yyyy-MM-dd'
$srcs=@(
  @{ track='life'; file=Join-Path $mem 'TODOS-life.md' },
  @{ track='work'; file=Join-Path $mem 'TODOS-work.md' },
  @{ track='daily'; file=Join-Path $mem ('daily\'+$today+'.todo.md') }
)
$found=$false; $unfinished=0; $overdue=@()
foreach($s in $srcs){
  if(-not (Test-Path $s.file)){ continue }
  $found=$true
  $txt=[IO.File]::ReadAllText($s.file,[Text.Encoding]::UTF8)
  $body=$txt -replace '^<!--[\s\S]*?-->\s*',''
  $body=$body -replace '^\s*§\s*\r?\n?',''
  $entries=@($body -split '§' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  foreach($e in $entries){
    $first=($e -split "`r?`n")[0]
    $status='pending'
    if($first -match '\[status:\s*([a-z]+)\]'){ $status=$Matches[1] }
    if($status -in @('done','cancelled')){ continue }
    $unfinished++
    if($first -match '\[due:\s*(\d{4}-\d{2}-\d{2})\]'){
      $due=$Matches[1]
      if($due -lt $today){
        $title=(($e -split "`r?`n") | Select-Object -Skip 1 | Where-Object { $_ -ne '' } | Select-Object -First 1)
        if($title -eq $null){ $title=$first }
        $overdue+=@{ track=$s.track; due=$due; title=$title }
      }
    }
  }
}
$obj=@{ generatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); unfinished=$unfinished; overdue=$overdue; source=$found }
try{ [IO.File]::WriteAllText($cache,($obj | ConvertTo-Json -Depth 4),$enc) }catch{}
if(-not $found){
  Write-Output ('[DUES] '+$today+' source=none（没有待办文件，欠债 0）')
  exit 0
}
Write-Output ('[DUES] '+$today+' 未完成 '+$unfinished+' 件，逾期 '+$overdue.Count+' 件')
$shown=0
foreach($o in ($overdue | Sort-Object due)){
  if($shown -ge 4){ break }
  Write-Output ('[DUES-ITEM] 逾期 '+$o.due+' ['+$o.track+'] '+$o.title)
  $shown++
}
exit 0
