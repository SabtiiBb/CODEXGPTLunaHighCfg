# Shared helpers. Compatible with Windows PowerShell 5.1 and PowerShell 7.
function Get-FullRouterPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'La ruta esta vacia.' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded -eq '~' -or $expanded.StartsWith('~\') -or $expanded.StartsWith('~/')) {
        $expanded = Join-Path ([Environment]::GetFolderPath('UserProfile')) ($expanded.Substring(1).TrimStart('\','/'))
    }
    $full=[IO.Path]::GetFullPath($expanded)
    if ($full -eq [IO.Path]::GetPathRoot($full)) { return $full }
    return $full.TrimEnd('\','/')
}

function Get-RouterEnvironmentHome {
    foreach ($scope in @('Process','User','Machine')) {
        $value = [Environment]::GetEnvironmentVariable('CODEX_HOME', $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}
function Get-RouterDefaultProfile { return [Environment]::GetFolderPath('UserProfile') }
function Get-RouterDocumentHomes {
    $folders = @([Environment]::GetFolderPath('MyDocuments'),
        (Join-Path (Get-RouterDefaultProfile) 'Documents'),
        (Join-Path (Get-RouterDefaultProfile) 'Documentos'))
    foreach ($oneDriveRoot in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($oneDriveRoot) {
            $folders += Join-Path $oneDriveRoot 'Documents'
            $folders += Join-Path $oneDriveRoot 'Documentos'
        }
    }
    return @($folders | Where-Object { $_ } | ForEach-Object {
        $candidate = Join-Path $_ '.codex'
        if (Test-Path -LiteralPath (Join-Path $candidate 'config.toml') -PathType Leaf) { Get-FullRouterPath $candidate }
    } | Select-Object -Unique)
}
function Get-RouterDriveHomes {
    return @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
        $candidate = Join-Path $_.RootDirectory.FullName '.codex'
        if (Test-Path -LiteralPath (Join-Path $candidate 'config.toml') -PathType Leaf) { Get-FullRouterPath $candidate }
    } | Select-Object -Unique)
}
function Resolve-RouterHome([string]$ExplicitPath, [string]$InstalledScriptRoot) {
    if ($ExplicitPath) { return Get-FullRouterPath $ExplicitPath }
    $configured=Get-RouterEnvironmentHome
    if ($configured) { return Get-FullRouterPath $configured }
    if ($InstalledScriptRoot -and (Test-Path -LiteralPath (Join-Path $InstalledScriptRoot 'installation.json'))) {
        $saved = Read-RouterJson (Join-Path $InstalledScriptRoot 'installation.json')
        return Get-FullRouterPath $saved.codex_home
    }
    $standard = Join-Path (Get-RouterDefaultProfile) '.codex'
    if (Test-Path -LiteralPath (Join-Path $standard 'config.toml') -PathType Leaf) { return Get-FullRouterPath $standard }
    $candidates = @(@(Get-RouterDocumentHomes) + @(Get-RouterDriveHomes) | Select-Object -Unique)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) { throw "Hay varias instalaciones: $($candidates -join ', '). Indica -CodexHome <ruta>." }
    return Get-FullRouterPath $standard
}

function Read-RouterText([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [IO.File]::ReadAllText($Path) }
    return ''
}
function Read-RouterJson([string]$Path) { return (Read-RouterText $Path | ConvertFrom-Json) }
function Write-RouterText([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function ConvertTo-RouterTomlString([string]$Text) {
    return '"' + $Text.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n').Replace("`t",'\t') + '"'
}

# Walk TOML string state so headers or keys inside multiline instructions are never edited.
function Get-RouterTomlLines([string]$Text) {
    $section = ''; $mode = ''; $records = @()
    foreach ($line in [regex]::Split($Text, '\r?\n')) {
        $outside = ($mode -eq '')
        if ($outside -and $line -match '^\s*\[([^\[\]]+)\]\s*(?:#.*)?$') { $section = $Matches[1].Trim() }
        elseif ($outside -and $line -match '^\s*\[\[') { $section = '<array-table>' }
        $records += [PSCustomObject]@{ Text=$line; Section=$section; Outside=$outside }
        for ($i=0; $i -lt $line.Length; $i++) {
            $c = $line[$i]
            $triple = if ($i+2 -lt $line.Length) { $line.Substring($i,3) } else { '' }
            if ($mode -eq 'basic3') {
                if ($c -eq '\') { $i++; continue }
                if ($triple -eq '"""') { $mode=''; $i+=2 }
            } elseif ($mode -eq 'literal3') {
                if ($triple -eq "'''") { $mode=''; $i+=2 }
            } elseif ($mode -eq 'basic') {
                if ($c -eq '\') { $i++; continue }
                if ($c -eq '"') { $mode='' }
            } elseif ($mode -eq 'literal') {
                if ($c -eq "'") { $mode='' }
            } else {
                if ($c -eq '#') { break }
                if ($triple -eq '"""') { $mode='basic3'; $i+=2 }
                elseif ($triple -eq "'''") { $mode='literal3'; $i+=2 }
                elseif ($c -eq '"') { $mode='basic' }
                elseif ($c -eq "'") { $mode='literal' }
            }
        }
        if ($mode -eq 'basic' -or $mode -eq 'literal') { throw 'config.toml contiene una cadena sin cerrar.' }
    }
    if ($mode) { throw 'config.toml contiene una cadena multilinea sin cerrar.' }
    return $records
}

function Set-RouterTomlValues([string]$Text, [string]$Section, [System.Collections.IDictionary]$Values) {
    $records = @(Get-RouterTomlLines $Text)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($record in $records) { $lines.Add($record.Text) }
    $start = 0; $end = $records.Count; $headers = 0
    if ($Section) {
        $start = -1
        for ($i=0; $i -lt $records.Count; $i++) {
            if ($records[$i].Outside -and $records[$i].Text -match ('^\s*\['+[regex]::Escape($Section)+'\]\s*(?:#.*)?$')) { $start=$i+1; $headers++ }
            elseif ($records[$i].Outside -and $records[$i].Text -match ('^\s*\[\s*["'']'+[regex]::Escape($Section)+'["'']\s*\]')) {
                throw "La tabla [$Section] usa una forma citada no soportada. No se modifico la configuracion."
            }
        }
        if ($headers -gt 1) { throw "Tabla [$Section] duplicada." }
        if ($start -eq -1) { $lines.Add(''); $lines.Add("[$Section]"); foreach ($key in $Values.Keys) { $lines.Add("$key = $($Values[$key])") }; return ($lines -join "`r`n") }
    }
    for ($i=$start; $i -lt $records.Count; $i++) {
        if ($records[$i].Outside -and $records[$i].Text -match '^\s*\[') { $end=$i; break }
    }
    $missing = @()
    foreach ($key in $Values.Keys) {
        $found = @()
        for ($i=$start; $i -lt $end; $i++) {
            if ($records[$i].Outside -and $records[$i].Text -match ('^\s*(?:'+[regex]::Escape($key)+'|"'+[regex]::Escape($key)+'"|'''+[regex]::Escape($key)+''')\s*=')) { $found += $i }
        }
        if ($found.Count -gt 1) { throw "Clave $key duplicada en [$Section]." }
        if ($found.Count -eq 1) { $lines[$found[0]] = "$key = $($Values[$key])" }
        else { $missing += "$key = $($Values[$key])" }
    }
    for ($i=$missing.Count-1; $i -ge 0; $i--) { $lines.Insert($start,$missing[$i]) }
    return ($lines -join "`r`n")
}

function Merge-RouterInstructions([string]$Existing, [string]$Block) {
    $startCount = [regex]::Matches($Existing, '<!-- CODEX_AUTOROUTER_V\d+_START -->').Count
    $pattern = '(?s)<!-- CODEX_AUTOROUTER_V(\d+)_START -->.*?<!-- CODEX_AUTOROUTER_V\1_END -->'
    $matchesFound = [regex]::Matches($Existing,$pattern)
    if ($matchesFound.Count -ne $startCount -or [regex]::Matches($Existing,'<!-- CODEX_AUTOROUTER_V\d+_END -->').Count -ne $startCount) { throw 'Los marcadores del router en AGENTS.md estan incompletos.' }
    if ($matchesFound.Count -gt 0) {
        $result=$Existing
        for ($i=$matchesFound.Count-1; $i -ge 0; $i--) {
            $replacement=if ($i -eq 0) { $Block.Trim() } else { '' }
            $result=$result.Remove($matchesFound[$i].Index,$matchesFound[$i].Length).Insert($matchesFound[$i].Index,$replacement)
        }
        return $result
    }
    if ($Existing -match '# Codex Automatic Model/Reasoning Router') { throw 'Router antiguo sin marcadores en AGENTS.md. Delimitalo antes de migrar para preservar las instrucciones personales.' }
    return ($Existing.TrimEnd()+"`r`n`r`n"+$Block.Trim()+"`r`n").TrimStart()
}

function Resolve-RouterExe([string]$ExplicitPath, [string]$TargetRoot) {
    if ($ExplicitPath) {
        $resolved = Get-FullRouterPath $ExplicitPath
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "No existe CodexExe: $resolved" }
        return $resolved
    }
    if ($env:CODEX_CLI_PATH -and (Test-Path -LiteralPath $env:CODEX_CLI_PATH -PathType Leaf)) { return $env:CODEX_CLI_PATH }
    $cfg = Read-RouterText (Join-Path $TargetRoot 'config.toml')
    foreach ($line in @(Get-RouterTomlLines $cfg)) {
        if ($line.Outside -and $line.Text -match '^\s*CODEX_CLI_PATH\s*=\s*''([^'']+)''') {
            if (Test-Path -LiteralPath $Matches[1] -PathType Leaf) { return $Matches[1] }
        }
        if ($line.Outside -and $line.Text -match '^\s*CODEX_CLI_PATH\s*=\s*"((?:\\.|[^"\\])*)"') {
            $candidate = ('"'+$Matches[1]+'"') | ConvertFrom-Json
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    $cmd = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $binRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $binRoot) {
        $candidate = Get-ChildItem -LiteralPath $binRoot -Filter codex.exe -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        foreach ($package in @(Get-AppxPackage '*Codex*' -ErrorAction SilentlyContinue)) {
            $candidate = Get-ChildItem -LiteralPath $package.InstallLocation -Filter codex.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($candidate) { return $candidate.FullName }
        }
    }
    $installationPath=Join-Path $TargetRoot 'autorouter\installation.json'
    if (Test-Path -LiteralPath $installationPath) {
        $saved=Read-RouterJson $installationPath
        if ($saved.codex_cli_hint -and (Test-Path -LiteralPath $saved.codex_cli_hint -PathType Leaf)) { return $saved.codex_cli_hint }
    }
    throw 'No se encontro codex.exe. Abre Codex una vez o indica -CodexExe <ruta al ejecutable>.'
}

function ConvertTo-RouterArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting; never invoke a shell with interpolated commands.
    return '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}
function Invoke-RouterCli([string]$Exe, [string[]]$Arguments, [string]$TargetRoot, [int]$TimeoutSeconds=60) {
    if ([IO.Path]::GetExtension($Exe) -ne '.exe') { throw 'CodexExe debe apuntar al ejecutable .exe, no a un script de shell.' }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Exe; $info.Arguments=($Arguments | ForEach-Object { ConvertTo-RouterArgument $_ }) -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.EnvironmentVariables['CODEX_HOME']=$TargetRoot
    $process = New-Object Diagnostics.Process
    $process.StartInfo=$info
    try {
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) { $process.Kill(); $process.WaitForExit(); throw "Codex supero el limite de $TimeoutSeconds segundos." }
        $out=$stdout.GetAwaiter().GetResult(); $err=$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Codex fallo ($($process.ExitCode)): $err" }
        return $out
    } finally { $process.Dispose() }
}

function Get-RouterCatalog([string]$TargetRoot, [string]$Exe, [string]$CatalogPath, [switch]$AllowCache) {
    if ($CatalogPath) { return [PSCustomObject]@{ Document=(Read-RouterJson $CatalogPath); Source='explicit-file'; Path=(Get-FullRouterPath $CatalogPath) } }
    try {
        $raw=Invoke-RouterCli $Exe @('debug','models') $TargetRoot
        return [PSCustomObject]@{ Document=($raw | ConvertFrom-Json); Source='codex debug models'; Path=$Exe }
    } catch {
        if (-not $AllowCache) { throw }
        $cachePath=Join-Path $TargetRoot 'models_cache.json'
        $doc=Read-RouterJson $cachePath
        if (-not $doc.fetched_at -or ([DateTimeOffset]::Now - [DateTimeOffset]::Parse($doc.fetched_at)).TotalHours -gt 24) { throw 'El cache no tiene fecha valida o supera 24 horas. Abre Codex y vuelve a intentar.' }
        Write-Warning 'Consulta CLI fallida; se usa el cache local reciente (disponibilidad no verificada en vivo).'
        return [PSCustomObject]@{ Document=$doc; Source='recent-cache'; Path=$cachePath }
    }
}

function Get-RouterTaskName([string]$TargetRoot) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($TargetRoot.ToLowerInvariant())))).Replace('-','').Substring(0,12) } finally { $sha.Dispose() }
    return "Codex AutoRouter V4 - $hash"
}

# Commit only explicitly managed relative files. Backup first, rollback on any write error.
function Save-RouterChanges([string]$TargetRoot, [System.Collections.IDictionary]$Files, [System.Collections.IDictionary]$ExpectedFiles) {
    $root=Get-FullRouterPath $TargetRoot
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $lockPath=Join-Path $root 'autorouter-v4.lock'
    $lock=$null
    try {
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if ($ExpectedFiles) {
            foreach ($relative in $ExpectedFiles.Keys) {
                if ((Read-RouterText (Join-Path $root $relative)) -cne $ExpectedFiles[$relative]) { throw "Cambio concurrente en $relative. Vuelve a ejecutar." }
            }
        }
        $changes=@()
        foreach ($relative in $Files.Keys) {
            $full=[IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "Destino fuera de Codex: $relative" }
            if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Read-RouterText $full) -ceq $Files[$relative]) { continue }
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $appliedHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Files[$relative])))).Replace('-','') } finally { $sha.Dispose() }
            $changes += [PSCustomObject]@{ relative=$relative; full=$full; existed=(Test-Path -LiteralPath $full -PathType Leaf); applied_hash=$appliedHash }
        }
        if ($changes.Count -eq 0) { return $null }
        $backup=Join-Path $root ('autorouter\backups\V4_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,6))
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($change in $changes) {
            if ($change.existed) {
                $dest=Join-Path $backup $change.relative
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
                [IO.File]::Copy($change.full,$dest,$false)
            }
        }
        Write-RouterText (Join-Path $backup 'manifest.json') (([ordered]@{codex_home=$root;files=@($changes | Select-Object relative,existed,applied_hash)}) | ConvertTo-Json -Depth 5)
        $written=@()
        try {
            foreach ($change in $changes) {
                $written += $change
                Write-RouterText $change.full $Files[$change.relative]
            }
        } catch {
            $failure=$_
            foreach ($change in $written) {
                if ($change.existed) { [IO.File]::Copy((Join-Path $backup $change.relative),$change.full,$true) }
                elseif (Test-Path -LiteralPath $change.full) { [IO.File]::Delete($change.full) }
            }
            throw $failure
        }
        return $backup
    } finally { if ($lock) { $lock.Dispose() } }
}
