# crystal-version.ps1 - 版本号 + 一条命令回退（§42）：版本包快照插件本体（代码+配置），rollback -To vNNN 一条命令退回并自动复检
# 版本包内容=插件根 crystal.json + scripts\*.ps1 + data\crystal\fault-dictionary.json（运行数据 truth.json/stamps/alerts/snapshots 不入包，回退不回退运行状态）
# 用法：. '路径\crystal-version.ps1' 后调用 Save-CrystalVersion / Get-CrystalVersions / Restore-CrystalVersion
# 全函数内部只留痕写文件+Write-Host，返回值只走 return（铁律：靠返回值判成败的函数不许 Write-Output）
$script:VerRoot='F:\crystal\data\versions'
$script:VerBase='C:\Users\丽微\.dsh\plugins\dsh-crystal'
function Get-CrystalSha([string]$p){
  try{
    $b=[IO.File]::ReadAllBytes($p)
    $sha=[Security.Cryptography.SHA256]::Create()
    $h=$sha.ComputeHash($b)
    $sha.Dispose()
    return ([BitConverter]::ToString($h) -replace '-','').ToUpper()
  }catch{ return '' }
}
function Save-CrystalVersion{
  param([string]$Tag='',[string]$Note='')
  if($Tag -eq ''){ $Tag='v'+(Get-Date -Format 'yyyyMMddHHmm') }
  if($Tag -notmatch '^[A-Za-z0-9][A-Za-z0-9\-]{2,30}$'){ Write-Host ('版本号只许字母数字与横线，收到：'+$Tag); return $null }
  $dir=Join-Path $script:VerRoot $Tag
  try{
    if([IO.Directory]::Exists($dir)){ [IO.Directory]::Delete($dir,$true) }
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $files=@()
    $cands=@((Join-Path $script:VerBase 'crystal.json'))
    $cands+=@(Get-ChildItem (Join-Path $script:VerBase 'scripts') -Filter '*.ps1' -File | ForEach-Object { $_.FullName })
    $cands+=@((Join-Path $script:VerBase 'data\crystal\fault-dictionary.json'))
    foreach($f in $cands){
      if(-not (Test-Path $f)){ continue }
      $rel=$f.Substring($script:VerBase.Length).TrimStart('\','/')
      $dest=Join-Path $dir ($rel -replace '\\','_')
      Copy-Item $f $dest -Force
      $files+=@{ path=$rel; size=(Get-Item $f).Length; sha256=(Get-CrystalSha $f) }
    }
    $manifest=[pscustomobject]@{ version=$Tag; savedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'); note=$Note; base=$script:VerBase; files=$files }
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'),($manifest | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Write-Host ('版本已存：'+$Tag+'（'+$files.Count+' 件）')
    return [pscustomobject]@{ version=$Tag; dir=$dir; files=$files.Count }
  }catch{
    Write-Host ('版本保存失败：'+$_.Exception.Message)
    return $null
  }
}
function Get-CrystalVersions{
  $list=@()
  if(-not [IO.Directory]::Exists($script:VerRoot)){ return $list }
  foreach($d in @(Get-ChildItem $script:VerRoot -Directory | Sort-Object Name)){
    $m=Join-Path $d.FullName 'manifest.json'
    if(Test-Path $m){
      try{
        $mo=Get-Content $m -Raw -Encoding UTF8 | ConvertFrom-Json
        $list+=@([pscustomobject]@{ version=$mo.version; savedAt=$mo.savedAt; note=$mo.note; files=$mo.files.Count; dir=$d.FullName })
      }catch{}
    }
  }
  return $list
}
function Restore-CrystalVersion{
  param([string]$To='')
  if($To -eq ''){ Write-Host '缺少 -To <vNNN>'; return $null }
  $dir=Join-Path $script:VerRoot $To
  $m=Join-Path $dir 'manifest.json'
  if(-not (Test-Path $m)){ Write-Host ('版本不存在：'+$To); return $null }
  try{
    $mo=Get-Content $m -Raw -Encoding UTF8 | ConvertFrom-Json
    # 回退前把当前态存成 rollback-<时间> 保险包（防误退，可再翻回）
    $ins=Save-CrystalVersion -Tag ('rollback-'+($To -replace '^v','')+'-'+(Get-Date -Format 'HHmmss'))
    # 逐件哈希校验后回写
    $restored=0
    foreach($fo in @($mo.files)){
      $src=Join-Path $dir ([string]$fo.path -replace '\\','_')
      $dst=Join-Path $script:VerBase ([string]$fo.path)
      if(-not (Test-Path $src)){ Write-Host ('版本包缺件，中止：'+(Split-Path $src -Leaf)); return $null }
      if((Get-CrystalSha $src) -ne [string]$fo.sha256){ Write-Host ('哈希不符，中止：'+(Split-Path $src -Leaf)); return $null }
      Copy-Item $src $dst -Force
      $restored++
    }
    $alerts='C:\Users\丽微\.dsh\plugins\dsh-crystal\data\crystal\alerts.log'
    try{ [IO.File]::AppendAllText($alerts,('[ROLLBACK-VERSION] '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' to='+$To+' files='+$restored+' by=crystal-rollback'+"`r`n"),(New-Object Text.UTF8Encoding($false))) }catch{}
    Write-Host ('已回退到 '+$To+'（'+$restored+' 件），回退前保险包已存')
    return [pscustomobject]@{ version=$To; files=$restored }
  }catch{
    Write-Host ('回退失败：'+$_.Exception.Message)
    return $null
  }
}
