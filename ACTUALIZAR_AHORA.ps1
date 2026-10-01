[CmdletBinding()]
param([string]$CodexHome,[string]$CodexExe,[switch]$Preview,[switch]$AllowCache,[ValidateSet('Preserve','LunaHigh','LunaMax')][string]$PrimaryMode='Preserve')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'router\Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome ''
$updater=Join-Path $targetRoot 'autorouter\ACTUALIZAR_MODELOS.ps1'
if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'autorouter\installation.json'))) { throw 'Instala V4 primero con INSTALAR_GLOBAL_V4.ps1.' }
& $updater -CodexHome $targetRoot -CodexExe $CodexExe -Preview:$Preview -AllowCache:$AllowCache -PrimaryMode $PrimaryMode
