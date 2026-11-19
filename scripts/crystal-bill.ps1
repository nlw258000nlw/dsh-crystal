# crystal-bill.ps1 - 按插件分账视图（P9 ③）：只汇总 usage.jsonl 的 module 用量，不改账、不算钱
# 用法：powershell -File crystal-bill.ps1（输出 ≤12 行；金额口径=cost.jsonl，真实 usage 写入端待授权）
$ErrorActionPreference='SilentlyContinue'
$UsageFile='F:\crystal\data\usage.jsonl'
try{ $cjB=(Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json); if($cjB.paths.usage -and $cjB.paths.usage -ne ''){ $UsageFile=[string]$cjB.paths.usage } }catch{}
try{
  $t=Get-Content 'C:\Users\丽微\.dsh\plugins\dsh-crystal\crystal.json' -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $t.paths -and $null -ne $t.paths.usage -and $t.paths.usage -ne ''){ $UsageFile=[string]$t.paths.usage }
}catch{}
if(-not (Test-Path $UsageFile)){
  Write-Output '[BILL] usage.jsonl 不存在（真实用量写入端待授权后才有账单）'
  exit 0
}
$mods=@{}
$total=@{rows=0;ok=0;inTok=[long]0;outTok=[long]0;dur=[long]0}
foreach($l in @(Get-Content $UsageFile -Encoding UTF8)){
  if(($l.Trim()) -eq ''){ continue }
  try{ $o=$l | ConvertFrom-Json }catch{ continue }
  if($null -eq $o){ continue }
  $m=[string]$o.module; if($m -eq ''){ $m='unknown' }
  if(-not $mods.ContainsKey($m)){ $mods[$m]=@{rows=0;ok=0;inTok=[long]0;outTok=[long]0;dur=[long]0;lastTs=''} }
  $e=$mods[$m]
  $e.rows+=1
  if($o.ok){ $e.ok+=1 }
  $it=[long]$o.inputTokens; if($it -gt 0){ $e.inTok+=$it }
  $ot=[long]$o.outputTokens; if($ot -gt 0){ $e.outTok+=$ot }
  $du=[long]$o.durationMs; if($du -gt 0){ $e.dur+=$du }
  $ts=[string]$o.ts; if($ts -gt $e.lastTs){ $e.lastTs=$ts }
  $total.rows+=1; if($o.ok){ $total.ok+=1 }; $total.inTok+=$it; $total.outTok+=$ot; $total.dur+=$du
}
$nfmt={ param([long]$n) '{0:N0}' -f $n }
Write-Output '[BILL] module | 行数 | 成功 | 输入tok | 输出tok | 耗时ms'
foreach($m in @($mods.Keys | Sort-Object)){
  $e=$mods[$m]
  Write-Output ('[BILL] '+$m+' | '+$e.rows+' | '+$e.ok+' | '+$e.inTok+' | '+$e.outTok+' | '+$e.dur)
}
Write-Output ('[BILL] 合计 | '+$total.rows+' | '+$total.ok+' | '+$total.inTok+' | '+$total.outTok+' | '+$total.dur)
Write-Output '[BILL] 只汇总用量不改账；金额口径=cost.jsonl（真实 usage 写入端待授权）'
exit 0
