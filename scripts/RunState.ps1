function Write-GitHubRunJson {
    <#
    .SYNOPSIS
    Atomically saves UTF-8/LF state so the read-only monitor never sees a partial document.
    .PARAMETER Path
    Owned destination file.
    .PARAMETER Value
    Explicit report data.
    #>
    param([string]$Path, $Value)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $text = ((ConvertTo-Json -InputObject $Value -Depth 30) -replace "`r`n", "`n") + "`n"
    [void][IO.File]::WriteAllTextAsync($temporary, $text, [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [IO.File]::Move($temporary, $Path, $true)
}

function Write-GitHubRunSummary {
    <#
    .SYNOPSIS
    Saves a static framed terminal summary with project identity and compact duration.
    .PARAMETER Directory
    Owned report directory.
    .PARAMETER State
    Final worker state.
    #>
    param([string]$Directory, [hashtable]$State)
    . (Join-Path $PSScriptRoot 'Monitor.Time.ps1')
    $duration = Get-QuietMonitorDuration -StartedUtc $State.StartedUtc -FinishedUtc $State.FinishedUtc
    $widths = @(12, 12, 10, 10, 8, 8)
    $lines = @("Projet : $($State.Project) | Tâche : $($State.Task)", $State.Workspace, $State.ProjectDirectory)
    $lines += '┌' + (($widths | ForEach-Object { '─' * $_ }) -join '┬') + '┐'
    foreach ($row in @(@('Platform', 'State', 'Duration', 'Process', 'Passed', 'Failed'), @($State.Platform, $State.State, $duration, $State.ProcessId, $State.Passed, $State.Failed))) {
        $cells = for ($i = 0; $i -lt $widths.Count; $i++) {
            $value = [string]$row[$i]
            if ($value.Length -gt $widths[$i]) { $value = $value.Substring(0, $widths[$i] - 1) + '…' }
            if ($i -ge 2) { $value.PadLeft($widths[$i]) } else { $value.PadRight($widths[$i]) }
        }
        $lines += '|' + ($cells -join '|') + '|'
    }
    $lines += '└' + (($widths | ForEach-Object { '─' * $_ }) -join '┴') + '┘'
    if ($State.Error) { $lines += $State.Error }
    [void][IO.File]::WriteAllTextAsync((Join-Path $Directory 'summary.txt'), (($lines -join "`n") -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}
