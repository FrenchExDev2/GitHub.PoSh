#requires -Version 7.6
<#
.SYNOPSIS
Builds only the compatible integrated Core engine in an explicitly checked-out CI dependency.
.PARAMETER QuietCliRoot
Immutable dependency checkout selected by the CI workflow.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$QuietCliRoot)
$ErrorActionPreference = 'Stop'
if ($env:CI -ne 'true') { throw 'DependencyBootstrapIsCIOnly' }
$QuietCliRoot = [IO.Path]::GetFullPath($QuietCliRoot)
$manifest = Import-PowerShellDataFile (Join-Path $QuietCliRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
if ([version]$manifest.ModuleVersion -lt [version]'0.2.0') { throw 'CoreDependencyMustBeAtLeast020' }
# CI bootstrap is intentionally independent of the product being bootstrapped.
. (Join-Path $QuietCliRoot 'scripts/Common.ps1')
$project = 'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
$framework = if ([Environment]::Version.Major -ge 11) { 'net11.0' } else { 'net10.0' }
$output = if ($framework -eq 'net10.0') { 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess' } else { 'FrenchExDev2.QuietCli.Core.PoSh/lib/engine' }
$inputs = @(Get-QuietBinaryInputs $QuietCliRoot $project)
$null = Invoke-WorkspaceNative dotnet @('build', (Join-Path $QuietCliRoot $project), '-f', $framework, '-c', 'Release', '-o', (Join-Path $QuietCliRoot $output), '--nologo') $QuietCliRoot
Write-QuietBuildManifest -WorkspaceRoot $QuietCliRoot -Project $project -Output $output -Inputs $inputs -Configuration Release
