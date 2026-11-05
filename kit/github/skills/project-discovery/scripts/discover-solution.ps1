# discover-solution.ps1 - Maps the repository for the AI kit (project-discovery skill).
# Output: .ai-local/discovery/discovery.json (full data) and discovery.md (compact report meant for agents).
# Read-only on the repository. Windows PowerShell 5.1 / PowerShell 7+. ASCII-only.
[CmdletBinding()]
param([string]$OutDir, [int]$MaxExamples = 3, [int]$MaxFiles = 6000, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitDotnet.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$cfg = Get-KitConfig -Root $root
if (-not $OutDir) { $OutDir = Get-KitStateDir -Root $root -Sub 'discovery' }
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Get-Rel {
    param([string]$Path)
    return (Get-KitRelativePath -Path $Path -Root $root)
}
function Add-Count {
    param([hashtable]$Map, [string]$Key)
    if ($Map.ContainsKey($Key)) { $Map[$Key] = $Map[$Key] + 1 } else { $Map[$Key] = 1 }
}

# ============================================================================ git
$git = [ordered]@{ isRepo = $false; remote = $null; defaultBranch = ''; currentBranch = ''; branchPrefixes = @(); conventionalCommitsPct = 0; workItemStyle = '' }
$r = Invoke-KitGit -Root $root -Arguments @('rev-parse', '--is-inside-work-tree') -TimeoutSec 10
if ($r.ExitCode -eq 0) {
    $git.isRepo = $true
    $git.currentBranch = Get-KitGitBranch -Root $root
    $u = Invoke-KitGit -Root $root -Arguments @('remote', 'get-url', 'origin') -TimeoutSec 10
    if ($u.ExitCode -eq 0 -and $u.StdOut.Count -gt 0) { $git.remote = Get-KitRemoteInfo -Url $u.StdOut[0] }
    $h = Invoke-KitGit -Root $root -Arguments @('symbolic-ref', '--short', 'refs/remotes/origin/HEAD') -TimeoutSec 10
    if ($h.ExitCode -eq 0 -and $h.StdOut.Count -gt 0) { $git.defaultBranch = ($h.StdOut[0] -replace '^origin/', '') }
    $rb = Invoke-KitGit -Root $root -Arguments @('branch', '-a', '--format=%(refname:short)') -TimeoutSec 20
    $prefixes = @{}
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($b in $rb.StdOut) {
        $n = ($b -replace '^origin/', '')
        $names.Add($n)
        if ($n -match '^([A-Za-z]+)/') { Add-Count -Map $prefixes -Key ($Matches[1] + '/') }
    }
    if (-not $git.defaultBranch) { foreach ($cand in @('develop', 'main', 'master')) { if ($names.Contains($cand)) { $git.defaultBranch = $cand; break } } }
    $git.branchPrefixes = @($prefixes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6 | ForEach-Object { '{0} ({1})' -f $_.Key, $_.Value })
    $lg = Invoke-KitGit -Root $root -Arguments @('log', '-n', '40', '--format=%s') -TimeoutSec 20
    $subjects = @($lg.StdOut | Where-Object { $_ })
    if ($subjects.Count -gt 0) {
        $cc = @($subjects | Where-Object { $_ -match '^(feat|fix|chore|docs|refactor|test|tests|build|ci|perf|style|revert)(\([^)]+\))?!?:' }).Count
        $git.conventionalCommitsPct = [int](100 * $cc / $subjects.Count)
        if (@($subjects | Where-Object { $_ -match 'AB#\d+' }).Count -gt 0) { $git.workItemStyle = 'AB#<id>' }
        elseif (@($subjects | Where-Object { $_ -match '(^|\s)#\d+' }).Count -gt 0) { $git.workItemStyle = '#<id>' }
    }
}

# ============================================================================ SDK and tools
$sdk = [ordered]@{ globalJson = ''; rollForward = ''; installed = ''; testRunner = (Get-KitTestRunnerMode -Root $root); pwsh = [bool](Get-Command -Name pwsh -ErrorAction SilentlyContinue); dotnetTools = @() }
$gj = Read-KitJsonFile -Path (Join-Path $root 'global.json')
if ($gj) {
    $sdkNode = Get-KitProp -Object $gj -Names @('sdk')
    $sdk.globalJson = [string](Get-KitProp -Object $sdkNode -Names @('version'))
    $sdk.rollForward = [string](Get-KitProp -Object $sdkNode -Names @('rollForward'))
}
$dv = Invoke-KitNative -FilePath 'dotnet' -Arguments @('--version') -WorkingDirectory $root -TimeoutSec 30
if ($dv.ExitCode -eq 0 -and $dv.StdOut.Count -gt 0) { $sdk.installed = $dv.StdOut[0].Trim() }
elseif ($dv.ExitCode -eq 127) { $sdk.installed = 'dotnet not found on PATH' }
else { $sdk.installed = 'error: ' + (Format-KitMessage -Text ((@($dv.StdErr) + @($dv.StdOut)) -join "`n") -MaxLines 2) }
$tm = Read-KitJsonFile -Path (Join-Path $root '.config/dotnet-tools.json')
if ($tm -and $tm.tools) { $sdk.dotnetTools = @($tm.tools.PSObject.Properties | ForEach-Object { '{0} {1}' -f $_.Name, $_.Value.version }) }

# ============================================================================ build configuration
$buildProps = [ordered]@{}
$propNames = @('TargetFramework', 'TargetFrameworks', 'Nullable', 'ImplicitUsings', 'LangVersion', 'TreatWarningsAsErrors', 'WarningsAsErrors', 'AnalysisLevel', 'AnalysisMode', 'EnforceCodeStyleInBuild', 'GenerateDocumentationFile', 'ManagePackageVersionsCentrally', 'RestorePackagesWithLockFile', 'InvariantGlobalization')
foreach ($f in (Get-KitRepoFiles -Root $root -Patterns @('Directory.Build.props', '*/Directory.Build.props', 'Directory.Packages.props'))) {
    try {
        $x = New-Object System.Xml.XmlDocument
        $x.Load($f)
        foreach ($name in $propNames) {
            foreach ($n in $x.GetElementsByTagName($name)) { if (-not $buildProps.Contains($name)) { $buildProps[$name] = $n.InnerText.Trim() } }
        }
    } catch { }
}
$central = Get-KitCentralPackageVersions -Root $root
$lockFiles = (Get-KitRepoFiles -Root $root -Patterns @('*packages.lock.json')).Count
$editor = [ordered]@{ present = $false; diagnosticRules = 0; namespaceStyle = ''; notable = @() }
$ecPath = Join-Path $root '.editorconfig'
if (Test-Path -LiteralPath $ecPath) {
    $ect = Read-KitTextFile -Path $ecPath
    $editor.present = $true
    $editor.diagnosticRules = ([regex]::Matches($ect, '(?m)^\s*dotnet_diagnostic\.')).Count
    $m = [regex]::Match($ect, '(?m)^\s*csharp_style_namespace_declarations\s*=\s*([a-z_]+)')
    if ($m.Success) { $editor.namespaceStyle = $m.Groups[1].Value }
    $editor.notable = @([regex]::Matches($ect, '(?m)^\s*(csharp_style_var_for_built_in_types|csharp_prefer_braces|dotnet_sort_system_directives_first|csharp_style_expression_bodied_methods|csharp_style_prefer_primary_constructors)\s*=\s*([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value.Trim() })
}

# ============================================================================ NuGet configuration
function Read-NuGetConfigFile {
    param([string]$Path, [string]$Scope)
    $res = [ordered]@{ path = $Path; scope = $Scope; clear = $false; sources = @(); mapping = @() }
    try { $x = New-Object System.Xml.XmlDocument; $x.Load($Path) } catch { return $res }
    $ps = $x.SelectSingleNode('/configuration/packageSources')
    if ($ps) {
        foreach ($c in $ps.ChildNodes) {
            if ($c.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            if ($c.LocalName -eq 'clear') { $res.clear = $true; continue }
            if ($c.LocalName -eq 'add') {
                $url = $c.GetAttribute('value')
                $res.sources += [pscustomobject]@{ name = $c.GetAttribute('key'); url = $url; internal = -not ($url -match '(?i)api\.nuget\.org|^https?://(www\.)?nuget\.org') }
            }
        }
    }
    $map = $x.SelectSingleNode('/configuration/packageSourceMapping')
    if ($map) {
        foreach ($s in $map.ChildNodes) {
            if ($s.NodeType -ne [System.Xml.XmlNodeType]::Element -or $s.LocalName -ne 'packageSource') { continue }
            $key = $s.GetAttribute('key')
            foreach ($p in $s.ChildNodes) {
                if ($p.NodeType -eq [System.Xml.XmlNodeType]::Element -and $p.LocalName -eq 'package') { $res.mapping += [pscustomobject]@{ source = $key; pattern = $p.GetAttribute('pattern') } }
            }
        }
    }
    return $res
}
$nugetFiles = New-Object System.Collections.Generic.List[object]
foreach ($f in (Get-KitRepoFiles -Root $root -Patterns @('nuget.config', 'NuGet.Config', 'NuGet.config', '*/nuget.config', '*/NuGet.Config', '*/NuGet.config'))) {
    $nc = Read-NuGetConfigFile -Path $f -Scope 'repo'
    $nc.path = (Get-Rel $f)
    $nugetFiles.Add($nc)
}
$parent = Split-Path -Path $root -Parent
while ($parent) {
    foreach ($n in @('nuget.config', 'NuGet.Config', 'NuGet.config')) { $pp = Join-Path $parent $n; if (Test-Path -LiteralPath $pp) { $nugetFiles.Add((Read-NuGetConfigFile -Path $pp -Scope 'parent')); break } }
    $next = Split-Path -Path $parent -Parent
    if (-not $next -or $next -eq $parent) { break }
    $parent = $next
}
$userCfg = $null
if ($env:APPDATA) { $userCfg = Join-Path $env:APPDATA 'NuGet\NuGet.Config' } else { $userCfg = Join-Path $HOME '.nuget/NuGet/NuGet.Config' }
if ($userCfg -and (Test-Path -LiteralPath $userCfg)) { $nugetFiles.Add((Read-NuGetConfigFile -Path $userCfg -Scope 'user')) }
$allSources = @($nugetFiles | ForEach-Object { $_.sources } | Where-Object { $_ })
$internalSourceNames = @($allSources | Where-Object { $_.internal } | ForEach-Object { $_.name } | Select-Object -Unique)
$mappingInternal = @($nugetFiles | ForEach-Object { $_.mapping } | Where-Object { $_ -and ($internalSourceNames -contains $_.source) -and $_.pattern -ne '*' } | ForEach-Object { $_.pattern } | Select-Object -Unique)

# ============================================================================ projects and layers
$graph = Get-KitProjectGraph -Root $root
$layers = $cfg.architecture.layers
$byPath = @{}
foreach ($p in $graph) { $byPath[$p.FullPath.ToLowerInvariant()] = $p }
$projects = New-Object System.Collections.Generic.List[object]
$unassigned = New-Object System.Collections.Generic.List[string]
foreach ($p in $graph) {
    $layer = Get-KitLayerOf -ProjectName $p.Name -Layers $layers
    $layerName = ''
    if ($layer) { $layerName = [string]$layer.name } else { $unassigned.Add($p.Name) }
    $refNames = @($p.References | ForEach-Object { $t = $byPath[$_.ToLowerInvariant()]; if ($t) { $t.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($_) } })
    $kind = 'library'
    if ($p.IsTest) { $kind = 'test' } elseif ($p.Sdk -match '(?i)Web') { $kind = 'web' } elseif ($p.OutputType -match '(?i)exe') { $kind = 'exe' } elseif ($p.Sdk -match '(?i)Worker') { $kind = 'worker' }
    $projects.Add([pscustomobject]@{ name = $p.Name; path = (Get-Rel $p.FullPath); layer = $layerName; kind = $kind; sdk = $p.Sdk; tfm = $p.TargetFramework; references = $refNames; packages = @($p.Packages | ForEach-Object { if ($_.Version) { $_.Id + ' ' + $_.Version } else { $_.Id } }) })
}
$violations = Test-KitArchitecture -Projects $graph -Config $cfg
$solutions = @((Get-KitRepoFiles -Root $root -Patterns @('*.sln', '*.slnx')) | ForEach-Object { Get-Rel $_ })

# ============================================================================ packages
$globalPackages = Get-KitNuGetGlobalFolder -Root $root
$prefixGlobs = Get-KitInternalPrefixGlobs -Config $cfg
$pkgIndex = @{}
foreach ($p in $graph) {
    foreach ($k in $p.Packages) {
        if (-not $pkgIndex.ContainsKey($k.Id)) { $pkgIndex[$k.Id] = [pscustomobject]@{ id = $k.Id; versions = New-Object System.Collections.Generic.List[string]; projects = New-Object System.Collections.Generic.List[string]; origin = ''; source = '' } }
        $e = $pkgIndex[$k.Id]
        if ($k.Version -and -not $e.versions.Contains([string]$k.Version)) { $e.versions.Add([string]$k.Version) }
        if (-not $e.projects.Contains($p.Name)) { $e.projects.Add($p.Name) }
    }
}
foreach ($e in $pkgIndex.Values) {
    $e.source = Get-KitPackageSource -GlobalFolder $globalPackages -Id $e.id -Versions $e.versions.ToArray()
    $e.origin = Get-KitPackageOrigin -Id $e.id -Source $e.source -PrefixGlobs $prefixGlobs -MappingGlobs $mappingInternal
}
$packages = @($pkgIndex.Values | Sort-Object id)
$internalPkgs = @($packages | Where-Object { $_.origin -eq 'internal' })
$unknownPkgs = @($packages | Where-Object { $_.origin -eq 'unknown' })
$prefixCounts = @{}
foreach ($e in (@($internalPkgs) + @($unknownPkgs))) { $seg = ($e.id -split '\.')[0]; if ($seg) { Add-Count -Map $prefixCounts -Key ($seg + '.') } }
$suggestedPrefixes = @($prefixCounts.GetEnumerator() | Where-Object { $_.Value -ge 2 } | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object { '{0}* ({1} packages)' -f $_.Key, $_.Value })

$frameworkRules = [ordered]@{
    'MediatR' = '^MediatR$'; 'Mediator (source generator)' = '^Mediator\.'; 'Wolverine' = '^WolverineFx'; 'FluentValidation' = '^FluentValidation'
    'AutoMapper' = '^AutoMapper'; 'Mapster' = '^Mapster'; 'Mapperly' = '^Riok\.Mapperly'
    'EF Core' = '^Microsoft\.EntityFrameworkCore$'; 'EF Core SqlServer' = '^Microsoft\.EntityFrameworkCore\.SqlServer'; 'EF Core PostgreSQL' = '^Npgsql\.EntityFrameworkCore'; 'Dapper' = '^Dapper'
    'Serilog' = '^Serilog'; 'OpenTelemetry' = '^OpenTelemetry'; 'Polly / resilience' = '^(Polly|Microsoft\.Extensions\.Http\.Resilience)'
    'MassTransit' = '^MassTransit'; 'Azure Service Bus' = '^Azure\.Messaging\.ServiceBus'; 'Hangfire' = '^Hangfire'; 'Quartz' = '^Quartz'
    'Swashbuckle' = '^Swashbuckle'; 'NSwag' = '^NSwag'; 'ASP.NET OpenAPI' = '^Microsoft\.AspNetCore\.OpenApi'; 'Asp.Versioning' = '^Asp\.Versioning'
    'FastEndpoints' = '^FastEndpoints'; 'Carter' = '^Carter'; 'ErrorOr' = '^ErrorOr'; 'OneOf' = '^OneOf'; 'Ardalis.Result' = '^Ardalis\.Result'; 'FluentResults' = '^FluentResults'; 'Ardalis.Specification' = '^Ardalis\.Specification'
    'Microsoft.Identity.Web' = '^Microsoft\.Identity\.Web'; 'Azure Key Vault' = '^Azure\.(Security\.KeyVault|Extensions\.AspNetCore\.Configuration\.Secrets)'; 'Feature management' = '^Microsoft\.FeatureManagement'; '.NET Aspire' = '^Aspire\.'
    'xUnit v2' = '^xunit$'; 'xUnit v3' = '^xunit\.v3'; 'NUnit' = '^NUnit$'; 'MSTest' = '^MSTest'; 'TUnit' = '^TUnit'
    'FluentAssertions' = '^FluentAssertions'; 'AwesomeAssertions' = '^AwesomeAssertions'; 'Shouldly' = '^Shouldly'; 'NSubstitute' = '^NSubstitute'; 'Moq' = '^Moq$'; 'FakeItEasy' = '^FakeItEasy'
    'Bogus' = '^Bogus'; 'AutoFixture' = '^AutoFixture'; 'Testcontainers' = '^Testcontainers'; 'WebApplicationFactory' = '^Microsoft\.AspNetCore\.Mvc\.Testing'; 'Respawn' = '^Respawn'; 'WireMock' = '^WireMock'
    'NetArchTest' = '^NetArchTest'; 'ArchUnitNET' = 'ArchUnitNET'; 'Verify' = '^Verify\.'; 'coverlet' = '^coverlet'; 'BenchmarkDotNet' = '^BenchmarkDotNet'
}
$frameworks = New-Object System.Collections.Generic.List[string]
foreach ($k in $frameworkRules.Keys) {
    $hit = @($packages | Where-Object { $_.id -match $frameworkRules[$k] } | Select-Object -First 1)
    if ($hit.Count -gt 0) { $v = ''; if ($hit[0].versions.Count -gt 0) { $v = ' ' + $hit[0].versions[0] }; $frameworks.Add($k + $v) }
}

# ============================================================================ code patterns and golden example candidates
$testDirs = @($graph | Where-Object { $_.IsTest } | ForEach-Object { $_.Dir })
$patternDefs = @(
    @('aggregate root', 'prod', '\bclass\s+\w+[^{\r\n]*:\s*[^{\r\n]*\b(AggregateRoot|IAggregateRoot)\b'),
    @('entity', 'prod', '\bclass\s+\w+[^{\r\n]*:\s*[^{\r\n]*\b(Entity|BaseEntity|AuditableEntity|BaseAuditableEntity)\b'),
    @('value object', 'prod', ':\s*[^{\r\n]*\bValueObject\b|\brecord\s+struct\s+\w+Id\b|\breadonly\s+record\s+struct\b'),
    @('domain event', 'prod', ':\s*[^{\r\n]*\b(IDomainEvent|DomainEvent|BaseEvent)\b'),
    @('command', 'prod', '\b(record|class)\s+\w+Command\b'),
    @('query', 'prod', '\b(record|class)\s+\w+Query\b'),
    @('use case handler', 'prod', '\b(ICommandHandler|IQueryHandler|IRequestHandler|INotificationHandler)<|\bclass\s+\w+Handler\b'),
    @('validator', 'prod', 'AbstractValidator<'),
    @('repository', 'prod', '\b(class|interface)\s+I?\w+Repository\b'),
    @('specification', 'prod', ':\s*[^{\r\n]*\bSpecification<'),
    @('DbContext', 'prod', ':\s*[^{\r\n]*\bDbContext\b'),
    @('EF configuration', 'prod', 'IEntityTypeConfiguration<'),
    @('minimal API endpoint', 'prod', '\.Map(Get|Post|Put|Delete|Patch|Group)\s*\('),
    @('controller', 'prod', ':\s*[^{\r\n]*\b(ControllerBase|Controller)\b|\[ApiController\]'),
    @('DI registration', 'prod', '\bstatic\s+class\s+\w*(DependencyInjection|ServiceCollectionExtensions)\b|\bthis\s+IServiceCollection\s+\w+'),
    @('error handling', 'prod', '\bIExceptionHandler\b|UseExceptionHandler|\bProblemDetails\b'),
    @('result type', 'prod', '\b(Result<|ErrorOr<|OneOf<)|\bResult\.(Success|Failure|Ok|Fail)\b'),
    @('mapping', 'prod', '\.Adapt<|\bIMapper\b|\bTypeAdapterConfig\b|\[Mapper\]'),
    @('options', 'prod', '\bIOptions(Snapshot|Monitor)?<|\.Configure<\w+>\(|BindConfiguration\('),
    @('logging', 'prod', '\bILogger<|\[LoggerMessage'),
    @('unit test', 'test', '\[(Fact|Theory|Test|TestMethod|TestCase)\b'),
    @('integration test', 'test', 'WebApplicationFactory<|ICollectionFixture<|IClassFixture<|Testcontainers|IAsyncLifetime'),
    @('architecture test', 'test', 'NetArchTest|Types\.InAssembly|ArchRuleDefinition|ArchUnitNET'),
    @('test data builder', 'test', '\bclass\s+\w+(Builder|Fixture|Faker|Mother)\b')
)
$opts = [System.Text.RegularExpressions.RegexOptions]::Multiline
$compiled = @($patternDefs | ForEach-Object { [pscustomobject]@{ Name = $_[0]; Scope = $_[1]; Rx = (New-Object System.Text.RegularExpressions.Regex($_[2], $opts)); Hits = (New-Object System.Collections.Generic.List[object]) } })
$style = [ordered]@{ csFiles = 0; fileScopedNamespaces = 0; blockNamespaces = 0; sealedClasses = 0; classes = 0; records = 0; primaryConstructors = 0; minimalApiCalls = 0; controllers = 0 }
$sep = [string][System.IO.Path]::DirectorySeparatorChar
$csFiles = @((Get-KitRepoFiles -Root $root -Patterns @('*.cs') -Max $MaxFiles) | Where-Object { $_ -notmatch '[\\/](obj|bin)[\\/]' -and $_ -notmatch '(?i)(\.g|\.g\.i|\.designer)\.cs$|AssemblyInfo\.cs$' })
foreach ($f in $csFiles) {
    $text = $null
    try { $text = [System.IO.File]::ReadAllText($f) } catch { continue }
    if (-not $text) { continue }
    $style.csFiles++
    $isTestFile = $false
    foreach ($d in $testDirs) { if ($f.StartsWith($d + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { $isTestFile = $true; break } }
    $lines = ([regex]::Matches($text, "`n")).Count + 1
    $rel = Get-Rel $f
    foreach ($c in $compiled) {
        if (($c.Scope -eq 'prod' -and $isTestFile) -or ($c.Scope -eq 'test' -and -not $isTestFile)) { continue }
        if ($c.Rx.IsMatch($text)) { $c.Hits.Add([pscustomobject]@{ path = $rel; lines = $lines }) }
    }
    if ([regex]::IsMatch($text, '(?m)^\s*namespace\s+[\w.]+\s*;')) { $style.fileScopedNamespaces++ } elseif ([regex]::IsMatch($text, '(?m)^\s*namespace\s+[\w.]+\s*(\{|$)')) { $style.blockNamespaces++ }
    $style.classes += ([regex]::Matches($text, '\bclass\s+\w+')).Count
    $style.sealedClasses += ([regex]::Matches($text, '\bsealed\s+(partial\s+)?class\b')).Count
    $style.records += ([regex]::Matches($text, '\brecord\s+(class\s+|struct\s+)?\w+')).Count
    $style.primaryConstructors += ([regex]::Matches($text, '\b(class|struct)\s+\w+(<[^>]+>)?\s*\(')).Count
    $style.minimalApiCalls += ([regex]::Matches($text, '\.Map(Get|Post|Put|Delete|Patch)\s*\(')).Count
    if ([regex]::IsMatch($text, ':\s*[^{\r\n]*\bControllerBase\b|\[ApiController\]')) { $style.controllers++ }
}
$patterns = New-Object System.Collections.Generic.List[object]
foreach ($c in $compiled) {
    if ($c.Hits.Count -eq 0) { continue }
    $preferred = @($c.Hits | Where-Object { $_.lines -ge 12 -and $_.lines -le 250 } | Sort-Object lines)
    if ($preferred.Count -eq 0) { $preferred = @($c.Hits | Sort-Object lines) }
    $examples = @($preferred | Select-Object -First $MaxExamples | ForEach-Object { '{0} ({1} lines)' -f $_.path, $_.lines })
    $patterns.Add([pscustomobject]@{ name = $c.Name; files = $c.Hits.Count; examples = $examples })
}

# ============================================================================ CI/CD
$ciFiles = (Get-KitRepoFiles -Root $root -Patterns @('azure-pipelines*.yml', 'azure-pipelines*.yaml', '*/azure-pipelines*.yml', '*.pipeline.yml', '.azuredevops/*.yml', 'pipelines/*.yml', '*/pipelines/*.yml', '.pipelines/*.yml', 'build/*.yml', 'deploy/*.yml', 'templates/*.yml', '.github/workflows/*.yml', '.github/workflows/*.yaml'))
function Get-KitUniqueGroups {
    param($MatchList, [int]$Group = 1, [int]$Max = 12)
    return @(@($MatchList) | ForEach-Object { $_.Groups[$Group].Value.Trim().Trim("'").Trim('"') } | Where-Object { $_ } | Select-Object -Unique -First $Max)
}
$ci = New-Object System.Collections.Generic.List[object]
$ciFormat = New-Object System.Collections.Generic.List[string]
foreach ($f in $ciFiles) {
    $t = Read-KitTextFile -Path $f
    if (-not $t) { continue }
    # Pipelines that verify formatting (not the kit's own PR checks template, where the check is optional).
    if ($t -notmatch 'kit:pr-checks' -and $t -match '(?i)\bdotnet\s+format\b|\bcsharpier\b') { $ciFormat.Add((Get-Rel $f)) }
    $kind = 'azure-pipelines'
    if ((Get-Rel $f) -like '.github/workflows/*') { $kind = 'github-actions' }
    $triggers = New-Object System.Collections.Generic.List[string]
    $inTrigger = $false
    foreach ($line in ($t -split "\r?\n")) {
        if ($line -match '^(trigger|pr):\s*(.*)$') { $inTrigger = $true; if ($Matches[2].Trim()) { $triggers.Add($Matches[1] + ': ' + $Matches[2].Trim()) }; continue }
        if ($inTrigger) {
            if ($line -match '^\S') { $inTrigger = $false; continue }
            if ($line -match '^\s*-\s*(.+)$') { $triggers.Add($Matches[1].Trim()) }
        }
    }
    $ci.Add([pscustomobject]@{
        file         = (Get-Rel $f)
        kind         = $kind
        triggers     = @($triggers | Select-Object -Unique -First 8)
        extends      = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^extends:\s*\r?\n\s+template:\s*(\S+)')) 1 3)
        stages       = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*-\s*stage:\s*(\S+)')))
        jobs         = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*-\s*(?:job|deployment):\s*(\S+)')))
        templates    = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*-?\s*template:\s*(\S+)')))
        tasks        = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*-?\s*task:\s*([\w.\-]+@\d+)')) 1 20)
        actions      = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*-?\s*uses:\s*(\S+)')) 1 15)
        dotnet       = (Get-KitUniqueGroups ([regex]::Matches($t, '(dotnet\s+(?:restore|build|test|publish|pack|format|tool|ef)\b[^\r\n''"]*)')) 1 10)
        cliCommands  = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*command:\s*''?(restore|build|test|publish|pack|push|custom)''?\s*$')))
        groups       = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*-\s*group:\s*(.+?)\s*$')))
        environments = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*environment:\s*(.+?)\s*$')))
        pools        = (Get-KitUniqueGroups ([regex]::Matches($t, '(?m)^\s*(?:vmImage|runs-on):\s*(.+?)\s*$')))
    })
}
$formatting = [ordered]@{ ciVerifies = $ciFormat.ToArray(); csharpierTool = ((Get-KitFormatterMode -Root $root) -eq 'csharpier'); suggested = 'off' }
if ($formatting.ciVerifies.Count -gt 0 -or $formatting.csharpierTool) { $formatting.suggested = 'auto' }

# ============================================================================ other assets
function Get-RelList {
    param([string[]]$Patterns, [int]$Max = 8)
    return @((Get-KitRepoFiles -Root $root -Patterns $Patterns -Max 200) | ForEach-Object { Get-Rel $_ } | Select-Object -First $Max)
}
$other = [ordered]@{
    docker       = (Get-RelList @('Dockerfile', '*/Dockerfile', '*Dockerfile*', 'docker-compose*.yml', '*/docker-compose*.yml', 'compose*.yaml'))
    iac          = (Get-RelList @('*.bicep', '*.tf', '*/azuredeploy*.json', '*Chart.yaml'))
    docs         = (Get-RelList @('README.md', 'CONTRIBUTING.md', 'docs/*.md', 'doc/*.md', 'ARCHITECTURE.md'))
    aiFiles      = (Get-RelList @('AGENTS.md', '*/AGENTS.md', '.github/copilot-instructions.md', 'CLAUDE.md', '.cursorrules', '.cursor/rules/*'))
    templateJson = (Get-RelList @('.template.config/template.json', '*/.template.config/template.json'))
    prTemplates  = (Get-RelList @('.azuredevops/pull_request_template.md', 'pull_request_template.md', 'docs/pull_request_template.md', '.github/pull_request_template.md'))
}

# ============================================================================ write outputs
$data = [ordered]@{
    generatedAt  = (Get-Date).ToString('o')
    root         = $root
    git          = $git
    sdk          = $sdk
    build        = [ordered]@{ props = $buildProps; centralPackageManagement = ($central.Count -gt 0); lockFiles = $lockFiles; editorconfig = $editor }
    nuget        = [ordered]@{ files = @($nugetFiles); internalSources = $internalSourceNames; internalMappingPatterns = $mappingInternal }
    solutions    = $solutions
    projects     = $projects.ToArray()
    unassigned   = $unassigned.ToArray()
    violations   = $violations
    packages     = @($packages | ForEach-Object { [pscustomobject]@{ id = $_.id; versions = $_.versions.ToArray(); projects = $_.projects.ToArray(); origin = $_.origin; source = $_.source } })
    suggestedInternalPrefixes = $suggestedPrefixes
    frameworks   = $frameworks.ToArray()
    patterns     = $patterns.ToArray()
    style        = $style
    ci           = $ci.ToArray()
    formatting   = $formatting
    other        = $other
}
$jsonPath = Join-Path $OutDir 'discovery.json'
Write-KitJsonFile -Path $jsonPath -Object $data -Depth 8

$md = New-Object System.Text.StringBuilder
function Add-Line {
    param([string]$Text = '')
    [void]$md.AppendLine($Text)
}
function Join-KitList {
    param($Items, [string]$Empty = 'none')
    $a = @($Items | Where-Object { $_ }); if ($a.Count -eq 0) { return $Empty }; return ($a -join ', ')
}
$repoName = Split-Path -Path $root -Leaf
Add-Line "# Discovery report - $repoName"
Add-Line ('Generated ' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + ' by the project-discovery skill. Facts only: verify before writing them into docs/ai/project-context.md.')
Add-Line ''
Add-Line '## Repository'
if ($git.isRepo) {
    $rem = 'none'
    if ($git.remote) { $rem = $git.remote.Provider; if ($git.remote.Org) { $rem += ' (' + ((@($git.remote.Org, $git.remote.Project, $git.remote.Repo) | Where-Object { $_ }) -join '/') + ')' } }
    Add-Line ('- Remote: ' + $rem + ' | default branch: ' + (Join-KitList @($git.defaultBranch) 'unknown') + ' | current: ' + $git.currentBranch)
    Add-Line ('- Branch prefixes: ' + (Join-KitList $git.branchPrefixes) + ' | conventional commits: ' + $git.conventionalCommitsPct + '% of last 40 | work item refs: ' + (Join-KitList @($git.workItemStyle)))
} else { Add-Line '- Not a git repository yet.' }
Add-Line ('- .NET SDK: global.json ' + (Join-KitList @($sdk.globalJson) 'not pinned') + ' (rollForward ' + (Join-KitList @($sdk.rollForward) 'default') + ') | dotnet --version: ' + $sdk.installed + ' | test runner: ' + $sdk.testRunner + ' | PowerShell 7: ' + $sdk.pwsh)
if ($sdk.dotnetTools.Count -gt 0) { Add-Line ('- Local dotnet tools: ' + (Join-KitList $sdk.dotnetTools)) }
$bp = @($buildProps.Keys | ForEach-Object { $_ + '=' + $buildProps[$_] })
Add-Line ('- Build props: ' + (Join-KitList $bp) + ' | central package management: ' + ($central.Count -gt 0) + ' | lock files: ' + $lockFiles)
Add-Line ('- .editorconfig: ' + $editor.present + ' (' + $editor.diagnosticRules + ' diagnostic rules; namespace style: ' + (Join-KitList @($editor.namespaceStyle) 'n/a') + ') ' + (Join-KitList $editor.notable ''))
$fsPct = 0
if (($style.fileScopedNamespaces + $style.blockNamespaces) -gt 0) { $fsPct = [int](100 * $style.fileScopedNamespaces / ($style.fileScopedNamespaces + $style.blockNamespaces)) }
$sealedPct = 0
if ($style.classes -gt 0) { $sealedPct = [int](100 * $style.sealedClasses / $style.classes) }
Add-Line ('- Code style (from ' + $style.csFiles + ' .cs files): file-scoped namespaces ' + $fsPct + '%, sealed classes ' + $sealedPct + '%, records ' + $style.records + ', primary constructors ' + $style.primaryConstructors + ' | API style: minimal API calls ' + $style.minimalApiCalls + ', controllers ' + $style.controllers)
Add-Line ''
Add-Line '## Solution and projects'
Add-Line ('Solutions: ' + (Join-KitList $solutions))
Add-Line ''
Add-Line '| Layer | Project | Kind | TFM | References |'
Add-Line '|---|---|---|---|---|'
foreach ($p in ($projects | Sort-Object layer, name)) { Add-Line ('| {0} | {1} (`{2}`) | {3} | {4} | {5} |' -f (Join-KitList @($p.layer) '?'), $p.name, $p.path, $p.kind, $p.tfm, (Join-KitList $p.references '-')) }
Add-Line ''
Add-Line ('Projects without layer (adjust architecture.layers in .github/kit/config.json): ' + (Join-KitList $unassigned))
Add-Line ('Layer violations with the current rules: ' + (Join-KitList $violations))
Add-Line ''
Add-Line '## Packages'
Add-Line ('- NuGet sources: ' + (Join-KitList @($allSources | ForEach-Object { $s = $_.name; if ($_.internal) { $s += ' [internal]' }; $s } | Select-Object -Unique)) + ' | internal mapping patterns: ' + (Join-KitList $mappingInternal))
Add-Line ('- Internal packages (' + $internalPkgs.Count + '): ' + (Join-KitList @($internalPkgs | ForEach-Object { $_.id + ' ' + ($_.versions -join '/') + ' -> ' + ($_.projects -join ', ') })))
Add-Line ('- Unknown origin, verify (' + $unknownPkgs.Count + '): ' + (Join-KitList @($unknownPkgs | Select-Object -First 25 | ForEach-Object { $_.id })))
Add-Line ('- Suggested internal prefixes: ' + (Join-KitList $suggestedPrefixes))
Add-Line ('- Frameworks: ' + (Join-KitList $frameworks))
Add-Line ''
Add-Line '## Conventions: golden example candidates'
Add-Line 'Read 1-2 examples per pattern before writing similar code; promote the best ones into docs/ai/project-context.md.'
foreach ($p in $patterns) { Add-Line ('- ' + $p.name + ' (' + $p.files + ' files): ' + ($p.examples -join '; ')) }
if ($patterns.Count -eq 0) { Add-Line '- no C# patterns found (empty solution?)' }
Add-Line ''
Add-Line '## CI/CD'
if ($ci.Count -eq 0) { Add-Line '- No pipeline files found.' }
foreach ($c in $ci) {
    Add-Line ('- ' + $c.file + ' (' + $c.kind + ')')
    Add-Line ('  - triggers: ' + (Join-KitList $c.triggers) + ' | extends: ' + (Join-KitList $c.extends) + ' | stages: ' + (Join-KitList $c.stages) + ' | jobs: ' + (Join-KitList $c.jobs))
    Add-Line ('  - templates: ' + (Join-KitList $c.templates) + ' | tasks/actions: ' + (Join-KitList (@($c.tasks) + @($c.actions))))
    Add-Line ('  - dotnet steps: ' + (Join-KitList (@($c.dotnet) + @($c.cliCommands))) + ' | variable groups: ' + (Join-KitList $c.groups) + ' | environments: ' + (Join-KitList $c.environments) + ' | pools: ' + (Join-KitList $c.pools))
}
Add-Line ('- Formatting verified by CI: ' + (Join-KitList $formatting.ciVerifies 'no') + ' | CSharpier local tool: ' + $formatting.csharpierTool + ' | suggested qualityGate.format: ' + $formatting.suggested)
Add-Line ''
Add-Line '## Other'
Add-Line ('- Docker: ' + (Join-KitList $other.docker) + ' | IaC: ' + (Join-KitList $other.iac))
Add-Line ('- Docs: ' + (Join-KitList $other.docs) + ' | PR templates: ' + (Join-KitList $other.prTemplates))
Add-Line ('- Existing AI instruction files: ' + (Join-KitList $other.aiFiles) + ' | dotnet new template sources: ' + (Join-KitList $other.templateJson))
Add-Line ''
Add-Line '## Hints for /bootstrap'
if ($graph.Count -eq 0) { Add-Line '- No projects found: run INIT (create the solution from the company template) first.' }
if ($unassigned.Count -gt 0) { Add-Line '- Some projects have no layer: extend the layer patterns so the guard and the quality gate understand them.' }
if ($violations.Count -gt 0) { Add-Line '- The template itself violates the default layer rules: the template is the reference, adapt mayReference/forbiddenPackages (or document the exception in an ADR).' }
if ($suggestedPrefixes.Count -gt 0 -and @($cfg.internalPackages.prefixes).Count -eq 0) { Add-Line '- Confirm the internal package prefixes with the user and save them in internalPackages.prefixes.' }
if (-not $sdk.pwsh) { Add-Line '- PowerShell 7 not found: run configure-kit.ps1 -Launcher powershell (or install PowerShell 7).' }
if ($sdk.testRunner -eq 'mtp') { Add-Line '- Tests use Microsoft.Testing.Platform: set qualityGate.testArgs for filters (no --filter / TRX logger).' }
if ($formatting.suggested -ne 'off' -and [string]$cfg.qualityGate.format -eq 'off') { Add-Line '- Formatting is enforced in this repository: run configure-kit.ps1 -Format auto so the quality gate formats the changed files.' }
Add-Line ('- Discovery took ' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's. Full data: .ai-local/discovery/discovery.json')
$mdPath = Join-Path $OutDir 'discovery.md'
Write-KitTextFile -Path $mdPath -Text $md.ToString()

if (-not $Quiet) {
    Write-Output ('Discovery written: ' + (Get-Rel $mdPath) + ' and ' + (Get-Rel $jsonPath))
    Write-Output ('Projects: ' + $graph.Count + ' | layer violations: ' + $violations.Count + ' | internal packages: ' + $internalPkgs.Count + ' | unknown packages: ' + $unknownPkgs.Count + ' | pipelines: ' + $ci.Count + ' | ' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's')
    Write-Output 'Next: read the .md report (not the JSON) and continue the bootstrap.'
}
