#requires -Version 7.6
<#
.SYNOPSIS
Implements the tested subset of gh using isolated JSON state and optional local Git repositories.
.PARAMETER StatePath
Owned fixture state file; also owns the adjacent invocation journal.
.PARAMETER CoreManifest
Exact QuietCli Core manifest used for local Git commands.
.PARAMETER CliArguments
Arguments that would otherwise be passed to gh.
#>
param([string]$StatePath, [string]$CoreManifest, [Parameter(ValueFromRemainingArguments)][string[]]$CliArguments)
$ErrorActionPreference = 'Stop'
$state = Get-Content -LiteralPath $StatePath -Encoding utf8 -Raw | ConvertFrom-Json -AsHashtable -DateKind String
$journal = "$StatePath.calls.jsonl"
[void][IO.File]::AppendAllTextAsync($journal, (ConvertTo-Json -InputObject @($CliArguments) -Compress) + "`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
$calls = @(Get-Content -LiteralPath $journal -Encoding utf8 | ForEach-Object { ,(ConvertFrom-Json $_) })
$operation = $CliArguments -join ' '
$metadataReads = @($calls | Where-Object { ($_ -join ' ') -match '/pulls/[0-9]+$' }).Count
$mutations = @($calls | Where-Object { ($_ -join ' ') -match '^pr update-branch .*--rebase$' }).Count
if ($CliArguments[0] -eq '--version') { 'gh version 2.83.0 (fixture)'; exit 0 }
if ($operation -eq 'pr update-branch --help') { 'Usage: gh pr update-branch <url> --rebase'; exit 0 }
if ($state.Mode -eq 'Timeout' -and $CliArguments[0] -eq 'api') { [void][Threading.Tasks.Task]::Delay(10000).GetAwaiter().GetResult() }
if ($state.Mode -eq 'Malformed') { '{broken'; exit 0 }
if ($state.Mode -eq 'Denied') { [Console]::Error.WriteLine('fixture forbidden'); exit 1 }

function Invoke-LocalGit {
    <#
    .SYNOPSIS
    Executes bounded Git operations against owned local fixtures through QuietCli.
    .PARAMETER Arguments
    Exact native Git argument vector.
    .PARAMETER AllowFailure
    Returns unsuccessful commands for independent conflict assertions.
    #>
    param([string[]]$Arguments, [switch]$AllowFailure)
    if (!(Get-Module FrenchExDev2.QuietCli.Core.PoSh)) { Import-Module $CoreManifest -ErrorAction Stop }
    if ((Get-Module FrenchExDev2.QuietCli.Core.PoSh).Path -ne [IO.Path]::ChangeExtension($CoreManifest, 'psm1')) { throw 'FixtureCorePathMismatch' }
    $gitManifest = Join-Path (Split-Path (Split-Path $CoreManifest -Parent) -Parent) 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1'
    if (!(Get-Module FrenchExDev2.QuietCli.Git.PoSh)) { Import-Module $gitManifest -ErrorAction Stop }
    if ((Get-Module FrenchExDev2.QuietCli.Git.PoSh).Path -ne [IO.Path]::ChangeExtension($gitManifest, 'psm1')) { throw 'FixtureGitModulePathMismatch' }
    $diagnostics = [Text.StringBuilder]::new()
    $result = quiet -AsObject -FilePath git -ArgumentList $Arguments -Environment $state.GitEnvironment -Data @{ Out = [Text.StringBuilder]::new(); Err = $diagnostics } -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            if ($runtime.Data.Out.Length + $event.Text.Length -gt 32768) { throw 'FixtureOutputTooLarge' }
            [void]$runtime.Data.Out.Append($event.Text)
        } elseif ($runtime.Data.Err.Length -lt 2000) { [void]$runtime.Data.Err.Append($event.Text) }
    }
    if ($result.Outcome -ne 'Success' -and !$AllowFailure) { throw ('FixtureGitFailed: ' + ($Arguments -join ' ') + ' / ' + $diagnostics.ToString() + ' / ' + ($result.Error | ConvertTo-Json -Depth 5 -Compress)) }
    [pscustomobject]@{ Text = $result.Data.Out.ToString().Trim(); Success = $result.Outcome -eq 'Success' }
}

$base = $state.BaseSha; $head = $state.HeadSha; $ahead = $state.Ahead; $behind = $state.Behind
if ($state.ContainsKey('GitRoot')) {
    $work = Join-Path $state.GitRoot 'fork-work'
    if ($state.Mode -in @('RealTargetChanged', 'RealHeadChanged') -and $metadataReads -ge 2 -and !(Test-Path "$StatePath.changed")) {
        $changedWork = if ($state.Mode -eq 'RealTargetChanged') { Join-Path $state.GitRoot 'upstream-work' } else { $work }
        $changedBranch = if ($state.Mode -eq 'RealTargetChanged') { $state.BaseBranch } else { 'topic/é-hover' }
        [void][IO.File]::WriteAllTextAsync((Join-Path $changedWork 'concurrent.txt'), "concurrent change`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $null = Invoke-LocalGit @('-C', $changedWork, 'add', 'concurrent.txt')
        $null = Invoke-LocalGit @('-C', $changedWork, 'commit', '-m', 'Concurrent reference movement')
        $null = Invoke-LocalGit @('-C', $changedWork, 'push', 'origin', $changedBranch)
        if ($state.Mode -eq 'RealTargetChanged') { $null = Invoke-LocalGit @('-C', $work, 'fetch', 'upstream') }
        [void][IO.File]::WriteAllTextAsync("$StatePath.changed", 'applied', [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    $base = (Invoke-LocalGit @('--git-dir', (Join-Path $state.GitRoot 'upstream.git'), 'rev-parse', "refs/heads/$($state.BaseBranch)")).Text
    $head = (Invoke-LocalGit @('--git-dir', (Join-Path $state.GitRoot 'fork.git'), 'rev-parse', 'refs/heads/topic/é-hover')).Text
    $counts = (Invoke-LocalGit @('-C', $work, 'rev-list', '--left-right', '--count', "$base...$head")).Text -split '\s+'
    $behind = [int]$counts[0]; $ahead = [int]$counts[1]
} elseif ($mutations -gt 0 -and $state.Mode -notin @('Fail', 'Unconfirmed', 'BatchFail')) {
    $head = 'dddddddddddddddddddddddddddddddddddddddd'; $behind = 0
}
if ($state.Mode -eq 'Changed' -and $metadataReads -gt 1) { $head = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' }
if ($state.Mode -eq 'TargetChanged' -and $metadataReads -gt 1) { $base = 'ffffffffffffffffffffffffffffffffffffffff' }
$value = $null
if ($operation -match '^pr update-branch ') {
    if ($CliArguments[-1] -ne '--rebase') { throw 'FixtureMissingRebaseFlag' }
    if ($state.Mode -eq 'MutationTimeout') { [void][Threading.Tasks.Task]::Delay(10000).GetAwaiter().GetResult() }
    if ($state.Mode -eq 'Fail' -or ($state.Mode -eq 'BatchFail' -and $operation -match '/pull/1 ')) { exit 1 }
    if ($state.ContainsKey('GitRoot')) {
        $null = Invoke-LocalGit @('-C', $work, 'fetch', 'upstream')
        $rebased = Invoke-LocalGit @('-C', $work, 'rebase', "upstream/$($state.BaseBranch)") -AllowFailure
        if (!$rebased.Success) { exit 1 }
        $null = Invoke-LocalGit @('-C', $work, 'push', '--force-with-lease', 'origin', 'HEAD:refs/heads/topic/é-hover')
    }
    if ($state.Mode -eq 'BatchFail') {
        $state.Mode = 'Eligible'
        [void][IO.File]::WriteAllTextAsync($StatePath, (ConvertTo-Json $state -Depth 15), [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    'fixture accepted'; exit 0
} elseif ($operation -match '^pr view ') {
    $value = @{ reviewDecision = 'REVIEW_REQUIRED'; statusCheckRollup = @(@{ name = 'fixture CI'; status = 'IN_PROGRESS' }) }
} elseif ($CliArguments[-1] -eq 'user') {
    $value = @{ login = $state.Login }
} elseif ($CliArguments[-1] -match '^search/issues') {
    $endpoint = $CliArguments[-1]
    $page = [int]([regex]::Match($endpoint, 'page=(\d+)$').Groups[1].Value)
    $items = @()
    $count = [int]$state.Count
    for ($i = ($page - 1) * 100 + 1; $i -le [Math]::Min($page * 100, $count); $i++) {
        $number = if ($state.Mode -eq 'Duplicate') { 1 } else { $i }
        $items += @{ html_url = "https://github.com/$($state.Repository)/pull/$number" }
    }
    $value = @{ total_count = $count; incomplete_results = ($state.Mode -eq 'Incomplete'); items = $items }
} elseif ($CliArguments[-1] -match '/pulls/(\d+)$') {
    $number = [int]$Matches[1]
    if ($state.Mode -eq 'VerifyFail' -and $mutations -gt 0) { exit 1 }
    $mergeable = if ($state.Mode -eq 'Unknown') { $null } else { $state.Mode -ne 'Conflict' }
    $rebaseable = if ($state.Mode -eq 'Unknown') { $null } else { $state.Mode -notin @('Conflict', 'NotRebaseable') }
    $author = if ($state.Mode -eq 'OtherAuthor') { 'someone-else' } else { $state.Login }
    $lifecycle = if ($state.Mode -eq 'Closed' -or $state.Mode -eq 'ClosedLater' -and $metadataReads -gt 1) { 'closed' } else { 'open' }
    $branch = if ($state.ContainsKey('BaseBranch')) { $state.BaseBranch } else { 'main' }
    $value = @{ number = $number; title = 'Hover é fixture'; state = $lifecycle; draft = $true; user = @{ login = $author }
        base = @{ ref = $branch; sha = $state.MetadataBaseSha; repo = @{ full_name = $state.Repository } }
        head = @{ ref = 'topic/é-hover'; sha = $head; repo = @{ full_name = 'fixture-user/project' } }
        mergeable = $mergeable; rebaseable = $rebaseable; mergeable_state = 'blocked' }
} elseif ($CliArguments[-1] -match '/git/ref/heads/(.+)$') {
    $branch = [Uri]::UnescapeDataString($Matches[1])
    $value = @{ ref = "refs/heads/$branch"; object = @{ sha = $base } }
} elseif ($CliArguments[-1] -match '/compare/([0-9a-f]+)\.\.\.([0-9a-f]+)$') {
    $comparedBase = $Matches[1]
    $actualBehind = if ($comparedBase -eq $state.MetadataBaseSha -and $comparedBase -ne $base) { 0 } else { $behind }
    $value = @{ ahead_by = $ahead; behind_by = $actualBehind; status = 'diverged' }
} else { throw "UnexpectedFixtureInvocation: $operation" }
$json = ConvertTo-Json -InputObject $value -Depth 15 -Compress
[Console]::WriteLine($json)
