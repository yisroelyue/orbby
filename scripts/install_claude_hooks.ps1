$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$hookScript = Join-Path $repoRoot ".claude\hooks\vibe_task_update.ps1"
if (-not (Test-Path $hookScript)) {
  throw "Hook script not found: $hookScript"
}

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"
New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

$settings = [pscustomobject]@{}
if (Test-Path $settingsPath) {
  $raw = Get-Content -Path $settingsPath -Raw
  if (-not [string]::IsNullOrWhiteSpace($raw)) {
    $settings = $raw | ConvertFrom-Json
  }
}

if ($null -eq $settings.hooks) {
  $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}

$escapedHookScript = $hookScript.Replace("\", "/")
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$escapedHookScript`""
$events = @(
  "SessionStart",
  "UserPromptSubmit",
  "PreToolUse",
  "PostToolUse",
  "Notification",
  "Stop",
  "SubagentStop"
)

foreach ($eventName in $events) {
  $entry = [ordered]@{
    matcher = ""
    hooks = @(
      [ordered]@{
        type = "command"
        command = $command
      }
    )
  }

  if ($settings.hooks.PSObject.Properties.Name -contains $eventName) {
    $existing = @($settings.hooks.$eventName)
    $alreadyInstalled = $false
    foreach ($existingEntry in $existing) {
      foreach ($existingHook in @($existingEntry.hooks)) {
        if ($existingHook.command -eq $command) {
          $alreadyInstalled = $true
        }
      }
    }

    if (-not $alreadyInstalled) {
      $settings.hooks.$eventName = @($settings.hooks.$eventName) + @($entry)
    }
  } else {
    $settings.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @($entry)
  }
}

$settings |
  ConvertTo-Json -Depth 100 |
  Set-Content -Path $settingsPath -Encoding UTF8

Write-Host "Claude Code hooks installed to $settingsPath"
Write-Host "State file: $env:USERPROFILE\.orbby\vibe_task.json"
