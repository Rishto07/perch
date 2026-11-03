# Install Perch hooks for Codex CLI (Windows).
# Merges lifecycle hooks into %USERPROFILE%\.codex\hooks.json without touching
# anyone else's entries. Dated backup first, like the Claude installer.
# Usage: powershell -ExecutionPolicy Bypass -File agents\codex\install.ps1 [-Uninstall]
param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$hookExe = Join-Path $env:LOCALAPPDATA "Perch\bin\perch-hook.exe"
if (-not (Test-Path -LiteralPath $hookExe)) {
  Write-Error "perch-hook.exe not found at $hookExe. Launch Perch once first (it installs the relay)."
}
$settings = Join-Path $env:USERPROFILE ".codex\hooks.json"
New-Item -ItemType Directory -Path (Split-Path $settings) -Force | Out-Null
if (-not (Test-Path -LiteralPath $settings)) { "{}" | Set-Content -LiteralPath $settings -Encoding utf8NoBOM }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item -LiteralPath $settings -Destination "$settings.bak-$stamp"
Write-Host "backup: $settings.bak-$stamp"

$exe = $hookExe -replace '\\', '/'
$data = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json -AsHashtable
if (-not $data.ContainsKey("hooks") -or $null -eq $data["hooks"]) { $data["hooks"] = @{} }
$events = @("SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","Notification","Stop","StopFailure")

foreach ($ev in $events) {
  $list = @()
  if ($data["hooks"].ContainsKey($ev) -and $null -ne $data["hooks"][$ev]) { $list = @($data["hooks"][$ev]) }
  $list = @($list | Where-Object {
    $cmds = @($_["hooks"] | ForEach-Object { $_["command"] })
    -not ($cmds -match "perch-hook")
  })
  if (-not $Uninstall) {
    $list += @{ matcher = ""; hooks = @(@{ type = "command"; command = "`"$exe`" $ev codex"; timeout = 10 }) }
  }
  if ($list.Count -gt 0) { $data["hooks"][$ev] = $list } else { $data["hooks"].Remove($ev) }
}

$data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $settings -Encoding utf8NoBOM
Write-Host ($(if ($Uninstall) { "uninstalled" } else { "installed: $settings" }))
