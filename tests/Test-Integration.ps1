param([string]$PackageRoot=(Join-Path $PSScriptRoot '..'))
$ErrorActionPreference='Stop'
. (Join-Path $PackageRoot 'router\Common.ps1')
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw "ASSERT: $Message" } }
function Expect-Failure([scriptblock]$Action,[string]$Message) {
    $failed=$false
    try { & $Action | Out-Null } catch { $failed=$true }
    Assert $failed $Message
}
$testBase=Join-Path ([IO.Path]::GetTempPath()) ('CodexAutoRouterTests_'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$target=Join-Path $testBase 'Otro Usuario (2)\.codex'
$exe=Resolve-RouterExe '' (Resolve-RouterHome '' '')
$fixture=Join-Path $testBase 'catalog.json'
$models=@()
foreach ($family in @('luna','terra','sol','astra')) {
    $slug=if ($family -eq 'terra') {'gpt-5.6-terra'} elseif ($family -eq 'sol') {'gpt-6.1-sol'} else {'gpt-6-'+$family}
    $levels=@('low','medium','high','xhigh','max'); if ($family -ne 'luna') {$levels+='ultra'}
    $models += [PSCustomObject]@{slug=$slug;visibility='list';description=$family;upgrade=$null;supported_reasoning_levels=@($levels | ForEach-Object {[PSCustomObject]@{effort=$_}})}
}
Write-RouterText $fixture (([PSCustomObject]@{models=$models;fetched_at=[DateTimeOffset]::Now.ToString('o')}) | ConvertTo-Json -Depth 8)
$config=@'
# personal configuration
model = "previous-model"
model_reasoning_effort = "medium"
developer_instructions = """
[agents]
model = "leave this example alone"
"""
[agents] # preserve this existing table
enabled = false
max_concurrent_threads_per_session = 3
interrupt_message = true
[projects.'C:\My Work']
trust_level = "trusted"
[custom]
flag = true
'@
$md="Personal prefix`r`n<!-- CODEX_AUTOROUTER_V3_START -->`r`nold router`r`n<!-- CODEX_AUTOROUTER_V3_END -->`r`nPersonal suffix"
$duplicateMerge=Merge-RouterInstructions ($md+$md) '<!-- CODEX_AUTOROUTER_V4_START -->new<!-- CODEX_AUTOROUTER_V4_END -->'
Assert ([regex]::Matches($duplicateMerge,'V4_START').Count -eq 1) 'Duplicate old blocks collapse to one'
Assert ([regex]::Matches($duplicateMerge,'Personal suffix').Count -eq 2) 'Text between duplicate blocks is retained'
Write-RouterText (Join-Path $target 'config.toml') $config
Write-RouterText (Join-Path $target 'AGENTS.md') $md
Write-RouterText (Join-Path $target 'agents\efficient_worker.toml') 'name = "efficient_worker"'
Assert ((Get-FullRouterPath 'C:\') -eq 'C:\') 'Drive root must not become relative'
Assert ((Resolve-RouterHome $target '') -eq (Get-FullRouterPath $target)) 'Explicit home wins over CODEX_HOME'
if ($env:CODEX_HOME) { Assert ((Resolve-RouterHome '' '') -eq (Get-FullRouterPath $env:CODEX_HOME)) 'CODEX_HOME respected' }
# Simulate another Windows user without modifying environment variables or registry.
& {
    function Get-RouterEnvironmentHome { return $null }
    function Get-RouterDefaultProfile { return (Join-Path $testBase 'Users\OtroUsuario') }
    function Get-RouterDriveHomes { return @() }
    function Get-RouterDocumentHomes { return @() }
    $expected=Join-Path (Get-RouterDefaultProfile) '.codex'
    Assert ((Resolve-RouterHome '' '') -eq $expected) 'Different user without D uses own profile'
    Write-RouterText (Join-Path $expected 'config.toml') 'model = "sample"'
    function Get-RouterDriveHomes { return @('D:\.codex') }
    Assert ((Resolve-RouterHome '' '') -eq $expected) 'Existing standard profile precedes drive scan'
    function Get-RouterDefaultProfile { return (Join-Path $testBase 'Users\NoConfigYet') }
    Assert ((Resolve-RouterHome '' '') -eq 'D:\.codex') 'Unique custom drive home discovered'
    function Get-RouterDriveHomes { return @('D:\.codex','E:\.codex') }
    Expect-Failure { Resolve-RouterHome '' '' } 'Multiple custom homes require explicit selection'
    function Get-RouterDriveHomes { return @() }
    function Get-RouterDocumentHomes { return @((Join-Path $testBase 'OneDrive - Work\Documentos\.codex')) }
    Assert ((Resolve-RouterHome '' '') -eq (Get-RouterDocumentHomes)) 'Redirected Documents detected'
    function Get-RouterDriveHomes { return @('D:\.codex') }
    Expect-Failure { Resolve-RouterHome '' '' } 'Documents and drive ambiguity requires explicit selection'
}
$invokeArgs=@{CodexHome=$target;CodexExe=$exe;CatalogPath=$fixture;SinActualizacionAutomatica=$true}
& (Join-Path $PackageRoot 'INSTALAR_GLOBAL_V4.ps1') @invokeArgs -Preview
Assert ((Read-RouterText (Join-Path $target 'config.toml')) -ceq $config) 'Preview preserves config'
Assert (-not (Test-Path -LiteralPath (Join-Path $target 'autorouter'))) 'Preview installs no files'
& (Join-Path $PackageRoot 'INSTALAR_GLOBAL_V4.ps1') @invokeArgs
$newConfig=Read-RouterText (Join-Path $target 'config.toml')
Assert ($newConfig.Contains('model = "previous-model"') -and $newConfig.Contains('model_reasoning_effort = "medium"')) 'Existing primary and effort preserved'
Assert ($newConfig.Contains('model = "leave this example alone"')) 'Multiline example preserved'
Assert ($newConfig.Contains('max_concurrent_threads_per_session = 3')) 'Existing concurrency preserved'
Assert ($newConfig.Contains('[projects.''C:\My Work'']')) 'Project table preserved'
Assert ($newConfig.Contains('flag = true')) 'Unrelated config preserved'
$newMd=Read-RouterText (Join-Path $target 'AGENTS.md')
Assert ($newMd.Contains('Personal prefix') -and $newMd.Contains('Personal suffix')) 'Markdown prefix/suffix preserved'
Assert (-not $newMd.Contains('V3_START')) 'V3 marker replaced'
Assert ([regex]::Matches($newMd,'V4_START').Count -eq 1) 'One V4 block'
Assert ((Get-ChildItem -LiteralPath (Join-Path $target 'agents') -File).Count -eq 55) 'All supported roles emitted'
$backup=(Get-ChildItem -LiteralPath (Join-Path $target 'autorouter\backups') -Directory | Select-Object -First 1).FullName
Assert ((Read-RouterText (Join-Path $backup 'config.toml')) -ceq $config) 'Original backed up exactly'
& (Join-Path $PackageRoot 'VERIFICAR_GLOBAL_V4.ps1') -CodexHome $target -CodexExe $exe
& (Join-Path $PackageRoot 'INSTALAR_GLOBAL_V4.ps1') @invokeArgs
Assert ((Get-ChildItem -LiteralPath (Join-Path $target 'autorouter\backups') -Directory).Count -eq 1) 'Idempotence: unchanged install creates no backup'

# No catalog may change any managed config before discovery succeeds.
$badCatalog=Join-Path $testBase 'empty.json'
Write-RouterText $badCatalog '{"models":[]}'
Expect-Failure { & (Join-Path $PackageRoot 'router\ACTUALIZAR_MODELOS.ps1') -CodexHome $target -CodexExe $exe -CatalogPath $badCatalog -Silent } 'Empty catalog must fail'
Assert ((Read-RouterText (Join-Path $target 'config.toml')) -ceq $newConfig) 'Failure preserves installed config'

# Rollback after a later path fails preserves earlier writes and removes new files.
$rollback=Join-Path $testBase 'rollback'
Write-RouterText (Join-Path $rollback 'config.toml') 'original'
[IO.Directory]::CreateDirectory((Join-Path $rollback 'blocked.txt')) | Out-Null
Expect-Failure { Save-RouterChanges $rollback ([ordered]@{'config.toml'='changed';'new.txt'='new';'blocked.txt'='cannot write a directory'}) } 'Failed commit must roll back'
Assert ((Read-RouterText (Join-Path $rollback 'config.toml')) -ceq 'original') 'Rollback restores original'
Assert (-not (Test-Path -LiteralPath (Join-Path $rollback 'new.txt'))) 'Rollback removes new files'

# Restore the initial backup before testing further migrations.
& (Join-Path $PackageRoot 'RESTAURAR_BACKUP.ps1') -CodexHome $target -BackupPath $backup
Assert ((Read-RouterText (Join-Path $target 'config.toml')) -ceq $config) 'Restore exact original config'
Assert ((Read-RouterText (Join-Path $target 'AGENTS.md')) -ceq $md) 'Restore exact original instructions'
Assert ((Get-ChildItem -LiteralPath (Join-Path $target 'agents') -File).Count -eq 1) 'Restore removes newly created agents'

$collision=Join-Path $testBase 'collision'
Write-RouterText (Join-Path $collision 'agents\efficient_worker.toml') 'name = "efficient_worker" # personal'
Expect-Failure { & (Join-Path $PackageRoot 'INSTALAR_GLOBAL_V4.ps1') -CodexHome $collision -CodexExe $exe -CatalogPath $fixture -SinActualizacionAutomatica } 'Do not overwrite personal agent'
Assert (-not (Test-Path -LiteralPath (Join-Path $collision 'config.toml'))) 'Collision detected before config write'

# Loss of an upper family must never leave unavailable models in managed files.
$fallback=Join-Path $testBase 'fallback'
& (Join-Path $PackageRoot 'INSTALAR_GLOBAL_V4.ps1') -CodexHome $fallback -CodexExe $exe -CatalogPath $fixture -SinActualizacionAutomatica
$noAstra=Join-Path $testBase 'no-astra.json'
Write-RouterText $noAstra (([PSCustomObject]@{models=@($models | Where-Object {$_.slug -ne 'gpt-6-astra'});fetched_at=[DateTimeOffset]::Now.ToString('o')}) | ConvertTo-Json -Depth 8)
& (Join-Path $PackageRoot 'router\ACTUALIZAR_MODELOS.ps1') -CodexHome $fallback -CodexExe $exe -CatalogPath $noAstra -Silent
& (Join-Path $PackageRoot 'router\ACTUALIZAR_MODELOS.ps1') -CodexHome $fallback -CodexExe $exe -CatalogPath $noAstra -Silent
$state=Read-RouterJson (Join-Path $fallback 'autorouter\state-v4.json')
Assert (@($state.legacy_aliases).Count -gt 0) 'Legacy aliases tracked over repeated updates'
Get-ChildItem -LiteralPath (Join-Path $fallback 'agents') -File | ForEach-Object { Assert (-not (Read-RouterText $_.FullName).Contains('gpt-6-astra')) 'No stale Astra agent' }

# Explicit modes select exactly Luna 6; automatic refresh preserves the selection.
$modeTarget=Join-Path $testBase 'Luna Modes'
foreach ($mode in @('LunaHigh','LunaMax')) {
    & (Join-Path $PackageRoot 'INSTALAR_GLOBAL_V4.ps1') -CodexHome $modeTarget -CodexExe $exe -CatalogPath $fixture -SinActualizacionAutomatica -PrimaryMode $mode
    $modeConfig=Read-RouterText (Join-Path $modeTarget 'config.toml')
    $level=if ($mode -eq 'LunaMax') { 'max' } else { 'high' }
    Assert ($modeConfig.Contains('model = "gpt-6-luna"') -and $modeConfig.Contains('model_reasoning_effort = "'+$level+'"')) 'Exact Luna 6 selection'
    & (Join-Path $PackageRoot 'router\ACTUALIZAR_MODELOS.ps1') -CodexHome $modeTarget -CodexExe $exe -CatalogPath $fixture -Silent
    Assert ((Read-RouterText (Join-Path $modeTarget 'config.toml')) -ceq $modeConfig) 'Refresh preserves explicit Luna effort'
}
$noLuna=Join-Path $testBase 'no-luna.json'
Write-RouterText $noLuna (([pscustomobject]@{models=@($models | Where-Object { $_.slug -ne 'gpt-6-luna' })}) | ConvertTo-Json -Depth 8)
Expect-Failure { & (Join-Path $PackageRoot 'router\ACTUALIZAR_MODELOS.ps1') -CodexHome $modeTarget -CodexExe $exe -CatalogPath $noLuna -PrimaryMode LunaMax -Silent } 'Explicit Luna 6 never silently falls back'
Assert ((Read-RouterText (Join-Path $modeTarget 'config.toml')) -ceq $modeConfig) 'Missing requested Luna preserves config'

Write-Host 'PASS: discovery, preview, V3 migration, preservation, idempotence, rollback, restore, collisions, and catalog downgrade.' -ForegroundColor Green
Write-Output "TEST_ROOT=$testBase"
