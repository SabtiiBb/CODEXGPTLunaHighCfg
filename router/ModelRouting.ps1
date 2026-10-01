# This file deliberately only defines functions.  It is safe to dot-source from
# the installer and from tests without reading the catalogue or changing config.

function Get-RouterCatalogModels {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Catalog)

    if ($null -eq $Catalog) { return @() }
    if ($Catalog.PSObject.Properties.Name -contains 'models') {
        return @($Catalog.models)
    }
    return @($Catalog)
}

function Test-RouterVisibleModel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Model)

    if ($null -eq $Model -or [string]::IsNullOrWhiteSpace([string]$Model.slug)) { return $false }
    $propertyNames = @($Model.PSObject.Properties.Name)
    if ($propertyNames -contains 'visibility' -and -not [string]::IsNullOrWhiteSpace([string]$Model.visibility)) {
        $visibility = ([string]$Model.visibility).ToLowerInvariant()
        if ($visibility -eq 'hide' -or $visibility -eq 'hidden' -or $visibility -eq 'none') { return $false }
        return ($visibility -eq 'list' -or $visibility -eq 'visible')
    }
    return ($propertyNames -contains 'visible' -and $Model.visible -eq $true)
}

function Get-RouterSupportedEfforts {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Model)

    $efforts = @()
    if ($Model.PSObject.Properties.Name -contains 'supported_reasoning_levels') {
        foreach ($level in @($Model.supported_reasoning_levels)) {
            $effort = if ($level -is [string]) { $level } else { [string]$level.effort }
            if ($effort -in @('none','minimal','low','medium','high','xhigh','max','ultra')) { $efforts += $effort.ToLowerInvariant() }
        }
    }
    return @($efforts | Select-Object -Unique)
}

function Resolve-RouterVisibleUpgrade {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Model,
        [Parameter(Mandatory = $true)]$VisibleBySlug
    )

    $current = $Model
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    while ($null -ne $current) {
        $slug = [string]$current.slug
        if ([string]::IsNullOrWhiteSpace($slug) -or -not $seen.Add($slug)) { return $null }
        if (-not ($current.PSObject.Properties.Name -contains 'upgrade') -or $null -eq $current.upgrade) { return $current }
        $upgradeSlug = $null
        if ($current.upgrade -is [string]) { $upgradeSlug = $current.upgrade }
        elseif ($current.upgrade.PSObject.Properties.Name -contains 'model') { $upgradeSlug = [string]$current.upgrade.model }
        if ([string]::IsNullOrWhiteSpace($upgradeSlug) -or -not $VisibleBySlug.ContainsKey($upgradeSlug)) { return $null }
        $current = $VisibleBySlug[$upgradeSlug]
    }
    return $null
}

function Get-RouterModelFamily {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Model)

    $slug = ([string]$Model.slug).ToLowerInvariant()
    foreach ($family in @('efficient', 'balanced', 'advanced', 'frontier')) {
        $token = @{ efficient = 'luna'; balanced = 'terra'; advanced = 'sol'; frontier = 'astra' }[$family]
        if ($slug -match ('(^|[-_.])' + $token + '($|[-_.])')) { return $family }
    }

    # Future slugs need not retain the current celestial names.  These phrases
    # describe capability classes, rather than relying on catalogue priority.
    $text = (([string]$Model.display_name) + ' ' + ([string]$Model.description)).ToLowerInvariant()
    if ($text -match '\b(mini|small|reserve|spark)\b') { return $null }
    if ($text -match '\bmost capable\b|\bfrontier\b|\bcomplex[, ]+demanding\b') { return 'frontier' }
    if ($text -match '\bbalanced\b') { return 'balanced' }
    if ($text -match '\b(reliable|workhorse)\b') { return 'advanced' }
    if ($text -match '\b(fast and affordable|affordable and fast|cost[ -]?efficient)\b') { return 'efficient' }
    return $null
}

function Get-RouterVersionRank {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Model)

    $match = [regex]::Match(([string]$Model.slug), '(?<!\d)(\d+)(?:\.(\d+))?(?:\.(\d+))?')
    if (-not $match.Success) { return 0L }
    $major = [int64]$match.Groups[1].Value
    $minor = if ($match.Groups[2].Success) { [int64]$match.Groups[2].Value } else { 0L }
    $patch = if ($match.Groups[3].Success) { [int64]$match.Groups[3].Value } else { 0L }
    return ($major * 1000000L) + ($minor * 1000L) + $patch
}

function Select-RouterFamilyModel {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Candidates,
        [Parameter(Mandatory = $true)][string]$Family
    )

    $familyCandidates = @($Candidates | Where-Object { $_.family -eq $Family })
    if ($familyCandidates.Count -eq 0) { return $null }
    return @($familyCandidates | Sort-Object @{ Expression = { Get-RouterVersionRank $_.model }; Descending = $true }, @{ Expression = { [string]$_.model.slug }; Descending = $true })[0].model
}

function Select-RouterEffort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Model,
        [Parameter(Mandatory = $true)][string]$Requested
    )

    $supported = @(Get-RouterSupportedEfforts $Model)
    if ($supported.Count -eq 0) { return $null }
    $requested = $Requested.ToLowerInvariant()
    if ($supported -contains $requested) { return $requested }
    $order = @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    $requestedIndex = [array]::IndexOf($order, $requested)
    if ($requestedIndex -lt 0) { return $supported[0] }
    $best = $null
    $bestDistance = [int]::MaxValue
    $bestIndex = -1
    foreach ($candidate in $supported) {
        $candidateIndex = [array]::IndexOf($order, $candidate)
        if ($candidateIndex -lt 0) { continue }
        $distance = [Math]::Abs($candidateIndex - $requestedIndex)
        # Prefer the stronger neighbouring setting on an equal distance.
        if ($distance -lt $bestDistance -or ($distance -eq $bestDistance -and $candidateIndex -gt $bestIndex)) {
            $best = $candidate; $bestDistance = $distance; $bestIndex = $candidateIndex
        }
    }
    if ($null -eq $best) { return $supported[0] }
    return $best
}

function New-RouterAgent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Model,
        [Parameter(Mandatory = $true)][string]$RequestedEffort,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$Instructions,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $effort = Select-RouterEffort -Model $Model -Requested $RequestedEffort
    if ($null -eq $effort) { return $null }
    if ($effort -ne $RequestedEffort) {
        $Warnings.Add("$Name requested $RequestedEffort on $($Model.slug); using supported $effort.")
    }
    return [pscustomobject]@{
        name = $Name
        model = [string]$Model.slug
        effort = $effort
        description = $Description
        instructions = $Instructions
    }
}

function New-RouterPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Catalog)

    $visible = @(Get-RouterCatalogModels $Catalog | Where-Object { Test-RouterVisibleModel $_ })
    $visibleBySlug = @{}
    foreach ($model in $visible) { $visibleBySlug[[string]$model.slug] = $model }

    $candidates = @()
    $candidateKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in $visible) {
        $resolved = Resolve-RouterVisibleUpgrade -Model $source -VisibleBySlug $visibleBySlug
        if ($null -eq $resolved) { continue }
        $family = Get-RouterModelFamily $resolved
        if ($null -eq $family) { $family = Get-RouterModelFamily $source }
        if ($null -eq $family -or @(Get-RouterSupportedEfforts $resolved).Count -eq 0) { continue }
        $key = "$family|$($resolved.slug)"
        if ($candidateKeys.Add($key)) { $candidates += [pscustomobject]@{ family = $family; model = $resolved } }
    }

    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $families = [ordered]@{}
    $modelsByFamily = @{}
    foreach ($family in @('efficient', 'balanced', 'advanced', 'frontier')) {
        $model = Select-RouterFamilyModel -Candidates $candidates -Family $family
        $modelsByFamily[$family] = $model
        $families[$family] = if ($null -eq $model) { $null } else { [string]$model.slug }
    }
    $primaryModel = $null
    foreach ($family in @('efficient','advanced','balanced','frontier')) {
        if ($null -ne $modelsByFamily[$family]) { $primaryModel=$modelsByFamily[$family]; break }
    }
    if ($null -eq $primaryModel) { throw 'No visible, reliable model family was found. Refusing to guess a default.' }
    if ($null -eq $modelsByFamily['efficient']) { $warnings.Add("Luna is unavailable; suggested fallback is $($primaryModel.slug). Existing primary selection is preserved.") }
    foreach ($family in @('balanced', 'advanced', 'frontier')) {
        if ($null -eq $modelsByFamily[$family]) { $warnings.Add("No visible $family model was found; its specialist roles were omitted.") }
    }

    $agents = New-Object 'System.Collections.Generic.List[object]'
    $shared = 'Handle the bounded task in the shared workspace. Preserve other agents'' work. Do not delegate or route recursively.'
    $semanticRoles = @(
        @{ name = 'efficient_worker'; family = 'efficient'; effort = 'high'; description = 'Fast implementation for clear, bounded work.' },
        @{ name = 'efficient_max_worker'; family = 'efficient'; effort = 'max'; description = 'Deep implementation for large, precise work.' },
        @{ name = 'balanced_engineer'; family = 'balanced'; effort = 'high'; description = 'Engineering across connected layers.' },
        @{ name = 'balanced_max_engineer'; family = 'balanced'; effort = 'max'; description = 'Hard but bounded engineering work.' },
        @{ name = 'deep_architect'; family = 'advanced'; effort = 'xhigh'; description = 'Root-cause and architecture analysis.' },
        @{ name = 'deep_max_architect'; family = 'advanced'; effort = 'max'; description = 'Maximum-depth architecture work.' },
        @{ name = 'frontier_architect'; family = 'frontier'; effort = 'high'; description = 'Complex, demanding frontier work.' },
        @{ name = 'frontier_max_architect'; family = 'frontier'; effort = 'max'; description = 'Maximum-depth frontier work.' }
    )
    foreach ($role in $semanticRoles) {
        $model = $modelsByFamily[$role.family]
        if ($null -ne $model) {
            $agent = New-RouterAgent -Name $role.name -Model $model -RequestedEffort $role.effort -Description $role.description -Instructions $shared -Warnings $warnings
            if ($null -ne $agent) { $agents.Add($agent) }
        }
    }

    # Expose every level the current catalogue actually supports.  Semantic roles
    # above remain stable; these roles make new or reduced effort sets selectable.
    foreach ($family in @('efficient', 'balanced', 'advanced', 'frontier')) {
        $model = $modelsByFamily[$family]
        if ($null -eq $model) { continue }
        foreach ($effort in @(Get-RouterSupportedEfforts $model)) {
            $name = "$family`_$effort"
            $instructions = $shared
            if ($family -eq 'frontier' -and $effort -eq 'ultra') {
                $instructions = 'Handle the bounded task in the shared workspace. Preserve other agents'' work. Do not spawn nested agents unless the user explicitly authorizes it.'
            }
            $agents.Add([pscustomobject]@{ name = $name; model = [string]$model.slug; effort = $effort; description = "$family specialist at $effort reasoning."; instructions = $instructions })
        }
    }

    # Exact roles retain every visible model, including older versions and unknown
    # families. A suggested upgrade does not remove an explicitly selectable model.
    $exactNames = @{}
    foreach ($model in @($visible | Sort-Object slug -Unique)) {
        $slug = [string]$model.slug
        $stem = 'model_' + [regex]::Replace($slug.ToLowerInvariant(), '[^a-z0-9_]', '_')
        foreach ($effort in @(Get-RouterSupportedEfforts $model)) {
            $name = $stem + '_' + $effort
            if ($exactNames.ContainsKey($name)) { throw "Conflicting normalized model names: $slug and $($exactNames[$name])." }
            $exactNames[$name] = $slug
            $agents.Add([pscustomobject]@{name=$name;model=$slug;effort=$effort;description="Exact $slug / $effort. Use for an explicit model request.";instructions=$shared})
        }
    }

    $ultraModel = $null
    foreach ($family in @('frontier', 'advanced', 'balanced')) {
        $candidate = $modelsByFamily[$family]
        if ($null -ne $candidate -and (Get-RouterSupportedEfforts $candidate) -contains 'ultra') { $ultraModel = $candidate; break }
    }
    if ($null -eq $ultraModel) {
        foreach ($family in @('frontier', 'advanced', 'balanced', 'efficient')) {
            if ($null -ne $modelsByFamily[$family]) { $ultraModel = $modelsByFamily[$family]; break }
        }
        if ($null -ne $ultraModel) { $warnings.Add("No selected upper-tier model supports ultra; ultra_orchestrator uses max on $($ultraModel.slug).") }
    }
    if ($null -ne $ultraModel) {
        $ultraEffort = if ((Get-RouterSupportedEfforts $ultraModel) -contains 'ultra') { 'ultra' } else { Select-RouterEffort -Model $ultraModel -Requested 'max' }
        if ($null -ne $ultraEffort) {
            $agents.Add([pscustomobject]@{
                name = 'ultra_orchestrator'; model = [string]$ultraModel.slug; effort = $ultraEffort
                description = 'Coordinates difficult work that cleanly separates.'
                instructions = 'Coordinate only when independently useful. Create at most 2 bounded child tasks, preserve shared ownership, and do not route recursively.'
            })
        }
    }

    $primaryEffort = Select-RouterEffort -Model $primaryModel -Requested 'high'
    $primary = [pscustomobject]@{ model = [string]$primaryModel.slug; effort = $primaryEffort }
    $agentArray = $agents.ToArray()
    $warningArray = $warnings.ToArray()
    return [pscustomobject]@{
        primary = $primary
        families = [pscustomobject]$families
        agents = $agentArray
        warnings = $warningArray
    }
}
