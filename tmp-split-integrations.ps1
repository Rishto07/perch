$src = "windows/src-tauri/src"
$file = "$src/integrations.rs"
$lines = [IO.File]::ReadAllText($file) -split "`n" | ForEach-Object { $_ -replace "\r$", "" }
Write-Output ("TOTAL_LINES=" + $lines.Count)

function Slice($a, $b) { return $lines[($a - 1)..($b - 1)] }
function Check($idx, $want) {
  $got = $lines[$idx - 1]
  if ($null -eq $got -or $got.IndexOf($want) -lt 0) { throw "Anchor mismatch at ${idx}: got [$got] want [$want]" }
}

Check 1  "// Integration pollers"
Check 17  "use tauri"
Check 23  "const TIMEOUT"
Check 29  "pub struct IntegrationUpdate"
Check 44  "fn emit"
Check 48  "fn client"
Check 57  "pub static PAUSED"
Check 64  "pub fn start"
Check 75  "fn enabled"
Check 84  "fn spawn"
Check 107 "poll_once"
Check 128 "fn is_new"
Check 136 "fn status_error"
Check 144 "Stripe"
Check 289 "GitHub"
Check 364 "Vercel"
Check 447 "Resend"
Check 512 "Notion"
Check 615 "Cal.com"
Check 684 "n8n"
Write-Output "ANCHORS_OK"

New-Item -ItemType Directory -Path "$src/integrations" -Force | Out-Null
function Write-File($path, $content) {
  [IO.File]::WriteAllText($path, ($content -join "`n"))
  Write-Output ("WROTE " + $path + " (" + [IO.File]::ReadAllLines($path).Count + " lines)")
}

$mod = (Slice 1 142) | ForEach-Object {
  $_ -replace '^use serde_json::\{json, Value\};', 'use serde_json::Value;' `
     -replace '^fn emit\(', 'pub(super) fn emit(' `
     -replace '^fn client\(', 'pub(super) fn client(' `
     -replace '^fn is_new\(', 'pub(super) fn is_new(' `
     -replace '^fn status_error\(', 'pub(super) fn status_error('
}
$mod = $mod + @(
  '',
  'mod calcom;',
  'mod github;',
  'mod notion;',
  'mod n8n;',
  'mod resend;',
  'mod stripe;',
  'mod vercel;',
  '',
  'use calcom::poll_calcom;',
  'use github::poll_github;',
  'use notion::poll_notion;',
  'use n8n::poll_n8n;',
  'use resend::poll_resend;',
  'use stripe::poll_stripe;',
  'use vercel::poll_vercel;',
  ''
)
Write-File "$src/integrations/mod.rs" $mod

Write-File "$src/integrations/stripe.rs" (@(
  'use super::{client, emit, is_new, status_error, IntegrationEvent, IntegrationUpdate};',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 144 288) + @(''))

Write-File "$src/integrations/github.rs" (@(
  'use super::{client, emit, status_error, IntegrationUpdate};',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 289 363) + @(''))

Write-File "$src/integrations/vercel.rs" (@(
  'use super::{client, emit, is_new, status_error, IntegrationEvent, IntegrationUpdate};',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 364 446) + @(''))

Write-File "$src/integrations/resend.rs" (@(
  'use super::{client, emit, status_error, IntegrationUpdate};',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 447 511) + @(''))

Write-File "$src/integrations/notion.rs" (@(
  'use super::{client, emit, status_error, IntegrationUpdate};',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 512 614) + @(''))

Write-File "$src/integrations/calcom.rs" (@(
  'use super::{client, emit, status_error, IntegrationUpdate};',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 615 683) + @(''))

Write-File "$src/integrations/n8n.rs" (@(
  'use super::{client, emit, is_new, IntegrationEvent, IntegrationUpdate};',
  'use crate::log;',
  'use crate::secrets;',
  'use serde_json::{json, Value};',
  'use tauri::AppHandle;',
  ''
) + (Slice 684 $lines.Count) + @(''))

Write-Output "SPLIT_DONE"
