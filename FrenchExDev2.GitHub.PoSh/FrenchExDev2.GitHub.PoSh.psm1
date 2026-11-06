#requires -Version 7.6
Set-StrictMode -Version Latest
$script:GitHubTransport = @{ FilePath = 'gh'; Prefix = @(); Environment = @{}; DelayMilliseconds = 1000; TimeoutSeconds = 60 }
$script:GitHubReadAnswer = { param($url) Read-Host "Rebase $url ? (y/n)" }
foreach ($source in @('Transport', 'Selection', 'Policy', 'Inspection', 'Commands')) {
    . (Join-Path $PSScriptRoot "src/$source.ps1")
}
Export-ModuleMember -Function Get-GitHubPullRequestRebase, Invoke-GitHubPullRequestRebase
