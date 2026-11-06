#requires -Version 7.6
<#
.SYNOPSIS
Runs the offline companion suite and saves every terminal outcome.
.PARAMETER RunDirectory
Owned report directory.
.PARAMETER CoreManifest
Selected QuietCli Core dependency.
.PARAMETER SkipMutation
Explicitly limited development scope.
#>
param([string]$RunDirectory, [string]$CoreManifest, [switch]$SkipMutation)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RunState.ps1')
$root = Split-Path $PSScriptRoot -Parent
$state = @{ Project = 'FrenchExDev2.GitHub.PoSh + FrenchExDev2.GitHub.Tests.PoSh'; Task = 'Offline qualification'; Workspace = $root; ProjectDirectory = (Join-Path $root 'FrenchExDev2.GitHub.PoSh') + ' | ' + (Join-Path $root 'FrenchExDev2.GitHub.Tests.PoSh'); Platform = [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier; ProcessId = $PID; StartedUtc = [DateTimeOffset]::UtcNow; FinishedUtc = $null; Passed = 0; Failed = 0; State = 'Running'; Case = 'Import'; Error = $null }
$result = $null
$sourceIdentity = @()
try {
    $sourceIdentity = @(Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Sort-Object FullName | ForEach-Object { @{ Path = [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/'); SHA256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } })
    Write-GitHubRunJson (Join-Path $RunDirectory 'status.json') $state
    . (Join-Path $PSScriptRoot 'Import-Workspace.ps1') -CoreManifest $CoreManifest
    $result = Invoke-GitHubFixtureTests -RunDirectory $RunDirectory -CoreManifest $CoreManifest -SkipMutation:$SkipMutation -OnProgress {
        param($case)
        $state.Case = $case.Name
        if ($case.Passed) { $state.Passed++ } else { $state.Failed++ }
        [void][IO.File]::AppendAllTextAsync((Join-Path $RunDirectory 'cases.jsonl'), ((ConvertTo-Json $case -Compress -Depth 8) -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        Write-GitHubRunJson (Join-Path $RunDirectory 'status.json') $state
    }
    $state.State = if ($state.Failed) { 'Failed' } else { 'Success' }
} catch { $state.State = 'Crash'; $state.Error = $_.ToString() + "`n" + $_.ScriptStackTrace }
finally {
    $state.FinishedUtc = [DateTimeOffset]::UtcNow
    if ($state.State -eq 'Success') {
        foreach ($entry in $sourceIdentity) {
            $path = Join-Path $root $entry.Path
            if (!(Test-Path $path) -or (Get-FileHash $path -Algorithm SHA256).Hash -cne $entry.SHA256) {
                $state.State = 'Failed'; $state.Failed++; $state.Error = 'SourcesChangedDuringRun: ' + $entry.Path; break
            }
        }
    }
    Write-GitHubRunJson (Join-Path $RunDirectory 'summary.json') @{ State = $state; Results = $result; Source = $sourceIdentity; Runtime = @{ PowerShell = $PSVersionTable.PSVersion.ToString(); Clr = [Environment]::Version.ToString(); CoreManifest = $CoreManifest; CoreManifestSHA256 = $(if (Test-Path $CoreManifest) { (Get-FileHash $CoreManifest -Algorithm SHA256).Hash } else { $null }) } }
    Write-GitHubRunSummary $RunDirectory $state
    Write-GitHubRunJson (Join-Path $RunDirectory 'status.json') $state
}
if ($state.State -ne 'Success') { exit 1 }
