@{
    RootModule = 'FrenchExDev2.GitHub.PoSh.psm1'
    ModuleVersion = '0.1.0'
    GUID = '94081f49-deb2-4caf-bb64-24cc22cfe3ae'
    Author = 'Stéphane Erard'
    Description = 'Inspect and rebase the authenticated user pull requests through GitHub CLI and QuietCli.'
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ ModuleName = 'FrenchExDev2.QuietCli.Core.PoSh'; ModuleVersion = '0.2.0' })
    FunctionsToExport = @('Get-GitHubPullRequestRebase', 'Invoke-GitHubPullRequestRebase')
    CmdletsToExport = @()
    AliasesToExport = @()
    VariablesToExport = @()
    PrivateData = @{ PSData = @{ Prerelease = 'preview'; Tags = @('GitHub', 'QuietCli', 'Rebase') } }
}
