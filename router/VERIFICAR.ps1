[CmdletBinding()]
param([string]$CodexHome,[string]$CodexExe)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome $PSScriptRoot
$state=Read-RouterJson (Join-Path $targetRoot 'autorouter\state-v4.json')
if (-not $state -or $state.version -ne 4) { throw 'No se encontro una instalacion V4 valida.' }
$exe=Resolve-RouterExe $CodexExe $targetRoot
$null=Invoke-RouterCli $exe @('features','list') $targetRoot
$config=Read-RouterText (Join-Path $targetRoot 'config.toml')
$records=@(Get-RouterTomlLines $config)
$modelLine='model = '+(ConvertTo-RouterTomlString $state.primary.model)
$effortLine='model_reasoning_effort = '+(ConvertTo-RouterTomlString $state.primary.effort)
foreach ($expected in @($modelLine,$effortLine)) {
    if ($state.primary_policy -eq 'preserve-on-refresh') { continue }
    if (@($records | Where-Object { $_.Outside -and $_.Section -eq '' -and $_.Text.Trim() -ceq $expected }).Count -ne 1) { Write-Warning "El default actual difiere del router: $expected. El selector de Codex puede haberlo cambiado." }
}
foreach ($agent in @(@($state.agents)+@($state.legacy_aliases) | Where-Object {$null -ne $_})) {
    if ($agent.name -notmatch '^[a-z][a-z0-9_]*$') { throw 'Estado con nombre de agente invalido.' }
    $path=Join-Path $targetRoot ('agents\'+$agent.name+'.toml')
    $text=Read-RouterText $path
    foreach ($expected in @(('name = '+(ConvertTo-RouterTomlString $agent.name)),('model = '+(ConvertTo-RouterTomlString $agent.model)),('model_reasoning_effort = '+(ConvertTo-RouterTomlString $agent.effort)))) {
        if (-not (($text -split '\r?\n') -ccontains $expected)) { throw "Agente alterado o incompleto: $path" }
    }
}
$md=Read-RouterText (Join-Path $targetRoot 'AGENTS.md')
if ([regex]::Matches($md,'<!-- CODEX_AUTOROUTER_V4_START -->').Count -ne 1 -or [regex]::Matches($md,'<!-- CODEX_AUTOROUTER_V4_END -->').Count -ne 1) { throw 'AGENTS.md no contiene exactamente un bloque V4.' }
Write-Host "V4 verificada en: $targetRoot" -ForegroundColor Green
Write-Host "Sugerencia del router: $($state.primary.model) / $($state.primary.effort). El principal existente se conserva al refrescar."
Write-Host "Agentes activos: $(@($state.agents).Count). Fuente: $($state.catalog_source)"
$state.agents | Format-Table name,model,effort -AutoSize | Out-Host
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    $task=Get-ScheduledTask -TaskName (Get-RouterTaskName $targetRoot) -ErrorAction SilentlyContinue
    if ($task) { $task | Select-Object TaskName,State | Format-Table | Out-Host }
    else { Write-Host 'Actualizacion automatica V4: no registrada.' }
}
