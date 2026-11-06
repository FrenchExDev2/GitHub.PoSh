@{
    RootModule = 'FrenchExDev2.GitHub.Tests.PoSh.psm1'
    ModuleVersion = '0.1.0'
    GUID = '0b64b67c-fe89-4adf-87cb-976c684edfd2'
    Author = 'Stéphane Erard'
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(@{ ModuleName = 'FrenchExDev2.GitHub.PoSh'; ModuleVersion = '0.1.0' })
    FunctionsToExport = @('Invoke-GitHubFixtureTests')
    CmdletsToExport = @(); AliasesToExport = @(); VariablesToExport = @()
}
