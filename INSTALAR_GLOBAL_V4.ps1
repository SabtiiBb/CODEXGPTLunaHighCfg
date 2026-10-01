[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$CodexExe,
    [ValidateSet('Preserve','LunaHigh','LunaMax')][string]$PrimaryMode='Preserve',
    [switch]$SinActualizacionAutomatica,
    [switch]$Preview,
    [switch]$AllowCache,
    [string]$CatalogPath
)
$ErrorActionPreference='Stop'
$payload=Join-Path $PSScriptRoot 'router'
. (Join-Path $payload 'Common.ps1')
$targetRoot=Resolve-RouterHome $CodexHome ''
$exe=Resolve-RouterExe $CodexExe $targetRoot
Write-Host 'Codex AutoRouter V4 - Instalador portatil Windows' -ForegroundColor Cyan
& (Join-Path $payload 'ACTUALIZAR_MODELOS.ps1') -CodexHome $targetRoot -CodexExe $exe -CatalogPath $CatalogPath -PrimaryMode $PrimaryMode -AllowCache:$AllowCache -Preview:$Preview -InstallPayload
if ($Preview) { return }

if (-not $SinActualizacionAutomatica) {
    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        $taskName=Get-RouterTaskName $targetRoot
        $updater=Join-Path $targetRoot 'autorouter\ACTUALIZAR_MODELOS.ps1'
        $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Persist the resolved home in the action, since scheduled tasks may lack CODEX_HOME.
        # Rediscover the CLI on each run so app updates cannot stale a hashed binary path.
        $actionArgs='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File '+(ConvertTo-RouterArgument $updater)+' -CodexHome '+(ConvertTo-RouterArgument $targetRoot)+' -Silent'
        $action=New-ScheduledTaskAction -Execute $psExe -Argument $actionArgs
        $userId=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal=New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
        $triggers=@((New-ScheduledTaskTrigger -AtLogOn -User $userId),(New-ScheduledTaskTrigger -Daily -At '12:00'))
        $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description "Actualiza modelos AutoRouter V4 en $targetRoot para $userId." -Force | Out-Null
        Write-Host 'Actualizacion automatica: al iniciar sesion y diariamente a las 12:00.' -ForegroundColor Green
    } catch {
        Write-Warning "Configuracion instalada, pero no se pudo registrar la actualizacion automatica: $($_.Exception.Message). Usa ACTUALIZAR_AHORA.ps1."
    }
}
# Disable only a legacy V3 task that targets this installation, to prevent overwrites.
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    $legacy=Get-ScheduledTask -TaskName 'Codex AutoRouter V3 - Refresh Models' -ErrorAction SilentlyContinue
    if ($legacy) {
        $legacyPath=Join-Path $targetRoot 'autorouter\ACTUALIZAR_MODELOS.ps1'
        if (@($legacy.Actions | Where-Object { $_.Arguments -like ('*"'+$legacyPath+'"*') }).Count -gt 0) {
            try { $legacy | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Write-Host 'Tarea V3 de esta instalacion desactivada.' }
            catch { Write-Warning "Desactiva la tarea V3 de esta instalacion para evitar actualizaciones duplicadas: $($_.Exception.Message)" }
        }
    }
}
Write-Host "Instalacion V4 completada en $targetRoot. Cierra Codex completamente y vuelve a abrirlo." -ForegroundColor Green
Write-Host 'Las conversaciones existentes conservan su seleccion. Los refrescos futuros preservan el modelo y esfuerzo principal.'
Write-Host 'Para usar una ruta personalizada, inicia Codex con CODEX_HOME apuntando a esa carpeta.'
