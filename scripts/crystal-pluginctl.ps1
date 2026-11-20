# crystal-pluginctl.ps1 - 插件按需调度开关（§24/主人 m03412：用到自动开、不用自动关、全程留痕、不删插件）
# 用法：crystal-pluginctl.ps1 [-Verb] enable|disable|temp|off|list [-Arg1 <插件名>] [-Arg2 <小时>] [-Test]
# enable = 真改 profiles\desktop\package.json 的 dsh.profile.bundles（改前 .bak-20261119-<时刻> 点名）；disable = 从 bundles 移除
# 台账 $DataHome\plugin-toggles.json；留痕 $DataHome\plugin-toggles.jsonl
# 安全边界：off 档不许自动开；always 档（常驻核心）不许关；不在总表纳管清单的名字拒绝操作；-Test 只打计划不写任何文件
param([string]$Verb='list',[string]$Arg1='',[string]$Arg2='',[switch]$Test)
$ErrorActionPreference='SilentlyContinue'
$Plugin=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
$DetF=Join-Path $Plugin 'data\detected.json'
if(Test-Path $DetF){
  try{
    $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json
    if($det.dataRoot){ $DataHome=[string]$det.dataRoot }
    if($det.userHome){ $ProfilePkg=Join-Path ([string]$det.userHome) '.dsh\profiles\desktop\package.json' }
  }catch{}
}
$toggleFile=Join-Path $DataHome 'plugin-toggles.json'
$traceLog=Join-Path $DataHome 'plugin-toggles.jsonl'
if(-not $ProfilePkg){ $ProfilePkg=Join-Path $env:USERPROFILE '.dsh\profiles\desktop\package.json' }
$CrystalJson=Join-Path $Plugin 'crystal.json'
$enc=New-Object Text.UTF8Encoding($false)
$softOffFile=Join-Path $DataHome 'soft-off.json'
function Get-Bundles{
  try{
    $p=[IO.File]::ReadAllText($ProfilePkg,[Text.Encoding]::UTF8) | ConvertFrom-Json
    return @($p.dsh.profile.bundles)
  }catch{ return @() }
}
function Read-Toggles{
  if(Test-Path $toggleFile){
    try{ $o=[IO.File]::ReadAllText($toggleFile,[Text.Encoding]::UTF8) | ConvertFrom-Json; if($null -ne $o.entries){ return @($o.entries) } }catch{ return @() }
  }
  return @()
}
function Get-ManagedPlugins{
  try{ $cj=[IO.File]::ReadAllText($CrystalJson,[Text.Encoding]::UTF8) | ConvertFrom-Json; return @($cj.plugins) }catch{ return @() }
}
function Write-Bundles($newList){
  # 只在真实变化时写：先备份再写，幂等
  try{
    $p=[IO.File]::ReadAllText($ProfilePkg,[Text.Encoding]::UTF8) | ConvertFrom-Json
    $p.dsh.profile.bundles=$newList
    $bak=$ProfilePkg+'.bak-20261119-'+((Get-Date -Format 'HHmm'))
    if(-not (Test-Path $bak)){ Copy-Item $ProfilePkg $bak -Force }
    [IO.File]::WriteAllText($ProfilePkg,($p | ConvertTo-Json -Depth 10),$enc)
    Write-Output ('备份已落：'+(Split-Path $bak -Leaf)+' '+(Get-Item $bak).Length+'B')
    return $true
  }catch{
    Write-Output ('写 bundles 失败：'+$_.Exception.Message)
    return $false
  }
}
function Trace($action,$name,$extra){
  $tr='[PLUGIN-TOGGLE] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' name='+$name+' action='+$action+$extra
  [IO.File]::AppendAllText($traceLog, ($tr+"`r`n"), $enc)
  Write-Output $tr
}
switch($Verb.ToLower()){
  'enable' {
    if(-not $Arg1){ Write-Output '用法: pluginctl enable <插件名> [-Arg2 小时] [-Test]'; exit 0 }
    $mp=@(Get-ManagedPlugins | Where-Object { [string]$_.name -eq $Arg1 })
    if($mp.Count -eq 0){ Write-Output ('拒绝：'+$Arg1+' 不在总表纳管清单'); exit 1 }
    $demand=[string]($mp[0].demand)
    if($demand -eq 'off'){ Write-Output ('拒绝：'+$Arg1+' 是 off 档，不许自动开（需主人原话）'); exit 1 }
    $hours=72; if($Arg2){ try{ $hours=[int]$Arg2 }catch{} }
    $bundles=@(Get-Bundles)
    $already=($bundles -contains $Arg1)
    if($Test){
      $plan='[TEST] 计划：enable '+$Arg1+'（demand='+$demand+'，lease='+$hours+'h）——'
      if($already){ $plan+='已在 bundles，只刷台账' } else { $plan+='将加入 bundles 并落备份' }
      Write-Output $plan
      exit 0
    }
    $ok=$true
    if(-not $already){ $bundles+=@($Arg1); $ok=Write-Bundles $bundles; if(-not $ok){ exit 1 } }
    # 台账 upsert
    $entries=@(Read-Toggles | Where-Object { $_.name -ne $Arg1 })
    $deadline=(Get-Date).AddHours($hours).ToString('yyyy-MM-dd HH:mm:ss')
    $entries+=@{ name=$Arg1; since=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); deadline=$deadline; status='on'; demand=$demand }
    [IO.File]::WriteAllText($toggleFile, (@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=$entries } | ConvertTo-Json -Depth 4), $enc)
    Trace 'enable' $Arg1 (' lease='+$hours+'h deadline='+$deadline)
    Write-Output ('生效待 DSH 重载（重启前先跟主人说）；到期 doctor 会喊 [PLUGIN-AUTO-OFF-DUE]')
    exit 0
  }
  'disable' {
    if(-not $Arg1){ Write-Output '用法: pluginctl disable <插件名> [-Test]'; exit 0 }
    $mp=@(Get-ManagedPlugins | Where-Object { [string]$_.name -eq $Arg1 })
    if($mp.Count -eq 0){ Write-Output ('拒绝：'+$Arg1+' 不在总表纳管清单'); exit 1 }
    if([string]($mp[0].demand) -eq 'always'){ Write-Output ('拒绝：'+$Arg1+' 是 always 常驻核心，不许关（需主人原话）'); exit 1 }
    $bundles=@(Get-Bundles)
    $already=($bundles -contains $Arg1)
    if($Test){
      $plan='[TEST] 计划：disable '+$Arg1+'——'
      if($already){ $plan+='将从 bundles 移除并落备份' } else { $plan+='本就不在 bundles，只销台账' }
      Write-Output $plan
      exit 0
    }
    if($already){ if(-not (Write-Bundles @($bundles | Where-Object { $_ -ne $Arg1 }))){ exit 1 } }
    $entries=@(Read-Toggles | Where-Object { $_.name -ne $Arg1 })
    $entries+=@{ name=$Arg1; since=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); deadline=''; status='off'; demand=[string]($mp[0].demand) }
    [IO.File]::WriteAllText($toggleFile, (@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=$entries } | ConvertTo-Json -Depth 4), $enc)
    Trace 'disable' $Arg1 ''
    Write-Output ('生效待 DSH 重载（重启前先跟主人说）')
    exit 0
  }
  'temp' {
    if(-not $Arg1){ Write-Output '用法: pluginctl temp <插件名> <分钟>'; exit 0 }
    $m=60; if($Arg2){ try{ $m=[int]$Arg2 }catch{} }
    if($Test){ Write-Output ('[TEST] 计划：temp '+$Arg1+' '+$m+' 分钟（只登记台账，不改 bundles）'); exit 0 }
    $entries=@(Read-Toggles | Where-Object { $_.name -ne $Arg1 })
    $deadline=(Get-Date).AddMinutes($m).ToString('yyyy-MM-dd HH:mm:ss')
    $entries+=@{ name=$Arg1; since=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); deadline=$deadline; status='temp'; demand='' }
    [IO.File]::WriteAllText($toggleFile, (@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=$entries } | ConvertTo-Json -Depth 4), $enc)
    Trace 'temp' $Arg1 (' '+$m+'min deadline='+$deadline)
    Write-Output '到期后 doctor/scan 会喊 [PLUGIN-AUTO-OFF-DUE]；真实开关用 enable/disable'
    exit 0
  }
  'off' {
    if(-not $Arg1){ Write-Output '用法: pluginctl off <插件名>'; exit 0 }
    if($Test){ Write-Output ('[TEST] 计划：off '+$Arg1+'（销台账留痕）'); exit 0 }
    $entries=@(Read-Toggles | Where-Object { $_.name -ne $Arg1 })
    [IO.File]::WriteAllText($toggleFile, (@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=$entries } | ConvertTo-Json -Depth 4), $enc)
    Trace 'off' $Arg1 ''
    exit 0
  }
  'soft-off' {
    if(-not $Arg1){ Write-Output '用法: pluginctl soft-off <插件名>'; exit 0 }
    $t=Get-Content $CrystalJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $plug=@($t.plugins | Where-Object { $_.name -eq $Arg1 -or $_.id -eq $Arg1 })
    if($plug.Count -eq 0){ Write-Output ('[SOFT-OFF] 拒绝：'+$Arg1+' 不在总表纳管清单'); exit 1 }
    if($plug[0].demand -eq 'always'){ Write-Output ('[SOFT-OFF] 拒绝：'+$Arg1+' 是常驻核心档不许软关'); exit 1 }
    if($Test){ Write-Output ('[TEST] 计划：soft-off '+$Arg1+'（写软关清单，不碰 bundles，秒级生效）'); exit 0 }
    $so=@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=@() }
    if(Test-Path $softOffFile){ try{ $so=Get-Content $softOffFile -Raw -Encoding UTF8 | ConvertFrom-Json }catch{} }
    if($null -eq $so.entries){ $so=@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=@() } }
    $so.entries=@($so.entries | Where-Object { $_.name -ne $Arg1 }) + @(@{ name=$Arg1; at=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') })
    [IO.File]::WriteAllText($softOffFile, ($so | ConvertTo-Json -Depth 4), $enc)
    Trace 'soft-off' $Arg1 '软关（bundles 未动，秒级生效）'
    exit 0
  }
  'soft-on' {
    if(-not $Arg1){ Write-Output '用法: pluginctl soft-on <插件名>'; exit 0 }
    if($Test){ Write-Output ('[TEST] 计划：soft-on '+$Arg1+'（从软关清单移除，秒级恢复）'); exit 0 }
    $so=@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=@() }
    if(Test-Path $softOffFile){ try{ $so=Get-Content $softOffFile -Raw -Encoding UTF8 | ConvertFrom-Json }catch{} }
    if($null -eq $so.entries){ $so=@{ updatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries=@() } }
    $so.entries=@($so.entries | Where-Object { $_.name -ne $Arg1 })
    [IO.File]::WriteAllText($softOffFile, ($so | ConvertTo-Json -Depth 4), $enc)
    Trace 'soft-on' $Arg1 '恢复'
    exit 0
  }
  default {
    $entries=@(Read-Toggles)
    if($entries.Count -eq 0){ Write-Output '[PLUGIN-TOGGLE] 台账为空'; exit 0 }
    foreach($e in $entries){ Write-Output ('[PLUGIN-TOGGLE] '+$e.name+' since='+$e.since+' deadline='+$e.deadline+' status='+$e.status) }
    exit 0
  }
}
