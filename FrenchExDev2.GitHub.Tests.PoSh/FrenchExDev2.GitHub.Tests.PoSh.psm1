#requires -Version 7.6
. (Join-Path $PSScriptRoot 'fixtures/Repositories.ps1')

function Assert-FixtureEqual {
    <#
    .SYNOPSIS
    Asserts independent expected values with a useful failure message.
    .PARAMETER Actual
    Observed value.
    .PARAMETER Expected
    Independent expected value.
    #>
    param($Actual, $Expected)
    if ($Actual -cne $Expected) { throw "Expected [$Expected], observed [$Actual]" }
}

function Set-FixtureScenario {
    <#
    .SYNOPSIS
    Creates a fresh fake-client state and injects only its process entrypoint.
    .PARAMETER Mode
    Deterministic response scenario.
    .PARAMETER Overrides
    Explicit additional fixture inputs.
    #>
    param([string]$Mode = 'Eligible', [hashtable]$Overrides = @{})
    $state = Get-Content (Join-Path $PSScriptRoot 'fixtures/regression.json') -Encoding utf8 -Raw | ConvertFrom-Json -AsHashtable
    $state.Mode = $Mode
    foreach ($key in $Overrides.Keys) { $state[$key] = $Overrides[$key] }
    $script:StatePath = Join-Path $script:RunDirectory ([guid]::NewGuid().ToString('N') + '.json')
    [void][IO.File]::WriteAllTextAsync($script:StatePath, ((ConvertTo-Json $state -Depth 15) -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    & $script:Subject {
        param($runner, $fake, $path, $core)
        $script:GitHubTransport = @{ FilePath = $runner; Prefix = @('-File', $fake, '-StatePath', $path, '-CoreManifest', $core); Environment = @{}; DelayMilliseconds = 0; TimeoutSeconds = 30 }
        $script:GitHubReadAnswer = { throw 'UnexpectedInteractivePrompt' }
    } (Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })) (Join-Path $PSScriptRoot 'fixtures/Fake-Gh.ps1') $script:StatePath $script:CoreManifest
}

function Get-FixtureMutations {
    <# .SYNOPSIS
    Reads only this fixture's invocation journal and returns mutation argument vectors.
    #>
    if (!(Test-Path "$script:StatePath.calls.jsonl")) { return }
    foreach ($line in Get-Content "$script:StatePath.calls.jsonl" -Encoding utf8) {
        $vector = @(ConvertFrom-Json $line)
        if ($vector.Count -gt 1 -and $vector[0] -eq 'pr' -and $vector[1] -eq 'update-branch' -and $vector[-1] -ne '--help') { ,$vector }
    }
}

function Invoke-FixtureRebase {
    <#
    .SYNOPSIS
    Resolves the current module function so in-memory mutants cannot use stale exported bindings.
    .PARAMETER All
    Global author-filtered selection.
    .PARAMETER Org
    Organization filters.
    .PARAMETER Repository
    Repository filters.
    .PARAMETER PullRequest
    Explicit fixture URLs.
    .PARAMETER Ask
    Interactive fixture mode.
    .PARAMETER Auto
    Noninteractive fixture mode.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$All, [string[]]$Org, [string[]]$Repository, [string[]]$PullRequest, [switch]$Ask, [switch]$Auto)
    & $script:Subject { param($parameters) Invoke-GitHubPullRequestRebase @parameters } $PSBoundParameters
}

function Invoke-GitHubFixtureTests {
    <#
    .SYNOPSIS
    Runs isolated protocol, local Git, generated property, fuzz and targeted mutation campaigns.
    .PARAMETER RunDirectory
    Owned temporary report directory.
    .PARAMETER CoreManifest
    Verified selected QuietCli Core manifest.
    .PARAMETER OnProgress
    Receives each saved case result.
    .PARAMETER SkipMutation
    Omits mutation evaluation for an explicitly limited development pass.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunDirectory, [Parameter(Mandatory)][string]$CoreManifest, [scriptblock]$OnProgress, [switch]$SkipMutation)
    $script:RunDirectory = $RunDirectory; $script:CoreManifest = $CoreManifest
    $script:Subject = Get-Module FrenchExDev2.GitHub.PoSh
    $originalTransport = & $script:Subject { $script:GitHubTransport }
    $originalPrompt = & $script:Subject { $script:GitHubReadAnswer }
    $url = 'https://github.com/fixture-org/project/pull/1'
    $cases = [ordered]@{}
    $cases['workspace import does not load the Git companion'] = {
        Assert-FixtureEqual @(Get-Module FrenchExDev2.QuietCli.Git.PoSh).Count 0
        Assert-FixtureEqual @(Get-Module FrenchExDev2.QuietCli.Core.PoSh).Count 1
        Assert-FixtureEqual @($script:Subject.ExportedFunctions.Keys).Count 2
    }
    $cases['stale metadata regression uses the live base SHA'] = {
        Set-FixtureScenario
        $r = Get-GitHubPullRequestRebase -PullRequest $url
        Assert-FixtureEqual $r.BehindBy 12; Assert-FixtureEqual $r.AheadBy 3
        Assert-FixtureEqual $r.BaseSha ('a' * 40); Assert-FixtureEqual $r.MetadataBaseSha ('b' * 40)
        Assert-FixtureEqual $r.Decision 'Eligible'; Assert-FixtureEqual $r.Author 'fixture-user'
        Assert-FixtureEqual $r.IsDraft $true; Assert-FixtureEqual $r.ReviewDecision 'REVIEW_REQUIRED'
        Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    $cases['WhatIf cannot mutate'] = {
        Set-FixtureScenario
        $r = Invoke-FixtureRebase -PullRequest $url -WhatIf
        Assert-FixtureEqual $r.Result 'NotApplied'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    $cases['Ask accepts y after invalid answers'] = {
        Set-FixtureScenario
        & $script:Subject { $script:Answers = [Collections.Generic.Queue[string]]::new([string[]]@('invalid', '', 'Y')); $script:GitHubReadAnswer = { $script:Answers.Dequeue() } }
        $r = Invoke-FixtureRebase -PullRequest $url -Ask
        Assert-FixtureEqual $r.Result 'Rebased'; Assert-FixtureEqual @(Get-FixtureMutations).Count 1
        Assert-FixtureEqual (& $script:Subject { $script:Answers.Count }) 0
    }
    $cases['Ask declines n without mutation'] = {
        Set-FixtureScenario
        & $script:Subject { $script:GitHubReadAnswer = { 'n' } }
        $r = Invoke-FixtureRebase -PullRequest $url -Ask
        Assert-FixtureEqual $r.Result 'Declined'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    $cases['Ask with WhatIf never prompts'] = {
        Set-FixtureScenario
        $r = Invoke-FixtureRebase -PullRequest $url -Ask -WhatIf
        Assert-FixtureEqual $r.Result 'NotApplied'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    $cases['Auto never prompts'] = {
        Set-FixtureScenario
        $r = Invoke-FixtureRebase -PullRequest $url -Auto
        Assert-FixtureEqual $r.Result 'Rebased'; Assert-FixtureEqual @(Get-FixtureMutations).Count 1
    }
    $cases['Ask and Auto cannot be combined'] = {
        Set-FixtureScenario
        $message = ''
        try { $null = Invoke-FixtureRebase -PullRequest $url -Ask -Auto } catch { $message = $_.Exception.Message }
        Assert-FixtureEqual $message 'AskAndAutoAreMutuallyExclusive'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    $cases['successful update uses rebase once and verifies the new head'] = {
        Set-FixtureScenario
        $r = Invoke-FixtureRebase -PullRequest $url
        Assert-FixtureEqual $r.Result 'Rebased'; Assert-FixtureEqual $r.EffectConfirmed $true
        $commands = @(Get-FixtureMutations)
        Assert-FixtureEqual $commands.Count 1; Assert-FixtureEqual $commands[0][-1] '--rebase'
    }
    $cases['up to date branch is never mutated'] = {
        Set-FixtureScenario -Overrides @{ Behind = 0 }
        $r = Invoke-FixtureRebase -PullRequest $url
        Assert-FixtureEqual $r.Decision 'UpToDate'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    foreach ($scenario in @('OtherAuthor', 'Closed', 'Conflict', 'Unknown', 'NotRebaseable')) {
        $cases["policy excludes $scenario"] = {
            param($scenario)
            Set-FixtureScenario $scenario
            $r = Invoke-FixtureRebase -PullRequest $url
            $expected = @{ OtherAuthor = 'NotOwned'; Closed = 'Closed'; Conflict = 'Conflicts'; Unknown = 'Unknown'; NotRebaseable = 'NotRebaseable' }[$scenario]
            Assert-FixtureEqual $r.Decision $expected; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
            if ($scenario -eq 'Unknown') {
                $reads = @(Get-Content "$script:StatePath.calls.jsonl" -Encoding utf8 | Where-Object { $_ -match '/pulls/1"' })
                Assert-FixtureEqual $reads.Count 3
            }
        }
    }
    foreach ($scenario in @('Changed', 'TargetChanged', 'ClosedLater')) {
        $cases["preflight catches $scenario"] = {
            param($scenario)
            Set-FixtureScenario $scenario
            $r = Invoke-FixtureRebase -PullRequest $url
            if ($scenario -eq 'ClosedLater') { Assert-FixtureEqual $r.Decision 'Closed' }
            else { Assert-FixtureEqual $r.Result 'ChangedBeforeApply' }
            Assert-FixtureEqual @(Get-FixtureMutations).Count 0
        }
    }
    foreach ($scenario in @('Incomplete', 'Malformed', 'Denied')) {
        $cases["discovery blocks $scenario"] = {
            param($scenario)
            Set-FixtureScenario $scenario
            $thrown = $false
            try { $null = Invoke-FixtureRebase -All -ErrorAction Stop } catch { $thrown = $true }
            Assert-FixtureEqual $thrown $true; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
        }
    }
    $cases['search ceiling blocks all mutations'] = {
        Set-FixtureScenario -Overrides @{ Count = 1001 }
        $thrown = $false
        try { $null = Invoke-FixtureRebase -All -ErrorAction Stop } catch { $thrown = $true }
        Assert-FixtureEqual $thrown $true; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
    }
    $cases['selection paginates and deduplicates overlapping results'] = {
        Set-FixtureScenario -Overrides @{ Count = 101 }
        $session = & $script:Subject { Get-GitHubSession }
        $identities = @(& $script:Subject { param($s) Find-GitHubPullRequests $s.Login @{ Org = @('one', 'two') } } $session)
        Assert-FixtureEqual $identities.Count 101
        $searches = @(Get-Content "$script:StatePath.calls.jsonl" -Encoding utf8 | Where-Object { $_ -match 'search/issues' })
        Assert-FixtureEqual $searches.Count 4
    }
    $cases['repository filter and authenticated author reach the search endpoint'] = {
        Set-FixtureScenario -Overrides @{ Count = 0 }
        Assert-FixtureEqual @(Get-GitHubPullRequestRebase -Repository fixture-org/project).Count 0
        $journal = Get-Content "$script:StatePath.calls.jsonl" -Encoding utf8 -Raw
        $decoded = [Uri]::UnescapeDataString($journal)
        if ($decoded -notmatch 'author:fixture-user repo:fixture-org/project') { throw 'MissingRepositoryAuthorFilter' }
    }
    $cases['failure does not retry and later pull requests continue'] = {
        Set-FixtureScenario 'BatchFail' @{ Count = 2 }
        $r = @(Invoke-FixtureRebase -All)
        Assert-FixtureEqual $r.Count 2; Assert-FixtureEqual $r[0].Result 'Failed'; Assert-FixtureEqual $r[1].Result 'Rebased'
        Assert-FixtureEqual @(Get-FixtureMutations).Count 2
    }
    $cases['failed mutation is attempted once'] = {
        Set-FixtureScenario 'Fail'
        $r = Invoke-FixtureRebase -PullRequest $url
        Assert-FixtureEqual $r.Result 'Failed'; Assert-FixtureEqual @(Get-FixtureMutations).Count 1
    }
    $cases['verification failure preserves accepted but unconfirmed outcome'] = {
        Set-FixtureScenario 'VerifyFail'
        $r = Invoke-FixtureRebase -PullRequest $url
        Assert-FixtureEqual $r.Result 'AcceptedUnconfirmed'; Assert-FixtureEqual $r.CommandAccepted $true
        Assert-FixtureEqual @(Get-FixtureMutations).Count 1
    }
    $cases['mutation timeout is not replayed'] = {
        Set-FixtureScenario 'MutationTimeout'
        & $script:Subject { $script:GitHubTransport.TimeoutSeconds = 3 }
        $r = Invoke-FixtureRebase -PullRequest $url
        Assert-FixtureEqual $r.Result 'EffectUnconfirmed'; Assert-FixtureEqual @(Get-FixtureMutations).Count 1
    }
    foreach ($scenario in @('Diverged', 'Current', 'Conflict', 'Alternate')) {
        $cases["real upstream and fork: $scenario"] = {
            param($scenario)
            $fixture = New-GitHubRepositoryFixture (Join-Path $RunDirectory ([guid]::NewGuid().ToString('N'))) $scenario
            Set-FixtureScenario $(if ($scenario -eq 'Conflict') { 'Conflict' } else { 'Eligible' }) $fixture
            $r = Invoke-FixtureRebase -PullRequest $url
            $work = Join-Path $fixture.GitRoot 'fork-work'; $envGit = $fixture.GitEnvironment
            if ($scenario -in @('Diverged', 'Alternate')) {
                Assert-FixtureEqual $r.Result 'Rebased'
                $base = Invoke-FixtureGit @('--git-dir', (Join-Path $fixture.GitRoot 'upstream.git'), 'rev-parse', "refs/heads/$($fixture.BaseBranch)") $envGit
                $parent = Invoke-FixtureGit @('-C', $work, 'rev-parse', 'HEAD^') $envGit
                Assert-FixtureEqual $parent $base
                Assert-FixtureEqual ([IO.File]::ReadAllTextAsync((Join-Path $work 'feature.txt'), [Text.Encoding]::UTF8).GetAwaiter().GetResult()) "feature`n"
                Assert-FixtureEqual ([IO.File]::ReadAllTextAsync((Join-Path $work 'upstream.txt'), [Text.Encoding]::UTF8).GetAwaiter().GetResult()) "upstream`n"
                $remote = Invoke-FixtureGit @('--git-dir', (Join-Path $fixture.GitRoot 'fork.git'), 'rev-parse', 'refs/heads/topic/é-hover') $envGit
                Assert-FixtureEqual $remote $r.HeadSha
            } elseif ($scenario -eq 'Current') {
                Assert-FixtureEqual $r.Decision 'UpToDate'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
            } else {
                Assert-FixtureEqual $r.Decision 'Conflicts'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
                $null = Invoke-FixtureGit @('-C', $work, 'rebase', 'upstream/main') $envGit 1
                $unmerged = Invoke-FixtureGit @('-C', $work, 'ls-files', '-u') $envGit
                if ($unmerged -notmatch 'shared.txt') { throw 'ExpectedIndependentGitConflict' }
            }
        }
    }
    foreach ($scenario in @('RealTargetChanged', 'RealHeadChanged')) {
        $cases["real concurrent reference: $scenario"] = {
            param($scenario)
            $fixture = New-GitHubRepositoryFixture (Join-Path $RunDirectory ([guid]::NewGuid().ToString('N'))) 'Diverged'
            $upstream = Join-Path $fixture.GitRoot 'upstream.git'; $fork = Join-Path $fixture.GitRoot 'fork.git'
            $targetBefore = Invoke-FixtureGit @('--git-dir', $upstream, 'rev-parse', 'refs/heads/main') $fixture.GitEnvironment
            $headBefore = Invoke-FixtureGit @('--git-dir', $fork, 'rev-parse', 'refs/heads/topic/é-hover') $fixture.GitEnvironment
            Set-FixtureScenario $scenario $fixture
            $r = Invoke-FixtureRebase -PullRequest $url -Auto
            Assert-FixtureEqual $r.Result 'ChangedBeforeApply'; Assert-FixtureEqual @(Get-FixtureMutations).Count 0
            $targetAfter = Invoke-FixtureGit @('--git-dir', $upstream, 'rev-parse', 'refs/heads/main') $fixture.GitEnvironment
            $headAfter = Invoke-FixtureGit @('--git-dir', $fork, 'rev-parse', 'refs/heads/topic/é-hover') $fixture.GitEnvironment
            if ($scenario -eq 'RealTargetChanged') {
                Assert-FixtureEqual ($targetAfter -ne $targetBefore) $true; Assert-FixtureEqual $headAfter $headBefore
            } else {
                Assert-FixtureEqual ($headAfter -ne $headBefore) $true; Assert-FixtureEqual $targetAfter $targetBefore
            }
        }
    }
    $cases['generated policy properties and malformed identity fuzzing seed 346198'] = {
        $random = [Random]::new(346198)
        & $script:Subject {
            param($random)
            $campaign = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt 1000; $i++) {
                if ($campaign.Elapsed.TotalSeconds -gt 300) { throw 'PropertyFuzzCampaignTimeout' }
                $behind = $random.Next(1, 10000); $ahead = $random.Next(0, 10000)
                $pr = @{ user = @{ login = 'fixture-user' }; state = 'open'; mergeable = $true; rebaseable = $true }
                $comparison = @{ behind_by = $behind; ahead_by = $ahead }
                if ((Get-GitHubRebaseDecision $pr 'fixture-user' $comparison) -ne 'Eligible') { throw "GeneratedEligibleInvariant:$i" }
                if ((Get-GitHubRebaseDecision $pr 'someone-else' $comparison) -ne 'NotOwned') { throw "GeneratedAuthorInvariant:$i" }
                $comparison.behind_by = 0
                if ((Get-GitHubRebaseDecision $pr 'fixture-user' $comparison) -ne 'UpToDate') { throw "GeneratedCurrentInvariant:$i" }
                $comparison.behind_by = $behind; $pr.mergeable = $false
                if ((Get-GitHubRebaseDecision $pr 'fixture-user' $comparison) -ne 'Conflicts') { throw "GeneratedConflictInvariant:$i" }
                $bad = "https://github.com/org/repo/pull/$($random.Next(1, 999999));$([char]$random.Next(33, 127))"
                $rejected = $false
                try { $null = ConvertTo-GitHubPullRequestIdentity $bad } catch { $rejected = $true }
                if (!$rejected) { throw "FuzzIdentityAccepted:$i" }
            }
        } $random
        $script:Properties = 4000; $script:FuzzExecutions = 1000
    }
    $results = [Collections.Generic.List[object]]::new(); $script:Properties = 0; $script:FuzzExecutions = 0
    try {
        foreach ($entry in $cases.GetEnumerator()) {
            $timer = [Diagnostics.Stopwatch]::StartNew(); $errorText = $null
            try { & $entry.Value (($entry.Key -split ' ')[-1]) | Out-Null } catch { $errorText = $_.ToString() + "`n" + $_.ScriptStackTrace }
            $case = [pscustomobject]@{ Name = $entry.Key; Passed = !$errorText; Error = $errorText; DurationSeconds = $timer.Elapsed.TotalSeconds }
            $results.Add($case)
            if ($OnProgress) { & $OnProgress $case }
        }
        $mutants = @()
        if (!$SkipMutation -and @($results | Where-Object { !$_.Passed }).Count -eq 0) {
            . (Join-Path $PSScriptRoot 'mutation/Invoke-Mutations.ps1')
            $mutants = @(Invoke-FixtureMutationCampaign -Cases $cases -OnProgress $OnProgress)
        }
        [pscustomobject]@{ Cases = $results.ToArray(); Properties = $script:Properties; FuzzExecutions = $script:FuzzExecutions; Seed = 346198; Mutations = $mutants; MutationSkipped = [bool]$SkipMutation }
    } finally {
        & $script:Subject { param($original) $script:GitHubTransport = $original } $originalTransport
        & $script:Subject { param($original) $script:GitHubReadAnswer = $original } $originalPrompt
    }
}
Export-ModuleMember -Function Invoke-GitHubFixtureTests
