# crystal-pet-tell.ps1 - 桌宠提醒总线（P2-d）：四源写入 pet-inbox.jsonl，桌宠每 tick 读最新一条
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File crystal-pet-tell.ps1 -Text "有红项快去修" -Level red
# 四源：red=体检红项 / money=花费到 80% / plugin=插件租期到期 / mem=记忆建议清单
# 桌宠只读不回写；seen 水位记在 data\pet-inbox.state.json
param([string]$Text='',[string]$Level='info')
if([string]::IsNullOrWhiteSpace($Text)){ exit 2 }
$Pkg=Split-Path -Parent $PSScriptRoot
$inbox=Join-Path $Pkg 'data\pet-inbox.jsonl'
$o=[ordered]@{ ts=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); level=$Level; text=([string]$Text).Replace('"','') }
$line=($o | ConvertTo-Json -Compress)
[IO.File]::AppendAllText($inbox, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('[PET-TELL] ' + $Level + ' ' + $Text)
