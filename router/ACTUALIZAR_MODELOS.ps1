[CmdletBinding()]
param(
    [string]$CodexHome,
    [string]$CodexExe,
    [string]$CatalogPath,
    [ValidateSet('Preserve','LunaHigh','LunaMax')][string]$PrimaryMode='Preserve',
    [switch]$AllowCache,
    [switch]$Preview,
    [switch]$Silent,
    [switch]$InstallPayload
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'ModelRouting.ps1')

$targetRoot=Resolve-RouterHome $CodexHome $PSScriptRoot
$exe=Resolve-RouterExe $CodexExe $targetRoot
$catalog=Get-RouterCatalog $targetRoot $exe $CatalogPath -AllowCache:$AllowCache
$plan=New-RouterPlan -Catalog $catalog.Document
foreach ($message in $plan.warnings) { Write-Warning $message }
if (-not $Silent) {
    Write-Host "Codex Home: $targetRoot" -ForegroundColor Cyan
    Write-Host "Sugerencia: $($plan.primary.model) / $($plan.primary.effort). Modo solicitado: $PrimaryMode"
    $plan.agents | Select-Object name,model,effort | Format-Table -AutoSize | Out-Host
}

$configPath=Join-Path $targetRoot 'config.toml'
$mdPath=Join-Path $targetRoot 'AGENTS.md'
$originalConfig=Read-RouterText $configPath
$originalMd=Read-RouterText $mdPath
$config=$originalConfig
$hasPrimary=@(Get-RouterTomlLines $config | Where-Object { $_.Outside -and $_.Section -eq '' -and $_.Text -match '^\s*(?:model|"model"|''model'')\s*=' }).Count -gt 0
if ($PrimaryMode -ne 'Preserve') {
    $luna=@(Get-RouterCatalogModels $catalog.Document | Where-Object { $_.slug -eq 'gpt-6-luna' -and (Test-RouterVisibleModel $_) })
    $requestedEffort=if ($PrimaryMode -eq 'LunaMax') { 'max' } else { 'high' }
    if ($luna.Count -ne 1 -or (Get-RouterSupportedEfforts $luna[0]) -notcontains $requestedEffort) { throw "GPT-6 Luna / $requestedEffort no esta disponible en este catalogo. No se modifico la configuracion." }
    $plan.primary=[pscustomobject]@{model='gpt-6-luna';effort=$requestedEffort}
}
if ($PrimaryMode -ne 'Preserve' -or -not $hasPrimary) {
    $config=Set-RouterTomlValues $config '' ([ordered]@{
        model=(ConvertTo-RouterTomlString $plan.primary.model)
        model_reasoning_effort=(ConvertTo-RouterTomlString $plan.primary.effort)
    })
}
$config=Set-RouterTomlValues $config 'agents' ([ordered]@{enabled='true'})
# Preserve an existing concurrency limit. New installations allow at most two children.
$hasLimit=@(Get-RouterTomlLines $config | Where-Object { $_.Outside -and $_.Section -eq 'agents' -and $_.Text -match '^\s*(?:max_concurrent_threads_per_session|max_threads|"max_concurrent_threads_per_session"|''max_concurrent_threads_per_session''|"max_threads"|''max_threads'')\s*=' }).Count -gt 0
if (-not $hasLimit) { $config=Set-RouterTomlValues $config 'agents' ([ordered]@{max_concurrent_threads_per_session='2'}) }
$block=Read-RouterText (Join-Path $PSScriptRoot 'ROUTING.md')
if (-not $block.Contains('<!-- CODEX_AUTOROUTER_V4_START -->')) { throw 'Falta la plantilla ROUTING.md V4.' }
$table=@('| Agent | Model | Reasoning |','| --- | --- | --- |')
foreach ($agent in $plan.agents) { $table += "| $($agent.name) | $($agent.model) | $($agent.effort) |" }
$block=$block.Replace('{{AGENT_TABLE}}',($table -join "`r`n"))
$block=$block.Replace('{{PRIMARY}}',"$($plan.primary.model) / $($plan.primary.effort)")
$files=[ordered]@{
    'config.toml'=$config
    'AGENTS.md'=(Merge-RouterInstructions $originalMd $block)
    'autorouter\MODELOS.md'=("# Catalogo local de agentes`r`n`r`n"+($table -join "`r`n")+"`r`n")
}
$legacyNames=@('efficient_worker','efficient_max_worker','balanced_engineer','balanced_max_engineer','deep_architect','deep_max_architect','ultra_orchestrator')
foreach ($agent in $plan.agents) {
    if ($agent.name -notmatch '^[a-z][a-z0-9_]*$') { throw 'Nombre de agente invalido.' }
    $existingAgent=Read-RouterText (Join-Path $targetRoot ('agents\'+$agent.name+'.toml'))
    $migratingKnownV3=($legacyNames -contains $agent.name -and $originalMd.Contains('<!-- CODEX_AUTOROUTER_V3_START -->'))
    if ($existingAgent -and -not $existingAgent.StartsWith('# Managed by Codex AutoRouter V4.') -and -not $migratingKnownV3) { throw "El agente personal $($agent.name) ocupa un nombre de V4. Renombralo antes de instalar." }
    $lines=@(
        '# Managed by Codex AutoRouter V4.'
        ('name = '+(ConvertTo-RouterTomlString $agent.name))
        ('description = '+(ConvertTo-RouterTomlString $agent.description))
        ('model = '+(ConvertTo-RouterTomlString $agent.model))
        ('model_reasoning_effort = '+(ConvertTo-RouterTomlString $agent.effort))
        ('developer_instructions = '+(ConvertTo-RouterTomlString ($agent.instructions -join "`n")))
    )
    $files['agents\'+$agent.name+'.toml']=($lines -join "`r`n")+"`r`n"
}
# Old managed variants whose model/effort disappeared remain valid aliases to the
# primary. This avoids deleting personal files or leaving unsupported agents loaded.
$oldStatePath=Join-Path $targetRoot 'autorouter\state-v4.json'
$legacyAliases=@()
$priorAgents=@()
if (Test-Path -LiteralPath $oldStatePath) {
    $oldState=Read-RouterJson $oldStatePath
    $priorAgents=@(@($oldState.agents)+@($oldState.legacy_aliases) | Where-Object { $null -ne $_ })
} elseif ($originalMd.Contains('<!-- CODEX_AUTOROUTER_V3_START -->')) {
    $priorAgents=@($legacyNames | ForEach-Object { [PSCustomObject]@{name=$_} })
}
foreach ($oldAgent in $priorAgents) {
        if ($oldAgent.name -notmatch '^[a-z][a-z0-9_]*$') { throw 'Nombre invalido en state-v4.json.' }
        $relative='agents\'+$oldAgent.name+'.toml'
        if (-not $files.Contains($relative)) {
            $oldText=Read-RouterText (Join-Path $targetRoot $relative)
            if ($oldText -and ($oldText.StartsWith('# Managed by Codex AutoRouter V4.') -or ($legacyNames -contains $oldAgent.name -and $originalMd.Contains('<!-- CODEX_AUTOROUTER_V3_START -->')))) {
                $alias=Set-RouterTomlValues $oldText '' ([ordered]@{
                    name=(ConvertTo-RouterTomlString $oldAgent.name)
                    model=(ConvertTo-RouterTomlString $plan.primary.model)
                    model_reasoning_effort=(ConvertTo-RouterTomlString $plan.primary.effort)
                    description=(ConvertTo-RouterTomlString 'Legacy alias: original model/effort unavailable. Prefer current roles listed in AGENTS.md.')
                    developer_instructions=(ConvertTo-RouterTomlString 'Handle only the bounded assigned task. Preserve shared work. Do not delegate recursively. Prefer the current roles in AGENTS.md for new assignments.')
                })
                if (-not $alias.StartsWith('# Managed by Codex AutoRouter V4.')) { $alias='# Managed by Codex AutoRouter V4.'+"`r`n"+$alias }
                $files[$relative]=$alias
                $legacyAliases += [PSCustomObject]@{name=$oldAgent.name;model=$plan.primary.model;effort=$plan.primary.effort}
            }
        }
}
$state=[ordered]@{
    version=4
    release='4.1'
    codex_home=$targetRoot
    catalog_source=$catalog.Source
    catalog_fetched_at=$catalog.Document.fetched_at
    primary=$plan.primary
    primary_policy='preserve-on-refresh'
    families=$plan.families
    agents=@($plan.agents | Select-Object name,model,effort)
    legacy_aliases=$legacyAliases
    warnings=@($plan.warnings)
}
$files['autorouter\state-v4.json']=$state | ConvertTo-Json -Depth 10
if ($InstallPayload) {
    foreach ($item in Get-ChildItem -LiteralPath $PSScriptRoot -File) {
        if ($item.Name -in @('Common.ps1','ModelRouting.ps1','ACTUALIZAR_MODELOS.ps1','ROUTING.md','VERIFICAR.ps1','RESTAURAR.ps1')) {
            $files['autorouter\'+$item.Name]=Read-RouterText $item.FullName
        }
    }
    $files['autorouter\installation.json']=([ordered]@{version=4;codex_home=$targetRoot;codex_cli_hint=$exe;task_name=(Get-RouterTaskName $targetRoot)}) | ConvertTo-Json
}

# The CLI's features command parses config; debug models alone does NOT validate it.
$stage=Join-Path ([IO.Path]::GetTempPath()) ('CodexAutoRouterV4_'+[Guid]::NewGuid().ToString('N'))
try {
    foreach ($relative in $files.Keys) {
        if ($relative -eq 'config.toml' -or $relative.StartsWith('agents\')) { Write-RouterText (Join-Path $stage $relative) $files[$relative] }
    }
    $null=Invoke-RouterCli $exe @('features','list') $stage
} finally {
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    $resolvedStage=[IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedStage -Leaf) -like 'CodexAutoRouterV4_*' -and (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
if ($Preview) {
    Write-Host 'PREVIEW validado. No se modifico la instalacion de Codex.' -ForegroundColor Green
    return
}
if ((Read-RouterText $configPath) -cne $originalConfig -or (Read-RouterText $mdPath) -cne $originalMd) { throw 'Codex modifico la configuracion durante la preparacion. Vuelve a ejecutar para no sobrescribir cambios.' }
$backup=Save-RouterChanges $targetRoot $files ([ordered]@{'config.toml'=$originalConfig;'AGENTS.md'=$originalMd})
if (-not $Silent) {
    if ($backup) { Write-Host "Configuracion aplicada. Backup: $backup" -ForegroundColor Green }
    else { Write-Host 'La configuracion ya estaba actualizada.' -ForegroundColor Green }
}
