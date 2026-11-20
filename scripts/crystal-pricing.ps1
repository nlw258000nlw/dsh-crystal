# crystal-pricing.ps1 - dsh-crystal CR-008 A 平价/高峰判定库（P1）
# 用法：. "$PSScriptRoot\crystal-pricing.ps1" 之后调 Get-CrystalPricing [-OverrideNow 'yyyy-MM-ddTHH:mm:ss']（OverrideNow 必须已是 Asia/Shanghai 本地时间，仅测试用）
# 返回：tier=peak|offpeak、label=高峰|平价、nextMinutes=下一窗口还有几分钟、nextLabel=窗口说明、fallback=是否用了默认配置
function Get-CrystalPricing([string]$OverrideNow=''){
  $cfg=Join-Path (Split-Path -Parent $PSScriptRoot) 'crystal.json'
  $pricing=$null; $fallback=$false
  try{
    $raw=[IO.File]::ReadAllBytes($cfg)
    if($raw.Length -ge 3 -and $raw[0]-eq 0xEF -and $raw[1]-eq 0xBB -and $raw[2]-eq 0xBF){ throw 'crystal.json 带 BOM' }
    $o=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json
    if($null -eq $o.pricing -or $null -eq $o.pricing.peakWindows -or @($o.pricing.peakWindows).Count -eq 0){ throw 'pricing 段缺失' }
    $pricing=$o.pricing
  }catch{
    $fallback=$true
    $pricing=[pscustomobject]@{ peakWindows=@('09:00-12:00','14:00-18:00'); offPeakRatio=0.5 }
  }
  if($OverrideNow -ne ''){ try{ $cn=[datetime]::Parse($OverrideNow) }catch{ $cn=Get-Date } }
  else{
    $tz=$null; try{ $tz=[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time') }catch{ $tz=[TimeZoneInfo]::Local }
    try{ $cn=[TimeZoneInfo]::ConvertTime((Get-Date),$tz) }catch{ $cn=Get-Date }
  }
  $tod=$cn.Hour*60+$cn.Minute
  $tier='offpeak'; $label='平价'; $nextMin=0; $nextLabel=''
  $best=$null
  foreach($w in @($pricing.peakWindows)){
    try{
      $parts=($w -split '-')
      $sm=[timespan]::Parse($parts[0]).TotalMinutes
      $em=[timespan]::Parse($parts[1]).TotalMinutes
      if($tod -ge $sm -and $tod -lt $em){ $tier='peak'; $label='高峰'; $nextMin=[int]($em-$tod); $nextLabel=($parts[1])+' 窗口结束'; break }
      if($sm -gt $tod){ if($null -eq $best -or $sm -lt $best){ $best=$sm } }
    }catch{}
  }
  if($tier -eq 'offpeak'){
    if($null -eq $best){
      try{ $first=[timespan]::Parse(((@($pricing.peakWindows)[0] -split '-')[0])).TotalMinutes; $nextMin=[int]($first+1440-$tod) }catch{ $nextMin=0 }
    } else { $nextMin=[int]($best-$tod) }
    $nextLabel='下一高峰窗口开始'
  }
  return [pscustomobject]@{ tier=$tier; label=$label; nextMinutes=$nextMin; nextLabel=$nextLabel; fallback=$fallback }
}
