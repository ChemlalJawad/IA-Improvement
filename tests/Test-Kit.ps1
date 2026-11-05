<#
.SYNOPSIS
    Self-test of the AI kit on this machine.
.DESCRIPTION
    1. Static checks: required files, front matter of agents / skills / instructions, JSON files,
       PowerShell syntax (real PowerShell parser), ASCII-only scripts, relative Markdown links.
    2. Sandbox: installs the kit into a temporary git repository with install.ps1, runs the hooks self-test
       and the helper scripts (spec, git context, conflict report, logs, configuration).
    3. .NET (skipped with -Quick or without the SDK): builds a small Clean Architecture sample that uses a fake
       internal package from a local "intranet" feed, then checks discovery, package digests, build/test
       reporting, the architecture rules and the Stop quality gate (block, block, give up).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Kit.ps1
.EXAMPLE
    pwsh -NoProfile -File tests/Test-Kit.ps1 -Quick
#>
param([switch]$Quick, [switch]$KeepSandbox)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = Split-Path -Path $PSScriptRoot -Parent
$kit = Join-Path $repo 'kit'
$psExe = (Get-Process -Id $PID).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
$results = New-Object System.Collections.Generic.List[object]
$script:extraEnv = @{}

function Add-Result {
    param([string]$Area, [string]$Name, [bool]$Ok, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Area = $Area; Name = $Name; Ok = $Ok; Detail = $Detail })
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    $suffix = ''
    if ($Detail -and -not $Ok) { $suffix = ' - ' + $Detail }
    Write-Host ('  {0}  [{1}] {2}{3}' -f $mark, $Area, $Name, $suffix)
}

function Join-Arguments {
    param([string[]]$Items)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Items) {
        if ($null -eq $a) { continue }
        if ($a -eq '') { $out.Add('""'); continue }
        if ($a -notmatch '[\s"]') { $out.Add($a); continue }
        $out.Add('"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"')
    }
    return ($out -join ' ')
}

function Invoke-Proc {
    param([string]$File, [string[]]$Arguments = @(), [string]$WorkingDirectory, [string]$Stdin, [hashtable]$Environment, [int]$TimeoutSec = 600)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = Join-Arguments -Items $Arguments
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $psi.EnvironmentVariables['DOTNET_CLI_UI_LANGUAGE'] = 'en'
    $psi.EnvironmentVariables['DOTNET_NOLOGO'] = '1'
    foreach ($k in @($script:extraEnv.Keys)) { $psi.EnvironmentVariables[[string]$k] = [string]$script:extraEnv[$k] }
    if ($Environment) { foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = [string]$Environment[$k] } }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    if ($Stdin) {
        $bytes = $utf8.GetBytes($Stdin)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ Exit = 124; Out = ''; Err = 'timeout' }
    }
    [void]$o.Wait(20000)
    [void]$e.Wait(5000)
    return [pscustomobject]@{ Exit = $p.ExitCode; Out = [string]$o.Result; Err = [string]$e.Result }
}

function Invoke-KitScript {
    param([string]$Path, [string[]]$Arguments = @(), [string]$Stdin, [hashtable]$Environment, [string]$WorkingDirectory)
    $all = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $Arguments
    if (-not $WorkingDirectory) { $WorkingDirectory = $script:sandbox }
    return (Invoke-Proc -File $psExe -Arguments $all -WorkingDirectory $WorkingDirectory -Stdin $Stdin -Environment $Environment)
}

function Get-FrontMatter {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, $utf8)
    $m = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---')
    $map = @{}
    if (-not $m.Success) { return $null }
    foreach ($line in ($m.Groups[1].Value -split "\r?\n")) {
        $kv = [regex]::Match($line, '^([A-Za-z][A-Za-z0-9-]*):\s*(.*)$')
        if ($kv.Success) { $map[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim().Trim("'").Trim('"') }
    }
    return $map
}

Write-Host ''
Write-Host ('AI kit self-test - ' + $repo)
Write-Host ('PowerShell ' + $PSVersionTable.PSVersion + ' (' + $psExe + ')')
Write-Host ''

# ============================================================================ 1. static checks
Write-Host '1. Static checks'
$required = @(
    'AGENTS.md', 'github/kit/config.json', 'github/kit/lib/KitCore.ps1', 'github/kit/lib/KitDotnet.ps1',
    'github/hooks/kit-hooks.json', 'github/hooks/scripts/pre-tool-guard.ps1', 'github/hooks/scripts/session-start.ps1',
    'github/hooks/scripts/stop-quality-gate.ps1', 'github/hooks/scripts/test-hooks.ps1',
    'github/skills/parallel-work/scripts/worktree.ps1', '.azuredevops/pipelines/ai-kit-pr-checks.yml',
    'vscode/settings.json', 'vscode/mcp.json', 'docs/ai/project-context.md', 'specs/_templates/spec.md'
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $kit $_)) })
Add-Result 'static' 'required kit files present' ($missing.Count -eq 0) ($missing -join ', ')

$skillDirs = @(Get-ChildItem -LiteralPath (Join-Path $kit 'github/skills') -Directory)
$skillProblems = New-Object System.Collections.Generic.List[string]
foreach ($d in $skillDirs) {
    $f = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $f)) { $skillProblems.Add("$($d.Name): no SKILL.md"); continue }
    $fm = Get-FrontMatter -Path $f
    if ($null -eq $fm) { $skillProblems.Add("$($d.Name): no front matter"); continue }
    if ($fm['name'] -ne $d.Name) { $skillProblems.Add("$($d.Name): name '$($fm['name'])' differs from folder") }
    if ($fm['name'] -notmatch '^[a-z0-9-]{1,64}$') { $skillProblems.Add("$($d.Name): invalid name") }
    if (-not $fm['description'] -or $fm['description'].Length -gt 1024) { $skillProblems.Add("$($d.Name): description missing or > 1024 chars") }
}
Add-Result 'static' ("skills front matter ($($skillDirs.Count) skills)") ($skillProblems.Count -eq 0) ($skillProblems -join '; ')

$agentFiles = @(Get-ChildItem -LiteralPath (Join-Path $kit 'github/agents') -Filter '*.agent.md' -File)
$agentNames = @($agentFiles | ForEach-Object { $_.Name -replace '\.agent\.md$', '' })
$agentProblems = New-Object System.Collections.Generic.List[string]
foreach ($a in $agentFiles) {
    $fm = Get-FrontMatter -Path $a.FullName
    $key = $a.Name -replace '\.agent\.md$', ''
    if ($null -eq $fm) { $agentProblems.Add("${key}: no front matter"); continue }
    if ($fm['name'] -ne $key) { $agentProblems.Add("${key}: name differs from file name") }
    if (-not $fm['description']) { $agentProblems.Add("${key}: no description") }
    if (-not $fm['tools']) { $agentProblems.Add("${key}: no tools") }
    $text = [System.IO.File]::ReadAllText($a.FullName, $utf8)
    foreach ($m in [regex]::Matches($text, '(?m)^\s+agent:\s*(\S+)')) { if ($agentNames -notcontains $m.Groups[1].Value) { $agentProblems.Add("${key}: handoff to unknown agent '$($m.Groups[1].Value)'") } }
    $am = [regex]::Match($text, "(?m)^agents:\s*\[(.*)\]")
    if ($am.Success) { foreach ($n in ($am.Groups[1].Value -split ',')) { $n = $n.Trim().Trim("'").Trim('"'); if ($n -and $agentNames -notcontains $n) { $agentProblems.Add("${key}: unknown subagent '$n'") } } }
}
Add-Result 'static' ("agents front matter, handoffs and subagents ($($agentFiles.Count) agents)") ($agentProblems.Count -eq 0) ($agentProblems -join '; ')

$instr = @(Get-ChildItem -LiteralPath (Join-Path $kit 'github/instructions') -Filter '*.instructions.md' -File)
$instrBad = @($instr | Where-Object { $fm = Get-FrontMatter -Path $_.FullName; ($null -eq $fm) -or (-not $fm['applyTo'] -and -not $fm['description']) } | ForEach-Object { $_.Name })
Add-Result 'static' ("instructions front matter ($($instr.Count) files)") ($instrBad.Count -eq 0) ($instrBad -join ', ')

$jsonBad = New-Object System.Collections.Generic.List[string]
foreach ($j in @('github/kit/config.json', 'github/hooks/kit-hooks.json', 'vscode/mcp.json', 'vscode/extensions.json', 'vscode/settings.json')) {
    $raw = [System.IO.File]::ReadAllText((Join-Path $kit $j), $utf8)
    if ($j -like '*settings.json') { $raw = (($raw -split "\r?\n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n" }
    try { $null = ConvertFrom-Json -InputObject $raw } catch { $jsonBad.Add($j + ': ' + $_.Exception.Message) }
}
Add-Result 'static' 'JSON files parse' ($jsonBad.Count -eq 0) ($jsonBad -join '; ')

$scripts = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '[\\/]\.ai-local[\\/]' })
$syntaxBad = New-Object System.Collections.Generic.List[string]
$asciiBad = New-Object System.Collections.Generic.List[string]
foreach ($s in $scripts) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) { $syntaxBad.Add($s.Name + ': ' + $errors[0].Message + ' (line ' + $errors[0].Extent.StartLineNumber + ')') }
    $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
    foreach ($b in $bytes) { if ($b -gt 127) { $asciiBad.Add($s.Name); break } }
}
Add-Result 'static' ("PowerShell syntax ($($scripts.Count) scripts)") ($syntaxBad.Count -eq 0) ($syntaxBad -join '; ')
Add-Result 'static' 'scripts are ASCII-only (Windows PowerShell 5.1 safe)' ($asciiBad.Count -eq 0) ($asciiBad -join ', ')

$linkBad = New-Object System.Collections.Generic.List[string]
foreach ($md in (Get-ChildItem -LiteralPath $kit -Recurse -File -Filter '*.md' -Force)) {
    $text = [System.IO.File]::ReadAllText($md.FullName, $utf8)
    foreach ($m in [regex]::Matches($text, '\]\((?!https?:|mailto:|#)([^)\s]+)\)')) {
        $target = ($m.Groups[1].Value -split '#')[0]
        if (-not $target -or $target -match '[{}<>]') { continue }
        $resolved = Join-Path $md.DirectoryName $target
        if (-not (Test-Path -LiteralPath $resolved)) { $linkBad.Add($md.Name + ' -> ' + $m.Groups[1].Value) }
    }
}
Add-Result 'static' 'relative Markdown links resolve' ($linkBad.Count -eq 0) ($linkBad -join '; ')

# ============================================================================ 2. sandbox
Write-Host ''
Write-Host '2. Sandbox repository'
$script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('ai-kit-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:sandbox -Force | Out-Null
$sandbox = $script:sandbox
$gitOk = [bool](Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)
try {
    $inst = Invoke-Proc -File $psExe -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repo 'install.ps1'), '-Target', $sandbox) -WorkingDirectory $repo
    Add-Result 'sandbox' 'install.ps1 copies the kit' ($inst.Exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $sandbox '.github/hooks/kit-hooks.json'))) ($inst.Err.Trim())

    if ($gitOk) {
        $gitExe = (Get-Command -Name git -CommandType Application | Select-Object -First 1).Path
        foreach ($g in @(@('init', '-q'), @('config', 'user.email', 'kit-test@example.invalid'), @('config', 'user.name', 'kit test'), @('checkout', '-q', '-b', 'feature/123-kit-test'), @('add', '-A'), @('commit', '-q', '-m', 'chore: kit'))) { $null = Invoke-Proc -File $gitExe -Arguments $g -WorkingDirectory $sandbox }
    } else {
        Add-Result 'sandbox' 'git available' $false 'git not found on PATH: some checks are skipped'
    }

    $th = Invoke-KitScript -Path (Join-Path $sandbox '.github/hooks/scripts/test-hooks.ps1')
    $latency = [regex]::Match($th.Out, 'latency: ~(\d+) ms').Groups[1].Value
    Add-Result 'hooks' ("hooks self-test (PreToolUse ~$latency ms)") ($th.Exit -eq 0) (($th.Out -split "`n" | Where-Object { $_ -match 'FAIL' }) -join ' | ')

    $title = 'D' + [char]0x00E9 + 'claration de sinistre par un courtier'
    $ns = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/spec/scripts/new-spec.ps1') -Arguments @('-Title', $title, '-WorkItem', 'AB#1234')
    $specDir = Join-Path $sandbox 'specs/001-declaration-de-sinistre-par-un-courtier'
    Add-Result 'scripts' 'new-spec creates a numbered spec with an ASCII slug' ($ns.Exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $specDir 'spec.md'))) ($ns.Out + $ns.Err).Trim()
    $np = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/spec/scripts/new-spec.ps1') -Arguments @('-Spec', '001', '-AddPlan')
    Add-Result 'scripts' 'new-spec -AddPlan creates plan.md and tasks.md' ($np.Exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $specDir 'tasks.md'))) ($np.Out + $np.Err).Trim()
    $specText = ''
    if (Test-Path -LiteralPath (Join-Path $specDir 'spec.md')) { $specText = [System.IO.File]::ReadAllText((Join-Path $specDir 'spec.md'), $utf8) }
    Add-Result 'scripts' 'spec keeps the accented title (UTF-8)' ($specText.Contains($title)) ''

    $ss = Invoke-KitScript -Path (Join-Path $sandbox '.github/hooks/scripts/session-start.ps1') -Stdin '{"hook_event_name":"SessionStart","source":"new"}'
    Add-Result 'hooks' 'session start reports bootstrap status and open specs' ($ss.Exit -eq 0 -and $ss.Out -match 'not adapted' -and $ss.Out -match '001-declaration') $ss.Out

    if ($gitOk) {
        $gc = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/git-workflow/scripts/git-context.ps1')
        Add-Result 'scripts' 'git-context reports branch and work item' ($gc.Exit -eq 0 -and $gc.Out -match 'feature/123-kit-test' -and $gc.Out -match 'AB#123') ($gc.Out + $gc.Err).Trim()

        $wtScript = Join-Path $sandbox '.github/skills/parallel-work/scripts/worktree.ps1'
        $wtPath = Join-Path ($sandbox + '.worktrees') '77-parallel-task'
        $w1 = Invoke-KitScript -Path $wtScript -Arguments @('-New', 'Parallel task', '-WorkItem', 'AB#77', '-Base', 'HEAD', '-NoFetch')
        Add-Result 'scripts' 'worktree -New creates a worktree on its own branch' ($w1.Exit -eq 0 -and $w1.Out -match 'feature/77-parallel-task' -and (Test-Path -LiteralPath (Join-Path $wtPath 'AGENTS.md'))) ($w1.Out + $w1.Err).Trim()
        $w2 = Invoke-KitScript -Path $wtScript -Arguments @('-List')
        Add-Result 'scripts' 'worktree -List shows it' ($w2.Exit -eq 0 -and $w2.Out -match '77-parallel-task') ($w2.Out + $w2.Err).Trim()
        $w3 = Invoke-KitScript -Path $wtScript -Arguments @('-Remove', '77-parallel-task', '-DeleteBranch')
        Add-Result 'scripts' 'worktree -Remove cleans it up' ($w3.Exit -eq 0 -and -not (Test-Path -LiteralPath $wtPath) -and $w3.Out -match 'Branch deleted') ($w3.Out + $w3.Err).Trim()

        $null = Invoke-Proc -File $gitExe -Arguments @('add', '-A') -WorkingDirectory $sandbox
        $null = Invoke-Proc -File $gitExe -Arguments @('commit', '-q', '-m', 'docs: spec') -WorkingDirectory $sandbox
        $conflictFile = Join-Path $sandbox 'conflict.txt'
        [System.IO.File]::WriteAllText($conflictFile, "line`n", $utf8)
        $null = Invoke-Proc -File $gitExe -Arguments @('add', '-A') -WorkingDirectory $sandbox
        $null = Invoke-Proc -File $gitExe -Arguments @('commit', '-q', '-m', 'base') -WorkingDirectory $sandbox
        $null = Invoke-Proc -File $gitExe -Arguments @('checkout', '-q', '-b', 'other') -WorkingDirectory $sandbox
        [System.IO.File]::WriteAllText($conflictFile, "theirs`n", $utf8)
        $null = Invoke-Proc -File $gitExe -Arguments @('commit', '-q', '-am', 'theirs') -WorkingDirectory $sandbox
        $null = Invoke-Proc -File $gitExe -Arguments @('checkout', '-q', 'feature/123-kit-test') -WorkingDirectory $sandbox
        [System.IO.File]::WriteAllText($conflictFile, "ours`n", $utf8)
        $null = Invoke-Proc -File $gitExe -Arguments @('commit', '-q', '-am', 'ours') -WorkingDirectory $sandbox
        $null = Invoke-Proc -File $gitExe -Arguments @('merge', 'other') -WorkingDirectory $sandbox
        $cr = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/merge-conflicts/scripts/conflict-report.ps1')
        Add-Result 'scripts' 'conflict-report detects the merge conflict' ($cr.Exit -eq 0 -and $cr.Out -match 'Operation: merge' -and $cr.Out -match 'conflict\.txt') ($cr.Out + $cr.Err).Trim()
        $null = Invoke-Proc -File $gitExe -Arguments @('merge', '--abort') -WorkingDirectory $sandbox
    }

    $sl = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/retro/scripts/summarize-logs.ps1')
    Add-Result 'scripts' 'summarize-logs reads the hook logs' ($sl.Exit -eq 0 -and $sl.Out -match 'Agent activity') ($sl.Out + $sl.Err).Trim()
    $configureKit = Join-Path $sandbox '.github/skills/bootstrap/scripts/configure-kit.ps1'
    $ck = Invoke-KitScript -Path $configureKit -Arguments @('-Show')
    Add-Result 'scripts' 'configure-kit -Show' ($ck.Exit -eq 0 -and $ck.Out -match 'Kit version') ($ck.Out + $ck.Err).Trim()
    $cf = Invoke-KitScript -Path $configureKit -Arguments @('-Format', 'whitespace', '-Show')
    Add-Result 'scripts' 'configure-kit -Format sets the quality gate formatting' ($cf.Exit -eq 0 -and $cf.Out -match 'format=whitespace') ($cf.Out + $cf.Err).Trim()
    $null = Invoke-KitScript -Path $configureKit -Arguments @('-Format', 'off')

    # ======================================================================== 3. .NET sample
    $dotnet = Get-Command -Name dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-Host ''
    if ($Quick -or -not $dotnet -or -not $gitOk) {
        Write-Host '3. .NET sample: skipped (-Quick, or dotnet / git not found)'
    } else {
        Write-Host '3. .NET sample (Clean Architecture + fake internal package)'
        $dn = $dotnet.Path
        $work = Join-Path $sandbox '.ai-local/test-work'
        $feed = Join-Path $work 'feed'
        New-Item -ItemType Directory -Path $feed -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $sandbox '.ai-local/.gitignore'), "*`n", $utf8)
        # Isolated NuGet cache: the fake package must not land in the user's global packages folder.
        $script:extraEnv['NUGET_PACKAGES'] = (Join-Path $work 'nuget-packages')
        $pkgDir = Join-Path $work 'Acme.Platform.Messaging'
        $null = Invoke-Proc -File $dn -Arguments @('new', 'classlib', '-n', 'Acme.Platform.Messaging', '-o', $pkgDir) -WorkingDirectory $work
        $csproj = Join-Path $pkgDir 'Acme.Platform.Messaging.csproj'
        $proj = [System.IO.File]::ReadAllText($csproj, $utf8)
        $proj = $proj.Replace('</PropertyGroup>', "  <GenerateDocumentationFile>true</GenerateDocumentationFile>`n    <Version>1.2.0</Version>`n    <Authors>Acme Platform Team</Authors>`n    <Description>Company messaging abstractions (fake package for the kit self-test).</Description>`n  </PropertyGroup>")
        [System.IO.File]::WriteAllText($csproj, $proj, $utf8)
        Remove-Item -LiteralPath (Join-Path $pkgDir 'Class1.cs') -ErrorAction SilentlyContinue
        $pkgCode = @'
namespace Acme.Platform.Messaging;

/// <summary>Publishes integration events to the company service bus.</summary>
public interface IEventPublisher
{
    /// <summary>Publishes an integration event.</summary>
    System.Threading.Tasks.Task PublishAsync<T>(T message, System.Threading.CancellationToken cancellationToken = default) where T : IntegrationEvent;
}

/// <summary>Base type for every integration event.</summary>
public abstract record IntegrationEvent(System.Guid Id, System.DateTimeOffset OccurredOn);
'@
        [System.IO.File]::WriteAllText((Join-Path $pkgDir 'Messaging.cs'), $pkgCode, $utf8)
        $pack = Invoke-Proc -File $dn -Arguments @('pack', $csproj, '-c', 'Release', '-o', $feed) -WorkingDirectory $work
        Add-Result 'dotnet' 'fake internal package packed into the local intranet feed' ($pack.Exit -eq 0) (((($pack.Out + $pack.Err) -split "`n") | Select-Object -Last 5) -join ' ')

        $nuget = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<configuration>`n  <packageSources>`n    <clear />`n    <add key=`"intranet`" value=`"$feed`" />`n    <add key=`"nuget.org`" value=`"https://api.nuget.org/v3/index.json`" />`n  </packageSources>`n  <packageSourceMapping>`n    <packageSource key=`"intranet`"><package pattern=`"Acme.*`" /></packageSource>`n    <packageSource key=`"nuget.org`"><package pattern=`"*`" /></packageSource>`n  </packageSourceMapping>`n</configuration>`n"
        [System.IO.File]::WriteAllText((Join-Path $sandbox 'nuget.config'), $nuget, $utf8)
        $steps = @(
            @('new', 'sln', '-n', 'Acme.Shop'),
            @('new', 'classlib', '-n', 'Acme.Shop.Domain', '-o', 'src/Acme.Shop.Domain'),
            @('new', 'classlib', '-n', 'Acme.Shop.Application', '-o', 'src/Acme.Shop.Application'),
            @('new', 'classlib', '-n', 'Acme.Shop.Infrastructure', '-o', 'src/Acme.Shop.Infrastructure'),
            @('new', 'classlib', '-n', 'Acme.Shop.Api', '-o', 'src/Acme.Shop.Api'),
            @('add', 'src/Acme.Shop.Application/Acme.Shop.Application.csproj', 'reference', 'src/Acme.Shop.Domain/Acme.Shop.Domain.csproj'),
            @('add', 'src/Acme.Shop.Infrastructure/Acme.Shop.Infrastructure.csproj', 'reference', 'src/Acme.Shop.Application/Acme.Shop.Application.csproj'),
            @('add', 'src/Acme.Shop.Api/Acme.Shop.Api.csproj', 'reference', 'src/Acme.Shop.Application/Acme.Shop.Application.csproj', 'src/Acme.Shop.Infrastructure/Acme.Shop.Infrastructure.csproj'),
            @('add', 'src/Acme.Shop.Application/Acme.Shop.Application.csproj', 'package', 'Acme.Platform.Messaging', '--version', '1.2.0')
        )
        $setupOk = $true
        foreach ($s in $steps) { $r = Invoke-Proc -File $dn -Arguments $s -WorkingDirectory $sandbox; if ($r.Exit -ne 0) { $setupOk = $false; Write-Host ('    step failed: dotnet ' + ($s -join ' ') + ' -> ' + (($r.Out + $r.Err).Trim() -split "`n" | Select-Object -Last 2)) } }
        $sln = @(Get-ChildItem -LiteralPath $sandbox -File | Where-Object { $_.Name -match '^Acme\.Shop\.slnx?$' } | Select-Object -First 1)
        if ($sln.Count -gt 0) { foreach ($p in @('src/Acme.Shop.Domain/Acme.Shop.Domain.csproj', 'src/Acme.Shop.Application/Acme.Shop.Application.csproj', 'src/Acme.Shop.Infrastructure/Acme.Shop.Infrastructure.csproj', 'src/Acme.Shop.Api/Acme.Shop.Api.csproj')) { $null = Invoke-Proc -File $dn -Arguments @('sln', $sln[0].Name, 'add', $p) -WorkingDirectory $sandbox } }
        foreach ($c in @('src/Acme.Shop.Domain/Class1.cs', 'src/Acme.Shop.Application/Class1.cs', 'src/Acme.Shop.Infrastructure/Class1.cs', 'src/Acme.Shop.Api/Class1.cs')) { Remove-Item -LiteralPath (Join-Path $sandbox $c) -ErrorAction SilentlyContinue }
        $domainCode = @'
namespace Acme.Shop.Domain;

public sealed class Order
{
    private readonly System.Collections.Generic.List<string> _lines = new();
    public bool IsClosed { get; private set; }
    public System.Collections.Generic.IReadOnlyList<string> Lines => _lines;

    public void AddLine(string product)
    {
        if (IsClosed) { throw new System.InvalidOperationException("Order is closed."); }
        _lines.Add(product);
    }

    public void Close() => IsClosed = true;
}
'@
        $appCode = @'
using Acme.Platform.Messaging;

namespace Acme.Shop.Application;

public sealed record OrderClosed(System.Guid Id, System.DateTimeOffset OccurredOn) : IntegrationEvent(Id, OccurredOn);

public sealed class CloseOrderHandler(IEventPublisher publisher)
{
    public System.Threading.Tasks.Task HandleAsync(System.Threading.CancellationToken cancellationToken)
        => publisher.PublishAsync(new OrderClosed(System.Guid.NewGuid(), System.DateTimeOffset.UtcNow), cancellationToken);
}
'@
        [System.IO.File]::WriteAllText((Join-Path $sandbox 'src/Acme.Shop.Domain/Order.cs'), $domainCode, $utf8)
        [System.IO.File]::WriteAllText((Join-Path $sandbox 'src/Acme.Shop.Application/CloseOrderHandler.cs'), $appCode, $utf8)

        # Test project needs xunit from nuget.org: optional when offline.
        $testsOk = $false
        $tn = Invoke-Proc -File $dn -Arguments @('new', 'xunit', '-n', 'Acme.Shop.Domain.Tests', '-o', 'tests/Acme.Shop.Domain.Tests') -WorkingDirectory $sandbox
        if ($tn.Exit -eq 0) {
            $null = Invoke-Proc -File $dn -Arguments @('add', 'tests/Acme.Shop.Domain.Tests/Acme.Shop.Domain.Tests.csproj', 'reference', 'src/Acme.Shop.Domain/Acme.Shop.Domain.csproj') -WorkingDirectory $sandbox
            Remove-Item -LiteralPath (Join-Path $sandbox 'tests/Acme.Shop.Domain.Tests/UnitTest1.cs') -ErrorAction SilentlyContinue
            $testCode = @'
using Acme.Shop.Domain;
using Xunit;

namespace Acme.Shop.Domain.Tests;

public class OrderTests
{
    [Fact]
    public void AddLine_adds_a_line()
    {
        var order = new Order();
        order.AddLine("book");
        Assert.Single(order.Lines);
    }

    [Fact]
    public void Cannot_add_line_to_closed_order()
    {
        var order = new Order();
        order.Close();
        order.AddLine("pen"); // fails on purpose: the self-test checks failure reporting
        Assert.Empty(order.Lines);
    }
}
'@
            [System.IO.File]::WriteAllText((Join-Path $sandbox 'tests/Acme.Shop.Domain.Tests/OrderTests.cs'), $testCode, $utf8)
            if ($sln.Count -gt 0) { $null = Invoke-Proc -File $dn -Arguments @('sln', $sln[0].Name, 'add', 'tests/Acme.Shop.Domain.Tests/Acme.Shop.Domain.Tests.csproj') -WorkingDirectory $sandbox }
        }
        $restore = Invoke-Proc -File $dn -Arguments @('restore') -WorkingDirectory $sandbox
        if ($restore.Exit -eq 0 -and $tn.Exit -eq 0) { $testsOk = $true }
        elseif ($tn.Exit -eq 0) {
            Write-Host '    restore failed (offline?): removing the test project and continuing without tests'
            if ($sln.Count -gt 0) { $null = Invoke-Proc -File $dn -Arguments @('sln', $sln[0].Name, 'remove', 'tests/Acme.Shop.Domain.Tests/Acme.Shop.Domain.Tests.csproj') -WorkingDirectory $sandbox }
            Remove-Item -LiteralPath (Join-Path $sandbox 'tests') -Recurse -Force -ErrorAction SilentlyContinue
            $restore = Invoke-Proc -File $dn -Arguments @('restore') -WorkingDirectory $sandbox
        }
        Add-Result 'dotnet' 'sample solution created and restored (intranet feed + nuget.org)' ($setupOk -and $restore.Exit -eq 0) (((($restore.Out + $restore.Err).Trim() -split "`n") | Select-Object -Last 3) -join ' ')
        $null = Invoke-Proc -File $gitExe -Arguments @('add', '-A') -WorkingDirectory $sandbox
        $null = Invoke-Proc -File $gitExe -Arguments @('commit', '-q', '-m', 'feat: sample') -WorkingDirectory $sandbox

        $disc = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/project-discovery/scripts/discover-solution.ps1')
        $dj = $null
        try { $dj = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText((Join-Path $sandbox '.ai-local/discovery/discovery.json'), $utf8)) } catch { }
        $domainLayer = ''
        $origin = ''
        if ($dj) {
            $domainLayer = [string](@($dj.projects | Where-Object { $_.name -eq 'Acme.Shop.Domain' } | Select-Object -First 1).layer)
            $origin = [string](@($dj.packages | Where-Object { $_.id -eq 'Acme.Platform.Messaging' } | Select-Object -First 1).origin)
        }
        Add-Result 'dotnet' 'discovery maps projects to layers' ($disc.Exit -eq 0 -and $domainLayer -eq 'Domain' -and @($dj.violations).Count -eq 0) ("layer=$domainLayer " + $disc.Err.Trim())
        Add-Result 'dotnet' 'discovery classifies the intranet package as internal' ($origin -eq 'internal') "origin=$origin"

        $ip = Invoke-KitScript -Path (Join-Path $sandbox '.github/skills/internal-packages/scripts/inspect-package.ps1') -Arguments @('-AllInternal')
        $digestPath = Join-Path $sandbox 'docs/ai/packages/Acme.Platform.Messaging.md'
        $digest = ''
        if (Test-Path -LiteralPath $digestPath) { $digest = [System.IO.File]::ReadAllText($digestPath, $utf8) }
        Add-Result 'dotnet' 'package digest lists the API, XML docs and usages' ($ip.Exit -eq 0 -and $digest -match 'IEventPublisher' -and $digest -match 'Publishes integration events' -and $digest -match 'CloseOrderHandler') (($ip.Out + $ip.Err).Trim())

        $check = Join-Path $sandbox '.github/skills/dotnet-build-test/scripts/dotnet-check.ps1'
        $b1 = Invoke-KitScript -Path $check -Arguments @('-Build')
        Add-Result 'dotnet' 'dotnet-check -Build passes on a clean solution' ($b1.Exit -eq 0 -and $b1.Out -match 'BUILD: OK') $b1.Out
        $orderPath = Join-Path $sandbox 'src/Acme.Shop.Domain/Order.cs'
        $original = [System.IO.File]::ReadAllText($orderPath, $utf8)
        [System.IO.File]::WriteAllText($orderPath, $original + "`npublic sealed class Broken { public int M() { int x = `"text`"; return x; } }`n", $utf8)
        $b2 = Invoke-KitScript -Path $check -Arguments @('-Build', '-Ci')
        Add-Result 'dotnet' 'dotnet-check reports compiler errors compactly (CS0029)' ($b2.Exit -eq 1 -and $b2.Out -match 'CS0029' -and $b2.Out -match 'Order\.cs') $b2.Out
        Add-Result 'dotnet' 'dotnet-check -Ci annotates the error for Azure Pipelines' ($b2.Out -match '##vso\[task\.logissue type=error;sourcepath=src/Acme\.Shop\.Domain/Order\.cs;linenumber=\d+') $b2.Out
        [System.IO.File]::WriteAllText($orderPath, $original, $utf8)

        $domainProj = Join-Path $sandbox 'src/Acme.Shop.Domain/Acme.Shop.Domain.csproj'
        $projOriginal = [System.IO.File]::ReadAllText($domainProj, $utf8)
        [System.IO.File]::WriteAllText($domainProj, $projOriginal.Replace('</Project>', "  <ItemGroup>`n    <ProjectReference Include=`"..\Acme.Shop.Infrastructure\Acme.Shop.Infrastructure.csproj`" />`n  </ItemGroup>`n</Project>"), $utf8)
        $a1 = Invoke-KitScript -Path $check -Arguments @('-Build', '-Architecture')
        Add-Result 'dotnet' 'architecture check flags Domain -> Infrastructure' ($a1.Exit -eq 1 -and $a1.Out -match 'ARCHITECTURE: 1 layer violation') $a1.Out
        [System.IO.File]::WriteAllText($domainProj, $projOriginal, $utf8)

        if ($testsOk) {
            $t1 = Invoke-KitScript -Path $check -Arguments @('-Test', '-Scope', 'all')
            Add-Result 'dotnet' 'dotnet-check reports the failing test with its location' ($t1.Exit -eq 1 -and $t1.Out -match 'Cannot_add_line_to_closed_order' -and $t1.Out -match '1 failed') $t1.Out
        } else {
            Add-Result 'dotnet' 'test reporting (skipped: xunit not restorable offline)' $true ''
        }

        # Stop quality gate: change a file, then stop three times without fixing anything.
        [System.IO.File]::WriteAllText($orderPath, $original + "`n// touched by the self-test`n", $utf8)
        $gate = Join-Path $sandbox '.github/hooks/scripts/stop-quality-gate.ps1'
        $payload = '{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"kit-selftest-gate"}'
        $g1 = Invoke-KitScript -Path $gate -Stdin $payload
        $g2 = Invoke-KitScript -Path $gate -Stdin $payload
        $g3 = Invoke-KitScript -Path $gate -Stdin $payload
        if ($testsOk) {
            Add-Result 'hooks' 'quality gate blocks on the failing test' ($g1.Exit -eq 0 -and $g1.Out -match '"decision":"block"' -and $g1.Out -match 'Cannot_add_line_to_closed_order') $g1.Out
            Add-Result 'hooks' 'quality gate reuses the cached failure (attempt 2)' ($g2.Out -match 'attempt 2 of 2') $g2.Out
            Add-Result 'hooks' 'quality gate gives up after maxBlocks' ($g3.Out -match 'still failing') $g3.Out
        } else {
            Add-Result 'hooks' 'quality gate passes a green change' ($g1.Exit -eq 0 -and $g1.Out -match 'Quality gate passed') $g1.Out
            Add-Result 'hooks' 'quality gate caches the green result' ($g2.Out.Trim() -eq '{}') $g2.Out
        }
        [System.IO.File]::WriteAllText($orderPath, $original, $utf8)
        $null = Invoke-Proc -File $dn -Arguments @('build-server', 'shutdown') -WorkingDirectory $sandbox
    }
} finally {
    if (-not $KeepSandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($sandbox + '.worktrees') -Recurse -Force -ErrorAction SilentlyContinue
    }
    else { Write-Host ('Sandbox kept: ' + $sandbox) }
}

$failed = @($results | Where-Object { -not $_.Ok })
Write-Host ''
Write-Host ('Result: {0}/{1} checks passed.' -f ($results.Count - $failed.Count), $results.Count)
if ($failed.Count -gt 0) { exit 1 }
exit 0
