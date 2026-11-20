# crystal-cost.ps1 - P12⑥ 真实金额入账：usage.jsonl 真实桶 × 价目表 → cost.jsonl（只记不改账）
# 价目表：crystal.json pricing.rates = { inputPerM, outputPerM, cacheReadPerM }（每百万 token 元）
# 行格式：ts|source|tier|inputTokens|outputTokens|cacheReadTokens|amountCny
# 每行按 tier 乘数：peak×2、offpeak×1（主人 m06283 口径：高峰贵）
param([switch]$Once)
$ErrorActionPreference='SilentlyContinue'
$Base=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$DetF=Join-Path $Base 'data\detected.json'
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
if(Test-Path $DetF){
  try{ $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json; if($det.dataRoot){ $DataHome=[string]$det.dataRoot }; if($det.crystalHome){ $Base=[string]$det.crystalHome } }catch{}
}
$Data=$DataHome
$UsageFile=Join-Path $DataHome 'usage.jsonl'
$CostFile=Join-Path $DataHome 'cost.jsonl'
$CrystalCfg=Join-Path $Base 'crystal.json'
try{
  $cj=Get-Content $CrystalCfg -Raw -Encoding UTF8 | ConvertFrom-Json
  if($cj.paths.crystalHome){ $Base=[string]$cj.paths.crystalHome }
  if($cj.paths.dataHome){ $Data=[string]$cj.paths.dataHome }
  if($cj.paths.usage){ $UsageFile=[string]$cj.paths.usage }
  if($cj.paths.cost){ $CostFile=[string]$cj.paths.cost }
}catch{}
$rates=@{ inputPerM=2.0; outputPerM=8.0; cacheReadPerM=0.5 }
try{
  $pr=$cj.pricing.rates
  if($pr.inputPerM){ $rates.inputPerM=[double]$pr.inputPerM }
  if($pr.outputPerM){ $rates.outputPerM=[double]$pr.outputPerM }
  if($pr.cacheReadPerM){ $rates.cacheReadPerM=[double]$pr.cacheReadPerM }
}catch{}
$enc=New-Object Text.UTF8Encoding($false)
$costRows=@()
try{
  $old=Get-Content $CostFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') }
  foreach($o in $old){ try{ $parts=$o -split '\|'; if($parts.Count -ge 7){ $costRows+=[pscustomobject]@{ ts=$parts[0]; tier=$parts[2]; keys=$parts[0]+'|'+$parts[1]+'|'+$parts[2] } } }catch{} }
}catch{}
$seen=@{}
foreach($r in $costRows){ $seen[$r.keys]=$true }
$newN=0
try{
  $rows=@(Get-Content $UsageFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
  $out=@()
  foreach($ln in $rows){
    try{
      $u=$ln | ConvertFrom-Json
      if(-not $u.ts){ continue }
      if($u.module -eq 'bridge-start'){ continue }
      $inTok=[double]$u.inputTokens; if(-not $inTok){ $inTok=0 }
      $outTok=[double]$u.outputTokens; if(-not $outTok){ $outTok=0 }
      $cacheTok=0
      try{ if($u.cacheReadTokens){ $cacheTok=[double]$u.cacheReadTokens } }catch{}
      $tier=[string]$u.tier; if(-not $tier){ $tier='offpeak' }
      $mult=1.0; if($tier -eq 'peak'){ $mult=2.0 }
      $amt=($inTok/1000000.0*$rates.inputPerM + $outTok/1000000.0*$rates.outputPerM + $cacheTok/1000000.0*$rates.cacheReadPerM)*$mult
      $amount=[math]::Round($amt,6)
      $ts=[string]$u.ts
      $src=[string]$u.source; if(-not $src){ $src='usage' }
      $key=$ts+'|'+$src+'|'+$tier
      if($seen.ContainsKey($key)){ continue }
      $seen[$key]=$true
      $out+=($ts+'|'+$src+'|'+$tier+'|'+$inTok+'|'+$outTok+'|'+$cacheTok+'|'+$amount)
      $newN++
    }catch{}
  }
  if($out.Count -gt 0){
    [IO.File]::AppendAllText($CostFile, ($out -join "`r`n")+"`r`n", $enc)
  }
}catch{}
Write-Host ('[COST] 新增 '+$newN+' 行真实金额，共 '+($seen.Count)+' 行（只记不改账；价目表=in '+$rates.inputPerM+'/out '+$rates.outputPerM+'/cache '+$rates.cacheReadPerM+' 元每百万，peak×2）')
