#requires -Version 7.6
<#
.SYNOPSIS
Starts offline tests in a background worker with a visible, automatically closing local monitor.
.PARAMETER CoreManifest
Exact selected QuietCli Core manifest.
.PARAMETER RunDirectory
New report directory, outside the checkout.
.PARAMETER Headless
CI-only mode; local Windows runs always display the monitor.
.PARAMETER SkipMutation
Explicitly limited development scope.
.PARAMETER TimeoutSeconds
Hard whole-run limit, at most fifteen minutes.
#>
[CmdletBinding()]
param(
    [string]$CoreManifest = (Join-Path $PSScriptRoot '../../QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'),
    [string]$RunDirectory, [switch]$Headless, [switch]$SkipMutation,
    [ValidateRange(1, 900)][int]$TimeoutSeconds = 900
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RunState.ps1')
$root = Split-Path $PSScriptRoot -Parent
if ($Headless -and $env:CI -ne 'true') { throw 'HeadlessIsReservedForCI' }
if (!$Headless -and !$IsWindows) { throw 'Local qualification requires a Windows visible monitor; use the CI workflow for Linux.' }
if (!$RunDirectory) {
    $identity = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($root))).Substring(0, 12).ToLowerInvariant()
    $RunDirectory = Join-Path ([IO.Path]::GetTempPath()) ('GitHubEcosystem/' + $identity + '/tests/' + [guid]::NewGuid().ToString('N'))
}
$RunDirectory = [IO.Path]::GetFullPath($RunDirectory)
$relative = [IO.Path]::GetRelativePath($root, $RunDirectory)
if (!$relative.StartsWith('..') -and ![IO.Path]::IsPathRooted($relative)) { throw 'ReportsMustBeOutsideCheckout' }
if (Test-Path -LiteralPath $RunDirectory) { throw 'RunDirectoryAlreadyExists' }
[void][IO.Directory]::CreateDirectory($RunDirectory)
$CoreManifest = [IO.Path]::GetFullPath($CoreManifest)
$runner = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$workerScript = Join-Path $PSScriptRoot 'Invoke-TestWorker.ps1'
$monitorScript = Join-Path $PSScriptRoot 'Watch-Tests.ps1'
$arguments = @('-File', ('"' + $workerScript + '"'), '-RunDirectory', ('"' + $RunDirectory + '"'), '-CoreManifest', ('"' + $CoreManifest + '"'))
if ($SkipMutation) { $arguments += '-SkipMutation' }
$options = @{ FilePath = $runner; ArgumentList = $arguments; PassThru = $true; RedirectStandardOutput = (Join-Path $RunDirectory 'stdout.log'); RedirectStandardError = (Join-Path $RunDirectory 'stderr.log') }
if ($IsWindows) { $options.WindowStyle = 'Hidden' }
$worker = Start-Process @options
$monitor = $null
"Reports: $RunDirectory"
"Monitor: pwsh -File `"$monitorScript`" -RunDirectory `"$RunDirectory`""
try {
    if (!$Headless) { $monitor = Start-Process $runner -WindowStyle Normal -ArgumentList @('-File', ('"' + $monitorScript + '"'), '-RunDirectory', ('"' + $RunDirectory + '"')) -PassThru }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (!$worker.HasExited -and $clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($monitor -and $monitor.HasExited) { $monitor = Start-Process $runner -WindowStyle Normal -ArgumentList @('-File', ('"' + $monitorScript + '"'), '-RunDirectory', ('"' + $RunDirectory + '"')) -PassThru }
        [void][Threading.Tasks.Task]::Delay(500).GetAwaiter().GetResult()
    }
    if (!$worker.HasExited) { $worker.Kill($true); $worker.WaitForExit() }
    $statusPath = Join-Path $RunDirectory 'status.json'
    $state = if (Test-Path $statusPath) { Get-Content $statusPath -Encoding utf8 -Raw | ConvertFrom-Json -AsHashtable } else { @{ StartedUtc = [DateTimeOffset]::UtcNow; Passed = 0; Failed = 0; Project = 'FrenchExDev2.GitHub.Tests.PoSh'; Task = 'Offline qualification'; Workspace = $root; ProjectDirectory = (Join-Path $root 'FrenchExDev2.GitHub.Tests.PoSh'); ProcessId = $worker.Id; Platform = [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier } }
    if ($state.State -notin @('Success', 'Failed', 'Crash')) {
        $state.State = if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { 'Timeout' } else { 'Crash' }
        $state.FinishedUtc = [DateTimeOffset]::UtcNow
        $state.Error = 'Worker terminated without a normal summary; inspect stdout.log, stderr.log and cases.jsonl.'
        Write-GitHubRunJson (Join-Path $RunDirectory 'summary.json') @{ State = $state }
        Write-GitHubRunSummary $RunDirectory $state
        Write-GitHubRunJson $statusPath $state
    }
    $state | Select-Object State, Passed, Failed
    if ($state.State -ne 'Success') { throw "Offline qualification failed: $RunDirectory" }
} catch {
    $failure = $_
    if (!$worker.HasExited) { $worker.Kill($true); $worker.WaitForExit() }
    $statusPath = Join-Path $RunDirectory 'status.json'
    if (Test-Path $statusPath) {
        $saved = Get-Content $statusPath -Encoding utf8 -Raw | ConvertFrom-Json -AsHashtable
        if ($saved.State -notin @('Success', 'Failed', 'Crash', 'Timeout', 'Cancelled')) {
            $saved.State = if ($failure.Exception -is [Management.Automation.PipelineStoppedException]) { 'Cancelled' } else { 'Crash' }
            $saved.FinishedUtc = [DateTimeOffset]::UtcNow; $saved.Error = $failure.ToString()
            Write-GitHubRunJson (Join-Path $RunDirectory 'summary.json') @{ State = $saved }
            Write-GitHubRunSummary $RunDirectory $saved
            Write-GitHubRunJson $statusPath $saved
        }
    }
    throw
} finally {
    if (!$worker.HasExited) { $worker.Kill($true); $worker.WaitForExit() }
    if ($monitor -and !$monitor.HasExited) { $null = $monitor.WaitForExit(3000); if (!$monitor.HasExited) { $monitor.CloseMainWindow() | Out-Null } }
}
