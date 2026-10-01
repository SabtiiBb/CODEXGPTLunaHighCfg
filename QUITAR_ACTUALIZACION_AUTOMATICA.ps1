[CmdletBinding()]
param([string]$CodexHome)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'router\Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome ''
$name=Get-RouterTaskName $targetRoot
$task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
if ($task) { Unregister-ScheduledTask -TaskName $name -Confirm:$false; Write-Host "Actualizacion automatica retirada: $name" }
else { Write-Host 'No hay una tarea V4 para esta ruta.' }
