# crystal-receipts.ps1 - 已读凭证（§24/要求清单）：把桥 social-v2.json 的已读水位镜像成凭证
# 只读桥状态：每个会话的 lastReadThroughSeq 前进时向 $DataHome\read-receipts.jsonl 追加一行凭证
# 并落 $DataHome\read-receipts.json 快照（generatedAt+sources mtime）；绝不写桥侧任何文件
# 用法：powershell -File crystal-receipts.ps1   （exit 0 正常；输出 [RECEIPTS] 汇总行）
#        powershell -File crystal-receipts.ps1 mark-rules-read <key>   （九.2 干活档已读凭证登记）
param([string]$Verb='run',[string]$Arg1='')
$ErrorActionPreference='SilentlyContinue'
$Base=(Get-Item (Join-Path $PSScriptRoot '..')).FullName
$CrystalJson=Join-Path $Base 'crystal.json'
$DetF=Join-Path $Base 'data\detected.json'
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
$BridgeHome=Join-Path $env:LOCALAPPDATA 'crystal\bridge'
if(Test-Path $DetF){
  try{
    $det=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json
    if($det.dataRoot){ $DataHome=[string]$det.dataRoot }
    if($det.bridgeHome){ $BridgeHome=[string]$det.bridgeHome }
  }catch{}
}
$Social=Join-Path $BridgeHome 'state\social-v2.json'
$Mirror=Join-Path $DataHome 'read-receipts.json'
$ReceiptLog=Join-Path $DataHome 'read-receipts.jsonl'
$enc=New-Object Text.UTF8Encoding($false)
try{
  $t=Get-Content $CrystalJson -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $t.paths){
    if($t.paths.socialV2 -and $t.paths.socialV2 -ne ''){ $Social=[string]$t.paths.socialV2 }
    if($t.paths.receipts -and $t.paths.receipts -ne ''){ $Mirror=[string]$t.paths.receipts }
    if($t.paths.receiptLog -and $t.paths.receiptLog -ne ''){ $ReceiptLog=[string]$t.paths.receiptLog }
  }
}catch{}
if($Verb -eq 'mark-rules-read'){
  if(-not $Arg1){ Write-Output '用法: crystal-receipts.ps1 mark-rules-read <key>'; exit 0 }
  $rrPath=Join-Path $DataHome 'rules-read.json'
  $rrMap=@{}
  try{
    $rrOld=Get-Content $rrPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($null -ne $rrOld -and $null -ne $rrOld.keys){
      foreach($rp in $rrOld.keys.PSObject.Properties){ $rrMap[$rp.Name]=[int64]$rp.Value }
    }
  }catch{}
  $rrMap[$Arg1]=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $rrObj=@{ generatedAt=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'); keys=$rrMap }
  [IO.File]::WriteAllText($rrPath, ($rrObj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
  $rl='[RULES-READ] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' key='+$Arg1
  try{ [IO.File]::AppendAllText($ReceiptLog, $rl+"`r`n", (New-Object Text.UTF8Encoding($false))) }catch{}
  Write-Output $rl
  exit 0
}
if(-not (Test-Path $Social)){
  Write-Output ('[RECEIPTS-ERR] '+$Social+' 读不到（桥状态文件不在）')
  exit 2
}
$oldMap=@{}
try{ $old=Get-Content $Mirror -Raw -Encoding UTF8 | ConvertFrom-Json; foreach($c in @($old.conversations)){ if($c.key){ $oldMap[[string]$c.key]=[int64]$c.readThroughSeq } } }catch{}
$conv=@()
$advances=@()
try{
  $sv=Get-Content $Social -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($p in $sv.conversations.PSObject.Properties){
    $st=$p.Value
    $seq=[int64]0; try{ $seq=[int64]$st.lastReadThroughSeq }catch{}
    $conv+=@{ key=[string]$p.Name; readThroughSeq=$seq; unreadSeq=[int64]$st.lastUnreadSeq; lastIncomingAt=[string]$st.lastIncomingAt; lastAiReplyAt=[string]$st.lastAiReplyAt }
    if($oldMap.ContainsKey([string]$p.Name) -and $seq -gt $oldMap[[string]$p.Name]){
      $advances+=@{ key=[string]$p.Name; prev=$oldMap[[string]$p.Name]; now=$seq }
    } elseif(-not $oldMap.ContainsKey([string]$p.Name) -and $seq -gt 0){
      $advances+=@{ key=[string]$p.Name; prev=0; now=$seq }
    }
  }
}catch{ Write-Output ('[RECEIPTS-ERR] '+$Social+' 解析失败：'+$_.Exception.Message); exit 2 }
$nowIso=Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'
foreach($a in $advances){
  $line=@{ ts=$nowIso; key=$a.key; prevSeq=$a.prev; newSeq=$a.now; source='bridge-watermark' } | ConvertTo-Json -Compress
  try{ [IO.File]::AppendAllText($ReceiptLog, $line+"`r`n", $enc) }catch{}
}
$mirrorObj=@{ generatedAt=$nowIso; source=$Social; conversations=$conv } | ConvertTo-Json -Depth 4
try{ [IO.File]::WriteAllText($Mirror, $mirrorObj, $enc) }catch{}
$maxSeq=0; foreach($c in $conv){ if($c.readThroughSeq -gt $maxSeq){ $maxSeq=$c.readThroughSeq } }
$sum='[RECEIPTS] '+$nowIso+' conversations='+$conv.Count+' 最大已读水位='+$maxSeq+' 本次新凭证='+$advances.Count+' 条'
Write-Output $sum
try{ [IO.File]::AppendAllText((Join-Path $DataHome 'boot-probe.log'), $sum+"`r`n", $enc) }catch{}
exit 0
