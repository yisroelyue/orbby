$ErrorActionPreference = "Stop"

try {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [Console]::InputEncoding = $utf8
  [Console]::OutputEncoding = $utf8
  $OutputEncoding = $utf8
} catch {
}

$homeDir = [Environment]::GetFolderPath("UserProfile")
if (-not $homeDir) {
  $homeDir = $env:USERPROFILE
}
if (-not $homeDir) {
  exit 0
}

$stateDir = Join-Path -Path $homeDir -ChildPath ".orbby"
$taskSessionId = if ($sessionId) { $sessionId } else { "default" }
$statePath = Join-Path -Path $stateDir -ChildPath "vibe_task_$taskSessionId.json"
$signalPath = Join-Path -Path $stateDir -ChildPath "vibe_task_$taskSessionId.signal"
$logPath = Join-Path -Path $stateDir -ChildPath "vibe_task_hook.log"

function Write-HookLog {
  param([string] $Message)

  try {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $time = [DateTimeOffset]::Now.ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $logPath -Value "[$time] $Message" -Encoding UTF8
  } catch {
  }
}

function Write-TextFileWithRetry {
  param(
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $true)] [string] $Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  for ($i = 0; $i -lt 6; $i++) {
    try {
      [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
      return
    } catch {
      if ($i -eq 5) {
        throw
      }
      Start-Sleep -Milliseconds (50 * ($i + 1))
    }
  }
}

function Get-EventValue {
  param(
    [Parameter(Mandatory = $true)] $Object,
    [Parameter(Mandatory = $true)] [string[]] $Names
  )

  foreach ($name in $Names) {
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $name) {
      $value = $Object.$name
      if ($null -ne $value -and "$value".Length -gt 0) {
        return "$value"
      }
    }
  }

  return ""
}

function Convert-JsonStringLiteral {
  param([string] $Value)

  try {
    return ("`"$Value`"" | ConvertFrom-Json)
  } catch {
    return $Value.Replace("\\", "\").Replace('\"', '"')
  }
}

function Get-RawJsonValue {
  param(
    [Parameter(Mandatory = $true)] [string] $Raw,
    [Parameter(Mandatory = $true)] [string] $Name
  )

  $pattern = '"' + [Regex]::Escape($Name) + '"\s*:\s*(?:"((?:\\.|[^"\\])*)"|([^,\}\]]+))'
  $match = [Regex]::Match($Raw, $pattern)
  if (-not $match.Success) {
    return ""
  }

  if ($match.Groups[1].Success) {
    return Convert-JsonStringLiteral $match.Groups[1].Value
  }

  $value = $match.Groups[2].Value.Trim()
  if ($value -eq "null") {
    return ""
  }
  return $value.Trim('"')
}

function Get-Status {
  param(
    [Parameter(Mandatory = $true)] [string] $HookName,
    [string] $NotificationType,
    [string] $Message
  )

  $reason = "$NotificationType $Message".Trim()
  switch ($HookName) {
    "SessionStart" { return "idle" }
    "UserPromptSubmit" { return "working" }
    "PreToolUse" { return "working" }
    "PostToolUse" { return "working" }
    "TaskCreated" { return "working" }
    "PermissionRequest" { return "needsApproval" }
    "AskUserQuestion" { return "needsInput" }
    "Notification" {
      if ($reason -match "(?i)permission|approval|approve|confirm|allow|deny") {
        return "needsApproval"
      }
      if ($reason -match "(?i)input|question|prompt") {
        return "needsInput"
      }
      return "needsInput"
    }
    "TaskCompleted" { return "completed" }
    "Stop" { return "completed" }
    "SubagentStop" { return "working" }
    "StopFailure" { return "failed" }
    default { return "working" }
  }
}

try {
  $rawInput = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-HookLog "Empty hook input."
    exit 0
  }

  $event = $rawInput | ConvertFrom-Json
} catch {
  Write-HookLog "JSON parse fallback: $($_.Exception.Message)"
  $event = $null
}

$hookName = ""
$sessionId = ""
$cwd = ""
$notificationType = ""
$message = ""
$toolName = ""

if ($null -ne $event) {
  $hookName = Get-EventValue $event @("hook_event_name", "hookEventName", "event", "type")
  $sessionId = Get-EventValue $event @("session_id", "sessionId")
  $cwd = Get-EventValue $event @("cwd")
  $notificationType = Get-EventValue $event @("notification_type", "notificationType")
  $message = Get-EventValue $event @("message", "prompt", "reason")
  $toolName = Get-EventValue $event @("tool_name", "toolName")

  if (-not $toolName -and $null -ne $event.tool) {
    $toolName = Get-EventValue $event.tool @("name")
  }

  if (-not $message -and $null -ne $event.tool_input) {
    $message = ($event.tool_input | ConvertTo-Json -Depth 5 -Compress)
  }
}

if (-not $hookName) { $hookName = Get-RawJsonValue $rawInput "hook_event_name" }
if (-not $hookName) { $hookName = Get-RawJsonValue $rawInput "hookEventName" }
if (-not $hookName) { $hookName = Get-RawJsonValue $rawInput "event" }
if (-not $hookName) { $hookName = Get-RawJsonValue $rawInput "type" }
if (-not $sessionId) { $sessionId = Get-RawJsonValue $rawInput "session_id" }
if (-not $sessionId) { $sessionId = Get-RawJsonValue $rawInput "sessionId" }
if (-not $cwd) { $cwd = Get-RawJsonValue $rawInput "cwd" }
if (-not $notificationType) { $notificationType = Get-RawJsonValue $rawInput "notification_type" }
if (-not $notificationType) { $notificationType = Get-RawJsonValue $rawInput "notificationType" }
if (-not $message) { $message = Get-RawJsonValue $rawInput "message" }
if (-not $message) { $message = Get-RawJsonValue $rawInput "prompt" }
if (-not $message) { $message = Get-RawJsonValue $rawInput "reason" }
if (-not $toolName) { $toolName = Get-RawJsonValue $rawInput "tool_name" }
if (-not $toolName) { $toolName = Get-RawJsonValue $rawInput "toolName" }

if (-not $hookName) {
  Write-HookLog "Hook input did not include a hook event name."
  exit 0
}

$projectName = if ($cwd) { Split-Path -Path $cwd -Leaf } else { "" }
if (-not $projectName) {
  $projectName = if ($sessionId) { $sessionId } else { "Claude Code" }
}

$displayName = $projectName
if ($toolName) {
  $displayName = "$projectName / $toolName"
}

$status = Get-Status `
  -HookName $hookName `
  -NotificationType $notificationType `
  -Message $message

try {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

  $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $state = [ordered]@{
    name = $displayName
    status = $status
    timestamp = $timestamp
    sessionId = $sessionId
    cwd = $cwd
    eventName = $hookName
    message = $message
    toolName = $toolName
  }

  $stateJson = $state | ConvertTo-Json -Depth 10
  Write-TextFileWithRetry -Path $statePath -Content $stateJson
  Write-TextFileWithRetry -Path $signalPath -Content "$timestamp"
  Write-HookLog "Updated state: event=$hookName status=$status session=$sessionId"
} catch {
  Write-HookLog "Failed to write state: $($_.Exception.Message)"
}

exit 0
