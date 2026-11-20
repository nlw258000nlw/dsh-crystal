# crystal-ability.ps1 - 能力台账生成器（只读扫描，输出 data\crystal\ability.json）
# 来源：31 个 scripts\*.ps1 首行注释 / crystal.ps1 的 switch 动词 / lib\index.js 路由 / fault-dictionary 22 条 / rules 20 槽 / bridge.js [crystal 钩子
# 用法：powershell -File crystal-ability.ps1 [-OutFile <路径>]；只读，不落盘任何业务文件
param([string]$OutFile='')
$ErrorActionPreference='Continue'
$Base=Split-Path -Parent $PSScriptRoot
$Data=Join-Path $Base 'data\crystal'
if($OutFile -eq ''){ $OutFile=Join-Path $Data 'ability.json' }
$enc=New-Object Text.UTF8Encoding($false)
$items=@()
# 1. scripts 首行注释
foreach($f in @(Get-ChildItem (Join-Path $PSScriptRoot '*.ps1') -File | Sort-Object Name)){
  $first=''
  foreach($l in @(Get-Content $f.FullName -Encoding UTF8 -TotalCount 4)){
    if($l -match '^#\s*([a-zA-Z0-9_.-]+\.ps1\s*-\s*.+)$'){ $first=$matches[1]; break }
  }
  $items+=[pscustomobject]@{ id=('script.'+$f.BaseName); group='脚本'; name=$f.Name; desc=$first; run=[pscustomobject]@{ kind='cli'; cmd=('powershell -NoProfile -ExecutionPolicy Bypass -File "'+$f.FullName+'"') }; state='unknown'; enabled=$true; doc=$f.FullName }
}
# 2. crystal.ps1 switch 动词
$cps=Join-Path $PSScriptRoot 'crystal.ps1'
$cp=@(Get-Content $cps -Encoding UTF8)
$verbs=@()
for($i=0; $i -lt $cp.Count; $i++){
  if($cp[$i] -match "^\s*'([a-z][a-z0-9-]*)' \{"){
    $verbs+=[pscustomobject]@{ verb=$matches[1]; line=$i+1 }
  }
}
foreach($v in $verbs){
  $items+=[pscustomobject]@{ id=('cli.'+$v.verb); group='命令'; name=('crystal '+$v.verb); desc=('crystal.ps1 动词（第 '+$v.line+' 行）'); run=[pscustomobject]@{ kind='cli'; cmd=('powershell -NoProfile -ExecutionPolicy Bypass -File "'+$cps+'" '+$v.verb) }; state='unknown'; enabled=$true; doc=$cps+'#'+$v.line }
}
# 3. lib\index.js 路由
$ix=Join-Path $Base 'lib\index.js'
if(Test-Path $ix){
  $ixt=[IO.File]::ReadAllText($ix)
  $rs=[regex]::Matches($ixt, "path:\s*ROUTE\s*\+\s*'([^']+)'")
  foreach($r in $rs){
    $rp=$r.Groups[1].Value
    $items+=[pscustomobject]@{ id=('route.'+$rp); group='接口'; name=('/dsh-crystal'+$rp); desc='面板 HTTP 路由'; run=$null; state='unknown'; enabled=$true; doc=$ix }
  }
}
# 4. fault-dictionary 22 条
$fd=Join-Path $Data 'fault-dictionary.json'
try{
  $fdj=Get-Content $fd -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($f in @($fdj.faults)){
    $items+=[pscustomobject]@{ id=('check.'+$f.id); group='体检'; name=$f.id; desc=[string]$f.symptom; run=[pscustomobject]@{ kind='cli'; cmd=('powershell -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'doctor.ps1')+'"') }; state='unknown'; enabled=$true; doc=$fd+'#'+$f.id }
  }
}catch{}
# 5. rules 20 槽
$cjf=Join-Path $Base 'crystal.json'
try{
  $cj=Get-Content $cjf -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($mode in @('chat','work')){
    foreach($r in @($cj.rules.$mode)){
      $txt=[string]$r.text
      $st='unknown'; if($txt){ $st='ok' }
      $items+=[pscustomobject]@{ id=('rule.'+$mode+'.'+$r.id); group=('规则-'+$mode); name=($mode+' 规则槽 '+$r.id); desc=('已填：'+($txt.Substring(0,[math]::Min(60,$txt.Length)))); run=$null; state=$st; enabled=($r.enabled -ne $false); doc=$cjf+'#rules.'+$mode }
    }
  }
}catch{}
# 6. bridge.js [crystal 钩子
$br='F:\qq-dsh-bridge\qq-bridge\src\bridge.js'
try{
  if(Test-Path $br){
    $b=[IO.File]::ReadAllText($br)
    $ms=[regex]::Matches($b,'\[crystal[^\]]*\]')
    $n=0
    foreach($m in $ms){ $n++
      $items+=[pscustomobject]@{ id=('hook.'+$n); group='桥侧钩子'; name=('hook.'+$n); desc=($m.Value+'（bridge.js）'); run=$null; state='unknown'; enabled=$true; doc=$br }
    }
  }
}catch{}
# counts
$counts=[ordered]@{
  scripts=@($items | Where-Object { $_.id -like 'script.*' }).Count
  cli=@($items | Where-Object { $_.id -like 'cli.*' }).Count
  routes=@($items | Where-Object { $_.id -like 'route.*' }).Count
  checks=@($items | Where-Object { $_.id -like 'check.*' }).Count
  rules=@($items | Where-Object { $_.id -like 'rule.*' }).Count
  hooks=@($items | Where-Object { $_.id -like 'hook.*' }).Count
}
$out=[ordered]@{ generatedAt=(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'); counts=$counts; items=$items }
try{ [IO.File]::WriteAllText($OutFile, ($out | ConvertTo-Json -Depth 8), $enc) }catch{}
Write-Output ('[ABILITY] 共 ' + $items.Count + ' 条 -> ' + $OutFile)
Write-Output ('counts=' + ($counts | ConvertTo-Json -Compress))
