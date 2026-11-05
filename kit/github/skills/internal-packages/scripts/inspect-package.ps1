# inspect-package.ps1 - API digests for company-internal NuGet packages (internal-packages skill).
# Works offline from the local NuGet cache: nuspec metadata, XML documentation, public API (metadata reader,
# PowerShell 7+) and how this solution already uses each package.
# Writes docs/ai/packages/<Id>.md (a "Notes for agents" section is preserved across runs)
# and refreshes the table in docs/ai/internal-packages.md.
# Examples:
#   pwsh -NoProfile -File .github/skills/internal-packages/scripts/inspect-package.ps1 -ListOnly
#   ... inspect-package.ps1 -AllInternal
#   ... inspect-package.ps1 -PackageId Acme.Platform.Messaging
# Run 'dotnet restore' first so the packages are in the local cache.
[CmdletBinding()]
param(
    [string[]]$PackageId,
    [switch]$AllInternal,
    [switch]$ListOnly,
    [string]$OutDir = 'docs/ai/packages',
    [int]$MaxTypes = 60,
    [int]$MaxMembers = 12,
    [switch]$NoUsages
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitDotnet.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$cfg = Get-KitConfig -Root $root
$nugetCache = Get-KitNuGetGlobalFolder -Root $root -AskDotnet
$outFull = Join-Path $root $OutDir

function Get-TfmRank {
    param([string]$Tfm)
    $t = $Tfm.ToLowerInvariant()
    $m = [regex]::Match($t, '^net(\d+)\.(\d+)')
    if ($m.Success) { return 1000 + [int]$m.Groups[1].Value * 10 + [int]$m.Groups[2].Value }
    $m = [regex]::Match($t, '^netstandard(\d)\.(\d)')
    if ($m.Success) { return 500 + [int]$m.Groups[1].Value * 10 + [int]$m.Groups[2].Value }
    $m = [regex]::Match($t, '^netcoreapp(\d)\.(\d)')
    if ($m.Success) { return 400 + [int]$m.Groups[1].Value * 10 + [int]$m.Groups[2].Value }
    $m = [regex]::Match($t, '^net(\d)(\d)(\d)?$')
    if ($m.Success) { return 100 + [int]$m.Groups[1].Value * 10 + [int]$m.Groups[2].Value }
    return 0
}

function Convert-DocNode {
    param($Node)
    if ($null -eq $Node) { return '' }
    $clone = $Node.Clone()
    foreach ($see in @($clone.SelectNodes('.//see|.//seealso|.//paramref|.//typeparamref'))) {
        $label = $see.GetAttribute('cref')
        if (-not $label) { $label = $see.GetAttribute('name') }
        if (-not $label) { $label = $see.GetAttribute('langword') }
        $label = ($label -replace '^[A-Z]:', '') -replace '\(.*$', ''
        $label = ($label -split '\.')[-1] -replace '`\d+', ''
        [void]$see.ParentNode.ReplaceChild($clone.OwnerDocument.CreateTextNode($label), $see)
    }
    $t = ($clone.InnerText -replace '\s+', ' ').Trim()
    if ($t.Length -gt 220) { $t = $t.Substring(0, 220) + '...' }
    return $t
}

function Read-XmlDocs {
    # Map: member id (T:/M:/P:/E:/F:) -> summary text
    param([string]$Path)
    $map = @{}
    try {
        $x = New-Object System.Xml.XmlDocument
        $x.Load($Path)
        foreach ($m in $x.SelectNodes('/doc/members/member')) { $map[$m.GetAttribute('name')] = Convert-DocNode -Node $m.SelectSingleNode('summary') }
    } catch { }
    return $map
}

function Format-TypeName {
    param([string]$Name)
    return ($Name -replace '`(\d+)', '<T$1>')
}

function Get-PublicApi {
    # Public types and members via System.Reflection.Metadata (PowerShell 7+ only). $null when unavailable.
    param([string]$Dll)
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $null }
    try { Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction SilentlyContinue } catch { }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($Dll)
        $pe = New-Object System.Reflection.PortableExecutable.PEReader($fs)
        if (-not $pe.HasMetadata) { return $null }
        $md = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
        $publicType = [int][System.Reflection.TypeAttributes]::Public
        $publicMember = [int][System.Reflection.MethodAttributes]::Public
        $types = New-Object System.Collections.Generic.List[object]
        foreach ($h in $md.TypeDefinitions) {
            $td = $md.GetTypeDefinition($h)
            if (([int]($td.Attributes -band [System.Reflection.TypeAttributes]::VisibilityMask)) -ne $publicType) { continue }
            $name = $md.GetString($td.Name)
            if ($name.StartsWith('<')) { continue }
            $ns = $md.GetString($td.Namespace)
            $kind = 'class'
            $attrs = [int]$td.Attributes
            if (($attrs -band [int][System.Reflection.TypeAttributes]::Interface) -ne 0) { $kind = 'interface' }
            else {
                $bt = $td.BaseType
                if (-not $bt.IsNil -and [string]$bt.Kind -eq 'TypeReference') {
                    $tr = $md.GetTypeReference([System.Reflection.Metadata.TypeReferenceHandle]$bt)
                    $btName = $md.GetString($tr.Name)
                    if ($btName -eq 'Enum') { $kind = 'enum' } elseif ($btName -eq 'ValueType') { $kind = 'struct' } elseif ($btName -eq 'MulticastDelegate') { $kind = 'delegate' }
                }
                if ($kind -eq 'class') {
                    $isAbstract = ($attrs -band [int][System.Reflection.TypeAttributes]::Abstract) -ne 0
                    $isSealed = ($attrs -band [int][System.Reflection.TypeAttributes]::Sealed) -ne 0
                    if ($isAbstract -and $isSealed) { $kind = 'static class' } elseif ($isAbstract) { $kind = 'abstract class' }
                }
            }
            $members = New-Object System.Collections.Generic.List[string]
            if ($kind -ne 'enum' -and $kind -ne 'delegate') {
                foreach ($mh in $td.GetMethods()) {
                    $m = $md.GetMethodDefinition($mh)
                    if (([int]($m.Attributes -band [System.Reflection.MethodAttributes]::MemberAccessMask)) -ne $publicMember) { continue }
                    $mn = $md.GetString($m.Name)
                    if ($mn -match '^(get_|set_|add_|remove_|op_)' -or $mn -eq '.cctor') { continue }
                    if ($mn -eq '.ctor') { $mn = 'ctor' }
                    $entry = $mn + '()'
                    if (-not $members.Contains($entry)) { $members.Add($entry) }
                }
                foreach ($ph in $td.GetProperties()) {
                    $pd = $md.GetPropertyDefinition($ph)
                    $getter = $pd.GetAccessors().Getter
                    if ($getter.IsNil) { continue }
                    $gm = $md.GetMethodDefinition($getter)
                    if (([int]($gm.Attributes -band [System.Reflection.MethodAttributes]::MemberAccessMask)) -ne $publicMember) { continue }
                    $members.Add($md.GetString($pd.Name))
                }
            }
            $types.Add([pscustomobject]@{ Namespace = $ns; Name = $name; Kind = $kind; Members = $members.ToArray() })
        }
        return ,$types.ToArray()
    } catch {
        return $null
    } finally {
        if ($fs) { $fs.Dispose() }
    }
}

# ============================================================================ resolve packages
$graph = Get-KitProjectGraph -Root $root
$resolved = @{}
$restoreSources = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$assetsFound = 0
foreach ($p in $graph) {
    $assets = Join-Path $p.Dir 'obj/project.assets.json'
    if (-not (Test-Path -LiteralPath $assets)) { continue }
    $assetsFound++
    $text = Read-KitTextFile -Path $assets
    # Regex extraction instead of ConvertFrom-Json: assets files can be several MB (slow or too big for PowerShell 5.1).
    $direct = @{}
    foreach ($m in [regex]::Matches($text, '"(?<id>[A-Za-z0-9_.\-]+)":\s*\{[^{}]*?"target":\s*"Package"')) { $direct[$m.Groups['id'].Value] = $true }
    # "sources": { "<feed>": {}, "<feed>": { "protocolVersion": 3 } }: each feed maps to an object, so allow one nesting level.
    $srcBlock = [regex]::Match($text, '"sources":\s*\{(?<body>(?:[^{}]|\{[^{}]*\})*)\}')
    if ($srcBlock.Success) {
        foreach ($m in [regex]::Matches($srcBlock.Groups['body'].Value, '"(?<src>[^"]+)":\s*\{')) {
            [void]$restoreSources.Add(($m.Groups['src'].Value -replace '\\\\', '\' -replace '\\/', '/'))
        }
    }
    foreach ($m in [regex]::Matches($text, '"(?<id>[A-Za-z0-9_.\-]+)/(?<ver>[0-9][A-Za-z0-9_.\-+]*)":\s*\{\s*"sha512"[^{}]*?"path":\s*"(?<path>[^"]+)"')) {
        $id = $m.Groups['id'].Value
        if (-not $resolved.ContainsKey($id)) {
            $resolved[$id] = [pscustomobject]@{ Id = $id; Version = $m.Groups['ver'].Value; RelPath = $m.Groups['path'].Value; Direct = $false; Projects = (New-Object System.Collections.Generic.List[string]); Origin = ''; Source = '' }
        }
        if ($direct.ContainsKey($id)) {
            $e = $resolved[$id]
            $e.Direct = $true
            if (-not $e.Projects.Contains($p.Name)) { $e.Projects.Add($p.Name) }
        }
    }
}
if ($assetsFound -eq 0) {
    # Not restored: fall back to the declared PackageReferences.
    foreach ($p in $graph) {
        foreach ($k in $p.Packages) {
            if (-not $resolved.ContainsKey($k.Id)) { $resolved[$k.Id] = [pscustomobject]@{ Id = $k.Id; Version = [string]$k.Version; RelPath = ''; Direct = $true; Projects = (New-Object System.Collections.Generic.List[string]); Origin = ''; Source = '' } }
            if (-not $resolved[$k.Id].Projects.Contains($p.Name)) { $resolved[$k.Id].Projects.Add($p.Name) }
        }
    }
}
$prefixGlobs = Get-KitInternalPrefixGlobs -Config $cfg
$mappingGlobs = @()
foreach ($e in $resolved.Values) {
    $e.Source = Get-KitPackageSource -GlobalFolder $nugetCache -Id $e.Id -Versions @($e.Version)
    $e.Origin = Get-KitPackageOrigin -Id $e.Id -Source $e.Source -PrefixGlobs $prefixGlobs -MappingGlobs $mappingGlobs
}

if ($ListOnly) {
    Write-Output ('NuGet cache: ' + $nugetCache + ' | restored projects: ' + $assetsFound + '/' + $graph.Count)
    if ($assetsFound -eq 0) { Write-Output 'No obj/project.assets.json found: run dotnet restore first for exact versions and feeds.' }
    if ($restoreSources.Count -gt 0) { Write-Output ('Restore sources: ' + (@($restoreSources | Sort-Object) -join ' | ')) }
    Write-Output ''
    Write-Output 'Origin    | Direct | Package (version) | Used by'
    $listOrder = @(@{ Expression = { @('internal', 'unknown', 'public').IndexOf($_.Origin) } }, 'Id')
    foreach ($e in ($resolved.Values | Sort-Object -Property $listOrder)) {
        if ($e.Origin -eq 'public' -and -not $e.Direct) { continue }
        $directText = 'transitive'
        if ($e.Direct) { $directText = 'direct' }
        Write-Output ('{0,-9} | {1,-10} | {2} ({3}) | {4}' -f $e.Origin, $directText, $e.Id, $e.Version, ($e.Projects -join ', '))
    }
    exit 0
}

$selected = New-Object System.Collections.Generic.List[object]
if ($PackageId) {
    foreach ($id in $PackageId) {
        $hit = $resolved[$id]
        if ($hit) { $selected.Add($hit) } else { $selected.Add([pscustomobject]@{ Id = $id; Version = ''; RelPath = ''; Direct = $false; Projects = (New-Object System.Collections.Generic.List[string]); Origin = 'requested'; Source = '' }) }
    }
} elseif ($AllInternal) {
    foreach ($e in ($resolved.Values | Where-Object { $_.Origin -eq 'internal' } | Sort-Object Id)) { $selected.Add($e) }
    if ($selected.Count -eq 0) {
        Write-Output 'No package classified as internal. Run with -ListOnly, then set internalPackages.prefixes in .github/kit/config.json (e.g. ["Acme.*"]) or pass -PackageId.'
        exit 0
    }
} else {
    Write-Output 'Specify -PackageId <id>, -AllInternal or -ListOnly.'
    exit 1
}

# ============================================================================ usages index (once)
$csIndex = @()
if (-not $NoUsages) {
    $csIndex = @((Get-KitRepoFiles -Root $root -Patterns @('*.cs') -Max 8000) | Where-Object { $_ -notmatch '[\\/](obj|bin)[\\/]' })
}
$fileTexts = @{}
function Get-FileText {
    param([string]$Path)
    if (-not $fileTexts.ContainsKey($Path)) { try { $fileTexts[$Path] = [System.IO.File]::ReadAllText($Path) } catch { $fileTexts[$Path] = '' } }
    return $fileTexts[$Path]
}

# ============================================================================ digests
if (-not (Test-Path -LiteralPath $outFull)) { New-Item -ItemType Directory -Path $outFull -Force | Out-Null }
$summary = New-Object System.Collections.Generic.List[object]
foreach ($pkg in $selected) {
    $idLower = $pkg.Id.ToLowerInvariant()
    $verDir = $null
    if ($pkg.RelPath) { $verDir = Join-Path $nugetCache $pkg.RelPath }
    if ((-not $verDir -or -not (Test-Path -LiteralPath $verDir)) -and $pkg.Version) { $verDir = Join-Path $nugetCache ($idLower + '/' + $pkg.Version.ToLowerInvariant()) }
    if (-not $verDir -or -not (Test-Path -LiteralPath $verDir)) {
        $pkgRoot = Join-Path $nugetCache $idLower
        if (Test-Path -LiteralPath $pkgRoot) { $verDir = @(Get-ChildItem -Path $pkgRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName })[0] }
    }
    if (-not $verDir -or -not (Test-Path -LiteralPath $verDir)) {
        Write-Output ("SKIP $($pkg.Id): not found in the local NuGet cache ($nugetCache). Run dotnet restore (intranet feed access needed).")
        continue
    }
    if (-not $pkg.Version) { $pkg.Version = Split-Path -Path $verDir -Leaf }

    # --- nuspec
    $meta = [ordered]@{ description = ''; authors = ''; projectUrl = ''; repository = ''; tags = ''; dependencies = @() }
    $nuspec = Get-ChildItem -Path $verDir -Filter '*.nuspec' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nuspec) {
        try {
            $nx = New-Object System.Xml.XmlDocument
            $nx.Load($nuspec.FullName)
            foreach ($n in $nx.GetElementsByTagName('description')) { $meta.description = ($n.InnerText -replace '\s+', ' ').Trim(); break }
            foreach ($n in $nx.GetElementsByTagName('authors')) { $meta.authors = $n.InnerText.Trim(); break }
            foreach ($n in $nx.GetElementsByTagName('projectUrl')) { $meta.projectUrl = $n.InnerText.Trim(); break }
            foreach ($n in $nx.GetElementsByTagName('repository')) { $meta.repository = $n.GetAttribute('url'); break }
            foreach ($n in $nx.GetElementsByTagName('tags')) { $meta.tags = $n.InnerText.Trim(); break }
            $meta.dependencies = @($nx.GetElementsByTagName('dependency') | ForEach-Object { $_.GetAttribute('id') } | Where-Object { $_ } | Select-Object -Unique -First 15)
        } catch { }
    }

    # --- assemblies
    $libDir = $null
    $tfmUsed = ''
    foreach ($folder in @('lib', 'ref')) {
        $base = Join-Path $verDir $folder
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $best = @(Get-ChildItem -Path $base -Directory | Sort-Object @{ Expression = { Get-TfmRank -Tfm $_.Name } } -Descending | Select-Object -First 1)
        if ($best.Count -gt 0) { $libDir = $best[0].FullName; $tfmUsed = $folder + '/' + $best[0].Name; break }
    }
    $dlls = @()
    if ($libDir) { $dlls = @(Get-ChildItem -Path $libDir -Filter '*.dll' -File) }
    $docs = @{}
    $docFiles = 0
    $api = New-Object System.Collections.Generic.List[object]
    $apiAvailable = $false
    foreach ($dll in $dlls) {
        $xmlPath = [System.IO.Path]::ChangeExtension($dll.FullName, '.xml')
        if (Test-Path -LiteralPath $xmlPath) { $docFiles++; $d = Read-XmlDocs -Path $xmlPath; foreach ($k in $d.Keys) { $docs[$k] = $d[$k] } }
        $types = Get-PublicApi -Dll $dll.FullName
        if ($null -ne $types) { $apiAvailable = $true; foreach ($t in $types) { $api.Add($t) } }
    }
    if (-not $apiAvailable) {
        # Build the type list from the XML documentation instead.
        foreach ($k in @($docs.Keys | Where-Object { $_ -like 'T:*' })) {
            $full = $k.Substring(2)
            $i = $full.LastIndexOf('.')
            $ns = ''
            $nm = $full
            if ($i -gt 0) { $ns = $full.Substring(0, $i); $nm = $full.Substring($i + 1) }
            $prefix = 'M:' + $full + '.'
            $propPrefix = 'P:' + $full + '.'
            $members = @($docs.Keys | Where-Object { $_.StartsWith($prefix) -or $_.StartsWith($propPrefix) } | ForEach-Object { $_.Substring(2 + $full.Length + 1) -replace '\(.*$', '()' -replace '#ctor', 'ctor' } | Select-Object -Unique)
            $api.Add([pscustomobject]@{ Namespace = $ns; Name = $nm; Kind = 'type'; Members = $members })
        }
    }

    $memberDocs = @{}
    foreach ($k in $docs.Keys) {
        if ($k -match '^[MPEF]:') {
            $short = ($k.Substring(2) -replace '\(.*$', '') -replace '#ctor', 'ctor'
            if (-not $memberDocs.ContainsKey($short) -and $docs[$k]) { $memberDocs[$short] = $docs[$k] }
        }
    }

    # --- usages in this solution
    $namespaces = @($api | ForEach-Object { $_.Namespace } | Where-Object { $_ } | Select-Object -Unique)
    if ($namespaces.Count -eq 0) { $namespaces = @($pkg.Id) }
    $typeNames = @($api | ForEach-Object { $_.Name -replace '`\d+$', '' } | Where-Object { $_ -and $_.Length -gt 2 } | Select-Object -Unique)
    $usage = @{}
    $examples = @{}
    $usingFiles = New-Object System.Collections.Generic.List[string]
    if (-not $NoUsages -and $csIndex.Count -gt 0) {
        $nsAlternation = ($namespaces | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $usingRx = New-Object System.Text.RegularExpressions.Regex(('(?m)^\s*(global\s+)?using\s+(static\s+)?(' + $nsAlternation + ')(\.[\w.]+)?\s*;|\b(' + $nsAlternation + ')\.[A-Z]\w*'))
        $typeRx = $null
        if ($typeNames.Count -gt 0) { $typeRx = New-Object System.Text.RegularExpressions.Regex(('\b(' + (@($typeNames | Select-Object -First 400 | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b')) }
        foreach ($f in $csIndex) {
            $text = Get-FileText -Path $f
            if (-not $text -or -not $usingRx.IsMatch($text)) { continue }
            $usingFiles.Add($f)
            if ($null -eq $typeRx) { continue }
            $lines = $text -split "\r?\n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line -match '^\s*(using|//|\*|///)') { continue }
                foreach ($m in $typeRx.Matches($line)) {
                    $tn = $m.Value
                    if ($usage.ContainsKey($tn)) { $usage[$tn] = $usage[$tn] + 1 } else { $usage[$tn] = 1 }
                    if (-not $examples.ContainsKey($tn)) { $examples[$tn] = New-Object System.Collections.Generic.List[string] }
                    if ($examples[$tn].Count -lt 2) {
                        $code = $line.Trim()
                        if ($code.Length -gt 120) { $code = $code.Substring(0, 120) + '...' }
                        $examples[$tn].Add(('{0}:{1} `{2}`' -f (Get-KitRelativePath -Path $f -Root $root), ($i + 1), ($code -replace '`', "'")))
                    }
                }
            }
        }
    }

    # --- markdown
    $digestPath = Join-Path $outFull ($pkg.Id + '.md')
    $notes = "- (none yet) Add non-obvious rules here: lifetimes, required configuration, pitfalls, preferred overloads."
    $old = Read-KitTextFile -Path $digestPath
    if ($old) {
        $nm = [regex]::Match($old, '(?s)<!-- kit:notes:start -->\s*(.*?)\s*<!-- kit:notes:end -->')
        if ($nm.Success -and $nm.Groups[1].Value.Trim()) { $notes = $nm.Groups[1].Value.Trim() }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# $($pkg.Id) $($pkg.Version) - internal package digest")
    [void]$sb.AppendLine('<!-- Generated by inspect-package.ps1 on ' + (Get-Date).ToString('yyyy-MM-dd') + '. Regenerate after upgrades; only the "Notes for agents" section is preserved. -->')
    [void]$sb.AppendLine('')
    $desc = $meta.description
    if (-not $desc) { $desc = '(no description in the nuspec)' }
    [void]$sb.AppendLine("- Description: $desc")
    $feed = $pkg.Source
    if (-not $feed) { $feed = 'unknown' }
    [void]$sb.AppendLine(('- Feed: {0} | Authors: {1} | Assets: {2}' -f $feed, $meta.authors, $tfmUsed))
    if ($meta.projectUrl -or $meta.repository) { [void]$sb.AppendLine(('- Links: {0} {1}' -f $meta.projectUrl, $meta.repository).TrimEnd()) }
    $usedBy = 'not referenced directly'
    if ($pkg.Projects.Count -gt 0) { $usedBy = ($pkg.Projects -join ', ') }
    [void]$sb.AppendLine("- Referenced directly by: $usedBy")
    if (@($meta.dependencies).Count -gt 0) { [void]$sb.AppendLine('- Depends on: ' + (@($meta.dependencies) -join ', ')) }
    $apiSource = 'XML documentation only (run with PowerShell 7 for the full public API)'
    if ($apiAvailable) { $apiSource = 'assembly metadata' }
    if (-not $apiAvailable -and $docFiles -eq 0) { $apiSource = 'none: no XML documentation and PowerShell 7 not available' }
    [void]$sb.AppendLine("- API listing source: $apiSource | XML doc files: $docFiles")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## How this solution uses it')
    if ($usingFiles.Count -eq 0) {
        [void]$sb.AppendLine('No usage found in the solution source (or usage scan disabled).')
    } else {
        [void]$sb.AppendLine("$($usingFiles.Count) file(s) use it. Most used types:")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Type | Uses | Examples |')
        [void]$sb.AppendLine('|---|---|---|')
        foreach ($kv in ($usage.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15)) {
            [void]$sb.AppendLine(('| `{0}` | {1} | {2} |' -f $kv.Key, $kv.Value, (($examples[$kv.Key] -join '<br>') -replace '\|', '\|')))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Public API (key types)')
    $usageOf = { param($t) $n = $t.Name -replace '`\d+$', ''; if ($usage.ContainsKey($n)) { return $usage[$n] }; return 0 }
    $priority = @(
        @{ Expression = { & $usageOf $_ }; Descending = $true },
        @{ Expression = { if ($docs.ContainsKey('T:' + $_.Namespace + '.' + $_.Name)) { 0 } else { 1 } } },
        'Namespace',
        'Name'
    )
    $top = @($api | Sort-Object -Property $priority | Select-Object -First $MaxTypes)
    $grouping = @('Namespace', @{ Expression = { & $usageOf $_ }; Descending = $true }, 'Name')
    $ordered = @($top | Sort-Object -Property $grouping)
    $currentNs = $null
    foreach ($t in $ordered) {
        if ($t.Namespace -ne $currentNs) { $currentNs = $t.Namespace; [void]$sb.AppendLine(''); [void]$sb.AppendLine("### $currentNs") }
        $sum = ''
        $docKey = 'T:' + $t.Namespace + '.' + $t.Name
        if ($t.Namespace -eq '') { $docKey = 'T:' + $t.Name }
        if ($docs.ContainsKey($docKey) -and $docs[$docKey]) { $sum = ' - ' + $docs[$docKey] }
        [void]$sb.AppendLine(('- `{0}` ({1}){2}' -f (Format-TypeName $t.Name), $t.Kind, $sum))
        $shown = 0
        foreach ($mem in @($t.Members)) {
            if ($shown -ge $MaxMembers) { [void]$sb.AppendLine(('  - ... +{0} more' -f (@($t.Members).Count - $MaxMembers))); break }
            $mdoc = ''
            $memName = $mem -replace '\(\)$', ''
            $memFull = $t.Namespace + '.' + $t.Name + '.' + $memName
            if ($t.Namespace -eq '') { $memFull = $t.Name + '.' + $memName }
            if ($memberDocs.ContainsKey($memFull)) { $mdoc = ' - ' + $memberDocs[$memFull] }
            [void]$sb.AppendLine(('  - `{0}`{1}' -f $mem, $mdoc))
            $shown++
        }
    }
    if ($api.Count -gt $MaxTypes) { [void]$sb.AppendLine(''); [void]$sb.AppendLine(('_{0} more public types not listed (raise -MaxTypes)._' -f ($api.Count - $MaxTypes))) }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Notes for agents (curated, preserved)')
    [void]$sb.AppendLine('<!-- kit:notes:start -->')
    [void]$sb.AppendLine($notes)
    [void]$sb.AppendLine('<!-- kit:notes:end -->')
    Write-KitTextFile -Path $digestPath -Text $sb.ToString()
    $purpose = $meta.description
    $dot = $purpose.IndexOf('. ')
    if ($dot -gt 0) { $purpose = $purpose.Substring(0, $dot + 1) }
    if ($purpose.Length -gt 110) { $purpose = $purpose.Substring(0, 110) + '...' }
    $summary.Add([pscustomobject]@{ Id = $pkg.Id; Version = $pkg.Version; UsedBy = $usedBy; Purpose = $purpose; Digest = ($OutDir.TrimEnd('/') + '/' + $pkg.Id + '.md'); Types = $api.Count; Files = $usingFiles.Count })
    Write-Output ('OK   {0} {1}: {2} public types, used in {3} file(s) -> {4}' -f $pkg.Id, $pkg.Version, $api.Count, $usingFiles.Count, (Get-KitRelativePath -Path $digestPath -Root $root))
}

# ============================================================================ index
if ($summary.Count -gt 0) {
    $indexPath = Join-Path $root 'docs/ai/internal-packages.md'
    $index = Read-KitTextFile -Path $indexPath
    if (-not $index) { $index = "# Internal packages`n`nCompany packages from the intranet feed. Read the digest before using a package; never guess an API.`n" }
    $rows = New-Object System.Text.StringBuilder
    [void]$rows.AppendLine('<!-- kit:packages:start -->')
    [void]$rows.AppendLine('| Package | Version | Used by | Purpose | Digest |')
    [void]$rows.AppendLine('|---|---|---|---|---|')
    $existing = @{}
    $em = [regex]::Match($index, '(?s)<!-- kit:packages:start -->(.*?)<!-- kit:packages:end -->')
    if ($em.Success) {
        foreach ($line in ($em.Groups[1].Value -split "\r?\n")) {
            $cm = [regex]::Match($line, '^\|\s*`?(?<id>[A-Za-z0-9_.\-]+)`?\s*\|')
            if ($cm.Success -and $cm.Groups['id'].Value -ne 'Package' -and $cm.Groups['id'].Value -notmatch '^-+$') { $existing[$cm.Groups['id'].Value] = $line }
        }
    }
    foreach ($s in $summary) { $existing[$s.Id] = ('| `{0}` | {1} | {2} | {3} | [digest]({4}) |' -f $s.Id, $s.Version, $s.UsedBy, ($s.Purpose -replace '\|', '/'), ($s.Digest -replace '^docs/ai/', '')) }
    foreach ($k in ($existing.Keys | Sort-Object)) { [void]$rows.AppendLine($existing[$k]) }
    [void]$rows.Append('<!-- kit:packages:end -->')
    if ($em.Success) { $index = $index.Substring(0, $em.Index) + $rows.ToString() + $index.Substring($em.Index + $em.Length) }
    else { $index = $index.TrimEnd() + "`n`n" + $rows.ToString() + "`n" }
    Write-KitTextFile -Path $indexPath -Text $index
    Write-Output ('Index updated: docs/ai/internal-packages.md (' + $existing.Count + ' package(s))')
}
