#requires -Version 7.6
<#
.SYNOPSIS
Imports the exact selected Core and both sibling projects without rebuilding or installing anything.
.PARAMETER CoreManifest
Explicit Core manifest; defaults to the selected sibling QuietCli checkout.
#>
[CmdletBinding()]
param([string]$CoreManifest = (Join-Path $PSScriptRoot '../../QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'))
$ErrorActionPreference = 'Stop'
$CoreManifest = [IO.Path]::GetFullPath($CoreManifest)
$expected = [IO.Path]::ChangeExtension($CoreManifest, 'psm1')
$loaded = Get-Module FrenchExDev2.QuietCli.Core.PoSh
if ($loaded -and $loaded.Path -ne $expected) { throw 'DifferentCoreAlreadyLoaded: start a fresh PowerShell process.' }
if (!$loaded) { Import-Module $CoreManifest -ErrorAction Stop }
if ((Get-Module FrenchExDev2.QuietCli.Core.PoSh).Path -ne $expected) { throw 'SelectedCorePathMismatch' }
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'FrenchExDev2.GitHub.PoSh/FrenchExDev2.GitHub.PoSh.psd1') -ErrorAction Stop
Import-Module (Join-Path $root 'FrenchExDev2.GitHub.Tests.PoSh/FrenchExDev2.GitHub.Tests.PoSh.psd1') -ErrorAction Stop
