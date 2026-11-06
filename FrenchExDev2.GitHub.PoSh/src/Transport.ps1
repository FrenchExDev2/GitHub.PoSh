function Invoke-GitHubCli {
    <#
    .SYNOPSIS
    Executes one bounded CLI request through QuietCli, without retaining raw output history.
    .PARAMETER Arguments
    Exact GitHub CLI arguments, excluding the executable.
    .PARAMETER Json
    Requires a single complete JSON response.
    #>
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Json)
    $state = @{ Out = [Text.StringBuilder]::new(); Err = [Text.StringBuilder]::new(); Limit = 4194304 }
    $result = quiet -AsObject -FilePath $script:GitHubTransport.FilePath -ArgumentList @($script:GitHubTransport.Prefix + $Arguments) -Environment $script:GitHubTransport.Environment -TimeoutSeconds $script:GitHubTransport.TimeoutSeconds -Data $state -Output {
        param($event, $runtime)
        $buffer = if ($event.Stream -eq 'stdout') { $runtime.Data.Out } else { $runtime.Data.Err }
        if ($buffer.Length + $event.Text.Length -gt $runtime.Data.Limit) { throw 'GitHubResponseTooLarge' }
        [void]$buffer.Append($event.Text)
    }
    $complete = $result.Completeness.Source -and $result.Completeness.Analysis
    $success = $result.Outcome -eq 'Success' -and $result.Execution.Native.ExitCode -eq 0 -and $complete
    $value = $null
    if ($success -and $Json) {
        try { $value = ConvertFrom-Json -InputObject $state.Out.ToString() -AsHashtable -Depth 80 -ErrorAction Stop }
        catch { $success = $false }
    } elseif ($success) { $value = $state.Out.ToString() }
    [pscustomobject]@{ Success = $success; Value = $value; Outcome = $result.Outcome; Complete = $complete; ExitCode = $result.Execution.Native.ExitCode; Diagnostic = $state.Err.ToString().Substring(0, [Math]::Min(2000, $state.Err.Length)) }
}

function Get-GitHubApiValue {
    <#
    .SYNOPSIS
    Reads a REST endpoint and rejects unsuccessful or malformed responses.
    .PARAMETER Endpoint
    Relative GitHub REST endpoint.
    #>
    param([Parameter(Mandatory)][string]$Endpoint)
    $response = Invoke-GitHubCli -Arguments @('api', '--hostname', 'github.com', '--method', 'GET', $Endpoint) -Json
    if (!$response.Success -or $null -eq $response.Value) { throw "GitHubReadFailed: $Endpoint ($($response.Outcome)) $($response.Diagnostic)" }
    return ,$response.Value
}

function Get-GitHubSession {
    <# .SYNOPSIS
    Checks CLI capability and resolves the authenticated account without interactive authentication.
    #>
    $version = Invoke-GitHubCli -Arguments @('--version')
    $help = Invoke-GitHubCli -Arguments @('pr', 'update-branch', '--help')
    if (!$version.Success -or !$help.Success -or $help.Value -notmatch '--rebase') { throw 'GitHubCliRebaseUnavailable' }
    $user = Get-GitHubApiValue 'user'
    if (!$user.login -or $user.login -notmatch '^[A-Za-z0-9-]+$') { throw 'GitHubAuthenticatedUserUnavailable' }
    [pscustomobject]@{ Login = [string]$user.login; CliVersion = ($version.Value -split "`n")[0].Trim() }
}
