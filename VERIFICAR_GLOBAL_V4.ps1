[CmdletBinding()]
param([string]$CodexHome,[string]$CodexExe)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'router\Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome ''
& (Join-Path $PSScriptRoot 'router\VERIFICAR.ps1') -CodexHome $targetRoot -CodexExe $CodexExe
