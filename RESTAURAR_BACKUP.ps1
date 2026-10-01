[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BackupPath,[string]$CodexHome)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'router\Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome ''
& (Join-Path $PSScriptRoot 'router\RESTAURAR.ps1') -BackupPath $BackupPath -CodexHome $targetRoot
