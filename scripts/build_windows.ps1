[CmdletBinding()]
param(
    [switch]$SkipFlutterBuild,
    [string]$OutputDirectory = "build/windows/x64/runner/Release"
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeSource = Join-Path $projectRoot 'agent-runtime'
$runtimeTarget = Join-Path $projectRoot $OutputDirectory

function Invoke-Checked([string]$Command, [string[]]$Arguments, [string]$WorkingDirectory) {
    Push-Location $WorkingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Command exited with code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $runtimeSource 'package.json'))) {
    throw "agent-runtime/package.json was not found."
}

Write-Host 'Building agent-runtime...'
Invoke-Checked 'npm' @('run', 'build') $runtimeSource

if (-not $SkipFlutterBuild) {
    Write-Host 'Building Flutter Windows release...'
    Invoke-Checked 'flutter' @('build', 'windows', '--release') $projectRoot
}

if (-not (Test-Path $runtimeTarget)) {
    throw "Flutter output directory was not found: $runtimeTarget"
}

$runtimeTarget = Join-Path $runtimeTarget 'agent-runtime'
if (Test-Path $runtimeTarget) {
    Remove-Item -LiteralPath $runtimeTarget -Recurse -Force
}
New-Item -ItemType Directory -Path $runtimeTarget | Out-Null

Write-Host 'Packaging agent-runtime (including node_modules)...'
Copy-Item -LiteralPath (Join-Path $runtimeSource 'dist') -Destination $runtimeTarget -Recurse
Copy-Item -LiteralPath (Join-Path $runtimeSource 'node_modules') -Destination $runtimeTarget -Recurse
Copy-Item -LiteralPath (Join-Path $runtimeSource 'package.json') -Destination $runtimeTarget
if (Test-Path (Join-Path $runtimeSource 'package-lock.json')) {
    Copy-Item -LiteralPath (Join-Path $runtimeSource 'package-lock.json') -Destination $runtimeTarget
}

Write-Host "Windows package is ready: $runtimeTarget"
