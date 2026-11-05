# worktree.ps1 - One git worktree per task, so several agent sessions can work in parallel (parallel-work skill).
# A worktree is a second working folder of the same repository, on its own branch: sessions never touch each other's
# files, and each folder has its own bin/obj and .ai-local state. Worktrees live next to the repository in
# <repo>.worktrees/<folder>. The script never forces anything: dirty worktrees and unmerged branches are kept.
# Examples:
#   pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -New "Broker claim declaration" -WorkItem 1234
#   ... worktree.ps1 -New "spike cache" -Base origin/develop -Open
#   ... worktree.ps1 -List
#   ... worktree.ps1 -Remove 1234-broker-claim-declaration -DeleteBranch
#   ... worktree.ps1 -Prune
[CmdletBinding()]
param(
    [string]$New,
    [string]$WorkItem = '',
    [string]$Base,
    [string]$Branch,
    [string]$Path,
    [switch]$Open,
    [switch]$NoFetch,
    [switch]$List,
    [string]$Remove,
    [switch]$DeleteBranch,
    [switch]$Prune
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$cfg = Get-KitConfig -Root $root
$probe = Invoke-KitGit -Root $root -Arguments @('rev-parse', '--is-inside-work-tree')
if ($probe.ExitCode -ne 0) { Write-Output 'Not a git repository.'; exit 1 }

function Get-KitNormalizedPath {
    param([string]$P)
    if (-not $P) { return '' }
    return [System.IO.Path]::GetFullPath($P).TrimEnd('\', '/').Replace('\', '/')
}

function Get-KitWorktrees {
    # Parses 'git worktree list --porcelain'. The first entry is the main working tree.
    $r = Invoke-KitGit -Root $root -Arguments @('worktree', 'list', '--porcelain') -TimeoutSec 20
    $items = New-Object System.Collections.Generic.List[object]
    $cur = $null
    foreach ($l in @($r.StdOut) + @('')) {
        if ($l -match '^worktree (.+)$') {
            $cur = [pscustomobject]@{ Path = (Get-KitNormalizedPath $Matches[1]); Branch = ''; Head = ''; Detached = $false; Prunable = $false; Locked = $false }
            continue
        }
        if ($null -eq $cur) { continue }
        if ($l -match '^branch refs/heads/(.+)$') { $cur.Branch = $Matches[1]; continue }
        if ($l -match '^HEAD (\w+)') { $cur.Head = $Matches[1]; continue }
        if ($l -eq 'detached') { $cur.Detached = $true; continue }
        if ($l -match '^prunable') { $cur.Prunable = $true; continue }
        if ($l -match '^locked') { $cur.Locked = $true; continue }
        if ($l -eq '') { $items.Add($cur); $cur = $null }
    }
    return ,$items.ToArray()
}

function Get-KitDirtyCount {
    param([string]$P)
    $s = Invoke-KitGit -Root $P -Arguments @('status', '--porcelain=v1') -TimeoutSec 30
    if ($s.ExitCode -ne 0) { return -1 }
    return @($s.StdOut | Where-Object { $_ }).Count
}

$worktrees = Get-KitWorktrees
if ($worktrees.Count -eq 0) { Write-Output 'Cannot list worktrees (git worktree list failed).'; exit 1 }
$mainPath = $worktrees[0].Path
$currentPath = Get-KitNormalizedPath $root
$container = (Split-Path -Path $mainPath -Parent).Replace('\', '/') + '/' + (Split-Path -Path $mainPath -Leaf) + '.worktrees'

# ---------------------------------------------------------------- new
if ($New) {
    $slug = ConvertTo-KitSlug -Text $New
    $wi = ''
    if ($WorkItem -match '(\d+)') { $wi = $Matches[1] }
    $folder = $slug
    if ($wi) { $folder = $wi + '-' + $slug }

    $branchName = $Branch
    if (-not $branchName) {
        $pattern = [string]$cfg.git.branchPattern
        if (-not $pattern) { $pattern = 'feature/{workitem}-{slug}' }
        $branchName = $pattern.Replace('{slug}', $slug)
        if ($wi) { $branchName = $branchName.Replace('{workitem}', $wi) } else { $branchName = $branchName -replace '\{workitem\}[-_/]?', '' }
    }
    $chk = Invoke-KitGit -Root $root -Arguments @('check-ref-format', '--branch', $branchName) -TimeoutSec 10
    if ($chk.ExitCode -ne 0) { Write-Output "Invalid branch name: $branchName (use -Branch)."; exit 1 }
    if (Test-KitProtectedBranch -Branch $branchName -Patterns $cfg.guard.protectedBranches) { Write-Output "Refused: '$branchName' is a protected branch. Work on a feature branch."; exit 1 }
    $taken = @($worktrees | Where-Object { $_.Branch -eq $branchName })
    if ($taken.Count -gt 0) { Write-Output "Branch '$branchName' is already checked out in $($taken[0].Path)."; exit 1 }

    $target = $Path
    if (-not $target) { $target = $container + '/' + $folder }
    $target = Get-KitNormalizedPath $target
    if (Test-Path -LiteralPath $target) { Write-Output "Folder already exists: $target (choose another title or -Path)."; exit 1 }

    $baseRef = Get-KitBaseRef -Root $root -Config $cfg -Explicit $Base
    if (-not $baseRef) { $baseRef = 'HEAD' }
    $note = ''
    if (-not $NoFetch -and $baseRef -like 'origin/*') {
        $f = Invoke-KitGit -Root $root -Arguments @('fetch', '--quiet', 'origin', ($baseRef -replace '^origin/', '')) -TimeoutSec 120
        if ($f.ExitCode -ne 0) { $note = " (fetch failed, local copy of $baseRef used)" }
    }

    $exists = Invoke-KitGit -Root $root -Arguments @('rev-parse', '--verify', '--quiet', ('refs/heads/' + $branchName)) -TimeoutSec 10
    if ($exists.ExitCode -eq 0) {
        $add = Invoke-KitGit -Root $root -Arguments @('worktree', 'add', $target, $branchName) -TimeoutSec 300
        $from = 'existing branch'
    } else {
        $add = Invoke-KitGit -Root $root -Arguments @('worktree', 'add', '--no-track', '-b', $branchName, $target, $baseRef) -TimeoutSec 300
        $from = $baseRef + $note
    }
    if ($add.ExitCode -ne 0) { Write-Output ('git worktree add failed: ' + ((@($add.StdErr) + @($add.StdOut)) -join ' ')); exit 1 }
    Write-KitLog -Root $root -EventName 'worktree' -Data @{ action = 'new'; branch = $branchName } -Config $cfg

    Write-Output "Worktree created: $target"
    Write-Output "  branch: $branchName (from $from)"
    Write-Output 'Next:'
    Write-Output "  1. Open it in its own VS Code window: code -n `"$target`""
    Write-Output '  2. In that window, one chat session for this task (e.g. /spec, /spec-implement specs/NNN-..., or the implementer agent).'
    Write-Output '  3. First build there: dotnet restore (each worktree has its own bin/obj; the NuGet cache is shared).'
    Write-Output "  When merged: worktree.ps1 -Remove $folder -DeleteBranch"
    if ($Open) {
        $codeCmd = Get-Command -Name code -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($codeCmd) {
            Start-Process -FilePath $codeCmd.Source -ArgumentList @('-n', ('"' + $target + '"')) -WindowStyle Hidden
            Write-Output '  Opened in a new VS Code window.'
        } else { Write-Output '  (VS Code "code" command not found on PATH: open the folder manually.)' }
    }
    exit 0
}

# ---------------------------------------------------------------- remove
if ($Remove) {
    $key = $Remove.Replace('\', '/').TrimEnd('/')
    $hit = $null
    foreach ($w in $worktrees) {
        $leaf = Split-Path -Path $w.Path -Leaf
        if ($w.Path -eq (Get-KitNormalizedPath $key) -or $leaf -eq $key -or $w.Branch -eq $key) { $hit = $w; break }
    }
    if ($null -eq $hit) { Write-Output "No worktree matches '$Remove'. Use -List."; exit 1 }
    if ($hit.Path -eq $mainPath) { Write-Output 'Refused: this is the main working tree.'; exit 1 }
    if ($hit.Path -eq $currentPath) { Write-Output 'Refused: you are inside this worktree. Run the command from another one.'; exit 1 }
    if ($hit.Prunable) {
        $null = Invoke-KitGit -Root $root -Arguments @('worktree', 'prune') -TimeoutSec 60
        Write-Output "Folder already gone: stale entry pruned ($($hit.Path))."
    } else {
        $dirty = Get-KitDirtyCount -P $hit.Path
        if ($dirty -gt 0) { Write-Output "Kept: $($hit.Path) has $dirty uncommitted change(s). Commit or discard them first (this script never forces)."; exit 1 }
        $rm = Invoke-KitGit -Root $root -Arguments @('worktree', 'remove', $hit.Path) -TimeoutSec 120
        if ($rm.ExitCode -ne 0) { Write-Output ('git worktree remove failed: ' + ((@($rm.StdErr) + @($rm.StdOut)) -join ' ')); exit 1 }
        Write-Output "Worktree removed: $($hit.Path)"
    }
    if ($DeleteBranch -and $hit.Branch) {
        $db = Invoke-KitGit -Root $root -Arguments @('branch', '-d', $hit.Branch) -TimeoutSec 30
        if ($db.ExitCode -eq 0) { Write-Output "Branch deleted: $($hit.Branch)" }
        else { Write-Output "Branch kept: $($hit.Branch) is not merged into the current branch (git branch -d refused; expected after a squash merge). Delete it with 'git branch -D' once its pull request is completed." }
    }
    Write-KitLog -Root $root -EventName 'worktree' -Data @{ action = 'remove'; branch = $hit.Branch } -Config $cfg
    exit 0
}

# ---------------------------------------------------------------- prune
if ($Prune) {
    $p = Invoke-KitGit -Root $root -Arguments @('worktree', 'prune', '--verbose') -TimeoutSec 60
    $lines = @(@($p.StdOut) + @($p.StdErr) | Where-Object { $_ })
    if ($lines.Count -eq 0) { Write-Output 'Nothing to prune.' } else { $lines | ForEach-Object { Write-Output $_ } }
    exit 0
}

# ---------------------------------------------------------------- list (default)
Write-Output "Worktrees of $mainPath (new ones go to $container):"
foreach ($w in $worktrees) {
    $mark = ' '
    if ($w.Path -eq $currentPath) { $mark = '*' }
    $name = $w.Branch
    if (-not $name) { $name = '(detached ' + $w.Head.Substring(0, [math]::Min(8, $w.Head.Length)) + ')' }
    if ($w.Prunable) { Write-Output ("  $mark $name | missing folder (run -Prune) | " + $w.Path); continue }
    $dirty = Get-KitDirtyCount -P $w.Path
    $state = 'clean'
    if ($dirty -gt 0) { $state = "$dirty change(s)" } elseif ($dirty -lt 0) { $state = 'unreadable' }
    $last = Invoke-KitGit -Root $w.Path -Arguments @('log', '-1', '--format=%cr: %s') -TimeoutSec 15
    $lastText = ''
    if ($last.ExitCode -eq 0 -and @($last.StdOut).Count -gt 0) { $lastText = $last.StdOut[0] }
    if ($lastText.Length -gt 70) { $lastText = $lastText.Substring(0, 70) + '...' }
    Write-Output ("  $mark $name | $state | $lastText | " + $w.Path)
}
exit 0
