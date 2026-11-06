function ConvertTo-GitHubPullRequestIdentity {
    <#
    .SYNOPSIS
    Validates a public GitHub pull request URL before constructing CLI arguments.
    .PARAMETER Url
    Absolute github.com pull request URL.
    #>
    param([string]$Url)
    if ($Url -notmatch '^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)/?$') { throw "InvalidPullRequestUrl: $Url" }
    [pscustomobject]@{ Repository = "$($Matches[1])/$($Matches[2])"; Number = [long]$Matches[3]; Url = $Url.TrimEnd('/') }
}

function Find-GitHubPullRequests {
    <#
    .SYNOPSIS
    Discovers the complete selected set before allowing any mutation.
    .PARAMETER Login
    Authenticated author, never an arbitrary caller-supplied account.
    .PARAMETER Selection
    Bound public selection parameters.
    #>
    param([string]$Login, [System.Collections.IDictionary]$Selection)
    $found = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($Selection.ContainsKey('PullRequest')) {
        foreach ($url in $Selection.PullRequest) {
            $identity = ConvertTo-GitHubPullRequestIdentity $url
            $found[$identity.Url] = $identity
        }
    } else {
        $filters = @('')
        if ($Selection.ContainsKey('Org')) {
            $filters = foreach ($org in $Selection.Org) {
                if ($org -notmatch '^[A-Za-z0-9-]+$') { throw "InvalidOrganization: $org" }
                " org:$org"
            }
        } elseif ($Selection.ContainsKey('Repository')) {
            $filters = foreach ($repository in $Selection.Repository) {
                if ($repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "InvalidRepository: $repository" }
                " repo:$repository"
            }
        }
        foreach ($filter in $filters) {
            $query = [Uri]::EscapeDataString("is:pr is:open author:$Login$filter")
            $expected = $null; $received = 0
            for ($page = 1; $page -le 10; $page++) {
                $response = Get-GitHubApiValue "search/issues?q=$query&per_page=100&page=$page"
                if (!$response.ContainsKey('total_count') -or $response.total_count -isnot [ValueType] -or $response.total_count -lt 0 -or !$response.ContainsKey('incomplete_results') -or $response.incomplete_results -isnot [bool] -or $response.incomplete_results -or $response.total_count -gt 1000 -or !$response.ContainsKey('items')) { throw 'GitHubSelectionIncomplete' }
                if ($null -eq $expected) { $expected = [long]$response.total_count }
                if ($expected -ne $response.total_count) { throw 'GitHubSelectionChangedDuringPagination' }
                $items = @($response.items)
                foreach ($item in $items) {
                    $identity = ConvertTo-GitHubPullRequestIdentity $item.html_url
                    $found[$identity.Url] = $identity
                }
                $received += $items.Count
                if ($received -eq $expected) { break }
                if ($items.Count -eq 0 -or $received -gt $expected -or $page -eq 10) { throw 'GitHubSelectionIncomplete' }
            }
        }
    }
    return @($found.Values | Sort-Object Repository, Number)
}
