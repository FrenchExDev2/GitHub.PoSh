function Get-GitHubRebaseDecision {
    <#
    .SYNOPSIS
    Applies author, lifecycle and independently observed divergence invariants.
    .PARAMETER PullRequest
    REST pull request metadata.
    .PARAMETER Login
    Authenticated user login.
    .PARAMETER Comparison
    Comparison against the freshly resolved target reference.
    #>
    param([hashtable]$PullRequest, [string]$Login, [hashtable]$Comparison)
    if ($PullRequest.user.login -ine $Login) { return 'NotOwned' }
    if ($PullRequest.state -ne 'open') { return 'Closed' }
    if ($Comparison.behind_by -eq 0) { return 'UpToDate' }
    if ($PullRequest.mergeable -eq $false) { return 'Conflicts' }
    if ($PullRequest.rebaseable -isnot [bool] -or $PullRequest.mergeable -isnot [bool]) { return 'Unknown' }
    if (!$PullRequest.rebaseable) { return 'NotRebaseable' }
    return 'Eligible'
}

function New-GitHubRebaseReport {
    <#
    .SYNOPSIS
    Creates a stable typed result even when inspection fails.
    .PARAMETER Identity
    Validated target repository and pull request number.
    #>
    param($Identity)
    [pscustomobject]@{
        PSTypeName = 'FrenchExDev2.GitHub.PullRequestRebase'
        Repository = $Identity.Repository; Number = $Identity.Number; Url = $Identity.Url
        Author = $null; Title = $null; IsDraft = $null; BaseBranch = $null; HeadBranch = $null
        BaseSha = $null; MetadataBaseSha = $null; HeadSha = $null; HeadRepository = $null
        AheadBy = $null; BehindBy = $null; Rebaseable = $null; Mergeable = $null
        MergeState = $null; ReviewDecision = $null; Checks = @(); ObservedAt = [DateTimeOffset]::UtcNow
        Decision = 'Error'; Result = 'NotAttempted'; Reason = $null; CliVersion = $null
        PreviousHeadSha = $null; CommandAccepted = $false; EffectConfirmed = $false
    }
}
