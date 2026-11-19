# crystal-keywords.ps1 - 关键词自动归纳：从 crystal.json 的 plugin-capability 条目 tasks 自动生成关键词→插件映射
# 输出 F:\crystal\data\keyword-map.json {generatedAt, entries:[{word, plugins:[]}]}；只读总表不写回
# 用法：powershell -File crystal-keywords.ps1   （exit 0；输出 [KEYWORDS] 汇总行）
$ErrorActionPreference='SilentlyContinue'
$Cj='C:\Users\丽微\.dsh\plugins\dsh-crystal\crystal.json'
$Out='F:\crystal\data\keyword-map.json'
try{
  $cj=Get-Content $Cj -Raw -Encoding UTF8 | ConvertFrom-Json
  if($cj.paths.keywords){ $Out=[string]$cj.paths.keywords }
}catch{}
$caps=@()
try{ $caps=@($cj.'plugin-capability') }catch{}
$map=@{}
foreach($c in $caps){
  $plug=[string]$c.plugin
  foreach($t in @($c.tasks)){
    foreach($raw in ([regex]::Split([string]$t,'[/、，,|;；。]'))){
      $w=$raw.Trim().ToLower()
      if($w.Length -lt 2 -or $w.Length -gt 12){ continue }
      if($w -match '^(的|了|和|或|与|一个|怎么|什么)$'){ continue }
      if(-not $map.ContainsKey($w)){ $map[$w]=New-Object System.Collections.ArrayList }
      if(-not ($map[$w] -contains $plug)){ [void]$map[$w].Add($plug) }
    }
  }
}
$entries=@()
foreach($k in ($map.Keys | Sort-Object)){ $entries+=@{ word=$k; plugins=@($map[$k]) } }
$obj=@{ generatedAt=(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'); source='plugin-capability'; entries=$entries }
[IO.File]::WriteAllText($Out,($obj | ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
Write-Output ('[KEYWORDS] '+$obj.generatedAt+' 关键词 '+$entries.Count+' 条 → '+$Out)
exit 0
