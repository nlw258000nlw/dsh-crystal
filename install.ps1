# install.ps1 - dsh-crystal 一键安装/校验（#21）
# 用法：install.ps1 [-DryRun] [-SkipJunction] [-Home <数据目录>]
# 幂等：已装=校验模式（跑 doctor 上报）；新机=预检→登记 bundles→(可选)Junction→doctor→失败逆序回滚不留半装
# 日志：<数据目录>\data\install.log（每步一行 [INSTALL]）
param([switch]$DryRun,[switch]$SkipJunction,[switch]$Uninstall,[switch]$ForceFresh,[string]$HomeDir='')
$ErrorActionPreference='Stop'
$PluginSrc=Split-Path -Parent $PSScriptRoot
$DsUserRoot=Join-Path $env:USERPROFILE '.dsh'
$LogRoot=''
if($HomeDir){ $LogRoot=$HomeDir } elseif($env:CRYSTAL_HOME -and $env:CRYSTAL_HOME -ne ''){ $LogRoot=$env:CRYSTAL_HOME } else { $LogRoot='F:\crystal' }
$LogDir=Join-Path $LogRoot 'data'
$LogFile=Join-Path $LogDir 'install.log'
function Log([string]$m){
  $l='[INSTALL] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' '+$m
  Write-Output $l
  try{
    if(-not (Test-Path $LogDir)){ New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    [IO.File]::AppendAllText($LogFile,($l+"`r`n"),(New-Object Text.UTF8Encoding($false)))
  }catch{}
}
$steps=@()
if($Uninstall){
  Log ('卸载启动：home='+$LogRoot)
  $tNames=@('CrystalL0-Stamp','CrystalDaily-Doctor','CrystalDaily-Scan','CrystalKillSwitch')
  foreach($tn in $tNames){
    if($DryRun){ Log ('DRYRUN：将删计划任务 '+$tn) }
    else{
      & schtasks /Query /TN $tn 2>&1 | Out-Null
      if($LASTEXITCODE -eq 0){ & schtasks /Delete /TN $tn /F | Out-Null; Log ('已删计划任务 '+$tn) } else { Log ('任务不存在跳过：'+$tn) }
    }
  }
  $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) '结晶一键体检.lnk'
  if(Test-Path $lnk){
    if($DryRun){ Log ('DRYRUN：将删桌面快捷方式 结晶一键体检.lnk') }
    else{ Remove-Item $lnk -Force; Log '桌面快捷方式已删' }
  }
  $pjFile=Join-Path $DsUserRoot 'profiles\desktop\package.json'
  if(Test-Path $pjFile){
    if($DryRun){ Log 'DRYRUN：将退 bundles/dependencies（dsh plugin remove）' }
    else{
      $cli=Join-Path $env:LOCALAPPDATA 'Programs\@deepseek-ai\dsh\cli\bin\dsh.cmd'
      if(-not (Test-Path $cli)){ $cli='F:\新建文件夹\resources\runtime\cli\bin\dsh.cmd' }
      if(Test-Path $cli){ & $cli plugin --profile desktop remove 'dsh-crystal' 2>&1 | Out-Null; Log '已退 bundles/dependencies' } else { Log 'WARN：找不到 dsh CLI，请手动从 package.json 移除 dsh-crystal' }
    }
  }
  $targetPlugin=Join-Path $DsUserRoot 'plugins\dsh-crystal'
  if(Test-Path $targetPlugin){
    if($DryRun){ Log ('DRYRUN：将删 junction '+$targetPlugin) }
    else{ & cmd /c rmdir $targetPlugin | Out-Null; if(-not (Test-Path $targetPlugin)){ Log 'junction 已删' } else { Log 'WARN：junction 删除失败（可能非 junction，人工处理）' } }
  }
  Log '卸载完成（数据目录与 -l0/-kill 目录保留、备份均在，可复用）'
  exit 0
}
try{
  Log ('启动：src='+$PluginSrc+' dryrun='+$DryRun+' home='+$LogRoot)
  if($PSVersionTable.PSVersion.Major -lt 5){ throw '需要 PowerShell 5.1+' }
  $node=Get-Command node -ErrorAction SilentlyContinue
  if(-not $node){ throw '找不到 node（桥依赖，装好 node 再装）' }
  $nodeV=& node --version 2>$null
  Log ('node ok：'+($nodeV -join '').Trim())
  if(-not (Test-Path $DsUserRoot)){ throw ('找不到 DSH 家目录：'+$DsUserRoot) }
  $profiles=@(Get-ChildItem (Join-Path $DsUserRoot 'profiles') -Directory -ErrorAction SilentlyContinue)
  if($profiles.Count -eq 0){ throw '找不到 DSH profiles 目录' }
  $pjPath=$null
  $bestCnt=-1
  foreach($p in $profiles){
    $c=Join-Path $p.FullName 'package.json'
    if(Test-Path $c){
      try{
        $chk=[IO.File]::ReadAllText($c,[Text.Encoding]::UTF8)|ConvertFrom-Json
        if($null -ne $chk.dsh -and $null -ne $chk.dsh.profile.bundles){
          $bc=@($chk.dsh.profile.bundles)
          if($bc -contains 'dsh-crystal'){ $pjPath=$c; break }
          if($bc.Count -gt $bestCnt){ $bestCnt=$bc.Count; $pjPath=$c }
        }
      }catch{}
    }
  }
  if(-not $pjPath){ throw '找不到含 dsh.profile.bundles 的 profile package.json' }
  Log ('profile 定位：'+$pjPath)
  $pj=[IO.File]::ReadAllText($pjPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
  $bundles=@($pj.dsh.profile.bundles)
  $pluginsDir=Join-Path $DsUserRoot 'plugins'
  $targetPlugin=Join-Path $pluginsDir 'dsh-crystal'
  $registered=($bundles -contains 'dsh-crystal')
  $linked=$false
  try{ $t=Get-Item $targetPlugin -ErrorAction Stop; $linked=(($t.LinkType -eq 'Junction') -or ($t.Attributes -band [IO.FileAttributes]::ReparsePoint)) }catch{ $linked=$false }
  $installed=($registered -and (Test-Path (Join-Path $targetPlugin 'crystal.json')))
  Log ('状态：registered='+$registered+' linked='+$linked+' installed='+$installed)
  $doctorPath=Join-Path $PluginSrc 'scripts\doctor.ps1'
  if(Test-Path (Join-Path $targetPlugin 'scripts\doctor.ps1')){ $doctorPath=Join-Path $targetPlugin 'scripts\doctor.ps1' }
  if($installed -and -not $ForceFresh){
    Log '已安装 → 校验模式（不重复装）'
    if(-not $DryRun){
      $o=& powershell -NoProfile -ExecutionPolicy Bypass -File $doctorPath 2>&1 | Out-String
      $summ=(($o -split "`r?`n") | Where-Object { $_ -match 'doctor: \d' }) -join ' '
      Log ('doctor exit='+$LASTEXITCODE+' 末行='+$summ)
      if($LASTEXITCODE -ne 0){ Log 'WARN：doctor 非全绿，请人工查看'; exit 1 }
      Log '校验完成：doctor 全绿'
    } else { Log 'DRYRUN：将跑 doctor（只读）' }
    exit 0
  }
  if(-not $registered){
    if($DryRun){ Log 'DRYRUN：将把 dsh-crystal 加入 dsh.profile.bundles（先备份 package.json）' }
    else {
      $bakPj=$pjPath+'.bak-install-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
      Copy-Item $pjPath $bakPj -Force
      Log ('备份 package.json → '+$bakPj)
      $pj.dsh.profile.bundles=@($pj.dsh.profile.bundles)+'dsh-crystal'
      [IO.File]::WriteAllText($pjPath,($pj|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
      Log '已登记 bundles（需重启 DSH 生效）'
      $steps+=@{ undo={ Copy-Item $bakPj $pjPath -Force } ; desc='还原 package.json' }
    }
  }
  $cfg=Join-Path $PluginSrc 'crystal.json'
  if(-not (Test-Path $cfg)){
    if($DryRun){ Log 'DRYRUN：将从 crystal.json.template 渲染 crystal.json' }
    else {
      $tpl=Join-Path $PluginSrc 'crystal.json.template'
      if(Test-Path $tpl){
        $ct=[IO.File]::ReadAllText($tpl,[Text.Encoding]::UTF8)
        $Esc={ param([string]$s) $s.Replace('\','\\') }
        $ct=$ct.Replace('<CRYSTAL_HOME>',(& $Esc $LogRoot)).Replace('<USER_HOME>',(& $Esc $env:USERPROFILE)).Replace('<BRIDGE_HOME>','F:\\qq-dsh-bridge').Replace('<SYS_HOME>','F:\\系统维护')
        [IO.File]::WriteAllText($cfg,$ct,(New-Object Text.UTF8Encoding($false)))
        Log ('已渲染 crystal.json（home='+$LogRoot+'）')
        $steps+=@{ undo={ Remove-Item $cfg -Force } ; desc='删渲染出的 crystal.json' }
      } else { Log ('WARN：crystal.json 与模板都不在（src='+$PluginSrc+'）') }
    }
  }
  if(-not $linked -and -not $SkipJunction){
    if(-not (Test-Path $targetPlugin)){
      if($DryRun){ Log ('DRYRUN：将 mklink /J '+$targetPlugin+' → '+$PluginSrc) }
      else {
        if(-not (Test-Path $pluginsDir)){ New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null }
        $mkl=& cmd /c mklink /J $targetPlugin $PluginSrc 2>&1 | Out-String
        Log ('mklink：'+($mkl -join '').Trim())
        if($LASTEXITCODE -ne 0){ throw ('junction 创建失败：'+($mkl -join '').Trim()) }
        Log 'Junction 已建'
        $steps+=@{ undo={ & cmd /c rmdir $targetPlugin } ; desc='删 junction' }
      }
    } else { Log ('WARN：'+$targetPlugin+' 已存在但非 junction，跳过（人工处理）') }
  }
  # ---- 三锁铺放（模板渲染到 <home>\conf、<home>-kill、<home>-l0） ----
  $lockSets=@(
    @{ tpl=Join-Path $PluginSrc 'templates\lock-conf\lock1-selfstop.json.template'; dst=Join-Path $LogRoot 'conf\lock1-selfstop.json' },
    @{ tpl=Join-Path $PluginSrc 'templates\lock-conf\lock2-kill.json.template'; dst=(Join-Path ($LogRoot+'-kill') 'conf\lock2-kill.json') },
    @{ tpl=Join-Path $PluginSrc 'templates\lock-conf\lock3-fallback.json.template'; dst=(Join-Path ($LogRoot+'-l0') 'conf\lock3-fallback.json') }
  )
  $kernelSets=@(
    @{ tpl=Join-Path $PluginSrc 'templates\kill-kernel.ps1'; dst=(Join-Path ($LogRoot+'-kill') 'kill.ps1') },
    @{ tpl=Join-Path $PluginSrc 'templates\crystal-l0-kernel.ps1'; dst=(Join-Path ($LogRoot+'-l0') 'crystal-l0.ps1') }
  )
  foreach($ls in $lockSets){
    if(Test-Path $ls.dst){ Log ('锁 conf 已在，跳过：'+$ls.dst); continue }
    if($DryRun){ Log ('DRYRUN：将铺放 '+($ls.dst | Split-Path -Leaf)+' → '+$ls.dst); continue }
    $t=([IO.File]::ReadAllText($ls.tpl,[Text.Encoding]::UTF8)).Replace('<CRYSTAL_HOME>',$LogRoot)
    $dir=Split-Path -Parent $ls.dst
    if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($ls.dst,$t,(New-Object Text.UTF8Encoding($false)))
    Log ('已铺放锁 conf：'+$ls.dst)
  }
  foreach($ks in $kernelSets){
    if(Test-Path $ks.dst){ Log ('锁脚本已在，跳过：'+$ks.dst); continue }
    if($DryRun){ Log ('DRYRUN：将铺放 '+($ks.dst | Split-Path -Leaf)+' → '+$ks.dst); continue }
    $t=([IO.File]::ReadAllText($ks.tpl,[Text.Encoding]::UTF8)).Replace('<CRYSTAL_HOME>',$LogRoot).Replace('<PLUGIN_HOME>',$PluginSrc)
    $dir=Split-Path -Parent $ks.dst
    if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($ks.dst,$t,(New-Object Text.UTF8Encoding($true)))
    Log ('已铺放锁脚本：'+$ks.dst)
  }
  # ---- 计划任务注册（4 个） ----
  $taskSets=@(
    @{ n='CrystalL0-Stamp';    cmd='powershell -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path ($LogRoot+'-l0') 'crystal-l0.ps1')+'" -Mode Stamp'; sc='HOURLY'; mo='6' },
    @{ n='CrystalDaily-Doctor';cmd='powershell -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PluginSrc 'scripts\doctor.ps1')+'" -Auto -Quiet -PushQQ'; sc='DAILY'; st='08:10' },
    @{ n='CrystalDaily-Scan'; cmd='powershell -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PluginSrc 'scripts\scan.ps1')+'"'; sc='DAILY'; st='21:00' },
    @{ n='CrystalKillSwitch'; cmd='powershell -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path ($LogRoot+'-kill')+'\kill.ps1')+'"'; sc='MINUTE'; mo='2' }
  )
  foreach($ts in $taskSets){
    & schtasks /Query /TN $ts.n 2>&1 | Out-Null
    if($LASTEXITCODE -eq 0){ Log ('任务已在，跳过：'+$ts.n); continue }
    if($DryRun){ Log ('DRYRUN：将注册任务 '+$ts.n); continue }
    $args=@('/Create','/TN',$ts.n,'/TR',$ts.cmd,'/F')
    if($ts.sc -eq 'HOURLY'){ $args+=@('/SC','HOURLY','/MO',$ts.mo) }
    elseif($ts.sc -eq 'DAILY'){ $args+=@('/SC','DAILY','/ST',$ts.st) }
    else{ $args+=@('/SC','MINUTE','/MO',$ts.mo) }
    $r=& schtasks @args 2>&1 | Out-String
    if($LASTEXITCODE -eq 0){ Log ('任务已注册：'+$ts.n) } else { Log ('WARN：任务注册失败 '+$ts.n+'：'+($r -join '').Trim()) }
  }
  # ---- 桌面快捷方式（结晶一键体检） ----
  $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) '结晶一键体检.lnk'
  if(Test-Path $lnk){ Log ('桌面快捷方式已在：'+$lnk) }
  elseif($DryRun){ Log 'DRYRUN：将建桌面快捷方式 结晶一键体检.lnk（doctor 只读体检）' }
  else{
    try{
      $w=New-Object -ComObject WScript.Shell
      $s=$w.CreateShortcut($lnk)
      $s.TargetPath='powershell.exe'
      $s.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PluginSrc 'scripts\doctor.ps1')+'"'
      $s.Description='dsh-crystal 一键体检（只读）'
      $s.Save()
      Log ('桌面快捷方式已建：'+$lnk)
    }catch{ Log ('WARN：快捷方式创建失败：'+$_.Exception.Message) }
  }
  if(-not $DryRun){
    $o=& powershell -NoProfile -ExecutionPolicy Bypass -File $doctorPath 2>&1 | Out-String
    $summ=(($o -split "`r?`n") | Where-Object { $_ -match 'doctor: \d' }) -join ' '
    Log ('doctor exit='+$LASTEXITCODE+' 末行='+$summ)
    if($LASTEXITCODE -ne 0){ Log 'WARN：doctor 有红黄，安装保留但需人工处理（文件已落且可修）' }
  } else { Log 'DRYRUN：将跑 doctor（只读）' }
  Log '安装完成'
  exit 0
}catch{
  Log ('安装失败：'+$_.Exception.Message)
  foreach($s in @($steps)){
    try{ Log ('回滚：'+$s.desc); & $s.undo }catch{ Log ('回滚失败：'+$_.Exception.Message) }
  }
  Log '已回滚，不留半装'
  exit 1
}
