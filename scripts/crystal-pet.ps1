# crystal-pet.ps1 - 桌面小鱼桌宠（P12③）：透明置顶小窗 + 表情包立绘 + 气泡 + 语音说有用内容
# 用法：powershell -STA -NoProfile -ExecutionPolicy Bypass -File crystal-pet.ps1        （前台窗口宠物）
#       powershell -NoProfile -ExecutionPolicy Bypass -File crystal-pet.ps1 -NoWindow   （无窗自测：只跑数据/语音逻辑）
#       crystal-pet.ps1 -Once   （说一句当前状态就退出）
# 数据源（全部只读）：doctor-state.json 体检红黄绿灰 / usage.jsonl 今日用量 / dues.json 欠债 / endpoints.json 端口
# 配置：crystal.json pet{ enabled voice intervalMin silentFrom silentTo image size bubbleChars greetingAm greetingPm }
param([switch]$NoWindow,[switch]$Once)
$ErrorActionPreference='SilentlyContinue'
# DPI 感知（2026-11-20 13:46 修「桌宠跑到屏幕外」）：powershell 进程默认 DPI 未感知，
# WPF 的 Left/Top 会被系统按 150% 放大，2560 宽的屏上算出 3330 → 窗口落在屏幕右外，肉眼看不到。
# 先声明 Per-Monitor 感知（失败再退 SetProcessDPIAware），此后 Screen.WorkingArea 与 WPF 坐标同为物理像素。
try{
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class W32Dpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
}
"@ -ErrorAction Stop
  try{ [void][W32Dpi]::SetProcessDpiAwareness(2) }catch{ [void][W32Dpi]::SetProcessDPIAware() }
}catch{ try{ [void][W32Dpi]::SetProcessDPIAware() }catch{} }
$Pkg=Split-Path -Parent $PSScriptRoot
$cfgPath=Join-Path $Pkg 'crystal.json'
$pet=@{ enabled=$true; voice=$true; intervalMin=15; silentFrom='23:00'; silentTo='08:00'; image=(Join-Path $Pkg 'assets\pet\whale-girl.png'); bubbleChars=44; greetingAm=$true; greetingPm=$true; size=260 }
try{
  $cj=Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -ne $cj.pet){ foreach($p in $cj.pet.PSObject.Properties){ $pet[$p.Name]=$p.Value } }
}catch{}
$pet.image=[string]$pet.image
# 2026-11-20 14:02 修：配置里写的是相对路径 assets\pet\xxx，原逻辑直接 Test-Path（相对 CWD）→ 永远判缺失、悄悄换成 whale-girl
if($pet.image -and -not [IO.Path]::IsPathRooted($pet.image) -and -not (Test-Path $pet.image)){ $pet.image=Join-Path $Pkg $pet.image }
if(-not (Test-Path $pet.image)){ $pet.image=Join-Path $Pkg 'assets\pet\whale-girl.png' }
if(-not (Test-Path $pet.image)){ Write-Output '[PET] 立绘缺失：'+$pet.image; exit 2 }
# [fix-20261120-P2] 桌宠 UI 偏好单独存 pet-ui.json（不碰 crystal.json，避免和总表生成器抢作者）
$uiFile=Join-Path $Pkg 'data\pet-ui.json'
$ui=@{ posX=0; posY=0; size=0; intervalMin=0; muted=$false; skin='' }
try{ $u=Get-Content $uiFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach($k in 'posX','posY','size','intervalMin','muted','skin'){ if($null -ne $u.$k){ $ui[$k]=$u.$k } } }catch{}
function Save-PetUi{
  try{ $o=[ordered]@{ posX=$ui.posX; posY=$ui.posY; size=$ui.size; intervalMin=$ui.intervalMin; muted=$ui.muted; skin=$ui.skin }
       $json=($o | ConvertTo-Json -Compress); [IO.File]::WriteAllText($uiFile,$json,(New-Object System.Text.UTF8Encoding($false))) }catch{}
}
if([int]$ui.size -gt 0){ $pet.size=[int]$ui.size } else { $pet.size=100 }
if([int]$ui.intervalMin -gt 0){ $pet.intervalMin=[int]$ui.intervalMin }
if([string]$ui.skin){ $p=[string]$ui.skin; if(-not [IO.Path]::IsPathRooted($p)){ $p=Join-Path $Pkg $p }; if(Test-Path $p){ $pet.image=$p } }
$pet.muted=[bool]$ui.muted
$dsFile=Join-Path $Pkg 'data\crystal\doctor-state.json'
$DataHome=Join-Path $env:LOCALAPPDATA 'crystal\data'
$BridgeHome=Join-Path $env:LOCALAPPDATA 'crystal\bridge'
$DetF=Join-Path $Pkg 'data\detected.json'
if(Test-Path $DetF){
  try{ $detpet=Get-Content $DetF -Raw -Encoding UTF8 | ConvertFrom-Json; if($detpet.dataRoot){ $DataHome=[string]$detpet.dataRoot }; if($detpet.bridgeHome){ $BridgeHome=[string]$detpet.bridgeHome } }catch{}
}
try{ if($cj.paths.dataHome){ $DataHome=[string]$cj.paths.dataHome } }catch{}
$usagePath=Join-Path $DataHome 'usage.jsonl'
$duesCache=Join-Path $DataHome 'dues.json'
$epFile=Join-Path $DataHome 'endpoints.json'
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
  $h=[int](Get-Date -Format 'HH')
  $sFrom=[int](($pet.silentFrom -split ':')[0]); $sTo=[int](($pet.silentTo -split ':')[0])
  $silent=$false
  if($sFrom -le $sTo){ $silent=($h -ge $sFrom -and $h -lt $sTo) } else { $silent=($h -ge $sFrom -or $h -lt $sTo) }
  if($pet.voice -and $zhVoice -and -not $NoWindow -and -not $silent -and -not $pet.muted){ try{ $sapi.Speak($txt,1) | Out-Null }catch{} }
}
function Get-PetLine{
  $f=Get-PetFacts
  $h=[int](Get-Date -Format 'HH')
  if($f.red){ return '体检有红：'+$f.redMsg.Substring(0,[Math]::Min($f.redMsg.Length,40))+'，去看结晶面板吧' }
  if($f.overdue -gt 0){ return ('有 '+$f.overdue+' 件逾期啦，主人快去看看吧') }
  if($f.pending -gt 0){ return ('今天还有 '+$f.pending+' 件没做完，摸摸鱼再做也行嘛') }
  $tok=if($f.usedTok -gt 0){ [math]::Round($f.usedTok/1e6,1) } else { 0 }
  if($h -ge 5 -and $h -lt 11 -and $pet.greetingAm){ $pet.greetingAm=$false; return '主人早，今天也要元气满满哦' }
  if($h -ge 20 -and $pet.greetingPm){ $pet.greetingPm=$false; return '夜深啦，摸摸鱼就睡吧' }
  return ('体检全绿，今天已用 '+$tok+' M token，端口 '+$f.port+'，一切正常')
}
# [fix-20261120-P2] 右键菜单动作们（都走 crystal.ps1 或直写，不重启桌宠）
function Invoke-Crystal([string]$verb,[string]$arg){
  $c=Join-Path $PSScriptRoot 'crystal.ps1'
  $a=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$c,'-Verb',$verb); if($arg){ $a+='-Arg1'; $a+=$arg }
  $p=Start-Process powershell.exe -ArgumentList $a -PassThru -Wait
  return ('exit='+$p.ExitCode)
}
function Set-ModeNow([string]$mode){
  try{
    $cj2=Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $bridgeHome=[string]$cj2.paths.bridgeHome; if(-not $bridgeHome){ $bridgeHome=$BridgeHome }
    $wm=Join-Path $bridgeHome 'state\work-mode.json'
    if($mode -eq 'work'){ $t=@{ global=@{ at=[long]((Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalMilliseconds); tool='panel' } } }
    else { $t=@{} }
    $json=($t | ConvertTo-Json -Compress); [IO.File]::WriteAllText($wm,$json,(New-Object System.Text.UTF8Encoding($false)))
    return $true
  }catch{ return $false }
}
$script:petBubble=$null; $script:petBubbleText=$null
function Show-Line([string]$txt){
  if($script:petBubbleText){ $script:petBubbleText.Text=$txt; $script:petBubble.Visibility='Visible' }
  Say-Pet $txt
  if($script:petBubble){
    $hide=New-Object Windows.Threading.DispatcherTimer
    $hide.Interval=New-Object TimeSpan (0,0,12)
    $hide.Add_Tick({ $script:petBubble.Visibility='Collapsed'; $hide.Stop() })
    $hide.Start()
  }
}
$inboxFile=Join-Path $Pkg 'data\pet-inbox.jsonl'
$inboxState=Join-Path $Pkg 'data\pet-inbox.state.json'
function Read-Inbox{
  try{
    $seen=0; try{ $st=Get-Content $inboxState -Raw -Encoding UTF8 | ConvertFrom-Json; $seen=[long]$st.seen }catch{}
    if(-not (Test-Path $inboxFile)){ return '' }
    $lines=@(Get-Content $inboxFile -Encoding UTF8); $n=$lines.Count; $picked=''
    for($i=$n-1; $i -ge 0; $i--){ if($i+1 -le $seen){ break }; $l=$lines[$i]; if($l -and $l.StartsWith('{')){ try{ $o=$l|ConvertFrom-Json; $picked=[string]$o.text; break }catch{} } }
    if($picked){ try{ [IO.File]::WriteAllText($inboxState,('{"seen":'+$n+'}'),(New-Object System.Text.UTF8Encoding($false))) }catch{} }
    return $picked
  }catch{ return '' }
}
function Get-StatusTip{
  $f=Get-PetFacts
  $tip='小鱼桌宠 · 右键有菜单'
  try{
    $wm=Join-Path $bridgeHome 'state\work-mode.json'
    $mode='聊天档'; try{ $t=Get-Content $wm -Raw -Encoding UTF8 | ConvertFrom-Json; if($t.global){ $mode='干活档' } }catch{}
    $col=if($f.red){'红'}elseif($f.yellow){'黄'}elseif($f.gray){'灰'}else{'绿'}
    $tok=if($f.usedTok -gt 0){ [math]::Round($f.usedTok/1e6,1) } else { 0 }
    $tip=('状态灯：'+$col+' · '+$mode+' · 今日 '+$tok+'M token · 拖动可挪位置')
  }catch{}
  return $tip
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
      <Grid>
        <Ellipse x:Name="Ring" Stroke="#2fa36b" StrokeThickness="5" Fill="#22FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Center"/>
        <Image x:Name="Img" Width="200" Height="200" Stretch="UniformToFill">
          <Image.Clip><EllipseGeometry RadiusX="100" RadiusY="100" Center="100,100"/></Image.Clip>
        </Image>
      </Grid>
    </StackPanel>
  </Grid>
</Window>
"@
$reader=New-Object System.Xml.XmlNodeReader $xaml
$win=[Windows.Markup.XamlReader]::Load($reader)
$bubble=$win.FindName('Bubble')
$bubbleText=$win.FindName('BubbleText')
$img=$win.FindName('Img')
$ring=$win.FindName('Ring')
# 立绘加载（2026-11-20 13:50 修：原来 new Uri(路径) 得到的是相对 URI，BitmapImage 静默失败 → 窗口只剩一块底色）
try{
  $abs=[Uri]::new((Resolve-Path $pet.image).Path, [UriKind]::Absolute)
  $bmp=New-Object Windows.Media.Imaging.BitmapImage
  $bmp.BeginInit(); $bmp.UriSource=$abs; $bmp.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bmp.EndInit()
  $img.Source=$bmp
}catch{
  try{ $img.Source=New-Object Windows.Media.Imaging.BitmapImage ([Uri]::new((Resolve-Path $pet.image).Path, [UriKind]::Absolute)) }catch{}
}
$img.Width=$pet.size; $img.Height=$pet.size
$clip=New-Object Windows.Media.EllipseGeometry
$clip.RadiusX=$pet.size/2; $clip.RadiusY=$pet.size/2
$clip.Center=New-Object Windows.Point ($pet.size/2),($pet.size/2)
$img.Clip=$clip
# 定位：屏幕右下角（WinForms 物理像素，与 DPI 不感知进程的 WPF 坐标一致）
Add-Type -AssemblyName System.Windows.Forms
# 定位用 WPF 自己的 WorkArea（单位=DIP，与 $win.Left/Top 同一坐标系）。
# 2026-11-20 13:48 修：原来用 WinForms Screen.WorkingArea（物理像素）当 DIP 用，
# 在 150% 缩放的 2560 屏上算出 Left=2220 DIP = 3330 物理像素 → 窗口落在屏幕右外侧，看不见。
try{
  $wa=[System.Windows.SystemParameters]::WorkArea
  $ring.Width=$pet.size+16; $ring.Height=$pet.size+16
  $px=[int]$ui.posX; $py=[int]$ui.posY
  if($px -gt 0 -and $py -gt 0 -and $px -lt $wa.Right -and $py -lt $wa.Bottom){
    $win.Left=$px; $win.Top=$py
  } else {
    $win.Left=[math]::Max(0, ($wa.Right - $pet.size - 80))
    $win.Top=[math]::Max(0, ($wa.Bottom - $pet.size - 100))
  }
}catch{
  $scr=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $win.Left=[math]::Max(0, ($scr.Right - $pet.size - 80))
  $win.Top=[math]::Max(0, ($scr.Bottom - $pet.size - 100))
}
try{
  $diagLine = '[PET-IMG] ' + (Get-Date -Format 'HH:mm:ss') + ' srcIsNull=' + ($null -eq $img.Source) + ' bmpW=' + $(if($img.Source){$img.Source.PixelWidth}else{0}) + ' actual=' + $img.ActualWidth + 'x' + $img.ActualHeight + ' path=' + $pet.image
  [IO.File]::AppendAllText((Join-Path $DataHome 'pet-diag-out3.log'), $diagLine + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}catch{}
$win.Title='小鱼'
$script:petBubble=$bubble
$script:petBubbleText=$bubbleText
$win.Add_MouseLeftButtonDown({ $win.DragMove() })
$win.Add_MouseLeftButtonUp({
  try{ $ui.posX=[int]$win.Left; $ui.posY=[int]$win.Top; Save-PetUi }catch{}
})
# [fix-20261120-P2] 状态灯：红黄绿灰环 + 悬停提示
function Set-Ring{
  $f=Get-PetFacts
  $c=if($f.red){'#d33c3c'}elseif($f.yellow){'#e6a23c'}elseif($f.gray){'#909399'}else{'#2fa36b'}
  try{ $ring.Stroke=(New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($c))) }catch{}
}
Set-Ring
$win.ToolTip=(Get-StatusTip)
# [fix-20261120-P2] 右键九项菜单（大小/间隔/静音/换立绘/切档/体检/备份/回滚预演/关闭带确认）
$cm=New-Object System.Windows.Controls.ContextMenu
function Add-Mi([string]$txt,$fn){
  $mi=New-Object System.Windows.Controls.MenuItem; $mi.Header=$txt
  $sb=[scriptblock]$fn
  # GetNewClosure 把 $fn 与外部变量一起关进去；旧写法 & $fn 在点击时 $fn 已不在作用域=点了没反应
  $mi.Add_Click($sb.GetNewClosure())
  $cm.Items.Add($mi)
}
Add-Mi ('大小：小（100）'){ $ui.size=100; Save-PetUi; $img.Width=100; $img.Height=100; $clip.RadiusX=50; $clip.RadiusY=50; $clip.Center=New-Object Windows.Point (50),(50); $ring.Width=116; $ring.Height=116 }
Add-Mi ('大小：中（200）'){ $ui.size=200; Save-PetUi; $img.Width=200; $img.Height=200; $clip.RadiusX=100; $clip.RadiusY=100; $clip.Center=New-Object Windows.Point (100),(100); $ring.Width=216; $ring.Height=216 }
Add-Mi ('大小：大（300）'){ $ui.size=300; Save-PetUi; $img.Width=300; $img.Height=300; $clip.RadiusX=150; $clip.RadiusY=150; $clip.Center=New-Object Windows.Point (150),(150); $ring.Width=316; $ring.Height=316 }
Add-Mi ('说话间隔：5 分钟'){ $ui.intervalMin=5; Save-PetUi; Show-Line '好啦，五分钟说一句' }
Add-Mi ('说话间隔：15 分钟'){ $ui.intervalMin=15; Save-PetUi; Show-Line '十五分钟说一句哦' }
Add-Mi ('说话间隔：30 分钟'){ $ui.intervalMin=30; Save-PetUi; Show-Line '半小时才吱一声，别想我啦' }
Add-Mi ('说话间隔：60 分钟'){ $ui.intervalMin=60; Save-PetUi; Show-Line '一小时一句，安静陪你' }
Add-Mi (if($ui.muted){'静音：开声音'}else{'静音：闭嘴'}){ $ui.muted=(-not $ui.muted); Save-PetUi; if($ui.muted){ Show-Line '……' } else { Show-Line '又能说话啦' } }
Add-Mi ('换立绘：蓝色小鱼'){ $ui.skin='assets\pet\blue-fish.jpg'; Save-PetUi; try{ $abs=[Uri]::new((Resolve-Path (Join-Path $Pkg $ui.skin)).Path,[UriKind]::Absolute); $bmp2=New-Object Windows.Media.Imaging.BitmapImage; $bmp2.BeginInit(); $bmp2.UriSource=$abs; $bmp2.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bmp2.EndInit(); $img.Source=$bmp2 }catch{}; Show-Line '换好啦，我是蓝色小鱼' }
Add-Mi ('换立绘：鲸鱼娘'){ $ui.skin='assets\pet\whale-girl.png'; Save-PetUi; try{ $abs=[Uri]::new((Resolve-Path (Join-Path $Pkg $ui.skin)).Path,[UriKind]::Absolute); $bmp2=New-Object Windows.Media.Imaging.BitmapImage; $bmp2.BeginInit(); $bmp2.UriSource=$abs; $bmp2.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bmp2.EndInit(); $img.Source=$bmp2 }catch{}; Show-Line '鲸鱼娘来啦' }
Add-Mi ('切到干活档'){ if(Set-ModeNow 'work'){ Show-Line '切到干活档啦，整机生效' } else { Show-Line '切换失败了，去看面板吧' } }
Add-Mi ('切回聊天档'){ if(Set-ModeNow 'chat'){ Show-Line '切回聊天档，只许说话哦' } else { Show-Line '切换失败了，去看面板吧' } }
Add-Mi ('立即体检'){ $r=Invoke-Crystal 'doctor'; Show-Line ('体检跑完，'+$r) }
Add-Mi ('一键备份'){ $r=Invoke-Crystal 'backup'; Show-Line ('备份跑完，'+$r) }
Add-Mi ('回滚预演'){ $r=Invoke-Crystal 'rollback' '-DryRun'; Show-Line ('预演跑完，'+$r) }
Add-Mi ('关闭'){ $a=[System.Windows.MessageBox]::Show('真的要让小鱼下班吗？','小鱼',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question); if($a -eq [System.Windows.MessageBoxResult]::Yes){ $win.Close() } }
$win.ContextMenu=$cm
# 呼吸动画：立绘轻微缩放
$sb=New-Object Windows.Media.Animation.Storyboard
$da=New-Object Windows.Media.Animation.DoubleAnimation
$da.From=1.0; $da.To=1.04; $da.Duration=New-Object Windows.Duration ([TimeSpan]::FromSeconds(1.6))
$da.AutoReverse=$true; $da.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
[Windows.Media.Animation.Storyboard]::SetTarget($da,$img)
[Windows.Media.Animation.Storyboard]::SetTargetProperty($da,(New-Object Windows.PropertyPath '(UIElement.RenderTransform).(ScaleTransform.ScaleX)'))
$sb.Children.Add($da)
$da2=New-Object Windows.Media.Animation.DoubleAnimation
$da2.From=1.0; $da2.To=1.04; $da2.Duration=New-Object Windows.Duration ([TimeSpan]::FromSeconds(1.6))
$da2.AutoReverse=$true; $da2.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
[Windows.Media.Animation.Storyboard]::SetTarget($da2,$img)
[Windows.Media.Animation.Storyboard]::SetTargetProperty($da2,(New-Object Windows.PropertyPath '(UIElement.RenderTransform).(ScaleTransform.ScaleY)'))
$sb.Children.Add($da2)
$img.RenderTransform=New-Object Windows.Media.ScaleTransform
$img.RenderTransformOrigin=New-Object Windows.Point (0.5,0.5)
$sb.Begin()
# 主循环：每 intervalMin 说一句有用内容；先看提醒总线，再看体检事实
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=New-Object TimeSpan (0,[int]$pet.intervalMin,0)
$timer.Add_Tick({
  try{
    Set-Ring
    $win.ToolTip=(Get-StatusTip)
    $inb=Read-Inbox
    if($inb -ne ''){ Show-Line ('提醒：'+$inb) }
    else {
      $line=Get-PetLine
      if($line -ne '' -and $bubbleText.Text -ne $line){ Show-Line $line }
    }
  }catch{}
})
$timer.Interval=New-Object TimeSpan (0,[int]$pet.intervalMin,0)
Show-Line (Get-PetLine)
$timer.Start()
$win.ShowDialog()
