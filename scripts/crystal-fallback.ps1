# crystal-fallback.ps1 - 兜底留痕共用库：写 fallbacks.log + 同处连退计数（≥3 黄、≥10 红），禁止静默兜底（§10.4）
# 用法：. '路径\crystal-fallback.ps1' 后调用 Write-CrystalFallback -Module '<模块>' -Reason '<原因>' -FallbackTo '<退到哪>'
# 返回 PSCustomObject{ count, level }；level=ok|yellow|red；计数状态落 F:\crystal\data\fallback-state.json
function Write-CrystalFallback{
  param([string]$Module='unknown',[string]$Reason='',[string]$FallbackTo='')
  $cfgPath=Join-Path $PSScriptRoot '..\crystal.json'
  $log='F:\crystal\data\fallbacks.log'
  try{
    $cj=Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($null -ne $cj.paths -and $null -ne $cj.paths.fallbacks -and $cj.paths.fallbacks -ne ''){ $log=[string]$cj.paths.fallbacks }
  }catch{}
  $statePath='F:\crystal\data\fallback-state.json'
  $enc=New-Object Text.UTF8Encoding($false)
  $now=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  $st=@{}
  try{
    $old=Get-Content $statePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json
    if($null -ne $old){
      foreach($p in $old.PSObject.Properties){
        $st[$p.Name]=@{ count=[int]$p.Value.count; lastAt=[string]$p.Value.lastAt }
      }
    }
  }catch{}
  if(-not $st.ContainsKey($Module)){ $st[$Module]=@{ count=0; lastAt='' } }
  if([string]::IsNullOrEmpty($FallbackTo)){ $FallbackTo='内置默认' }
  $cnt=[int]$st[$Module].count + 1
  $st[$Module].count=$cnt
  $st[$Module].lastAt=$now
  $level='ok'; if($cnt -ge 10){ $level='red' } elseif($cnt -ge 3){ $level='yellow' }
  if($level -eq 'yellow'){ $tag='[FALLBACK-YELLOW]' } elseif($level -eq 'red'){ $tag='[FALLBACK-RED]' } else { $tag='[FALLBACK]' }
  $line=$tag+' '+$now+' module='+$Module+' reason='+$Reason+' fallbackTo='+$FallbackTo+' count='+$cnt
  try{
    [IO.File]::AppendAllText($log, $line+"`r`n", $enc)
    [IO.File]::WriteAllText($statePath, ($st | ConvertTo-Json -Depth 5), $enc)
  }catch{}
  Write-Host $line
  return [pscustomobject]@{ count=$cnt; level=$level }
}

# Get-CrystalAlertsPath - alerts.log 路径的唯一作者：先读总表 crystal.json paths.alerts，缺失才退内置默认并留痕（§10 一张表不许两个作者）
function Get-CrystalAlertsPath{
  $cfgPath=Join-Path $PSScriptRoot '..\crystal.json'
  $p=''
  try{ $cj=Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $cj.paths -and $null -ne $cj.paths.alerts -and $cj.paths.alerts -ne ''){ $p=[string]$cj.paths.alerts } }catch{}
  if($p -eq ''){
    $p=Join-Path (Split-Path $PSScriptRoot -Parent) 'data\crystal\alerts.log'
    try{ Write-CrystalFallback -Module 'alerts-path' -Reason 'crystal.json paths.alerts 缺失' -FallbackTo $p | Out-Null }catch{}
  }
  return $p
}