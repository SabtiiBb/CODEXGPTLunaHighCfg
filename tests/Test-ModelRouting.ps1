$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\router\ModelRouting.ps1')
$callerScopeUndefinedVariable = $routerPlanCallerScopeUndefinedVariable

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw "$Message Expected '$Expected', got '$Actual'." }
}
function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}
function New-TestModel([string]$Slug, [string]$Description, [string[]]$Efforts, [string]$Visibility = 'list', $Upgrade = $null) {
    [pscustomobject]@{ slug = $Slug; display_name = $Slug; description = $Description; visibility = $Visibility; supported_reasoning_levels = @($Efforts | ForEach-Object { [pscustomobject]@{ effort = $_ } }); upgrade = $Upgrade }
}
function Get-Agent($Plan, [string]$Name) {
    $matches = @($Plan.agents | Where-Object { $_.name -eq $Name })
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

$luna = New-TestModel 'gpt-5.6-luna' 'Fast and affordable agentic coding model.' @('low','medium','high','xhigh','max')
$terra = New-TestModel 'gpt-5.6-terra' 'Balanced agentic coding model for everyday work.' @('low','medium','high','xhigh','max','ultra')
$sol = New-TestModel 'gpt-5.6-sol' 'Reliable agentic workhorse for everyday tasks.' @('low','medium','high','xhigh','max','ultra')
$astra = New-TestModel 'gpt-6-astra' 'Our most capable model for complex, demanding work.' @('low','medium','high','xhigh','max','ultra')
$current = [pscustomobject]@{ models = @($luna,$terra,$sol,$astra) }
$plan = New-RouterPlan $current
Assert-Equal 'gpt-5.6-luna' $plan.primary.model 'Primary model'
Assert-Equal 'high' $plan.primary.effort 'Primary effort'
Assert-Equal 'gpt-5.6-terra' $plan.families.balanced 'Balanced family'
Assert-Equal 'gpt-5.6-sol' $plan.families.advanced 'Advanced family'
Assert-Equal 'gpt-6-astra' $plan.families.frontier 'Frontier family'
Assert-Equal 'gpt-6-astra' (Get-Agent $plan 'frontier_max_architect').model 'Frontier role'
Assert-Equal 'gpt-6-astra' (Get-Agent $plan 'ultra_orchestrator').model 'Ultra preference'
Assert-True ($null -eq (Get-Agent $plan 'efficient_ultra')) 'Luna must not receive an invented ultra role'

$noAstra = New-RouterPlan ([pscustomobject]@{ models = @($luna,$terra,$sol) })
Assert-Equal $null $noAstra.families.frontier 'Missing Astra should stay absent'
Assert-Equal 'gpt-5.6-sol' (Get-Agent $noAstra 'ultra_orchestrator').model 'Ultra should degrade to Sol'
Assert-True (($noAstra.warnings -join ' ') -match 'frontier') 'Missing tier warning'

$noUltraModels = @(
    (New-TestModel 'gpt-5.6-luna' 'Fast and affordable agentic coding model.' @('low','medium','high','xhigh','max')),
    (New-TestModel 'gpt-5.6-terra' 'Balanced agentic coding model.' @('low','high','max')),
    (New-TestModel 'gpt-5.6-sol' 'Reliable agentic workhorse.' @('low','high','xhigh','max')),
    (New-TestModel 'gpt-6-astra' 'Our most capable model for complex, demanding work.' @('low','high','max'))
)
$noUltra = New-RouterPlan ([pscustomobject]@{ models = $noUltraModels })
Assert-Equal 'gpt-6-astra' (Get-Agent $noUltra 'ultra_orchestrator').model 'No-ultra fallback should prefer Astra'
Assert-Equal 'max' (Get-Agent $noUltra 'ultra_orchestrator').effort 'No-ultra fallback effort'
Assert-True ($null -eq (Get-Agent $noUltra 'balanced_medium')) 'Unsupported level must not be rendered'

$oldLuna = New-TestModel 'gpt-5.4-mini' 'Small fast coding model.' @('high') 'list' ([pscustomobject]@{ model = 'gpt-7-swift' })
$newLuna = New-TestModel 'gpt-7-swift' 'Fast and affordable agentic coding model.' @('medium','xhigh')
$upgradePlan = New-RouterPlan ([pscustomobject]@{ models = @($oldLuna,$newLuna,$terra,$sol,$astra) })
Assert-Equal 'gpt-7-swift' $upgradePlan.primary.model 'Visible upgrade target'
Assert-Equal 'xhigh' $upgradePlan.primary.effort 'Nearest supported primary effort'

$hiddenLuna = New-TestModel 'gpt-9-luna' 'Fast and affordable agentic coding model.' @('high') 'hide'
$hiddenPlan = New-RouterPlan ([pscustomobject]@{ models = @($hiddenLuna,$luna,$terra,$sol,$astra) })
Assert-Equal 'gpt-5.6-luna' $hiddenPlan.primary.model 'Hidden catalogue entries must be ignored'

$missingUpgrade = New-TestModel 'gpt-99-luna' 'Fast and affordable agentic coding model.' @('high') 'list' ([pscustomobject]@{ model = 'retired-luna' })
$missingUpgradePlan = New-RouterPlan ([pscustomobject]@{ models = @($missingUpgrade,$luna,$terra,$sol,$astra) })
Assert-Equal 'gpt-5.6-luna' $missingUpgradePlan.primary.model 'Missing upgrade target must exclude obsolete source'
$hiddenUpgradeTarget = New-TestModel 'gpt-100-luna' 'Fast and affordable agentic coding model.' @('high') 'hide'
$hiddenUpgrade = New-TestModel 'gpt-99-luna' 'Fast and affordable agentic coding model.' @('high') 'list' ([pscustomobject]@{ model = 'gpt-100-luna' })
$hiddenUpgradePlan = New-RouterPlan ([pscustomobject]@{ models = @($hiddenUpgrade,$hiddenUpgradeTarget,$luna,$terra,$sol,$astra) })
Assert-Equal 'gpt-5.6-luna' $hiddenUpgradePlan.primary.model 'Hidden upgrade target must exclude obsolete source'
$cycleA = New-TestModel 'gpt-99-luna' 'Fast and affordable agentic coding model.' @('high') 'list' ([pscustomobject]@{ model = 'gpt-100-terra' })
$cycleB = New-TestModel 'gpt-100-terra' 'Balanced agentic coding model.' @('high') 'list' ([pscustomobject]@{ model = 'gpt-99-luna' })
$cyclePlan = New-RouterPlan ([pscustomobject]@{ models = @($cycleA,$cycleB,$luna,$terra,$sol,$astra) })
Assert-Equal 'gpt-5.6-luna' $cyclePlan.primary.model 'Upgrade cycle must exclude all cyclic sources'
$oldSol = New-TestModel 'gpt-5.9-sol' 'Reliable agentic workhorse.' @('high','xhigh','max') 'list' ([pscustomobject]@{ model = 'gpt-6-astra' })
$migratedSolPlan = New-RouterPlan ([pscustomobject]@{ models = @($luna,$terra,$oldSol,$astra) })
Assert-Equal $null $migratedSolPlan.families.advanced 'Sol upgraded to Astra must not retain advanced family'
Assert-Equal 'gpt-6-astra' $migratedSolPlan.families.frontier 'Resolved target family wins source lineage'

$future = @(
    (New-TestModel 'codex-sprint' 'Fast and affordable agentic coding model.' @('high','max')),
    (New-TestModel 'codex-steady' 'Balanced coding model for everyday work.' @('high','max')),
    (New-TestModel 'codex-reason' 'Reliable agentic workhorse.' @('high','xhigh','max')),
    (New-TestModel 'codex-apex' 'Our most capable model for complex, demanding work.' @('high','max','ultra'))
)
$futurePlan = New-RouterPlan ([pscustomobject]@{ models = $future })
Assert-Equal 'codex-sprint' $futurePlan.primary.model 'Description fallback efficient family'
Assert-Equal 'codex-apex' $futurePlan.families.frontier 'Description fallback frontier family'
Assert-Equal 'xhigh' (Get-Agent $futurePlan 'deep_architect').effort 'Supported advanced effort'

$unknownVisibility = [pscustomobject]@{
    slug = 'codex-untrusted'; display_name = 'codex-untrusted'; description = 'Fast and affordable agentic coding model.'
    supported_reasoning_levels = @([pscustomobject]@{ effort = 'high' })
}
Assert-True (-not (Test-RouterVisibleModel $unknownVisibility)) 'Missing visibility metadata must fail closed'
$explicitVisible = [pscustomobject]@{
    slug = 'codex-visible'; display_name = 'codex-visible'; description = 'Fast and affordable agentic coding model.'; visible = $true
    supported_reasoning_levels = @([pscustomobject]@{ effort = 'high' })
}
$explicitVisiblePlan = New-RouterPlan ([pscustomobject]@{ models = @($explicitVisible) })
Assert-Equal 'codex-visible' $explicitVisiblePlan.primary.model 'Explicit visible=true model'

$withoutLuna=New-RouterPlan ([pscustomobject]@{ models = @($terra,$sol,$astra) })
Assert-Equal $sol.slug $withoutLuna.primary.model 'Missing Luna uses known Sol fallback'
Assert-True ($null -ne (Get-Agent $withoutLuna 'deep_architect')) 'Specialists remain available without Luna'
try {
    New-RouterPlan ([pscustomobject]@{ models = @() }) | Out-Null
    throw 'Expected failure for an empty catalogue.'
} catch {
    Assert-True ($_.Exception.Message -match 'No visible, reliable model family') 'Empty catalogue must fail closed'
}

$luna6=New-TestModel 'gpt-6-luna' 'Efficient' @('low','medium','high','xhigh','max')
$sol61=New-TestModel 'gpt-6.1-sol' 'Workhorse' @('low','medium','high','xhigh','max','ultra')
$unknown=New-TestModel 'custom-focus' 'Unclassified model' @('none','minimal','high','imaginary')
$modern=New-RouterPlan ([pscustomobject]@{models=@($luna,$luna6,$sol,$sol61,$astra,$unknown,$hiddenLuna)})
Assert-Equal 'gpt-6-luna' $modern.primary.model 'Luna 6 wins older Luna'
Assert-Equal 'gpt-6.1-sol' $modern.families.advanced 'Sol 6.1 wins older Sol'
Assert-Equal 'gpt-6-luna' (Get-Agent $modern 'efficient_worker').model 'High worker uses Luna 6'
Assert-Equal 'max' (Get-Agent $modern 'efficient_max_worker').effort 'Max worker uses supported max'
foreach ($model in @($luna,$luna6,$sol,$sol61,$astra,$unknown)) {
    foreach ($effort in @(Get-RouterSupportedEfforts $model)) {
        $name='model_'+[regex]::Replace($model.slug,'[^a-z0-9_]','_')+'_'+$effort
        Assert-Equal $model.slug (Get-Agent $modern $name).model 'Every visible model retains exact roles'
        Assert-Equal $effort (Get-Agent $modern $name).effort 'Exact role preserves effort'
    }
}
Assert-True ($null -eq (Get-Agent $modern 'model_gpt_9_luna_high')) 'Hidden exact model omitted'
Assert-True ($null -eq (Get-Agent $modern 'model_gpt_6_luna_ultra')) 'Luna ultra never invented'
Assert-True ($null -eq (Get-Agent $modern 'model_custom_focus_imaginary')) 'Unknown effort not emitted'
Assert-Equal $modern.agents.Count @($modern.agents.name | Select-Object -Unique).Count 'Agent names are unique'

Write-Host 'ModelRouting tests passed.'
