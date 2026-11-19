# crystal-pet.ps1 - 桌面大肥鱼桌宠（P12③）：透明置顶小窗 + 表情包立绘 + 气泡 + 语音说有用内容
# 用法：powershell -STA -NoProfile -ExecutionPolicy Bypass -File crystal-pet.ps1        （前台窗口宠物）
#       powershell -NoProfile -ExecutionPolicy Bypass -File crystal-pet.ps1 -NoWindow   （无窗自测：只跑数据/语音逻辑）
#       crystal-pet.ps1 -Once   （说一句当前状态就退出）
# 数据源（全部只读）：doctor-state.json 体检红黄绿灰 / usage.jsonl 今日用量 / dues.json 欠债 / endpoints.json 端口
# 配置：crystal.json pet{ enabled voice intervalMin silentFrom silentTo image size bubbleChars greetingAm greetingPm }
param([switch]$NoWindow,[switch]$Once)
$ErrorActionPreference='SilentlyContinue'
$Pkg=Split-Path -Parent $PSScriptRoot
$cfgPath=Join-Path $Pkg 'crystal.json'
$pet=@{ enabled=$true; voice=$true; intervalMin=15; silentFrom='23:00'; silentTo='08:00'; image=(Join-Path $Pkg 'assets\pet\whale-girl.png'); bubbleChars=44; greetingAm=$true; greetingPm=$true; size=200 }
try{
  $cj=Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $cj.pet){ foreach($p in $cj.pet.PSObject.Properties){ $pet[$p.Name]=$p.Value } }
}catch{}
$pet.image=[string]$pet.image
if(-not (Test-Path $pet.image)){ $pet.image=Join-Path $Pkg 'assets\pet\whale-girl.png' }
if(-not (Test-Path $pet.image)){ Write-Output '[PET] 立绘缺失：'+$pet.image; exit 2 }
$dsFile=Join-Path $Pkg 'data\crystal\doctor-state.json'
$usagePath='F:\crystal\data\usage.jsonl'
$duesCache='F:\crystal\data\dues.json'
$epFile='F:\crystal\data\endpoints.json'
try{ if($cj.paths.usage){ $usagePath=[string]$cj.paths.usage } }catch{}
function Get-PetFacts{
  $f=@{ red=$false; yellow=$false; gray=$false; redMsg=''; usedTok=0; pending=0; overdue=0; port=0 }
  try{ $ds=Get-Content $dsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if([int]$ds.red -gt 0){ $f.red=$true; $f.redMsg=[string]$ds.redMsg }
    if([int]$ds.yellow -gt 0){ $f.yellow=$true }
    if([int]$ds.gray -gt 0){ $f.gray=$true }
  }catch{}
  try{
    $today=(Get-Date).ToString('yyyy-MM-dd')
    foreach($l in @(Get-Content $usagePath -Encoding UTF8)){
      if($l -and $l.StartsWith('{')){
        try{ $o=$l | ConvertFrom-Json; if([string]$o.ts -and [string]$o.ts.StartsWith($today)){ $f.usedTok+=([long]$o.inputTokens+[long]$o.outputTokens) } }catch{}
      }
    }
  }catch{}
  try{ $dj=Get-Content $duesCache -Raw -Encoding UTF8 | ConvertFrom-Json; $f.pending=[int]$dj.pending; $f.overdue=[int]$dj.overdue }catch{}
  try{ $ep=Get-Content $epFile -Raw -Encoding UTF8 | ConvertFrom-Json; $f.port=[int]$ep.gui.port }catch{}
  return $f
}
$zhVoice=$false
try{ $sapi=New-Object -ComObject SAPI.SpVoice; foreach($v in $sapi.GetVoices()){ if([string]$v.GetDescription() -match 'Huihui|Chinese|中文'){ $zhVoice=$true } } }catch{}
function Say-Pet([string]$txt){
  $txt=$txt.Trim()
  Write-Output ('[PET-SAY] '+(Get-Date -Format 'HH:mm:ss')+' '+$txt)
  if($script:bubbleText -ne $null){ $script:bubbleText.Text=$txt }
  if($pet.voice -and $zhVoice -and -not $NoWindow){ try{ $sapi.Speak($txt,1) | Out-Null }catch{} }
}
function Get-PetLine{
  $f=Get-PetFacts
  $h=[int](Get-Date -Format 'HH')
  # 静音时段：只更新数据不开口（自测模式 -NoWindow/-Once 不受静音限制）
  if(-not $NoWindow -and -not $Once){
    $sFrom=[int](($pet.silentFrom -split ':')[0]); $sTo=[int](($pet.silentTo -split ':')[0])
    if($sFrom -le $sTo){ if($h -ge $sFrom -and $h -lt $sTo){ return '' } } else { if($h -ge $sFrom -or $h -lt $sTo){ return '' } }
  }
  if($f.red){ return '体检有红：'+$f.redMsg.Substring(0,[Math]::Min($f.redMsg.Length,40))+'，去看结晶面板吧' }
  if($f.overdue -gt 0){ return ('有 '+$f.overdue+' 件逾期啦，脑公快去看看吧') }
  if($f.pending -gt 0){ return ('今天还有 '+$f.pending+' 件没做完，摸摸鱼再做也行嘛') }
  $tok=if($f.usedTok -gt 0){ [math]::Round($f.usedTok/1e6,1) } else { 0 }
  if($h -ge 5 -and $h -lt 11 -and $pet.greetingAm){ $pet.greetingAm=$false; return '脑公早，今天也要元气满满哦' }
  if($h -ge 20 -and $pet.greetingPm){ $pet.greetingPm=$false; return '夜深啦，摸摸鱼就睡吧' }
  return ('体检全绿，今天已用 '+$tok+' M token，端口 '+$f.port+'，一切正常')
}
if($NoWindow){
  Say-Pet (Get-PetLine)
  exit 0
}
if($Once){
  Say-Pet (Get-PetLine)
  exit 0
}
# ---- WPF 透明置顶小窗 ----
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
[xml]$xaml=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" SizeToContent="WidthAndHeight">
  <Grid>
    <StackPanel>
      <Border x:Name="Bubble" Background="#F2FFFFFF" CornerRadius="12" Padding="10,6" Margin="0,0,0,6" Visibility="Collapsed">
        <TextBlock x:Name="BubbleText" TextWrapping="Wrap" MaxWidth="220" FontSize="13" Foreground="#333333"/>
      </Border>
      <Image x:Name="Img" Width="200" Height="200" Stretch="Uniform"/>
    </StackPanel>
  </Grid>
</Window>
"@
$reader=New-Object System.Xml.XmlNodeReader $xaml
$win=[Windows.Markup.XamlReader]::Load($reader)
$bubble=$win.FindName('Bubble')
$bubbleText=$win.FindName('BubbleText')
$img=$win.FindName('Img')
$img.Source=New-Object Windows.Media.Imaging.BitmapImage (New-Object Uri((Resolve-Path $pet.image).Path))
$img.Width=$pet.size; $img.Height=$pet.size
$script:bubbleText=$bubbleText
$win.Add_MouseLeftButtonDown({ $win.DragMove() })
$win.Add_MouseRightButtonUp({ $win.Close() })
# 呼吸动画：立绘轻微缩放
$sb=New-Object Windows.Media.Animation.Storyboard
$da=New-Object Windows.Media.Animation.DoubleAnimation
$da.From=$pet.size; $da.To=($pet.size*1.04); $da.Duration=New-Object Windows.Duration ([TimeSpan]::FromSeconds(1.6))
$da.AutoReverse=$true; $da.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
[Windows.Media.Animation.Storyboard]::SetTarget($da,$img)
[Windows.Media.Animation.Storyboard]::SetTargetProperty($da,(New-Object Windows.PropertyPath '(UIElement.RenderTransform).(ScaleTransform.ScaleX)'))
$sb.Children.Add($da)
$da2=New-Object Windows.Media.Animation.DoubleAnimation
$da2.From=$pet.size; $da2.To=($pet.size*1.04); $da2.Duration=New-Object Windows.Duration ([TimeSpan]::FromSeconds(1.6))
$da2.AutoReverse=$true; $da2.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
[Windows.Media.Animation.Storyboard]::SetTarget($da2,$img)
[Windows.Media.Animation.Storyboard]::SetTargetProperty($da2,(New-Object Windows.PropertyPath '(UIElement.RenderTransform).(ScaleTransform.ScaleY)'))
$sb.Children.Add($da2)
$img.RenderTransform=New-Object Windows.Media.ScaleTransform
$img.RenderTransformOrigin=New-Object Windows.Point (0.5,0.5)
$sb.Begin()
# 主循环：每 intervalMin 说一句有用内容
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=New-Object TimeSpan (0,[int]$pet.intervalMin,0)
$timer.Add_Tick({
  $line=Get-PetLine
  if($line -ne '' -and $bubbleText.Text -ne $line){
    $bubbleText.Text=$line
    $bubble.Visibility='Visible'
    Say-Pet $line
    $hide=New-Object Windows.Threading.DispatcherTimer
    $hide.Interval=New-Object TimeSpan (0,0,12)
    $hide.Add_Tick({ $bubble.Visibility='Collapsed'; $hide.Stop() })
    $hide.Start()
  }
})
Say-Pet (Get-PetLine)
$bubble.Visibility='Visible'
$timer.Start()
$win.ShowDialog()
