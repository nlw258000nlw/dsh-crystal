# crystal-daily.ps1 - 每日体检日报（P7 大管家创意③）：读盘面生成 ≤150 字人话报告
# 用法：crystal-daily.ps1 [-Push] [-Quiet]（-Push=经桥 console API 发主人私聊；缺省只落盘 $DataHome\daily-report.txt）
# 数据源：doctor-state.json（最后全绿/最后红时刻）、usage.jsonl 今日 token 汇总、plugin-toggles.json 台账、endpoints.json 端口
# 红线遵守：console-token 只读不落任何文件；现网六件不碰；不加计划任务（由 CrystalDaily-Scan 的 scan.ps1 调用）
param([switch]$Push,[switch]$Quiet)
$ErrorActionPreference='SilentlyContinue'
$Plugin=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
$BridgeHome=Join-Path $env:LOCALAPPDATA 'crystal\bridge'
$MaintHome=Join-Path $env:LOCALAPPDATA 'crystal\sys'
$DetF=Join-Path $Plugin 'data\detected.json'
if(Test-Path $DetF){
  try{
    $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json
    if($det.dataRoot){ $DataHome=[string]$det.dataRoot }
    if($det.bridgeHome){ $BridgeHome=[string]$det.bridgeHome }
    if($det.maintHome){ $MaintHome=[string]$det.maintHome }
  }catch{}
}
$Data=$DataHome
$DoctorState=Join-Path $Plugin 'data\crystal\doctor-state.json'
$Usage=Join-Path $Data 'usage.jsonl'
$Toggles=Join-Path $Data 'plugin-toggles.json'
$Ep=Join-Path $Data 'endpoints.json'
$Report=Join-Path $Data 'daily-report.txt'
$ReportHist=Join-Path $Data 'daily-report.jsonl'
$enc=New-Object Text.UTF8Encoding($false)
$today=(Get-Date -Format 'yyyy-MM-dd')
# 1. 体检状态（doctor-state.json 最后全绿/最后红；比 grep 日志行可靠）
$stateLine='体检状态未知'
try{
  $ds=Get-Content $DoctorState -Raw -Encoding UTF8 | ConvertFrom-Json
  $lg=[string]$ds.lastGreenAt; $lr=[string]$ds.lastRedAt
  if($lg -and $lg -ne ''){
    $lgT=if($lg.Length -ge 16){ $lg.Substring(11,5) } else { $lg }
    $stateLine='体检最后全绿 '+$lgT
  }
  if($lr -and $lr -ne ''){
    $lrT=if($lr.Length -ge 16){ $lr.Substring(11,5) } else { $lr }
    if($lrT -ge $lgT){ $stateLine='体检有红（上次红 '+$lrT+'）' }
  }
}catch{}
# 2. 今日用量（usage.jsonl 今天行求和）
$todayTok=0; $todayRows=0
try{
  if(Test-Path $Usage){
    $us=@(Get-Content $Usage -Encoding UTF8)
    foreach($u in $us){
      try{ $uo=$u | ConvertFrom-Json }catch{ continue }
      if($null -eq $uo.ts -or ($uo.ts -notlike '202*')){ continue }
      $t0=([string]$uo.ts).Substring(0,10)
      if($t0 -eq $today){
        if($uo.inputTokens){ $todayTok += [double]$uo.inputTokens }
        $todayRows++
      }
    }
  }
}catch{}
$tokTxt=''
if($todayTok -ge 100000000){ $tokTxt=('今天已用 '+[math]::Round($todayTok/100000000,2)+' 亿 token') }
elseif($todayTok -gt 0){ $tokTxt=('今天已用 '+[math]::Round($todayTok/10000,0)+' 万 token') }
# 3. 端口
$portTxt=''
try{ $ep=Get-Content $Ep -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $ep.gui.port){ $portTxt=('端口 '+$ep.gui.port) } }catch{}
# 4. 按需插件台账
$togTxt=''
try{ $tg=Get-Content $Toggles -Raw -Encoding UTF8 | ConvertFrom-Json; if($null -ne $tg.entries -and @($tg.entries).Count -gt 0){ $togTxt=('按需开 '+@($tg.entries).Count+' 个插件') } }catch{}
# 4.5 预算线（crystal.json checks.budget：钱线触顶在早报里喊一句，只报警不打断）
$budgetTxt=''
try{
  $cj=Get-Content (Join-Path $Plugin 'crystal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $bud=$cj.checks.budget
  if($null -ne $bud){
    $warnCny=[double]$bud.warnCnyDaily
    $todayCny=0.0
    try{
      $costFile=Join-Path $Data 'cost.jsonl'
      if(Test-Path $costFile){
        foreach($cl in @(Get-Content $costFile -Encoding UTF8)){
          try{ $co=$cl | ConvertFrom-Json }catch{ continue }
          if($null -ne $co.ts -and ([string]$co.ts).StartsWith($today)){ $todayCny += [double]$co.amountCny }
        }
      }
    }catch{}
    if($warnCny -gt 0 -and $todayCny -ge $warnCny){
      $budgetTxt=('预算报警：今天已花 '+[math]::Round($todayCny,2)+' 元触顶 '+$warnCny+' 元（只报警不打断）')
      # [fix-20261120-P2d] 桌宠提醒总线：花钱到线也进 pet-inbox
      try{ $tell=Join-Path $PSScriptRoot 'crystal-pet-tell.ps1'; & $tell -Text $budgetTxt -Level 'money' }catch{}
    }
  }
}catch{}
# 5.0 三行新增（P11）：欠债/黄历/近 24h 动过文件
$duesLine=''; $fortLine=''; $chgLine=''
try{ $duesOut=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-dues.ps1') 2>$null | Out-String; $m1=[regex]::Match($duesOut,'\[DUES\]\s+\S+\s+(.+)'); if($m1.Success){ $duesLine=('欠债 '+$m1.Groups[1].Value.Trim()) } }catch{}
try{ $fortOut=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'crystal-fortune.ps1') 2>$null | Out-String; $m2=[regex]::Match($fortOut,'宜：(.+)'); if($m2.Success){ $fortLine=('黄历 '+$m2.Groups[1].Value.Trim()) } }catch{}
try{
  $cut24=(Get-Date).AddHours(-24)
  $changed=@(Get-ChildItem (Join-Path $Plugin 'scripts'),$MaintHome -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $cut24 -and $_.Name -notlike '*bak-*' } | Sort-Object LastWriteTime -Descending | Select-Object -First 3 -ExpandProperty Name)
  if($changed.Count -gt 0){ $chgLine=('动过 '+($changed -join '、')) }
}catch{}
# 5. 拼报告（≤150 字，人话）
$parts=@()
$parts+='小鱼早报：'+$stateLine
if($duesLine){ $parts+=$duesLine }
if($fortLine){ $parts+=$fortLine }
if($chgLine){ $parts+=$chgLine }
if($tokTxt){ $parts+=$tokTxt }
if($budgetTxt){ $parts+=$budgetTxt }
if($togTxt){ $parts+=$togTxt }
if($portTxt){ $parts+=$portTxt }
$msg=($parts -join '，')+'。'
if($msg.Length -gt 150){
  $cut=150
  $idx=$msg.LastIndexOf('，',149)
  if($idx -ge 100){ $cut=$idx }
  $msg=$msg.Substring(0,$cut)+'。'
}
# 6. 落盘（最新一份 + 历史 jsonl 留痕）
try{ [IO.File]::WriteAllText($Report,($msg+"`r`n"),$enc) }catch{}
$nowS=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$pushFlag='false'; if($Push){ $pushFlag='true' }
$histLine='{"ts":"'+$nowS+'","report":"'+($msg.Replace('"',''))+'","todayTokens":'+$todayTok+',"rows":'+$todayRows+',"push":'+$pushFlag+'}'
try{ [IO.File]::AppendAllText($ReportHist,($histLine+"`r`n"),$enc) }catch{}
if(-not $Quiet){ Write-Output $msg }
# 7. 推送（-Push 才发；console-token 只读、不进任何落盘内容）
if($Push){
  try{
    $tok=[IO.File]::ReadAllText((Join-Path $BridgeHome 'state\console-token')).Trim()
    $bodyFile=Join-Path $env:TEMP ('crystal-push-'+[guid]::NewGuid().ToString('N')+'.json')
    $bodyJson='{"userId":"","message":"'+($msg.Replace('"',''))+'"}'
    [IO.File]::WriteAllText($bodyFile,$bodyJson,(New-Object Text.UTF8Encoding($false)))
    $resp=& curl.exe -s -X POST 'http://127.0.0.1:3100/api/send/private' -H ('x-console-token: '+$tok) -H 'Content-Type: application/json' --data-binary ('@'+$bodyFile) 2>&1 | Out-String
    Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
    if(-not $Quiet){ Write-Output ('[DAILY-PUSH] '+($resp -replace '\s+',' ').Trim()) }
  }catch{ if(-not $Quiet){ Write-Output ('[DAILY-PUSH] 推送失败：'+$_.Exception.Message) } }
}
exit 0
