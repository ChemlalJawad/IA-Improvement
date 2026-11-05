# KitDotnet.ps1 - .NET helpers: project graph, layer checks, build and test with compact output.
# Requires KitCore.ps1 to be dot-sourced first. Windows PowerShell 5.1 / PowerShell 7+. ASCII-only.

function Get-KitRepoFiles {
    # Files matching git pathspecs (tracked + untracked, .gitignore respected). Falls back to a filtered tree walk.
    param([string]$Root, [string[]]$Patterns, [int]$Max = 20000)
    $list = New-Object System.Collections.Generic.List[string]
    $gitArgs = @('ls-files', '--cached', '--others', '--exclude-standard', '--') + $Patterns
    $r = Invoke-KitGit -Root $Root -Arguments $gitArgs -TimeoutSec 60
    if ($r.ExitCode -eq 0) {
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($l in $r.StdOut) {
            if (-not $l) { continue }
            $full = [System.IO.Path]::GetFullPath((Join-Path $Root $l))
            if (-not $seen.Add($full)) { continue }
            if (Test-Path -LiteralPath $full -PathType Leaf) { $list.Add($full) }
            if ($list.Count -ge $Max) { break }
        }
        return ,$list.ToArray()
    }
    $skip = '[\\/](bin|obj|node_modules|\.git|\.vs|\.ai-local|packages|TestResults)([\\/]|$)'
    foreach ($pat in $Patterns) {
        $leaf = Split-Path -Path $pat -Leaf
        foreach ($f in (Get-ChildItem -Path $Root -Filter $leaf -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($f.FullName -match $skip) { continue }
            $list.Add($f.FullName)
            if ($list.Count -ge $Max) { break }
        }
    }
    return ,$list.ToArray()
}

function ConvertTo-KitInt {
    param($Value)
    $n = 0
    if ([int]::TryParse([string]$Value, [ref]$n)) { return $n }
    return 0
}

function Format-KitMessage {
    param([string]$Text, [int]$MaxLines = 3, [int]$MaxChars = 320)
    if (-not $Text) { return '' }
    $lines = @(($Text -split "\r?\n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $t = (@($lines | Select-Object -First $MaxLines)) -join ' | '
    if ($t.Length -gt $MaxChars) { $t = $t.Substring(0, $MaxChars) + '...' }
    return $t
}

function Get-KitStackLocation {
    param([string]$Stack, [string]$Root)
    if (-not $Stack) { return '' }
    foreach ($l in ($Stack -split "\r?\n")) {
        $m = [regex]::Match($l, ' in (?<file>.+?):line (?<line>\d+)')
        if ($m.Success) { return ('{0}:{1}' -f (Get-KitRelativePath -Path $m.Groups['file'].Value -Root $Root), $m.Groups['line'].Value) }
    }
    return ''
}

# --------------------------------------------------------------------------- project graph

function Get-KitCentralPackageVersions {
    param([string]$Root)
    $map = @{}
    foreach ($f in (Get-KitRepoFiles -Root $Root -Patterns @('Directory.Packages.props', '*/Directory.Packages.props'))) {
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.Load($f)
            foreach ($n in $xml.GetElementsByTagName('PackageVersion')) {
                $id = $n.GetAttribute('Include')
                if (-not $id) { $id = $n.GetAttribute('Update') }
                $v = $n.GetAttribute('Version')
                if ($id -and $v -and -not $map.ContainsKey($id)) { $map[$id] = $v }
            }
        } catch { }
    }
    return $map
}

function Read-KitProject {
    param([string]$Path, [hashtable]$CentralVersions)
    $xml = New-Object System.Xml.XmlDocument
    try { $xml.Load($Path) } catch { return $null }
    $dir = Split-Path -Path $Path -Parent
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $sdk = [string]$xml.DocumentElement.GetAttribute('Sdk')
    if (-not $sdk) { foreach ($s in $xml.GetElementsByTagName('Sdk')) { $sdk = $s.GetAttribute('Name'); break } }
    $props = @{}
    foreach ($pg in $xml.GetElementsByTagName('PropertyGroup')) {
        foreach ($c in $pg.ChildNodes) {
            if ($c.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            if (-not $props.ContainsKey($c.LocalName)) { $props[$c.LocalName] = $c.InnerText.Trim() }
        }
    }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $refs = New-Object System.Collections.Generic.List[string]
    foreach ($n in $xml.GetElementsByTagName('ProjectReference')) {
        $inc = $n.GetAttribute('Include')
        if (-not $inc -or $inc.Contains('$(')) { continue }
        $rel = $inc.Replace('\', $sep).Replace('/', $sep)
        $refs.Add([System.IO.Path]::GetFullPath((Join-Path $dir $rel)))
    }
    $pkgs = New-Object System.Collections.Generic.List[object]
    foreach ($n in $xml.GetElementsByTagName('PackageReference')) {
        $id = $n.GetAttribute('Include')
        if (-not $id) { continue }
        $ver = $n.GetAttribute('Version')
        if (-not $ver) { $ver = $n.GetAttribute('VersionOverride') }
        if (-not $ver) { foreach ($c in $n.ChildNodes) { if ($c.LocalName -eq 'Version') { $ver = $c.InnerText.Trim() } } }
        if (-not $ver -and $CentralVersions -and $CentralVersions.ContainsKey($id)) { $ver = $CentralVersions[$id] }
        $pkgs.Add([pscustomobject]@{ Id = $id; Version = $ver })
    }
    $pkgIds = @($pkgs | ForEach-Object { $_.Id })
    $tfm = $props['TargetFramework']
    if (-not $tfm) { $tfm = $props['TargetFrameworks'] }
    $testPkgs = @($pkgIds | Where-Object { $_ -match '^(?i)(Microsoft\.NET\.Test\.Sdk|xunit|xunit\.v3|xunit\.core|NUnit|MSTest\.TestFramework|MSTest|TUnit)$' })
    $isTest = ($props['IsTestProject'] -eq 'true') -or ($sdk -match '(?i)MSTest\.Sdk') -or ($testPkgs.Count -gt 0)
    if (-not $isTest -and $name -match '(?i)(\.|^)(Unit|Integration|Functional|Acceptance|Architecture|Component|E2E)?Tests?$') { $isTest = $true }
    return [pscustomobject]@{
        Name            = $name
        FullPath        = [System.IO.Path]::GetFullPath($Path)
        Dir             = [System.IO.Path]::GetFullPath($dir)
        Sdk             = $sdk
        TargetFramework = $tfm
        OutputType      = $props['OutputType']
        RootNamespace   = $props['RootNamespace']
        AssemblyName    = $props['AssemblyName']
        References      = $refs.ToArray()
        Packages        = $pkgs.ToArray()
        IsTest          = [bool]$isTest
        Properties      = $props
    }
}

function Get-KitProjectGraph {
    param([string]$Root)
    $central = Get-KitCentralPackageVersions -Root $Root
    $projects = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-KitRepoFiles -Root $Root -Patterns @('*.csproj', '*.fsproj', '*.vbproj'))) {
        $p = Read-KitProject -Path $f -CentralVersions $central
        if ($null -ne $p) { $projects.Add($p) }
    }
    return ,$projects.ToArray()
}

function Test-KitArchitecture {
    # Human-readable layer violations (project references and forbidden packages) for the current graph.
    param($Projects, $Config)
    $violations = New-Object System.Collections.Generic.List[string]
    if (-not $Config.architecture.enabled) { return ,$violations.ToArray() }
    $layers = $Config.architecture.layers
    $byPath = @{}
    foreach ($p in @($Projects)) { $byPath[$p.FullPath.ToLowerInvariant()] = $p }
    foreach ($p in @($Projects)) {
        $from = Get-KitLayerOf -ProjectName $p.Name -Layers $layers
        if ($null -eq $from) { continue }
        foreach ($r in $p.References) {
            $target = $byPath[$r.ToLowerInvariant()]
            $targetName = [System.IO.Path]::GetFileNameWithoutExtension($r)
            if ($target) { $targetName = $target.Name }
            $to = Get-KitLayerOf -ProjectName $targetName -Layers $layers
            if (-not (Test-KitLayerReferenceAllowed -FromLayer $from -ToLayer $to)) {
                $violations.Add(('{0} ({1}) must not reference {2} ({3})' -f $p.Name, $from.name, $targetName, $to.name))
            }
        }
        foreach ($pkg in $p.Packages) {
            $hit = Find-KitForbiddenPackage -Layer $from -PackageId $pkg.Id
            if ($hit) { $violations.Add(('{0} ({1}) must not use package {2} (rule {3})' -f $p.Name, $from.name, $pkg.Id, $hit)) }
        }
    }
    return ,$violations.ToArray()
}

function Get-KitAffectedProjects {
    # Projects impacted by changed files: owners of the files plus everything that references them (transitively).
    param($Projects, [string[]]$ChangedFiles, [string]$Root)
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    $sorted = @($Projects | Sort-Object -Property @{ Expression = { $_.Dir.Length } } -Descending)
    $changed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $global = $false
    foreach ($f in @($ChangedFiles)) {
        if (-not $f) { continue }
        if ($f -match '(?i)(^|/)(Directory\.(Build|Packages)\.(props|targets)|global\.json|nuget\.config|\.editorconfig)$' -or $f -match '(?i)\.slnx?$') { $global = $true; continue }
        $full = [System.IO.Path]::GetFullPath((Join-Path $Root $f))
        foreach ($p in $sorted) {
            if ($full.StartsWith($p.Dir + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { [void]$changed.Add($p.FullPath); break }
        }
    }
    if ($global) { return [pscustomobject]@{ All = $true; Projects = @($Projects) } }
    $reverse = @{}
    foreach ($p in @($Projects)) {
        foreach ($r in $p.References) {
            $k = $r.ToLowerInvariant()
            if (-not $reverse.ContainsKey($k)) { $reverse[$k] = New-Object System.Collections.Generic.List[string] }
            $reverse[$k].Add($p.FullPath)
        }
    }
    $affected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($c in $changed) { [void]$affected.Add($c); $queue.Enqueue($c) }
    while ($queue.Count -gt 0) {
        $k = $queue.Dequeue().ToLowerInvariant()
        if ($reverse.ContainsKey($k)) { foreach ($dep in $reverse[$k]) { if ($affected.Add($dep)) { $queue.Enqueue($dep) } } }
    }
    return [pscustomobject]@{ All = $false; Projects = @($Projects | Where-Object { $affected.Contains($_.FullPath) }) }
}

# --------------------------------------------------------------------------- packages (origin)

# Well-known public package prefixes: never classified as internal, even when restored through an intranet feed
# that proxies nuget.org (Azure Artifacts upstream sources).
$script:KitKnownPublicPackages = '^(?i)(Microsoft\.|System\.|Azure\.|AspNetCore\.|Newtonsoft\.|xunit|NUnit|MSTest|coverlet|FluentAssertions|AwesomeAssertions|Shouldly|NSubstitute|Moq|FakeItEasy|Bogus|AutoFixture|Testcontainers|Respawn|WireMock|Verify|BenchmarkDotNet|FluentValidation|AutoMapper|Mapster|Riok\.Mapperly|MediatR|Mediator\.|WolverineFx|Serilog|NLog|OpenTelemetry|Polly|Swashbuckle|NSwag|Scalar\.|Asp\.Versioning|FastEndpoints|Carter|ErrorOr|OneOf|Ardalis\.|FluentResults|CSharpFunctionalExtensions|Dapper|Npgsql|Pomelo\.|Oracle\.|MySql|MongoDB\.|StackExchange\.|Humanizer|Hangfire|Quartz|MassTransit|NServiceBus|Rebus|Refit|RestSharp|Scrutor|Duende\.|IdentityModel|Grpc\.|Google\.|AWSSDK\.|Aspire\.|Hellang\.|JetBrains\.|StyleCop\.|SonarAnalyzer|Roslynator|Meziantou|AsyncFixer|NetArchTest|TngTech\.ArchUnitNET|ArchUnitNET|Nito\.|NodaTime|HotChocolate|GraphQL|Elastic\.|Confluent\.|RabbitMQ\.|Octokit|Markdig|YamlDotNet|CsvHelper|EPPlus|ClosedXML|QuestPDF|SixLabors\.|Spectre\.|TUnit|NETStandard\.Library|runtime\.)'

function Get-KitNuGetGlobalFolder {
    param([string]$Root, [switch]$AskDotnet)
    if ($env:NUGET_PACKAGES -and (Test-Path -LiteralPath $env:NUGET_PACKAGES)) { return $env:NUGET_PACKAGES }
    $default = Join-Path $HOME '.nuget/packages'
    if ((Test-Path -LiteralPath $default) -and -not $AskDotnet) { return $default }
    $r = Invoke-KitNative -FilePath 'dotnet' -Arguments @('nuget', 'locals', 'global-packages', '--list') -WorkingDirectory $Root -TimeoutSec 60
    foreach ($l in $r.StdOut) {
        $m = [regex]::Match($l, 'global-packages:\s*(.+)$')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return $default
}

function Get-KitPackageSource {
    # Feed a package was restored from, as recorded by NuGet in .nupkg.metadata ('' when unknown).
    param([string]$GlobalFolder, [string]$Id, [string[]]$Versions)
    $pkgDir = Join-Path $GlobalFolder $Id.ToLowerInvariant()
    if (-not (Test-Path -LiteralPath $pkgDir)) { return '' }
    $cands = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($Versions)) { if ($v) { $cands.Add((Join-Path $pkgDir (([string]$v).ToLowerInvariant() + '/.nupkg.metadata'))) } }
    foreach ($d in @(Get-ChildItem -Path $pkgDir -Directory -ErrorAction SilentlyContinue)) { $cands.Add((Join-Path $d.FullName '.nupkg.metadata')) }
    foreach ($meta in $cands) {
        if (Test-Path -LiteralPath $meta) {
            $src = [string](Get-KitProp -Object (Read-KitJsonFile -Path $meta) -Names @('source'))
            if ($src) { return $src }
        }
    }
    return ''
}

function Get-KitPackageOrigin {
    # 'internal' | 'public' | 'unknown'. Order: configured prefixes > known public > internal source mapping > restore source.
    param([string]$Id, [string]$Source, $PrefixGlobs, $MappingGlobs)
    if (Find-KitGlobMatch -Path $Id -Globs $PrefixGlobs) { return 'internal' }
    if ($Id -match $script:KitKnownPublicPackages) { return 'public' }
    if (Find-KitGlobMatch -Path $Id -Globs $MappingGlobs) { return 'internal' }
    if ($Source -and $Source -match '(?i)nuget\.org') { return 'public' }
    if ($Source) { return 'internal' }
    return 'unknown'
}

function Get-KitInternalPrefixGlobs {
    param($Config)
    return ,@(@($Config.internalPackages.prefixes) | Where-Object { $_ } | ForEach-Object { if ($_ -match '[*?]') { [string]$_ } else { [string]$_ + '*' } })
}

# --------------------------------------------------------------------------- build

function Find-KitBuildTarget {
    param([string]$Root, $Config)
    $configured = [string]$Config.bootstrap.solution
    if ($configured) {
        $p = Join-Path $Root $configured
        if (Test-Path -LiteralPath $p) { return [System.IO.Path]::GetFullPath($p) }
    }
    foreach ($dir in @($Root, (Join-Path $Root 'src'), (Join-Path $Root 'source'))) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($pattern in @('*.slnx', '*.sln')) {
            $hits = @(Get-ChildItem -Path $dir -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object Name)
            if ($hits.Count -ge 1) { return $hits[0].FullName }
        }
    }
    return $null
}

function ConvertFrom-KitBuildOutput {
    param([string[]]$Lines, [string]$Root)
    $errors = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    # Paths may contain parentheses ("Program Files (x86)", "MyRepo (copy)"); parallel builds may prefix lines with "3>".
    $rxFile = '^\s*(?:\d+>)?(?<file>(?:[A-Za-z]:)?[^:]*?)\((?<line>\d+)(?:,(?<col>\d+))?(?:,\d+,\d+)?\)\s*:\s*(?<sev>error|warning)\s+(?<code>[A-Za-z]+[0-9]*)\s*:\s*(?<msg>.*?)(?:\s+\[[^\]]+\])?\s*$'
    $rxGeneric = '^\s*(?:\d+>)?(?<src>(?:[A-Za-z]:)?[^:]*?)\s*:\s*(?<sev>error|warning)\s+(?<code>[A-Za-z]+[0-9]*)\s*:\s*(?<msg>.*?)(?:\s+\[[^\]]+\])?\s*$'
    foreach ($line in @($Lines)) {
        if (-not $line) { continue }
        $item = $null
        $m = [regex]::Match($line, $rxFile)
        if ($m.Success) {
            $item = [pscustomobject]@{ Severity = $m.Groups['sev'].Value; Code = $m.Groups['code'].Value; File = (Get-KitRelativePath -Path $m.Groups['file'].Value.Trim() -Root $Root); Line = (ConvertTo-KitInt $m.Groups['line'].Value); Col = (ConvertTo-KitInt $m.Groups['col'].Value); Message = $m.Groups['msg'].Value.Trim() }
        } else {
            $g = [regex]::Match($line, $rxGeneric)
            if ($g.Success) { $item = [pscustomobject]@{ Severity = $g.Groups['sev'].Value; Code = $g.Groups['code'].Value; File = (Get-KitRelativePath -Path $g.Groups['src'].Value.Trim() -Root $Root); Line = 0; Col = 0; Message = $g.Groups['msg'].Value.Trim() } }
        }
        if ($null -eq $item) { continue }
        $key = '{0}|{1}|{2}|{3}|{4}' -f $item.Severity, $item.Code, $item.File, $item.Line, $item.Message
        if (-not $seen.Add($key)) { continue }
        if ($item.Severity -eq 'error') { $errors.Add($item) } else { $warnings.Add($item) }
    }
    return [pscustomobject]@{ Errors = $errors.ToArray(); Warnings = $warnings.ToArray() }
}

function Invoke-KitDotnetBuild {
    param([string]$Root, [string]$Target, [string]$Configuration = 'Debug', [switch]$NoRestore, [int]$TimeoutSec = 900)
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('build')
    if ($Target) { $a.Add($Target) }
    foreach ($x in @('-c', $Configuration, '-nologo', '-v:q', '-clp:NoSummary', '-p:GenerateFullPaths=true')) { $a.Add($x) }
    if ($NoRestore) { $a.Add('--no-restore') }
    $r = Invoke-KitNative -FilePath 'dotnet' -Arguments $a.ToArray() -WorkingDirectory $Root -TimeoutSec $TimeoutSec
    $all = @($r.StdOut) + @($r.StdErr)
    $parsed = ConvertFrom-KitBuildOutput -Lines $all -Root $Root
    $ok = ($r.ExitCode -eq 0 -and $parsed.Errors.Count -eq 0)
    $tail = @()
    if (-not $ok -and $parsed.Errors.Count -eq 0) { $tail = @($all | Where-Object { $_ } | Select-Object -Last 25) }
    return [pscustomobject]@{ Ok = $ok; ExitCode = $r.ExitCode; TimedOut = $r.TimedOut; Errors = $parsed.Errors; Warnings = $parsed.Warnings; DurationSec = $r.DurationSec; Tail = $tail }
}

function Get-KitFormatterMode {
    # 'csharpier' when the repository pins CSharpier as a local dotnet tool, otherwise 'whitespace' (dotnet format).
    param([string]$Root)
    $manifest = Read-KitTextFile -Path (Join-Path $Root '.config/dotnet-tools.json')
    if ($manifest -and $manifest -match '(?i)"csharpier"\s*:') { return 'csharpier' }
    return 'whitespace'
}

function Invoke-KitDotnetFormat {
    # Formats the given repo-relative .cs files. Modes: whitespace (dotnet format in folder mode: no project load),
    # csharpier (the repository's local tool), auto (csharpier when pinned in .config/dotnet-tools.json, else whitespace).
    param([string]$Root, [string[]]$Files, [string]$Mode = 'whitespace', [int]$TimeoutSec = 120)
    $cs = @($Files | Where-Object { $_ -match '(?i)\.cs$' -and (Test-Path -LiteralPath (Join-Path $Root $_)) })
    if ($cs.Count -eq 0) { return $null }
    if ($Mode -eq 'auto') { $Mode = Get-KitFormatterMode -Root $Root }
    if ($Mode -eq 'csharpier') {
        $manifest = [string](Read-KitTextFile -Path (Join-Path $Root '.config/dotnet-tools.json'))
        $a = @('csharpier', 'format') + $cs
        # CSharpier 0.x has no "format" verb: it formats the paths it is given.
        if ($manifest -match '(?s)"csharpier"\s*:\s*\{[^}]*"version"\s*:\s*"0\.') { $a = @('csharpier') + $cs }
        return (Invoke-KitNative -FilePath 'dotnet' -Arguments $a -WorkingDirectory $Root -TimeoutSec $TimeoutSec)
    }
    $a = @('format', 'whitespace', $Root, '--folder', '--include') + $cs
    return (Invoke-KitNative -FilePath 'dotnet' -Arguments $a -WorkingDirectory $Root -TimeoutSec $TimeoutSec)
}

# --------------------------------------------------------------------------- tests

function Get-KitTestRunnerMode {
    param([string]$Root)
    $gj = Read-KitJsonFile -Path (Join-Path $Root 'global.json')
    $runner = [string](Get-KitProp -Object (Get-KitProp -Object $gj -Names @('test')) -Names @('runner'))
    if ($runner -match '(?i)Microsoft\.Testing\.Platform') { return 'mtp' }
    return 'vstest'
}

function Read-KitTrx {
    param([string]$Path, [string]$Root)
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($Path)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
    $res = [pscustomobject]@{ Total = 0; Passed = 0; Failed = 0; Skipped = 0; Failures = @() }
    $c = $xml.SelectSingleNode('//t:ResultSummary/t:Counters', $ns)
    if ($c) {
        $res.Total = ConvertTo-KitInt $c.GetAttribute('total')
        $res.Passed = ConvertTo-KitInt $c.GetAttribute('passed')
        $res.Failed = (ConvertTo-KitInt $c.GetAttribute('failed')) + (ConvertTo-KitInt $c.GetAttribute('error')) + (ConvertTo-KitInt $c.GetAttribute('timeout')) + (ConvertTo-KitInt $c.GetAttribute('aborted'))
        $res.Skipped = ConvertTo-KitInt $c.GetAttribute('notExecuted')
    }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($n in $xml.SelectNodes("//t:Results/t:UnitTestResult[@outcome='Failed' or @outcome='Error' or @outcome='Timeout' or @outcome='Aborted']", $ns)) {
        $msgNode = $n.SelectSingleNode('t:Output/t:ErrorInfo/t:Message', $ns)
        $stackNode = $n.SelectSingleNode('t:Output/t:ErrorInfo/t:StackTrace', $ns)
        $msg = ''
        $stack = ''
        if ($msgNode) { $msg = $msgNode.InnerText }
        if ($stackNode) { $stack = $stackNode.InnerText }
        $list.Add([pscustomobject]@{ Name = $n.GetAttribute('testName'); Message = (Format-KitMessage -Text $msg); Location = (Get-KitStackLocation -Stack $stack -Root $Root) })
    }
    $res.Failures = $list.ToArray()
    return $res
}

function ConvertFrom-KitTestConsole {
    # Fallback parser for console output (VSTest and Microsoft.Testing.Platform formats).
    param([string[]]$Lines)
    $failures = New-Object System.Collections.Generic.List[object]
    $total = 0; $failed = 0; $passed = 0; $skipped = 0; $found = $false
    $mtp = $null
    $Lines = @($Lines)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = [string]$Lines[$i]
        # Microsoft.Testing.Platform prints "Test run summary: ..." then one "  total: N" / "  failed: N" ... line each.
        if ($l -match '(?i)^\s*Test run summary:') { $found = $true; $mtp = @{ total = 0; failed = 0; succeeded = 0; skipped = 0 }; continue }
        if ($null -ne $mtp) {
            $kv = [regex]::Match($l, '(?i)^\s*(?<k>total|failed|succeeded|skipped):\s*(?<v>\d+)\s*$')
            if ($kv.Success) { $mtp[$kv.Groups['k'].Value.ToLowerInvariant()] = ConvertTo-KitInt $kv.Groups['v'].Value; continue }
        }
        $m = [regex]::Match($l, '^\s*Failed\s+(?<name>[^\s\[]+(?:\([^)]*\))?)\s*\[')
        if (-not $m.Success) { $m = [regex]::Match($l, '^\s*failed\s+(?<name>\S[^(]*?)\s+\(\d') }
        if ($m.Success) {
            $msg = ''
            $end = [math]::Min($i + 8, $Lines.Count)
            for ($j = $i + 1; $j -lt $end; $j++) {
                $t = ([string]$Lines[$j]).Trim()
                if ($t -and $t -notmatch '^(Error Message:|Stack Trace:)$') { $msg = $t; break }
            }
            $failures.Add([pscustomobject]@{ Name = $m.Groups['name'].Value.Trim(); Message = (Format-KitMessage -Text $msg); Location = '' })
            continue
        }
        $s = [regex]::Match($l, '(?i)(Failed|Passed)!\s*-\s*Failed:\s*(?<f>\d+),\s*Passed:\s*(?<p>\d+),\s*Skipped:\s*(?<s>\d+),\s*Total:\s*(?<t>\d+)')
        if ($s.Success) {
            $found = $true
            $failed += ConvertTo-KitInt $s.Groups['f'].Value; $passed += ConvertTo-KitInt $s.Groups['p'].Value
            $skipped += ConvertTo-KitInt $s.Groups['s'].Value; $total += ConvertTo-KitInt $s.Groups['t'].Value
            continue
        }
        $s2 = [regex]::Match($l, '(?i)total:\s*(?<t>\d+).*?failed:\s*(?<f>\d+).*?succeeded:\s*(?<p>\d+).*?skipped:\s*(?<s>\d+)')
        if ($s2.Success) {
            $found = $true
            $failed += ConvertTo-KitInt $s2.Groups['f'].Value; $passed += ConvertTo-KitInt $s2.Groups['p'].Value
            $skipped += ConvertTo-KitInt $s2.Groups['s'].Value; $total += ConvertTo-KitInt $s2.Groups['t'].Value
        }
    }
    if ($null -ne $mtp -and $total -eq 0) { $total = $mtp.total; $failed = $mtp.failed; $passed = $mtp.succeeded; $skipped = $mtp.skipped }
    return [pscustomobject]@{ Found = $found; Total = $total; Passed = $passed; Failed = $failed; Skipped = $skipped; Failures = $failures.ToArray() }
}

function Invoke-KitDotnetTest {
    param([string]$Root, $TestProjects, [string]$Configuration = 'Debug', [switch]$NoBuild, [string]$Filter, [string[]]$ExtraArgs = @(), [int]$TimeoutSec = 900)
    $mode = Get-KitTestRunnerMode -Root $Root
    $resultsDir = Join-Path (Get-KitStateDir -Root $Root -Sub 'test-results') ((Get-Date).ToString('yyyyMMdd-HHmmss'))
    $agg = [pscustomobject]@{ Ok = $true; Total = 0; Passed = 0; Failed = 0; Skipped = 0; Failures = @(); Projects = @(); DurationSec = 0.0; Notes = @() }
    $fails = New-Object System.Collections.Generic.List[object]
    $notes = New-Object System.Collections.Generic.List[string]
    $names = New-Object System.Collections.Generic.List[string]
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($tp in @($TestProjects)) {
        $remaining = $TimeoutSec - [int]$sw.Elapsed.TotalSeconds
        if ($remaining -le 5) { $notes.Add("time budget exhausted before $($tp.Name)"); $agg.Ok = $false; break }
        $a = New-Object System.Collections.Generic.List[string]
        $a.Add('test')
        if ($mode -eq 'mtp') { $a.Add('--project') }
        $a.Add($tp.FullPath)
        $a.Add('-c'); $a.Add($Configuration)
        if ($NoBuild) { $a.Add('--no-build') }
        $trxName = $tp.Name + '.trx'
        if ($mode -eq 'vstest') {
            # VSTest only: in Microsoft.Testing.Platform mode unknown options are forwarded to the test app and rejected.
            $a.Add('-nologo')
            $a.Add('--logger'); $a.Add("trx;LogFileName=$trxName")
            $a.Add('--results-directory'); $a.Add($resultsDir)
            if ($Filter) { $a.Add('--filter'); $a.Add($Filter) }
        }
        foreach ($x in @($ExtraArgs)) { if ($x) { $a.Add([string]$x) } }
        $r = Invoke-KitNative -FilePath 'dotnet' -Arguments $a.ToArray() -WorkingDirectory $Root -TimeoutSec $remaining
        $names.Add($tp.Name)
        $parsed = $null
        $trx = Join-Path $resultsDir $trxName
        if (Test-Path -LiteralPath $trx) { try { $parsed = Read-KitTrx -Path $trx -Root $Root } catch { $parsed = $null } }
        if ($null -eq $parsed) {
            $c = ConvertFrom-KitTestConsole -Lines (@($r.StdOut) + @($r.StdErr))
            $parsed = [pscustomobject]@{ Total = $c.Total; Passed = $c.Passed; Failed = $c.Failed; Skipped = $c.Skipped; Failures = $c.Failures }
            if (-not $c.Found -and $r.ExitCode -ne 0 -and @($c.Failures).Count -eq 0) {
                $tail = (@(@($r.StdOut) + @($r.StdErr) | Where-Object { $_ } | Select-Object -Last 12)) -join "`n"
                $fails.Add([pscustomobject]@{ Name = "$($tp.Name) (test run failed)"; Message = (Format-KitMessage -Text $tail -MaxLines 12 -MaxChars 1200); Location = '' })
            }
        }
        $agg.Total += $parsed.Total; $agg.Passed += $parsed.Passed; $agg.Failed += $parsed.Failed; $agg.Skipped += $parsed.Skipped
        foreach ($f in @($parsed.Failures)) { $fails.Add($f) }
        if ($r.TimedOut) { $notes.Add("$($tp.Name): timed out"); $agg.Ok = $false }
        if ($r.ExitCode -ne 0) { $agg.Ok = $false }
    }
    $sw.Stop()
    if ($agg.Failed -gt 0 -or $fails.Count -gt 0) { $agg.Ok = $false }
    $agg.Failures = $fails.ToArray()
    $agg.Notes = $notes.ToArray()
    $agg.Projects = $names.ToArray()
    $agg.DurationSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    return $agg
}

# --------------------------------------------------------------------------- orchestration + report

function Format-KitCheckReport {
    param($Build, $Tests, $Architecture, [int]$Max = 20, [string]$TestScopeNote = '')
    $sb = New-Object System.Text.StringBuilder
    $arch = @($Architecture)
    if ($arch.Count -gt 0) {
        [void]$sb.AppendLine("ARCHITECTURE: $($arch.Count) layer violation(s)")
        foreach ($v in ($arch | Select-Object -First $Max)) { [void]$sb.AppendLine("  - $v") }
    }
    if ($Build) {
        if ($Build.Ok) {
            [void]$sb.AppendLine(('BUILD: OK - {0} warning(s) [{1}s]' -f @($Build.Warnings).Count, $Build.DurationSec))
        } else {
            $state = 'FAILED'
            if ($Build.TimedOut) { $state = 'TIMED OUT' }
            [void]$sb.AppendLine(('BUILD: {0} - {1} error(s), {2} warning(s) [{3}s]' -f $state, @($Build.Errors).Count, @($Build.Warnings).Count, $Build.DurationSec))
            foreach ($e in (@($Build.Errors) | Select-Object -First $Max)) {
                $loc = $e.File
                if ($e.Line -gt 0) { $loc = '{0}({1},{2})' -f $e.File, $e.Line, $e.Col }
                [void]$sb.AppendLine(('  {0}: {1} {2}' -f $loc, $e.Code, $e.Message))
            }
            if (@($Build.Errors).Count -gt $Max) { [void]$sb.AppendLine(('  (+{0} more)' -f (@($Build.Errors).Count - $Max))) }
            if (@($Build.Tail).Count -gt 0) {
                [void]$sb.AppendLine('  No parsable diagnostics. Last output lines:')
                foreach ($t in $Build.Tail) { [void]$sb.AppendLine("    $t") }
            }
        }
    }
    if ($Tests) {
        $scope = ''
        if ($TestScopeNote) { $scope = " ($TestScopeNote)" }
        if (@($Tests.Projects).Count -eq 0) {
            [void]$sb.AppendLine("TESTS: none run - no test project affected$scope")
        } elseif ($Tests.Ok) {
            [void]$sb.AppendLine(('TESTS: OK - {0} passed, {1} skipped, {2} total in {3} project(s){4} [{5}s]' -f $Tests.Passed, $Tests.Skipped, $Tests.Total, @($Tests.Projects).Count, $scope, $Tests.DurationSec))
        } else {
            [void]$sb.AppendLine(('TESTS: FAILED - {0} failed, {1} passed, {2} total in {3} project(s){4} [{5}s]' -f $Tests.Failed, $Tests.Passed, $Tests.Total, @($Tests.Projects).Count, $scope, $Tests.DurationSec))
            foreach ($f in (@($Tests.Failures) | Select-Object -First $Max)) {
                [void]$sb.AppendLine("  x $($f.Name)")
                if ($f.Message) { [void]$sb.AppendLine("    $($f.Message)") }
                if ($f.Location) { [void]$sb.AppendLine("    at $($f.Location)") }
            }
            if (@($Tests.Failures).Count -gt $Max) { [void]$sb.AppendLine(('  (+{0} more)' -f (@($Tests.Failures).Count - $Max))) }
        }
        foreach ($n in @($Tests.Notes)) { [void]$sb.AppendLine("  note: $n") }
    }
    return $sb.ToString().TrimEnd()
}

function Invoke-KitDotnetCheck {
    param(
        [string]$Root, $Config,
        [switch]$Build, [switch]$Test,
        [string]$Scope = 'affected',
        [string]$Target, [string]$Filter, [string[]]$TestArgs = @(),
        [string]$Configuration = 'Debug', [switch]$NoRestore,
        [string[]]$ChangedFiles, [int]$TimeoutSec = 900, [switch]$CheckArchitecture, [int]$Max = 20
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $graph = Get-KitProjectGraph -Root $Root
    $arch = @()
    if ($CheckArchitecture) { $arch = Test-KitArchitecture -Projects $graph -Config $Config }
    if (-not $Target) { $Target = Find-KitBuildTarget -Root $Root -Config $Config }
    $notes = New-Object System.Collections.Generic.List[string]
    if ($Build -and -not $Target) {
        $notes.Add('BUILD: skipped - no .sln/.slnx found (set bootstrap.solution in .github/kit/config.json); tests build their own projects')
        $Build = $false
    }
    $buildRes = $null
    if ($Build) { $buildRes = Invoke-KitDotnetBuild -Root $Root -Target $Target -Configuration $Configuration -NoRestore:$NoRestore -TimeoutSec $TimeoutSec }
    $testRes = $null
    $scopeNote = ''
    if ($Test -and $Scope -ne 'none' -and ($null -eq $buildRes -or $buildRes.Ok)) {
        $testProjects = @($graph | Where-Object { $_.IsTest })
        $scopeNote = 'all test projects'
        if ($Scope -eq 'affected') {
            if ($null -eq $ChangedFiles) { $ChangedFiles = Get-KitChangedFiles -Root $Root }
            $aff = Get-KitAffectedProjects -Projects $graph -ChangedFiles $ChangedFiles -Root $Root
            $testProjects = @($aff.Projects | Where-Object { $_.IsTest })
            $scopeNote = 'affected by current changes'
            if ($aff.All) { $scopeNote = 'all: a global build file changed' }
        }
        $remaining = [math]::Max(30, $TimeoutSec - [int]$sw.Elapsed.TotalSeconds)
        $testRes = Invoke-KitDotnetTest -Root $Root -TestProjects $testProjects -Configuration $Configuration -NoBuild:([bool]$Build) -Filter $Filter -ExtraArgs $TestArgs -TimeoutSec $remaining
    }
    $ok = ($arch.Count -eq 0) -and ($null -eq $buildRes -or $buildRes.Ok) -and ($null -eq $testRes -or $testRes.Ok)
    $report = Format-KitCheckReport -Build $buildRes -Tests $testRes -Architecture $arch -Max $Max -TestScopeNote $scopeNote
    if ($Build -and $buildRes -and -not $buildRes.Ok -and $Test) { $report += "`nTESTS: skipped because the build failed" }
    foreach ($n in $notes) { $report = ($n + "`n" + $report).TrimEnd() }
    $report += "`nRESULT: " + $(if ($ok) { 'PASSED' } else { 'FAILED' })
    return [pscustomobject]@{ Ok = $ok; Build = $buildRes; Tests = $testRes; Architecture = $arch; Target = $Target; Report = $report; DurationSec = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}
