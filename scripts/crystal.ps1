# crystal.ps1 - dsh-crystal CLI 口令面（§10.6）：六个动词 status|doctor|build|rollback|where|count
# 每动词 stdout ≤12 行（进对话只贴摘要），全文落 F:\crystal\data\logs\cli-<verb>-<时间戳>.log
# 红线：只读为主，不改现网六件、不重启 DSH/桥、不碰 SnowLuma-Guard
param([string]$Verb='status', [string]$Arg1='', [string]$Arg2='')
$ErrorActionPreference='SilentlyContinue'
$Plugin='C:\Users\丽微\.dsh\plugins\dsh-crystal'
$CrystalJson=Join-Path $Plugin 'crystal.json'
$Data=Join-Path $Plugin 'data\crystal'
$LogsDir='F:\crystal\data\logs'
$Doctor=Join-Path $Plugin 'scripts\doctor.ps1'
$Build=Join-Path $Plugin 'scripts\crystal-build.ps1'
$Rollback=Join-Path $Plugin 'scripts\rollback.ps1'
$Queue='F:\crystal\data\queue.json'
$Usage='F:\crystal\data\usage.log'
$SnapDir=Join-Path $Data 'snapshots'
$Fallbacks=Join-Path $Data 'fallbacks.log'
$enc=New-Object Text.UTF8Encoding($false)
$t=$null; try{ $t=Get-Content $CrystalJson -Raw -Encoding UTF8 | ConvertFrom-Json }catch{}
$stamp=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
if(-not (Test-Path $LogsDir)){ New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null }
$logFile=Join-Path $LogsDir ('cli-'+$Verb.ToLower()+'-'+($stamp -replace '[: .]','-')+'.log')
$out=New-Object Collections.Generic.List[string]
function Say([string]$line){ $out.Add($line) }
function Flush([int]$exitCode){
  $joined=($out -join "`r`n")
  try{ [IO.File]::WriteAllText($logFile, $joined + "`r`n", $enc) }catch{}
  $print=@($out)
  if($print.Count -gt 12){ $print=@($print | Select-Object -Last 12) }
  Write-Output ($print -join "`r`n")
  exit $exitCode
}

switch($Verb.ToLower()){
  'status' {
    Say ('[crystal status] '+$stamp)
    if($null -eq $t){ Say '总表: crystal.json 读不出（详见 logs）'; Flush 2 }
    Say ('总表: schema='+$t.schemaVersion+' writer='+$t._writer+' writtenAt='+$t._writtenAt)
    $docOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Doctor 2>&1 | Out-String
    foreach($ln in @($docOut -split "`r?`n")){ if($ln -match '未解决红|当前生效|PRICING'){ Say ('doctor: '+$ln.Trim()) } }
    $qn=0; try{ $qn=((Get-Content $Queue -Raw -Encoding UTF8|ConvertFrom-Json).items.Count) }catch{}
    $un=0; try{ $un=@(Get-Content $Usage -Encoding UTF8).Count }catch{}
    Say ('queue: '+$qn+' 件排队; usage: '+$un+' 行')
    $al='缺键（doctor 第 16 检会报黄）'
    if($null -ne $t -and $null -ne $t.autonomy){ $al=('askDelete='+$t.autonomy.askDelete+' askOutbound='+$t.autonomy.askOutbound+' askRoots='+$t.autonomy.askRoots+' 钱='+$t.autonomy.reportMoney.perTurn+'/'+$t.autonomy.reportMoney.daily+' silentVerify='+$t.autonomy.silentVerify) }
    Say ('autonomy: '+$al)
    $rl='缺键（doctor 第 18 检会报黄）'
    if($null -ne $t -and $null -ne $t.rules){
      $rc=@($t.rules).Count
      $re=0; foreach($rr in @($t.rules)){ try{ if($rr.enabled){ $re++ } }catch{} }
      $rl=('{0} 条，启用 {1} 条' -f $rc,$re)
    }
    Say ('rules: '+$rl)
    
    Say ('rules: '+$rl)
    Flush 0
  }
  'check' {
    Say ('[crystal check] '+$stamp)
    $cOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Plugin 'scripts\crystal-check.ps1') 2>&1 | Out-String
    foreach($ln in @($cOut -split "`r?`n")){ if($ln.Trim()){ Say ($ln.Trim()) } }
    Flush $LASTEXITCODE
  }
  'doctor' {
    Say ('[crystal doctor] '+$stamp)
    $docOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Doctor 2>&1 | Out-String
    foreach($ln in @($docOut -split "`r?`n")){ if($ln.Trim()){ Say ($ln.Trim()) } }
    Flush $LASTEXITCODE
  }
  'build' {
    Say ('[crystal build] '+$stamp)
    $bOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Build -Check 2>&1 | Out-String
    foreach($ln in @($bOut -split "`r?`n")){ if($ln.Trim()){ Say ($ln.Trim()) } }
    $rOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Build -Render 2>&1 | Out-String
    foreach($ln in @($rOut -split "`r?`n")){ if($ln.Trim()){ Say ($ln.Trim()) } }
    Flush 0
  }
  'rollback' {
    if($Arg1 -match '^v[0-9]{4,16}$'){
      Say ('[crystal rollback -To '+$Arg1+'] '+$stamp+'（版本回退：逐件 sha256 校验回写+自动 doctor 复检）')
      . (Join-Path $Plugin 'scripts\crystal-version.ps1')
      $rv=Restore-CrystalVersion -To $Arg1
      if($null -ne $rv){
        Say ('已回退到 '+$rv.version+'（'+$rv.files+' 件，回退前保险包已存）')
        $docOut=& powershell -NoProfile -ExecutionPolicy Bypass -File $Doctor 2>&1 | Out-String
        $docLines=@($docOut -split "`r?`n")
        Say ('回退后 doctor: exit='+$LASTEXITCODE+' '+((@($docLines | Where-Object { $_ -match 'doctor: \d' }) | Select-Object -Last 1) -join ''))
      } else {
        Say ('回退失败（版本不存在/缺件/哈希不符，见上面 Write-Host）')
      }
    } else {
      Say ('[crystal rollback] '+$stamp+'（-List 只读；版本回退用 crystal rollback -To vNNN）')
      $rbOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Rollback -List 2>&1 | Out-String
      foreach($ln in @($rbOut -split "`r?`n")){ if($ln.Trim()){ Say ($ln.Trim()) } }
    }
    Flush 0
  }
  'version' {
    . (Join-Path $Plugin 'scripts\crystal-version.ps1')
    if($Arg1 -match '^v[0-9]{4,16}$'){
      $sv=Save-CrystalVersion -Tag $Arg1 -Note 'crystal version'
      if($null -ne $sv){ Say ('已存版本 '+$sv.version+'（'+$sv.files+' 件）') } else { Say ('保存失败') }
    } else {
      Say ('[crystal version] '+$stamp)
      $vs=@(Get-CrystalVersions)
      if($vs.Count -eq 0){ Say ('（无版本包；存一个用 crystal version vNNN）') }
      foreach($v in $vs){ Say ($v.version+'  '+$v.savedAt+'  '+$v.files+' 件  '+$v.note) }
    }
    Flush 0
  }
  'where' {
    Say ('[crystal where] '+$stamp+' 查='+$Arg1)
    $map=@{ 'crystal'=$CrystalJson; 'truth'=(Join-Path $Data 'truth.json'); 'doctor'=$Doctor; 'build'=$Build; 'rollback'=$Rollback; 'lock1'='F:\crystal\conf\lock1-selfstop.json'; 'lock2'='F:\crystal-kill\conf\lock2-kill.json'; 'lock3'='F:\crystal-l0\conf\lock3-fallback.json'; 'queue'=$Queue; 'usage'=$Usage; 'logs'=$LogsDir; 'r1'='F:\qq-dsh-bridge\qq-bridge\state\inject-table.json'; 'r2'='F:\qq-dsh-bridge\qq-bridge\plugins\qq-agent-presets\qq-tool-restrict.mjs'; 'r3'='F:\qq-dsh-bridge\qq-bridge\src\bridge.js'; 'r4'='F:\qq-dsh-bridge\qq-bridge\plugins\qq-agent-presets\presets'; 'r5'='C:\Users\丽微\.dsh\AGENTS.md'; 'r6'='F:\qq-dsh-bridge\qq-bridge\config.json' }
    if(-not $Arg1){ Say ('用法: crystal where <名字>；可选: '+($map.Keys -join ', ')); Flush 0 }
    $k=$Arg1.ToLower()
    if($map.ContainsKey($k)){
      $p=$map[$k]
      if(Test-Path $p){ $it=Get-Item $p; Say ($Arg1+' = '+$p+'  '+$it.Length+'B  '+$it.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) }
      else { Say ($Arg1+' 映射='+$p+'（不存在）') }
    } else { Say ('未收录；可选: '+($map.Keys -join ', ')) }
    Flush 0
  }
  'reset-melt' {
    Say ('[crystal reset-melt] '+$stamp+' fault='+$Arg1)
    if(-not $Arg1){ Say '用法: crystal.ps1 -Verb reset-melt -Arg1 <fault-id>（清 fault-runs.json 该 fault 计数并写 [MELT-RESET] 到 alerts.log）'; Flush 0 }
    $runsP=Join-Path $Data 'fault-runs.json'
    $ro=$null; try{ $ro=Get-Content $runsP -Raw -Encoding UTF8 | ConvertFrom-Json }catch{}
    if($null -eq $ro){ $ro=New-Object PSObject }
    $old=0; try{ $v=$ro.$Arg1; if($null -ne $v){ $old=[int]$v } }catch{}
    $ro | Add-Member -NotePropertyName $Arg1 -NotePropertyValue 0 -Force
    try{ [IO.File]::WriteAllText($runsP,($ro | ConvertTo-Json -Compress),$enc) }catch{}
    $alertsP=Join-Path $Data 'alerts.log'
    $line='[MELT-RESET] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' fault='+$Arg1+' by=crystal-cli oldCount='+$old
    try{ [IO.File]::AppendAllText($alertsP,$line+"`r`n",$enc) }catch{}
    Say $line
    Flush 0
  }
  'plugins' {
    Say ('[crystal plugins] '+$stamp)
    $inv='F:\crystal\data\plugins-inventory.json'
    if(-not (Test-Path $inv)){ Say ('plugins-inventory.json 缺失：'+$inv+'（先跑 crystal-plugins.ps1）'); Flush 1 }
    $iv=Get-Content $inv -Raw -Encoding UTF8 | ConvertFrom-Json
    $cov=@($iv.entries | Where-Object { $_.status -eq 'covered' }).Count
    $reg=@($iv.entries | Where-Object { $_.status -eq 'registered' }).Count
    $pend=@($iv.entries | Where-Object { $_.status -eq 'pending' }).Count
    $unk=@($iv.entries | Where-Object { $_.status -eq 'unknown' }).Count
    Say ('盘点 '+$iv.generatedAt+'：covered='+$cov+' registered='+$reg+' pending='+$pend+' unknown='+$unk)
    Say ('差异明细（前 6 条）：')
    $diffs=@($iv.entries | Where-Object { $_.status -eq 'pending' -or $_.status -eq 'unknown' } | Select-Object -First 6)
    foreach($d in $diffs){ Say ('  ['+$d.status+'] '+$d.name+' ('+$d.source+') '+$d.evidence) }
    Flush 0
  }
  'receipts' {
    $rf='F:\crystal\data\read-receipts.jsonl'
    $rn=0; try{ $rn=@(Get-Content $rf -Encoding UTF8).Count }catch{}
    $rm='F:\crystal\data\read-receipts.json'
    $rmt='缺'
    try{ if(Test-Path $rm){ $rmt=(Get-Item $rm).LastWriteTime.ToString('MM-dd HH:mm:ss') } }catch{}
    Say ('read-receipts.jsonl: '+$rn+' 行凭证; 快照: '+$rmt)
    $rcOut=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-receipts.ps1') 2>&1 | Out-String
    Say ($rcOut.Trim())
    Flush 0
  }
  'pluginctl' {
    $pcArgs=@()
    if($Arg1){ $pcArgs+='-Verb'; $pcArgs+=$Arg1 }
    if($Arg2){ $pcArgs+='-Arg1'; $pcArgs+=$Arg2 }
    $pcOut=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-pluginctl.ps1') @pcArgs 2>&1 | Out-String
    $pcExit=$LASTEXITCODE
    Say ($pcOut.Trim())
    Flush $pcExit
  }
  'show' {
    Say ('[crystal show] '+$stamp+' 按任务找插件（可带关键词：crystal show <词>）')
    $cap=@()
    try{ $cj=(Get-Content (Join-Path $PSScriptRoot '..\crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json); $cap=@($cj.'plugin-capability') }catch{}
    if($cap.Count -eq 0){ Say 'plugin-capability 缺失或为空'; Flush 1 }
    $kw=$Arg1
    $hits=@($cap | Where-Object { if($kw){ ($_.plugin+($_.skills -join ' ')+($_.tasks -join ' ')) -like ('*'+$kw+'*') } else { $true } })
    if($hits.Count -eq 0){ Say ('无匹配：'+$kw); Flush 0 }
    foreach($h in $hits){ Say ($h.plugin+'['+$h.demand+'] '+($h.skills -join '/')+' ← '+($h.tasks -join '/')) }
    Flush 0
  }
  'daily' {
    # P7 创意③：每日体检日报（crystal daily 只落盘；crystal daily push 额外推脑公私聊）
    $dArgs=@()
    if($Arg1 -eq 'push'){ $dArgs+='-Push' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-daily.ps1') @dArgs
    Flush $LASTEXITCODE
  }
  'timeline' {
    # P7 创意④：系统大事记（缺省最近 20 条；crystal timeline all=全量）
    $tArgs=@()
    if($Arg1 -eq 'all'){ $tArgs+='-Count'; $tArgs+='0' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-timeline.ps1') @tArgs
    Flush $LASTEXITCODE
  }
  'upgrade' {
    # P7 创意⑤：升级参谋（crystal upgrade；crystal upgrade check 同义）
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-upgrade.ps1')
    Flush $LASTEXITCODE
  }
  'backup' {
    # 一键回滚现行备份刷新（F:\备份\现行-*，只留最新 2 份）
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-backup.ps1')
    Flush $LASTEXITCODE
  }
  'pet' {
    # P12③ 桌宠：start=前台小窗 / stop=按名字关进程 / status=看配置；-NoWindow 自测见脚本
    $pa='start'
    if($Arg1 -eq 'stop'){ $pa='stop' } elseif($Arg1 -eq 'status'){ $pa='status' }
    if($pa -eq 'stop'){
      Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*WindowsPowerShell*' } | Out-Null
      $killed=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*crystal-pet.ps1*' })
      foreach($k in $killed){ try{ Stop-Process -Id ([int]$k.ProcessId) -Force -ErrorAction SilentlyContinue; Say ('pet 已停 pid='+$k.ProcessId) }catch{} }
      if($killed.Count -eq 0){ Say 'pet 未在运行' }
      Flush 0; return
    }
    if($pa -eq 'status'){
      $pp=$null
      try{ $pcj=Get-Content (Join-Path $PSScriptRoot '..\crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $pp=$pcj.pet }catch{}
      if($null -eq $pp){ Say 'pet: 未配置（总表无 pet 键）'; Flush 1; return }
      $running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*crystal-pet.ps1*' }).Count
      Say ('pet: enabled='+$pp.enabled+' voice='+$pp.voice+' intervalMin='+$pp.intervalMin+' silent='+$pp.silentFrom+'-'+$pp.silentTo+' 运行中='+($running -gt 0))
      Flush 0; return
    }
    Start-Process powershell -ArgumentList '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'crystal-pet.ps1')
    Say 'pet 已启动（前台小窗，右键退出）'
    Flush 0
  }
  'bill' {
    # P9 ③按插件分账：只汇总 usage.jsonl 的 module 用量，不改账不算钱
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-bill.ps1')
    Flush $LASTEXITCODE
  }
  'dues' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-dues.ps1')
    Flush $LASTEXITCODE
  }
  'fortune' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-fortune.ps1')
    Flush $LASTEXITCODE
  }
  'intercepts' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-intercepts.ps1')
    Flush $LASTEXITCODE
  }
  'keywords' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-keywords.ps1')
    Flush $LASTEXITCODE
  }
  'keywords' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-keywords.ps1')
    Flush $LASTEXITCODE
  }
  'count' {
    Say ('[crystal count] '+$stamp)
    $un=0; try{ $un=@(Get-Content $Usage -Encoding UTF8).Count }catch{}
    Say ('usage.log: '+$un+' 行')
    $qn=0; try{ $qn=((Get-Content $Queue -Raw -Encoding UTF8|ConvertFrom-Json).items.Count) }catch{}
    Say ('queue: '+$qn+' 件排队')
    $sn=0; try{ $sn=@(Get-ChildItem $SnapDir -Directory).Count }catch{}
    $costN=0; $costAmt=0.0; $costRows=@()
    $costP='F:\crystal\data\cost.jsonl'
    try{ $cj=(Get-Content (Join-Path $PSScriptRoot '..\crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json); if($cj.paths.cost){ $costP=[string]$cj.paths.cost } }catch{}
    try{ $costRows=@(Get-Content $costP -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') }) }catch{}
    foreach($r in $costRows){ $costN++; try{ $parts=($r -split '\|'); $amt=[double]$parts[$parts.Count-1]; if($amt){ $costAmt+=$amt } }catch{} }
    Say ('cost.jsonl: '+$costN+' 行真实用量，合计 '+[math]::Round($costAmt,4)+' 元（只汇总不改账；空=no-usage-source 写入端待授权）')
    Say ('快照: '+$sn+' 个')
    $fb=0; if(Test-Path $Fallbacks){ $fb=@(Get-Content $Fallbacks -Encoding UTF8).Count }
    Say ('fallbacks.log: '+$fb+' 行')
    $al=0; if(Test-Path (Join-Path $Data 'alerts.log')){ $al=@(Get-Content (Join-Path $Data 'alerts.log') -Encoding UTF8).Count }
    Say ('alerts.log: '+$al+' 行')
    $er=0; if(Test-Path (Join-Path $Data 'errors.log')){ $er=@(Get-Content (Join-Path $Data 'errors.log') -Encoding UTF8).Count }
    Say ('errors.log: '+$er+' 行')
    Flush 0
  }
  default {
    Say '用法: crystal.ps1 [-Verb] status|doctor|check|build|rollback|version|where|count|receipts|plugins|pluginctl|reset-melt|show|daily|timeline|upgrade|backup|bill|dues|fortune|intercepts|keywords|pet [名字]'
    Flush 0
  }
}
