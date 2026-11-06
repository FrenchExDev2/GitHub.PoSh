function Invoke-FixtureMutationCampaign {
    <#
    .SYNOPSIS
    Applies isolated in-memory policy and orchestration mutations and runs independent regression cases.
    .PARAMETER Cases
    Baseline case catalogue already verified without mutations.
    .PARAMETER OnProgress
    Receives each mutant result.
    #>
    param([System.Collections.IDictionary]$Cases, [scriptblock]$OnProgress)
    $catalogue = @(
        @{ Name = 'author guard removed'; Function = 'Get-GitHubRebaseDecision'; From = '$PullRequest.user.login -ine $Login'; To = '$false'; Case = 'policy excludes OtherAuthor' },
        @{ Name = 'behind and ahead inverted'; Function = 'Get-GitHubRebaseDecision'; From = '$Comparison.behind_by -eq 0'; To = '$Comparison.ahead_by -eq 0'; Case = 'up to date branch is never mutated' },
        @{ Name = 'stale PR base SHA'; Function = 'Read-GitHubRebaseReport'; From = '$report.BaseSha = $reference.object.sha'; To = '$report.BaseSha = $pr.base.sha'; Case = 'stale metadata regression uses the live base SHA' },
        @{ Name = 'merge replaces rebase'; Function = 'Invoke-GitHubPullRequestRebase'; From = "'--rebase'"; To = "'--merge'"; Case = 'successful update uses rebase once and verifies the new head' },
        @{ Name = 'WhatIf guard bypassed'; Function = 'Invoke-GitHubPullRequestRebase'; From = 'if (!$PSCmdlet.ShouldProcess('; To = 'if ($false -and !$PSCmdlet.ShouldProcess('; Case = 'WhatIf cannot mutate' },
        @{ Name = 'mutation repeated'; Function = 'Invoke-GitHubPullRequestRebase'; From = '$after = Read-GitHubRebaseReport $identity $session'; To = '$null = Invoke-GitHubCli -Arguments @(''pr'', ''update-branch'', $identity.Url, ''--rebase''); $after = Read-GitHubRebaseReport $identity $session'; Case = 'failed mutation is attempted once' }
    )
    $campaign = [Diagnostics.Stopwatch]::StartNew()
    foreach ($mutation in $catalogue) {
        if ($campaign.Elapsed.TotalSeconds -gt 300) { throw 'MutationCampaignTimeout' }
        $original = & $script:Subject { param($name) (Get-Command $name).ScriptBlock.ToString() } $mutation.Function
        if (!$original.Contains($mutation.From)) { throw "InvalidMutationAnchor: $($mutation.Name)" }
        $replacement = $original.Replace($mutation.From, $mutation.To)
        $parseErrors = $null; $tokens = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($replacement, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "InvalidMutant: $($mutation.Name)" }
        $killed = $false
        try {
            & $script:Subject { param($name, $body) Set-Item -Path "Function:script:$name" -Value ([scriptblock]::Create($body)) } $mutation.Function $replacement
            try { & $Cases[$mutation.Case] (($mutation.Case -split ' ')[-1]) | Out-Null } catch { $killed = $true }
        } finally {
            & $script:Subject { param($name, $body) Set-Item -Path "Function:script:$name" -Value ([scriptblock]::Create($body)) } $mutation.Function $original
        }
        $result = [pscustomobject]@{ Name = "mutation: $($mutation.Name)"; Passed = $killed; Outcome = $(if ($killed) { 'Killed' } else { 'Survived' }); Error = $(if (!$killed) { 'Meaningful mutant survived its independent regression.' } else { $null }) }
        if ($OnProgress) { & $OnProgress $result }
        $result
    }
}
