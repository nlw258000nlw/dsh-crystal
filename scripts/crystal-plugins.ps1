# crystal-plugins.ps1 - 旧插件纳管只读盘点（P3 第一段）：三源对账，只读不写现网
# 源1=插件目录 C:\Users\丽微\.dsh\plugins（目录名=包名）；源2=profiles\desktop\package.json（dependencies key=包名、dsh.profile.bundles 条目=包名）；源3=crystal.json plugins（name）
# 归一口径：@scope/name → scope-name（去 @、/ 变 -、小写）；目录名与包名按归一后比对
# 产出=F:\crystal\data\plugins-inventory.json（schemaVersion 1、generatedAt、sources 三源 mtime、entries{name,source,version,status=covered|registered|pending|unknown,evidence}）
param([string]$OutFile='F:\crystal\data\plugins-inventory.json')
$ErrorActionPreference='SilentlyContinue'
$enc=New-Object Text.UTF8Encoding($false)
function Norm-Pkg([string]$n){ return ($n -replace '^@','' -replace '/','-').ToLower() }
$plugDir='C:\Users\丽微\.dsh\plugins'
$pkgJson='C:\Users\丽微\.dsh\profiles\desktop\package.json'
$crystalJson='C:\Users\丽微\.dsh\plugins\dsh-crystal\crystal.json'
$allDirs=@(Get-ChildItem $plugDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$bakDirs=@($allDirs | Where-Object { $_ -like '*.bak-*' })
$dirNames=@($allDirs | Where-Object { $_ -notlike '*.bak-*' })
$dirMtime=(Get-Item $plugDir).LastWriteTime
$pkg=Get-Content $pkgJson -Raw -Encoding UTF8 | ConvertFrom-Json
$depNames=@(); $depVer=@{}
foreach($p in $pkg.dependencies.PSObject.Properties){ $depNames+=$p.Name; $depVer[$p.Name]=[string]$p.Value }
$bundleNames=@($pkg.dsh.profile.bundles)
$pkgMtime=(Get-Item $pkgJson).LastWriteTime
$cj=Get-Content $crystalJson -Raw -Encoding UTF8 | ConvertFrom-Json
$crystalNames=@($cj.plugins | ForEach-Object { [string]$_.name })
$crystalMtime=(Get-Item $crystalJson).LastWriteTime
$dirNorm=@{}; foreach($d in $dirNames){ $dirNorm[(Norm-Pkg $d)]=$d }
$depNorm=@{}; foreach($d in $depNames){ $depNorm[(Norm-Pkg $d)]=$d }
$bunNorm=@{}; foreach($b in $bundleNames){ $bunNorm[(Norm-Pkg $b)]=$b }
$cryNorm=@{}; foreach($c in $crystalNames){ $cryNorm[(Norm-Pkg $c)]=$c }
foreach($bd in $bakDirs){ Write-Output ('[IGNORED] '+$plugDir+'\'+$bd+' 排除原因=*.bak-* 目录（备份目录，不纳管）') }
$entries=@()
foreach($dn in $dirNorm.Keys){
  $inBun=$bunNorm.ContainsKey($dn); $inDep=$depNorm.ContainsKey($dn)
  if(-not $inBun -and -not $inDep){
    if($cryNorm.ContainsKey($dn)){
      $entries+=@{ name=$dirNorm[$dn]; source='插件目录'; version=''; status='covered'; evidence=('目录在+总表纳管：'+$plugDir+'\'+$dirNorm[$dn]) }
    } else {
      $entries+=@{ name=$dirNorm[$dn]; source='插件目录'; version=''; status='pending'; evidence=('目录存在但 bundles/dependencies 均无登记：'+$plugDir+'\'+$dirNorm[$dn]) }
    }
  }
}
foreach($bn in $bunNorm.Keys){
  if(-not $dirNorm.ContainsKey($bn)){
    $entries+=@{ name=$bunNorm[$bn]; source='package.json bundles'; version=''; status='unknown'; evidence='bundles 已登记但插件目录无对应目录（在目录没登记→登记没目录）' }
  }
}
foreach($dn in $depNorm.Keys){
  if($dirNorm.ContainsKey($dn)){
    $inBun=$bunNorm.ContainsKey($dn)
    $inCry=$cryNorm.ContainsKey($dn)
    if($inCry){ $status='covered' } elseif($inBun){ $status='registered' } else { $status='pending' }
    $entries+=@{ name=$depNorm[$dn]; source='package.json dependencies'; version=$depVer[$depNorm[$dn]]; status=$status; evidence=('目录='+(Test-Path (Join-Path $plugDir $dirNorm[$dn]))+' bundles='+$inBun+' crystal='+$inCry) }
  }
}
foreach($cn in $cryNorm.Keys){
  if(-not $dirNorm.ContainsKey($cn)){
    $entries+=@{ name=$cryNorm[$cn]; source='crystal.json plugins'; version=''; status='unknown'; evidence='总表已纳管但插件目录无对应目录' }
  }
}
$obj=@{ schemaVersion=1; generatedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'); sources=@{ pluginsDir=$plugDir; pluginsDirMtime=$dirMtime.ToString('yyyy-MM-dd HH:mm:ss'); packageJson=$pkgJson; packageJsonMtime=$pkgMtime.ToString('yyyy-MM-dd HH:mm:ss'); crystalJson=$crystalJson; crystalJsonMtime=$crystalMtime.ToString('yyyy-MM-dd HH:mm:ss') }; entries=$entries }
[IO.File]::WriteAllText($OutFile,($obj | ConvertTo-Json -Depth 8),$enc)
$cov=@($entries | Where-Object { $_.status -eq 'covered' }).Count
$reg=@($entries | Where-Object { $_.status -eq 'registered' }).Count
$pend=@($entries | Where-Object { $_.status -eq 'pending' }).Count
$unk=@($entries | Where-Object { $_.status -eq 'unknown' }).Count
Write-Output ('[PLUGINS] '+$obj.generatedAt+' 三源='+$dirNames.Count+' 目录 / '+$depNames.Count+' 依赖 / '+$bundleNames.Count+' bundles / '+$crystalNames.Count+' 总表')
Write-Output ('[PLUGINS] covered='+$cov+' registered='+$reg+' pending='+$pend+' unknown='+$unk+' 明细='+$OutFile)
