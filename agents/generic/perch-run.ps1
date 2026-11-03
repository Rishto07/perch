# perch-run — wrap ANY coding agent so Perch shows its session (Windows).
# Usage:
#   agents\generic\perch-run.ps1 -Agent zcode -Prompt "refactor auth" -- zcode run --task refactor
#   agents\generic\perch-run.ps1 -- codex exec "fix the flaky test"
#   $env:PERCH_AGENT = "freebuff"; agents\generic\perch-run.ps1 -- freebuff "add dark mode"
#
# Sends SessionStart + UserPromptSubmit, runs the command, then Stop (or
# StopFailure on non-zero exit). Fire-and-forget: Perch closed costs nothing.
param(
  [string]$Agent = $env:PERCH_AGENT,
  [string]$Prompt = "",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Command
)
$ErrorActionPreference = "Continue"
if (-not $Agent) { $Agent = "generic" }
if ($Command.Count -gt 0 -and $Command[0] -eq "--") { $Command = @($Command | Select-Object -Skip 1) }
if ($Command.Count -eq 0) { Write-Error "usage: perch-run.ps1 [-Agent NAME] [-Prompt TEXT] -- <command…>"; exit 2 }

$hookExe = Join-Path $env:LOCALAPPDATA "Perch\bin\perch-hook.exe"
$hookReady = Test-Path -LiteralPath $hookExe
$session = "wrap-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$cwd = (Get-Location).Path
if (-not $Prompt) { $Prompt = $Command -join " " }

function Send-Hook([string]$Event, [string]$Extra = "") {
  if (-not $hookReady) { return }
  $payload = '{"hook_event_name":"' + $Event + '","agent":"' + $Agent + '","session_id":"' + $session + '","cwd":' + (ConvertTo-Json $cwd) + ',"prompt":' + (ConvertTo-Json $Prompt) + $Extra + '}'
  try { $payload | & $hookExe $Event $Agent 2>$null | Out-Null } catch { }
}

Send-Hook "SessionStart"
Send-Hook "UserPromptSubmit"
$code = 0
try { & $Command[0] @($Command | Select-Object -Skip 1); $code = $LASTEXITCODE } catch { $code = 1 }
if ($code -eq 0) { Send-Hook "Stop" } else { Send-Hook "StopFailure" }
exit $code
