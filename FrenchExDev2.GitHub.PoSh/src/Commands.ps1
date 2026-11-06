function Get-GitHubPullRequestRebase {
    <#
    .SYNOPSIS
    Inspects the authenticated user's open pull requests without mutation.
    .PARAMETER All
    Searches every repository containing an open pull request by the authenticated user; also the default.
    .PARAMETER Org
    Restricts discovery to the named organizations.
    .PARAMETER Repository
    Restricts discovery to owner/name repositories.
    .PARAMETER PullRequest
    Inspects explicit github.com pull request URLs, still enforcing author and lifecycle policy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [Parameter(Mandatory, ParameterSetName = 'Org')][ValidateNotNullOrEmpty()][string[]]$Org,
        [Parameter(Mandatory, ParameterSetName = 'Repository')][ValidateNotNullOrEmpty()][string[]]$Repository,
        [Parameter(Mandatory, ParameterSetName = 'PullRequest')][ValidateNotNullOrEmpty()][string[]]$PullRequest
    )
    $session = Get-GitHubSession
    $identities = @(Find-GitHubPullRequests $session.Login $PSBoundParameters)
    foreach ($identity in $identities) { Read-GitHubRebaseReport $identity $session }
}

function Invoke-GitHubPullRequestRebase {
    <#
    .SYNOPSIS
    Revalidates and rebases selected pull requests once each, continuing after individual failures.
    .PARAMETER All
    Selects all repositories containing the authenticated user's open pull requests; also the default.
    .PARAMETER Org
    Organization filters.
    .PARAMETER Repository
    Owner/name repository filters.
    .PARAMETER PullRequest
    Explicit public GitHub pull request URLs.
    .PARAMETER Ask
    Requires a y or n answer before each eligible rebase. Invalid answers are requested again.
    .PARAMETER Auto
    Executes eligible rebases without the additional y/n prompt; also the default.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [Parameter(Mandatory, ParameterSetName = 'Org')][ValidateNotNullOrEmpty()][string[]]$Org,
        [Parameter(Mandatory, ParameterSetName = 'Repository')][ValidateNotNullOrEmpty()][string[]]$Repository,
        [Parameter(Mandatory, ParameterSetName = 'PullRequest')][ValidateNotNullOrEmpty()][string[]]$PullRequest,
        [switch]$Ask,
        [switch]$Auto
    )
    if ($Ask -and $Auto) { throw 'AskAndAutoAreMutuallyExclusive' }
    $session = Get-GitHubSession
    $identities = @(Find-GitHubPullRequests $session.Login $PSBoundParameters)
    foreach ($identity in $identities) {
        $report = Read-GitHubRebaseReport $identity $session
        if ($report.Decision -ne 'Eligible') { $report; continue }
        if (!$PSCmdlet.ShouldProcess($identity.Url, 'Rebase pull request onto its current base branch')) {
            $report.Result = 'NotApplied'; $report; continue
        }
        if ($Ask) {
            do {
                $answer = & $script:GitHubReadAnswer $identity.Url
                if ($null -eq $answer) { throw 'GitHubConfirmationInputUnavailable' }
                $answer = ([string]$answer).Trim().ToLowerInvariant()
            } while ($answer -notin @('y', 'n'))
            if ($answer -eq 'n') { $report.Result = 'Declined'; $report.Reason = 'Rebase declined by user.'; $report; continue }
        }
        $before = Read-GitHubRebaseReport $identity $session
        if ($before.Decision -ne 'Eligible') { $before; continue }
        if ($before.BaseBranch -cne $report.BaseBranch -or $before.HeadBranch -cne $report.HeadBranch -or $before.HeadRepository -cne $report.HeadRepository -or $before.HeadSha -cne $report.HeadSha -or $before.BaseSha -cne $report.BaseSha) {
            $before.Result = 'ChangedBeforeApply'; $before.Reason = 'References changed; inspect again before rebasing.'; $before; continue
        }
        $command = Invoke-GitHubCli -Arguments @('pr', 'update-branch', $identity.Url, '--rebase')
        $after = Read-GitHubRebaseReport $identity $session
        $after.PreviousHeadSha = $before.HeadSha; $after.CommandAccepted = $command.Success
        $after.EffectConfirmed = $after.Decision -ne 'Error' -and $after.HeadSha -ne $before.HeadSha
        if (!$command.Success) {
            $after.Result = if (!$command.Complete -or $command.Outcome -notin @('Success', 'Failed')) { 'EffectUnconfirmed' } else { 'Failed' }
            $after.Reason = "Rebase command did not succeed ($($command.Outcome)); no retry was attempted."
        } elseif (!$after.EffectConfirmed) {
            $after.Result = 'AcceptedUnconfirmed'; $after.Reason = 'Command accepted; branch update could not be confirmed.'
        } elseif ($after.BehindBy -eq 0) { $after.Result = 'Rebased' }
        else { $after.Result = 'UpdatedStillBehind'; $after.Reason = 'Head changed, but the current base is still ahead.' }
        $after
    }
}
