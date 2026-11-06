function Read-GitHubRebaseReport {
    <#
    .SYNOPSIS
    Inspects immutable comparison endpoints using the current target branch, not PR base.sha.
    .PARAMETER Identity
    Validated pull request identity.
    .PARAMETER Session
    Authenticated account and CLI version.
    #>
    param($Identity, $Session)
    $report = New-GitHubRebaseReport $Identity
    $report.CliVersion = $Session.CliVersion
    try {
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            $pr = Get-GitHubApiValue "repos/$($Identity.Repository)/pulls/$($Identity.Number)"
            if ($pr.rebaseable -is [bool] -and $pr.mergeable -is [bool]) { break }
            if ($attempt -lt 2) { [void][Threading.Tasks.Task]::Delay($script:GitHubTransport.DelayMilliseconds).GetAwaiter().GetResult() }
        }
        if ($pr.base.repo.full_name -ine $Identity.Repository -or $pr.number -ne $Identity.Number) { throw 'GitHubIdentityMismatch' }
        $report.Author = $pr.user.login; $report.Title = $pr.title; $report.IsDraft = $pr.draft
        $report.BaseBranch = $pr.base.ref; $report.HeadBranch = $pr.head.ref
        $report.MetadataBaseSha = $pr.base.sha; $report.HeadSha = $pr.head.sha
        $report.HeadRepository = $pr.head.repo.full_name
        $report.Rebaseable = $pr.rebaseable; $report.Mergeable = $pr.mergeable; $report.MergeState = $pr.mergeable_state
        if ($report.HeadSha -notmatch '^[0-9a-f]{40}$') { throw 'InvalidGitHubHeadSha' }
        $branch = [Uri]::EscapeDataString($report.BaseBranch)
        $reference = Get-GitHubApiValue "repos/$($Identity.Repository)/git/ref/heads/$branch"
        $report.BaseSha = $reference.object.sha
        if ($report.BaseSha -notmatch '^[0-9a-f]{40}$' -or $reference.ref -cne "refs/heads/$($report.BaseBranch)") { throw 'InvalidGitHubBaseReference' }
        $comparison = Get-GitHubApiValue "repos/$($Identity.Repository)/compare/$($report.BaseSha)...$($report.HeadSha)"
        foreach ($key in @('ahead_by', 'behind_by')) {
            if (!$comparison.ContainsKey($key) -or $comparison[$key] -isnot [long] -and $comparison[$key] -isnot [int] -or $comparison[$key] -lt 0) { throw 'InvalidGitHubComparison' }
        }
        $report.AheadBy = $comparison.ahead_by; $report.BehindBy = $comparison.behind_by
        $details = Invoke-GitHubCli -Arguments @('pr', 'view', $Identity.Url, '--json', 'reviewDecision,statusCheckRollup') -Json
        if (!$details.Success -or $null -eq $details.Value) { throw 'GitHubReviewInspectionFailed' }
        $report.ReviewDecision = $details.Value.reviewDecision; $report.Checks = @($details.Value.statusCheckRollup)
        $report.Decision = Get-GitHubRebaseDecision $pr $Session.Login $comparison
        $report.Reason = $report.Decision
    } catch { $report.Decision = 'Error'; $report.Reason = $_.Exception.Message }
    $report.ObservedAt = [DateTimeOffset]::UtcNow
    return $report
}
