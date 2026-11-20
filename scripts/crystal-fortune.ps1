# crystal-fortune.ps1 - 今日黄历：本地纯计算的「宜/忌+彩头」一行（无网络、无外发）
# 宜/忌=日期字符串哈希取小池；彩头=doctor-state（lastGreenAt/lastRedAt）推导，写进每日早报。
param([switch]$Quiet)
$ErrorActionPreference='SilentlyContinue'
$d=Get-Date -Format 'yyyy-MM-dd'
$hash=0; foreach($ch in $d.ToCharArray()){ $hash=($hash+[int]$ch) % 9973 }
$yi=@('备份整理','读档复盘','修小毛病','调配置前先落 .bak','给插件写注释','盘点日志','整理记忆','清理缓存','跑一遍体检','规划明天','学一个命令','早点收工')
$ji=@('摸黑改配置','删文件前不备份','高峰硬跑重活','不写留痕就动手','乱改现网六件','重复造轮子','跳过自检直接报绿','把回滚点当摆设','忘记攒批清单','熬夜连轴转','把决定留给管家','口说无凭不落记录')
$yiIdx=$hash % $yi.Count
$jiIdx=($hash*7+3) % $ji.Count
$FrtData=Join-Path $env:LOCALAPPDATA 'crystal\data'
try{
  $detF=Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\detected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($detF.dataRoot){ $FrtData=[string]$detF.dataRoot }
}catch{}
$stateFile=Join-Path $FrtData 'doctor-state.json'
$cai='平：未见异常，照常安排。'
try{
  $st=Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $st){
    if($null -ne $st.lastGreenAt -and $st.lastGreenAt -ne ''){
      $age=((Get-Date)-([datetime]$st.lastGreenAt)).TotalHours
      if($age -lt 24){ $cai='吉：体检全绿，诸事顺遂。' }
    }
    if($null -ne $st.lastRedAt -and $st.lastRedAt -ne ''){
      $ageR=((Get-Date)-([datetime]$st.lastRedAt)).TotalHours
      if($ageR -lt 24){ $cai='警：24 小时内有过红，今日先修机再折腾。' }
    }
  }
}catch{}
$line='[FORTUNE] '+$d+' 宜：'+$yi[$yiIdx]+'；忌：'+$ji[$jiIdx]+'；彩头：'+$cai
Write-Output $line
exit 0
