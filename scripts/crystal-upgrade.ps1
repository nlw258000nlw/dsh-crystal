# crystal-upgrade.ps1 - 升级参谋（P7 大管家创意⑤）：升级 DSH/桥前的兼容性预检，只读只建议
# 用法：crystal-upgrade.ps1（缺省全检，exit 0=可以升/有黄建议，exit 1=有红拦截）
# 检查：①DSH 版本对齐（profiles\desktop\package.json @deepseek-ai/* vs 注册表 DisplayVersion）②备份新鲜度（一键回滚最新快照 ≤7 天）
#       ③bundles 台账对齐（package.json bundles 数 vs crystal.json plugins 条数）④桥脚本备份新鲜度（bridge.js.bak-* 最新一份 ≤14 天）
# ⑤doctor 终检（转调 doctor.ps1 摘要）——只读不写任何被查文件；产出 F:\crystal\data\upgrade-check.txt
$ErrorActionPreference='SilentlyContinue'
$Data='F:\crystal\data'
$Out=Join-Path $Data 'upgrade-check.txt'
$enc=New-Object Text.UTF8Encoding($false)
$rows=@()
$redCount=0
# ①版本对齐
try{
  $pkg=Get-Content 'C:\Users\丽微\.dsh\profiles\desktop\package.json' -Raw -Encoding UTF8 | ConvertFrom-Json
  $deps=@($pkg.dependencies.PSObject.Properties | Where-Object { $_.Name -like '@deepseek-ai/*' } | ForEach-Object { $_.Value })
  $regVer=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'DeepSeek Harness' } | Select-Object -First 1).DisplayVersion
  $bad=@($deps | Where-Object { $_ -ne $regVer })
  if($bad.Count -gt 0){ $rows+=('[RED] 版本不对齐：插件依赖 '+($bad -join ',')+' vs 宿主 '+$regVer+'——升级前先统一'); $redCount++ }
  else{ $rows+=('[GREEN] 版本对齐：@deepseek-ai/* 全部='+$regVer) }
}catch{ $rows+=('[YELLOW] 版本检查失败：'+$_.Exception.Message) }
# ②一键回滚现行备份新鲜度（真源=F:\备份\现行-*，七件齐全才算可用）
try{
  $snaps=@(Get-ChildItem 'F:\备份' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^现行-\d{8}-\d{4}$' } | Sort-Object Name -Descending)
  $need=@('桥接-bridge','维护脚本','工作区','插件配置-profile','插件-plugins','记忆','会话-今天')
  $usable=$null
  foreach($sn in $snaps){
    $miss=@($need | Where-Object { -not (Test-Path (Join-Path $sn.FullName $_)) })
    if($miss.Count -eq 0){ $usable=$sn; break }
  }
  if($null -eq $usable){ $rows+=('[RED] F:\备份 没有七件齐全的 现行-* 备份——升级前先跑 crystal backup 刷新'); $redCount++ }
  else{
    $age=(New-TimeSpan -Start $usable.LastWriteTime -End (Get-Date)).TotalDays
    if($age -gt 7){ $rows+=('[RED] 一键回滚最新备份 '+$usable.Name+' 已 '+[math]::Round($age,1)+' 天（>7 天）——先跑 crystal backup 刷新再升级'); $redCount++ }
    else{ $rows+=('[GREEN] 一键回滚备份 '+$usable.Name+'（'+[math]::Round($age,1)+' 天前，七件齐全）') }
  }
}catch{ $rows+=('[YELLOW] 备份检查失败：'+$_.Exception.Message) }
# ③bundles 台账对齐
try{
  $pkg=Get-Content 'C:\Users\丽微\.dsh\profiles\desktop\package.json' -Raw -Encoding UTF8 | ConvertFrom-Json
  $bn=@($pkg.dsh.profile.bundles).Count
  $cj=Get-Content 'C:\Users\丽微\.dsh\plugins\dsh-crystal\crystal.json' -Raw -Encoding UTF8 | ConvertFrom-Json
  $pn=@($cj.plugins).Count
  $rows+=('[INFO] bundles='+$bn+' 条，总表插件='+$pn+' 条（升级后应一致）')
}catch{ $rows+=('[YELLOW] bundles 检查失败：'+$_.Exception.Message) }
# ④桥脚本备份新鲜度
try{
  $baks=@(Get-ChildItem 'F:\qq-dsh-bridge\qq-bridge\src\bridge.js.bak-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if($baks.Count -eq 0){ $rows+=('[YELLOW] bridge.js 无备份——升级前先落一份 .bak') }
  else{
    $age=(New-TimeSpan -Start $baks[0].LastWriteTime -End (Get-Date)).TotalDays
    if($age -gt 14){ $rows+=('[YELLOW] bridge.js 最新备份 '+$baks[0].Name+' 已 '+[math]::Round($age,1)+' 天') }
    else{ $rows+=('[GREEN] bridge.js 备份新鲜（'+[math]::Round($age,1)+' 天前）') }
  }
}catch{ $rows+=('[YELLOW] 桥备份检查失败：'+$_.Exception.Message) }
# ⑤doctor 终检摘要
$docOut=& powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\丽微\.dsh\plugins\dsh-crystal\scripts\doctor.ps1' -Quiet 2>&1 | Out-String
$sum=@($docOut -split "`r?`n" | Where-Object { $_ -match '未解决红' } | Select-Object -First 1)
$rows+=('[INFO] doctor 终检：'+(if($sum){ ($sum -join '').Trim() } else { '无法获取（请手动跑 doctor.ps1）' }))
[IO.File]::WriteAllText($Out,(($rows -join "`r`n")+"`r`n"),$enc)
foreach($r in $rows){ Write-Output $r }
if($redCount -gt 0){ Write-Output ('[UPGRADE] 有 '+$redCount+' 条红，先处理再升'); exit 1 }
Write-Output '[UPGRADE] 全绿/仅黄建议，可以升级'
exit 0
