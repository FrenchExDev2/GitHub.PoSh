function Invoke-FixtureGit {
    <#
    .SYNOPSIS
    Executes independently asserted Git fixture setup and observations through QuietCli.
    .PARAMETER Arguments
    Exact argument vector, including an owned directory.
    .PARAMETER Environment
    Isolated Git environment.
    .PARAMETER ExpectedExit
    Expected native exit code.
    #>
    param([string[]]$Arguments, [hashtable]$Environment, [int]$ExpectedExit = 0)
    $core = Get-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
    $gitManifest = Join-Path (Split-Path (Split-Path $core.Path -Parent) -Parent) 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1'
    $gitModule = Get-Module FrenchExDev2.QuietCli.Git.PoSh
    if ($gitModule -and $gitModule.Path -ne [IO.Path]::ChangeExtension($gitManifest, 'psm1')) { throw 'FixtureGitModulePathMismatch' }
    if (!$gitModule) { Import-Module $gitManifest -ErrorAction Stop }
    $result = quiet -AsObject -FilePath git -ArgumentList $Arguments -Environment $Environment -Data ([Text.StringBuilder]::new()) -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            if ($runtime.Data.Length + $event.Text.Length -gt 32768) { throw 'FixtureOutputTooLarge' }
            [void]$runtime.Data.Append($event.Text)
        }
    }
    if ($result.Execution.Native.ExitCode -ne $ExpectedExit -or !$result.Completeness.Source -or !$result.Completeness.Analysis) { throw ('FixtureSetupFailed: ' + ($Arguments -join ' ')) }
    $result.Data.ToString().Trim()
}

function New-GitHubRepositoryFixture {
    <#
    .SYNOPSIS
    Creates two bare repositories and working clones with independently controlled histories.
    .PARAMETER Root
    New owned temporary directory.
    .PARAMETER Scenario
    History variant: divergence, current, conflict, or alternate target branch.
    #>
    param([string]$Root, [ValidateSet('Diverged', 'Current', 'Conflict', 'Alternate')][string]$Scenario)
    if (Test-Path -LiteralPath $Root) { throw 'FixtureRootAlreadyExists' }
    [void][IO.Directory]::CreateDirectory($Root)
    $environment = @{
        GIT_CONFIG_NOSYSTEM = '1'; GIT_CONFIG_GLOBAL = (Join-Path $Root 'empty.config'); GIT_CONFIG_COUNT = '2'
        GIT_CONFIG_KEY_0 = 'core.hooksPath'; GIT_CONFIG_VALUE_0 = (Join-Path $Root 'hooks')
        GIT_CONFIG_KEY_1 = 'commit.gpgsign'; GIT_CONFIG_VALUE_1 = 'false'
        GIT_AUTHOR_NAME = 'Fixture'; GIT_COMMITTER_NAME = 'Fixture'; GIT_AUTHOR_EMAIL = 'fixture@example.invalid'; GIT_COMMITTER_EMAIL = 'fixture@example.invalid'
        GIT_AUTHOR_DATE = '2020-01-01T00:00:00Z'; GIT_COMMITTER_DATE = '2020-01-01T00:00:00Z'
        GIT_TERMINAL_PROMPT = '0'; GIT_EDITOR = 'false'; GIT_SEQUENCE_EDITOR = 'false'; GIT_CEILING_DIRECTORIES = $Root
        GIT_DIR = $null; GIT_WORK_TREE = $null; GIT_INDEX_FILE = $null; GIT_COMMON_DIR = $null; GIT_OBJECT_DIRECTORY = $null; GIT_ALTERNATE_OBJECT_DIRECTORIES = $null
        GIT_CONFIG_PARAMETERS = $null
    }
    [void][IO.File]::WriteAllTextAsync($environment.GIT_CONFIG_GLOBAL, '', [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [void][IO.Directory]::CreateDirectory($environment.GIT_CONFIG_VALUE_0)
    $upstream = Join-Path $Root 'upstream.git'; $fork = Join-Path $Root 'fork.git'
    $upwork = Join-Path $Root 'upstream-work'; $work = Join-Path $Root 'fork-work'
    $null = Invoke-FixtureGit @('init', '--bare', '--initial-branch=main', '--object-format=sha1', $upstream) $environment
    $null = Invoke-FixtureGit @('clone', $upstream, $upwork) $environment
    [void][IO.File]::WriteAllTextAsync((Join-Path $upwork 'shared.txt'), "baseline`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $null = Invoke-FixtureGit @('-C', $upwork, 'add', '.') $environment
    $null = Invoke-FixtureGit @('-C', $upwork, 'commit', '-m', 'Initial shared history') $environment
    $initial = Invoke-FixtureGit @('-C', $upwork, 'rev-parse', 'HEAD') $environment
    $null = Invoke-FixtureGit @('-C', $upwork, 'push', 'origin', 'main') $environment
    $null = Invoke-FixtureGit @('clone', '--bare', $upstream, $fork) $environment
    $null = Invoke-FixtureGit @('clone', $fork, $work) $environment
    $null = Invoke-FixtureGit @('-C', $work, 'remote', 'add', 'upstream', $upstream) $environment
    $null = Invoke-FixtureGit @('-C', $work, 'switch', '-c', 'topic/é-hover') $environment
    $name = if ($Scenario -eq 'Conflict') { 'shared.txt' } else { 'feature.txt' }
    [void][IO.File]::WriteAllTextAsync((Join-Path $work $name), "feature`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $null = Invoke-FixtureGit @('-C', $work, 'add', '.') $environment
    $null = Invoke-FixtureGit @('-C', $work, 'commit', '-m', 'Feature change') $environment
    $null = Invoke-FixtureGit @('-C', $work, 'push', '-u', 'origin', 'topic/é-hover') $environment
    $branch = if ($Scenario -eq 'Alternate') { 'release/next' } else { 'main' }
    if ($Scenario -eq 'Alternate') { $null = Invoke-FixtureGit @('-C', $upwork, 'switch', '-c', $branch) $environment }
    if ($Scenario -ne 'Current') {
        $name = if ($Scenario -eq 'Conflict') { 'shared.txt' } else { 'upstream.txt' }
        [void][IO.File]::WriteAllTextAsync((Join-Path $upwork $name), "upstream`n", [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $null = Invoke-FixtureGit @('-C', $upwork, 'add', '.') $environment
        $null = Invoke-FixtureGit @('-C', $upwork, 'commit', '-m', 'Target advanced') $environment
        $null = Invoke-FixtureGit @('-C', $upwork, 'push', 'origin', $branch) $environment
    }
    $null = Invoke-FixtureGit @('-C', $work, 'fetch', 'upstream') $environment
    @{ GitRoot = $Root; GitEnvironment = $environment; MetadataBaseSha = $initial; BaseBranch = $branch }
}
