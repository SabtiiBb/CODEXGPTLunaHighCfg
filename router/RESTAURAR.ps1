[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BackupPath,[string]$CodexHome)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome $PSScriptRoot
$backup=Get-FullRouterPath $BackupPath
$allowed=Join-Path $targetRoot 'autorouter\backups'
if (-not $backup.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'El backup debe estar dentro de autorouter\backups de esta instalacion.' }
$manifest=Read-RouterJson (Join-Path $backup 'manifest.json')
if (-not $manifest -or (Get-FullRouterPath $manifest.codex_home) -ne $targetRoot) { throw 'El backup no corresponde a esta instalacion.' }
$lock=$null
try {
    $lock=[IO.File]::Open((Join-Path $targetRoot 'autorouter-v4.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $entries=@()
    foreach ($entry in $manifest.files) {
        $full=[IO.Path]::GetFullPath((Join-Path $targetRoot $entry.relative))
        $source=[IO.Path]::GetFullPath((Join-Path $backup $entry.relative))
        if (-not $full.StartsWith($targetRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $source.StartsWith($backup+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta invalida en manifest.json.' }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $entry.applied_hash) { throw "$($entry.relative) cambio despues del backup. Restaura manualmente ese archivo para no perder ediciones posteriores." }
        if ($entry.existed -and -not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Backup incompleto: $($entry.relative)." }
        $entries += [PSCustomObject]@{full=$full;source=$source;existed=$entry.existed}
    }
    # Disable refresh before restoring an older updater; no unrelated tasks are touched.
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $task=Get-ScheduledTask -TaskName (Get-RouterTaskName $targetRoot) -ErrorAction SilentlyContinue
        if ($task) { $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
    }
    foreach ($entry in $entries) {
        if ($entry.existed) { [IO.File]::Copy($entry.source,$entry.full,$true) }
        else { [IO.File]::Delete($entry.full) }
    }
    Write-Host 'Backup restaurado. Cierra y vuelve a abrir Codex. La tarea automatica V4 queda desactivada.' -ForegroundColor Green
} finally { if ($lock) { $lock.Dispose() } }
