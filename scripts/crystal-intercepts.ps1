# crystal-intercepts.ps1 - 拦截账：只读展示 F:\crystal\data\intercepts.jsonl（熔断/超时/兜底拦截留痕）
# 账本缺失=正常（尚无拦截事件）；路径可用 crystal.json paths.intercepts 覆盖
param([int]$Tail=10)
$ErrorActionPreference='SilentlyContinue'
$f='F:\crystal\data\intercepts.jsonl'
try{
  $t=Get-Content 'C:\Users\丽微\.dsh\plugins\dsh-crystal\crystal.json' -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $t.paths -and $null -ne $t.paths.intercepts -and $t.paths.intercepts -ne ''){ $f=[string]$t.paths.intercepts }
}catch{}
if(-not (Test-Path $f)){ Write-Output '[INTERCEPTS] 账本为空（尚无熔断/超时拦截事件）'; exit 0 }
$lines=@(Get-Content $f -Encoding UTF8)
Write-Output ('[INTERCEPTS] 共 '+$lines.Count+' 笔，最近 '+([Math]::Min($Tail,$lines.Count))+' 笔：')
$lines | Select-Object -Last $Tail | ForEach-Object { Write-Output ('  '+$_) }
exit 0
