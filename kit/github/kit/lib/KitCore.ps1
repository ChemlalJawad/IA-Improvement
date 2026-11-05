# KitCore.ps1 - core helpers shared by the AI kit hooks and skill scripts.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
# Usage (dot-source):  . (Join-Path $PSScriptRoot '..\..\kit\lib\KitCore.ps1')

Set-StrictMode -Off
$ProgressPreference = 'SilentlyContinue'
$script:KitUtf8 = New-Object System.Text.UTF8Encoding($false)
$script:KitGlobCache = @{}

# --------------------------------------------------------------------------- paths

function Get-KitRootFromScript {
    # Repository root, given a script directory and how many levels it sits below the root.
    # .github/hooks/scripts -> 3, .github/kit/lib -> 3, .github/skills/<name>/scripts -> 4
    param([Parameter(Mandatory = $true)][string]$ScriptDir, [int]$Levels = 3)
    $dir = $ScriptDir
    for ($i = 0; $i -lt $Levels; $i++) { $dir = Split-Path -Path $dir -Parent }
    return $dir
}

function Get-KitRelativePath {
    # Normalizes a path or file URI to a repo-relative path with forward slashes.
    # Paths outside the repository are returned absolute (forward slashes).
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim().Trim('"').Trim("'")
    if ($p.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $p = [System.Uri]::UnescapeDataString($p.Substring(7))
        if ($p -match '^/[A-Za-z]:') { $p = $p.Substring(1) }
    }
    $p = $p.Replace('\', '/')
    $r = $Root.Replace('\', '/').TrimEnd('/')
    if ($p.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return '.' }
    if ($p.StartsWith($r + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $p.Substring($r.Length + 1) }
    if ($p -match '^[A-Za-z]:/' -or $p.StartsWith('/') -or $p.StartsWith('~')) { return $p }
    while ($p.StartsWith('./')) { $p = $p.Substring(2) }
    return $p
}

function Test-KitPathOutsideRepo {
    param([string]$RelativePath)
    if (-not $RelativePath) { return $false }
    return ($RelativePath -match '^[A-Za-z]:/' -or $RelativePath.StartsWith('/') -or $RelativePath.StartsWith('~') -or $RelativePath.StartsWith('../'))
}

function ConvertTo-KitGlobRegex {
    # Glob -> regex. Supports **, *, ? and '**/' (zero or more directories). Case-insensitive at match time.
    param([string]$Glob)
    if ($script:KitGlobCache.ContainsKey($Glob)) { return $script:KitGlobCache[$Glob] }
    $g = $Glob.Replace('\', '/')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $i = 0
    while ($i -lt $g.Length) {
        $c = $g[$i]
        if ($c -eq [char]'*') {
            if (($i + 1) -lt $g.Length -and $g[$i + 1] -eq [char]'*') {
                if (($i + 2) -lt $g.Length -and $g[$i + 2] -eq [char]'/') { [void]$sb.Append('(?:.*/)?'); $i += 3; continue }
                [void]$sb.Append('.*'); $i += 2; continue
            }
            [void]$sb.Append('[^/]*'); $i++; continue
        }
        if ($c -eq [char]'?') { [void]$sb.Append('[^/]'); $i++; continue }
        [void]$sb.Append([regex]::Escape([string]$c)); $i++
    }
    [void]$sb.Append('$')
    $rx = $sb.ToString()
    $script:KitGlobCache[$Glob] = $rx
    return $rx
}

function Test-KitGlobMatch {
    param([string]$Path, [string]$Glob)
    if (-not $Path -or -not $Glob) { return $false }
    return ($Path.Replace('\', '/') -match (ConvertTo-KitGlobRegex -Glob $Glob))
}

function Find-KitGlobMatch {
    # Returns the first glob of $Globs matching $Path, or $null.
    param([string]$Path, $Globs)
    foreach ($g in @($Globs)) { if ($g -and (Test-KitGlobMatch -Path $Path -Glob ([string]$g))) { return [string]$g } }
    return $null
}

function ConvertTo-KitSlug {
    # ASCII kebab-case for folder and branch names ("Declaration de sinistre" -> "declaration-de-sinistre").
    param([string]$Text, [int]$Max = 40)
    $norm = ([string]$Text).Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $s = ($sb.ToString().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max).Trim('-') }
    if (-not $s) { $s = 'feature' }
    return $s
}

# --------------------------------------------------------------------------- objects

function Get-KitProp {
    # First non-null property among $Names (case-insensitive). Works for PSCustomObject and hashtables.
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($n in $Names) {
            foreach ($k in @($Object.Keys)) {
                if ([string]::Equals([string]$k, $n, [System.StringComparison]::OrdinalIgnoreCase) -and $null -ne $Object[$k]) { return $Object[$k] }
            }
        }
        return $null
    }
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}

function ConvertTo-KitHashtable {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-KitHashtable -Obj $p.Value }
        return $h
    }
    if (($Obj -is [System.Collections.IEnumerable]) -and -not ($Obj -is [string]) -and -not ($Obj -is [System.Collections.IDictionary])) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($i in $Obj) { $list.Add((ConvertTo-KitHashtable -Obj $i)) }
        return ,$list.ToArray()
    }
    return $Obj
}

function Add-KitStringLeaves {
    param($Node, [string]$Key, [int]$Depth, $Acc)
    if ($null -eq $Node -or $Depth -gt 12) { return }
    if ($Node -is [string]) { $Acc.Add([pscustomobject]@{ Key = $Key; Value = $Node }); return }
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($k in @($Node.Keys)) { Add-KitStringLeaves -Node $Node[$k] -Key ([string]$k) -Depth ($Depth + 1) -Acc $Acc }
        return
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Node.PSObject.Properties) { Add-KitStringLeaves -Node $p.Value -Key $p.Name -Depth ($Depth + 1) -Acc $Acc }
        return
    }
    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($i in $Node) { Add-KitStringLeaves -Node $i -Key $Key -Depth ($Depth + 1) -Acc $Acc }
    }
}

function Get-KitStringLeaves {
    # Flattens any JSON-like object into a list of { Key, Value } string leaves.
    param($Node)
    $acc = New-Object System.Collections.Generic.List[object]
    Add-KitStringLeaves -Node $Node -Key '' -Depth 0 -Acc $acc
    return ,$acc.ToArray()
}

# --------------------------------------------------------------------------- files / json

function Read-KitTextFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return [System.IO.File]::ReadAllText($Path, $script:KitUtf8)
}

function Write-KitTextFile {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, $script:KitUtf8)
}

function Read-KitJsonFile {
    param([string]$Path)
    try {
        $raw = Read-KitTextFile -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return (ConvertFrom-Json -InputObject $raw)
    } catch { return $null }
}

function Write-KitJsonFile {
    param([string]$Path, $Object, [int]$Depth = 12)
    Write-KitTextFile -Path $Path -Text ((ConvertTo-Json -InputObject $Object -Depth $Depth) + "`n")
}

# --------------------------------------------------------------------------- native commands

function ConvertTo-KitArgumentString {
    # Quotes arguments with the MSVCRT rules used by .NET on every OS.
    param([string[]]$Arguments)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Arguments) {
        if ($null -eq $a) { continue }
        if ($a.Length -eq 0) { $parts.Add('""'); continue }
        if ($a -notmatch '[\s"]') { $parts.Add($a); continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq [char]'\') { $bs++; continue }
            if ($ch -eq [char]'"') {
                [void]$sb.Append(('\' * ($bs * 2 + 1)))
                [void]$sb.Append('"')
                $bs = 0
                continue
            }
            if ($bs -gt 0) { [void]$sb.Append(('\' * $bs)); $bs = 0 }
            [void]$sb.Append($ch)
        }
        if ($bs -gt 0) { [void]$sb.Append(('\' * ($bs * 2))) }
        [void]$sb.Append('"')
        $parts.Add($sb.ToString())
    }
    return ($parts -join ' ')
}

function Split-KitLines {
    param([string]$Text)
    $list = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrEmpty($Text)) {
        foreach ($l in ($Text -split "\r?\n")) { $list.Add($l) }
        while ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
    }
    return ,$list.ToArray()
}

function Stop-KitProcessTree {
    param($Process)
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) { $Process.Kill($true); return }
    } catch { }
    try {
        if ($env:OS -eq 'Windows_NT') {
            $tk = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            if (Test-Path -LiteralPath $tk) { Start-Process -FilePath $tk -ArgumentList @('/PID', [string]$Process.Id, '/T', '/F') -WindowStyle Hidden -Wait | Out-Null; return }
        }
        $Process.Kill()
    } catch {
        try { $Process.Kill() } catch { }
    }
}

function Invoke-KitNative {
    # Runs an executable without a shell, captures UTF-8 stdout/stderr, never throws.
    # Returns: ExitCode (127 = not found, 124 = timeout), StdOut[], StdErr[], Output, TimedOut, DurationSec.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [int]$TimeoutSec = 0,
        [hashtable]$Environment
    )
    $res = [pscustomobject]@{ ExitCode = 127; StdOut = @(); StdErr = @(); Output = ''; TimedOut = $false; DurationSec = 0.0 }
    $cmd = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { $res.StdErr = @("command not found: $FilePath"); return $res }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cmd.Path
    $psi.Arguments = ConvertTo-KitArgumentString -Arguments $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:KitUtf8
    $psi.StandardErrorEncoding = $script:KitUtf8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.EnvironmentVariables['DOTNET_CLI_UI_LANGUAGE'] = 'en'
    $psi.EnvironmentVariables['DOTNET_NOLOGO'] = '1'
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    if ($Environment) { foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = [string]$Environment[$k] } }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { [void]$proc.Start() } catch { $res.StdErr = @("failed to start ${FilePath}: " + $_.Exception.Message); return $res }
    try { $proc.StandardInput.Close() } catch { }
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if ($TimeoutSec -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $res.TimedOut = $true
            Stop-KitProcessTree -Process $proc
            [void]$proc.WaitForExit(10000)
        }
    } else {
        $proc.WaitForExit()
    }
    $sw.Stop()
    $stdout = ''
    $stderr = ''
    # Child processes (e.g. build servers) may keep the pipes open: never wait forever.
    if ($outTask.Wait(20000)) { $stdout = $outTask.Result } else { $stdout = '[kit] output not fully captured: a child process still holds the pipe' }
    if ($errTask.Wait(5000)) { $stderr = $errTask.Result }
    if ($res.TimedOut) { $res.ExitCode = 124 } else { try { $res.ExitCode = $proc.ExitCode } catch { $res.ExitCode = 1 } }
    $res.Output = $stdout
    $res.StdOut = Split-KitLines -Text $stdout
    $res.StdErr = Split-KitLines -Text $stderr
    $res.DurationSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    return $res
}

function Invoke-KitGit {
    param([string]$Root, [string[]]$Arguments, [int]$TimeoutSec = 30)
    $all = @('-C', $Root, '-c', 'core.quotepath=off') + $Arguments
    return (Invoke-KitNative -FilePath 'git' -Arguments $all -TimeoutSec $TimeoutSec)
}

function Get-KitGitBranch {
    param([string]$Root)
    $r = Invoke-KitGit -Root $Root -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -TimeoutSec 10
    if ($r.ExitCode -eq 0 -and $r.StdOut.Count -gt 0) { return $r.StdOut[0].Trim() }
    return $null
}

function Get-KitChangedFiles {
    # Repo-relative paths (forward slashes) of modified, staged and untracked files.
    param([string]$Root)
    $r = Invoke-KitGit -Root $Root -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -TimeoutSec 30
    $files = New-Object System.Collections.Generic.List[string]
    if ($r.ExitCode -ne 0) { return ,$files.ToArray() }
    foreach ($line in $r.StdOut) {
        if ($line.Length -lt 4) { continue }
        $path = $line.Substring(3)
        if ($path.Contains(' -> ')) { $path = ($path -split ' -> ')[1] }
        $files.Add($path.Trim().Trim('"').Replace('\', '/'))
    }
    return ,$files.ToArray()
}

function Get-KitRemoteInfo {
    # Parses a git remote URL: Azure DevOps (services or server), GitHub / GitHub Enterprise, or generic git.
    param([string]$Url)
    $info = [pscustomobject]@{ Provider = 'none'; Url = $Url; Host = ''; Org = ''; Project = ''; Repo = ''; WebUrl = '' }
    if (-not $Url) { return $info }
    $u = $Url.Trim()
    $m = [regex]::Match($u, '^(?:https?://)?(?:[^@/]+@)?dev\.azure\.com/(?<org>[^/]+)/(?<proj>[^/]+)/_git/(?<repo>[^/?#]+)')
    if (-not $m.Success) { $m = [regex]::Match($u, '^(?:https?://)?(?:[^@/]+@)?(?<org>[^./@]+)\.visualstudio\.com/(?:DefaultCollection/)?(?<proj>[^/]+)/_git/(?<repo>[^/?#]+)') }
    if (-not $m.Success) { $m = [regex]::Match($u, '^(?:ssh://)?[^@]+@(?:ssh\.dev\.azure\.com|vs-ssh\.visualstudio\.com):v3/(?<org>[^/]+)/(?<proj>[^/]+)/(?<repo>[^/]+?)/?$') }
    if ($m.Success) {
        $info.Provider = 'azure-devops'
        $info.Host = 'dev.azure.com'
        $info.Org = [System.Uri]::UnescapeDataString($m.Groups['org'].Value)
        $info.Project = [System.Uri]::UnescapeDataString($m.Groups['proj'].Value)
        $info.Repo = [System.Uri]::UnescapeDataString(($m.Groups['repo'].Value -replace '\.git$', ''))
        $info.WebUrl = 'https://dev.azure.com/' + [System.Uri]::EscapeDataString($info.Org) + '/' + [System.Uri]::EscapeDataString($info.Project) + '/_git/' + [System.Uri]::EscapeDataString($info.Repo)
        return $info
    }
    $m = [regex]::Match($u, '^https?://(?:[^@/]+@)?(?<host>[^/]+)/(?<coll>[^/]+)/(?<proj>[^/]+)/_git/(?<repo>[^/?#]+)')
    if ($m.Success) {
        $info.Provider = 'azure-devops-server'
        $info.Host = $m.Groups['host'].Value
        $info.Org = [System.Uri]::UnescapeDataString($m.Groups['coll'].Value)
        $info.Project = [System.Uri]::UnescapeDataString($m.Groups['proj'].Value)
        $info.Repo = [System.Uri]::UnescapeDataString($m.Groups['repo'].Value)
        $info.WebUrl = 'https://' + $info.Host + '/' + $m.Groups['coll'].Value + '/' + $m.Groups['proj'].Value + '/_git/' + $m.Groups['repo'].Value
        return $info
    }
    $m = [regex]::Match($u, '^(?:https?://|ssh://)?(?:[^@/]+@)?(?<host>[^/:]+)[/:](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$')
    if ($m.Success) {
        $h = $m.Groups['host'].Value
        $info.Provider = 'git'
        if ($h -match '(?i)(^|\.)github\.com$') { $info.Provider = 'github' } elseif ($h -match '(?i)github|ghe\.com') { $info.Provider = 'github-enterprise' }
        $info.Host = $h
        $info.Org = $m.Groups['owner'].Value
        $info.Repo = $m.Groups['repo'].Value
        $info.WebUrl = 'https://' + $h + '/' + $info.Org + '/' + $info.Repo
    }
    return $info
}

function Test-KitProtectedBranch {
    param([string]$Branch, $Patterns)
    if (-not $Branch) { return $false }
    return ($null -ne (Find-KitGlobMatch -Path $Branch -Globs $Patterns))
}

function Get-KitBaseRef {
    # Base branch for diffs, worktrees and pull requests: explicit value, else git.baseBranch from the kit config
    # (remote-tracking copy preferred), else the first existing of origin/develop, origin/main, origin/master, local ones.
    param([string]$Root, $Config, [string]$Explicit)
    if ($Explicit) { return $Explicit }
    $candidates = @('origin/develop', 'origin/main', 'origin/master', 'develop', 'main', 'master')
    $configured = ''
    if ($null -ne $Config -and $null -ne $Config.git) { $configured = [string]$Config.git.baseBranch }
    if ($configured) {
        $short = $configured -replace '^origin/', ''
        $candidates = @(('origin/' + $short), $short)
    }
    foreach ($c in $candidates) {
        $v = Invoke-KitGit -Root $Root -Arguments @('rev-parse', '--verify', '--quiet', $c) -TimeoutSec 10
        if ($v.ExitCode -eq 0) { return $c }
    }
    return $configured
}

# --------------------------------------------------------------------------- config

function Get-KitDefaultConfig {
    return @{
        kitVersion       = '1.1.0'
        bootstrap        = @{ status = 'pending'; completedAt = $null; solution = $null; template = @{ packageId = $null; shortName = $null; version = $null; source = $null; parameters = @{} } }
        internalPackages = @{ prefixes = @(); sources = @() }
        architecture     = @{
            enabled = $true
            layers  = @(
                @{ name = 'Tests'; projectPattern = '(?i)(\.|^)(Unit|Integration|Functional|Acceptance|Architecture|Arch|Component|E2E)?Tests?$'; mayReference = @('*'); forbiddenPackages = @() },
                @{ name = 'SharedKernel'; projectPattern = '(?i)(\.|^)(SharedKernel|Kernel)$'; mayReference = @(); forbiddenPackages = @('Microsoft.EntityFrameworkCore*', 'Microsoft.AspNetCore*') },
                @{ name = 'Domain'; projectPattern = '(?i)(\.|^)Domain$'; mayReference = @('SharedKernel'); forbiddenPackages = @('Microsoft.EntityFrameworkCore*', 'Microsoft.AspNetCore*', 'Microsoft.Data.SqlClient', 'System.Data.SqlClient', 'Dapper*', 'Azure.*', 'Newtonsoft.Json') },
                @{ name = 'Contracts'; projectPattern = '(?i)(\.|^)(Contracts|Abstractions)$'; mayReference = @('SharedKernel'); forbiddenPackages = @('Microsoft.EntityFrameworkCore*') },
                @{ name = 'Application'; projectPattern = '(?i)(\.|^)(Application|UseCases)$'; mayReference = @('Domain', 'SharedKernel', 'Contracts'); forbiddenPackages = @('Microsoft.EntityFrameworkCore.SqlServer', 'Microsoft.EntityFrameworkCore.Sqlite', 'Npgsql*', 'Microsoft.AspNetCore.Mvc*') },
                @{ name = 'Infrastructure'; projectPattern = '(?i)(\.|^)(Infrastructure|Persistence|DataAccess|Integration|Adapters?)(\.[A-Za-z0-9]+)?$'; mayReference = @('Application', 'Domain', 'SharedKernel', 'Contracts'); forbiddenPackages = @() },
                @{ name = 'Presentation'; projectPattern = '(?i)(\.|^)(Api|WebApi|Web|Host|Presentation|Functions|Worker|Grpc|Endpoints|Server)$'; mayReference = @('Application', 'Infrastructure', 'Domain', 'SharedKernel', 'Contracts'); forbiddenPackages = @() }
            )
        }
        guard            = @{
            enabled           = $true
            secretScan        = $true
            piiScan           = $true
            protectedBranches = @('main', 'master', 'develop', 'release/*')
            denyReadPaths     = @('**/*.pfx', '**/*.p12', '**/*.pem', '**/*.key', '**/.env', '**/.env.*', '**/*.publishsettings', '**/id_rsa*', '**/*.snk')
            denyWritePaths    = @('.git/**', '**/*.g.cs', '**/*.g.i.cs', '**/*.Designer.cs', '**/obj/**', '**/bin/**')
            askWritePaths     = @('.github/hooks/**', '.github/kit/**', '**/nuget.config', '**/NuGet.Config', '**/Directory.Packages.props', '**/global.json', '**/Migrations/*.cs')
            extraDenyCommands = @()
            extraAskCommands  = @()
            allowCommands     = @()
        }
        qualityGate      = @{ enabled = $true; build = $true; tests = 'affected'; testFilter = ''; testArgs = @(); format = 'off'; maxBlocks = 2; timeoutSec = 840 }
        logging          = @{ enabled = $true; retentionDays = 30 }
        git              = @{ baseBranch = ''; branchPattern = 'feature/{workitem}-{slug}'; workItemStyle = 'AB#{id}'; mergeStrategy = 'squash' }
        models           = @{
            mode   = 'auto'
            tiers  = @{ reasoning = @(); balanced = @(); fast = @() }
            agents = @{ planner = 'reasoning'; reviewer = 'reasoning'; debugger = 'reasoning'; implementer = 'balanced'; devops = 'balanced'; 'context-engineer' = 'balanced'; conductor = 'balanced'; researcher = 'fast' }
        }
    }
}

function Merge-KitConfig {
    param([hashtable]$Base, $Override)
    if ($null -eq $Override) { return $Base }
    foreach ($p in $Override.PSObject.Properties) {
        $name = $p.Name
        $val = $p.Value
        if (($val -is [System.Management.Automation.PSCustomObject]) -and $Base.ContainsKey($name) -and ($Base[$name] -is [hashtable])) {
            [void](Merge-KitConfig -Base $Base[$name] -Override $val)
        } elseif ($val -is [System.Management.Automation.PSCustomObject]) {
            $Base[$name] = ConvertTo-KitHashtable -Obj $val
        } else {
            $Base[$name] = $val
        }
    }
    return $Base
}

function Get-KitConfigPath {
    param([string]$Root)
    return (Join-Path $Root '.github/kit/config.json')
}

function Get-KitConfig {
    param([string]$Root)
    $cfg = Get-KitDefaultConfig
    $obj = Read-KitJsonFile -Path (Get-KitConfigPath -Root $Root)
    if ($null -ne $obj) { [void](Merge-KitConfig -Base $cfg -Override $obj) }
    return $cfg
}

# --------------------------------------------------------------------------- local state + logs

function Get-KitStateDir {
    # .ai-local/ holds machine-local state and logs. It ignores itself via its own .gitignore.
    param([string]$Root, [string]$Sub = '')
    $base = Join-Path $Root '.ai-local'
    if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    $gi = Join-Path $base '.gitignore'
    if (-not (Test-Path -LiteralPath $gi)) { [System.IO.File]::WriteAllText($gi, "*`n", $script:KitUtf8) }
    if (-not $Sub) { return $base }
    $d = Join-Path $base $Sub
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Get-KitRedacted {
    param([string]$Text, [int]$Max = 160)
    if (-not $Text) { return '' }
    $t = $Text -replace '(?i)\b(password|pwd|secret|token|apikey|api_key|accountkey|sig|client_secret)\s*[=:]\s*([^;&\s"'']+)', '$1=***'
    $t = $t -replace '(?i)(bearer\s+)[A-Za-z0-9._\-]+', '$1***'
    $t = $t -replace '\bgh[pousr]_[A-Za-z0-9]{20,}', 'gh*_***'
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '...' }
    return $t
}

function Write-KitLog {
    # Appends one JSON line to .ai-local/logs/<date>.jsonl. Never throws.
    param([string]$Root, [string]$EventName, [hashtable]$Data, $Config)
    try {
        if ($null -ne $Config -and $null -ne $Config.logging -and -not $Config.logging.enabled) { return }
        $dir = Get-KitStateDir -Root $Root -Sub 'logs'
        $file = Join-Path $dir ((Get-Date).ToString('yyyy-MM-dd') + '.jsonl')
        $entry = [ordered]@{ ts = (Get-Date).ToString('o'); event = $EventName }
        if ($Data) { foreach ($k in @($Data.Keys)) { $entry[[string]$k] = $Data[$k] } }
        $line = (ConvertTo-Json -InputObject $entry -Compress -Depth 6) + "`n"
        [System.IO.File]::AppendAllText($file, $line, $script:KitUtf8)
    } catch { }
}

# --------------------------------------------------------------------------- hook I/O

function Read-KitHookInput {
    # Reads the hook payload (JSON) from stdin. Returns $null when absent or invalid.
    try {
        if (-not [Console]::IsInputRedirected) { return $null }
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $script:KitUtf8)
        $raw = $reader.ReadToEnd()
    } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return (ConvertFrom-Json -InputObject $raw) } catch { return $null }
}

function Write-KitHookOutput {
    # Writes exactly one JSON object to stdout (UTF-8, no BOM).
    param([hashtable]$Object)
    $json = '{}'
    if ($null -ne $Object -and $Object.Count -gt 0) { $json = ConvertTo-Json -InputObject $Object -Depth 10 -Compress }
    $bytes = $script:KitUtf8.GetBytes($json)
    $out = [Console]::OpenStandardOutput()
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}

function Write-KitHookError {
    param([string]$Message)
    try { [Console]::Error.WriteLine($Message); [Console]::Error.Flush() } catch { }
}

function Get-KitToolName {
    param($Payload)
    return [string](Get-KitProp -Object $Payload -Names @('tool_name', 'toolName', 'tool'))
}

function Get-KitToolInput {
    # Tool arguments across harness formats: tool_input (VS Code/Claude), toolArgs (Copilot, may be a JSON string).
    param($Payload)
    $ti = Get-KitProp -Object $Payload -Names @('tool_input', 'toolInput', 'toolArgs', 'tool_args', 'arguments', 'input')
    if ($ti -is [string]) {
        $s = $ti.Trim()
        if ($s.StartsWith('{') -or $s.StartsWith('[')) { try { $ti = ConvertFrom-Json -InputObject $s } catch { } }
    }
    return $ti
}

function Get-KitPatchPaths {
    param([string]$Text)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Text, '(?m)^\*\*\* (?:Add|Update|Delete) File: (.+?)\s*$')) { $paths.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($Text, '(?m)^\*\*\* Move to: (.+?)\s*$')) { $paths.Add($m.Groups[1].Value) }
    return ,$paths.ToArray()
}

function Get-KitPatchAddedText {
    # Only the added lines of an apply_patch style patch (removed lines must not trigger scans).
    param([string]$Text)
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($Text -split "\r?\n")) { if ($l.StartsWith('+') -and -not $l.StartsWith('+++')) { $added.Add($l.Substring(1)) } }
    return ($added -join "`n")
}

function Test-KitIsPatchText {
    param([string]$Text)
    return ($Text.IndexOf('*** Begin Patch') -ge 0 -or $Text.IndexOf('*** Update File:') -ge 0 -or $Text.IndexOf('*** Add File:') -ge 0)
}

function Get-KitToolPaths {
    # File paths referenced by a tool call, whatever the tool schema.
    param($Leaves)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($Leaves)) {
        $k = [string]$s.Key
        $v = [string]$s.Value
        if (-not $v) { continue }
        if (Test-KitIsPatchText -Text $v) { foreach ($p in (Get-KitPatchPaths -Text $v)) { $paths.Add($p) }; continue }
        if ($k -match '(?i)(path|paths|file|files|filename|uri|target|destination|notebook)$') {
            if ($v.Length -lt 500 -and $v -notmatch '[\r\n]' -and $v -notmatch '^[a-z]+://(?!/)' ) { $paths.Add($v) }
        }
    }
    return ,$paths.ToArray()
}

function Get-KitNewContent {
    # Text a tool call would write (new strings, file contents, added patch lines). Old/removed text is excluded.
    param($Leaves)
    $sb = New-Object System.Text.StringBuilder
    foreach ($s in @($Leaves)) {
        $k = [string]$s.Key
        $v = [string]$s.Value
        if (-not $v -or $v.Length -lt 8) { continue }
        if ($k -match '(?i)^old|^(explanation|description|query|pattern|includepattern|command|cmd)$') { continue }
        if ($k -match '(?i)(path|paths|file|files|filename|uri|target|destination)$' -and $v -notmatch '[\r\n]') { continue }
        if (Test-KitIsPatchText -Text $v) { [void]$sb.AppendLine((Get-KitPatchAddedText -Text $v)); continue }
        [void]$sb.AppendLine($v)
    }
    return $sb.ToString()
}

# --------------------------------------------------------------------------- architecture

function Get-KitLayerOf {
    param([string]$ProjectName, $Layers)
    foreach ($l in @($Layers)) {
        $pat = [string](Get-KitProp -Object $l -Names @('projectPattern', 'pattern'))
        if ($pat -and $ProjectName -match $pat) { return $l }
    }
    return $null
}

function Test-KitLayerReferenceAllowed {
    param($FromLayer, $ToLayer)
    if ($null -eq $FromLayer -or $null -eq $ToLayer) { return $true }
    $fromName = [string](Get-KitProp -Object $FromLayer -Names @('name'))
    $toName = [string](Get-KitProp -Object $ToLayer -Names @('name'))
    if ($fromName -eq $toName) { return $true }
    $may = @(Get-KitProp -Object $FromLayer -Names @('mayReference'))
    if ($may -contains '*') { return $true }
    return ($may -contains $toName)
}

function Find-KitForbiddenPackage {
    param($Layer, [string]$PackageId)
    if ($null -eq $Layer) { return $null }
    return (Find-KitGlobMatch -Path $PackageId -Globs @(Get-KitProp -Object $Layer -Names @('forbiddenPackages')))
}
