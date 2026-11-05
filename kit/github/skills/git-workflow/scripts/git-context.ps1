# git-context.ps1 - Compact git context for commits, pull requests and reviews (git-workflow skill).
# Branch, upstream, base branch and merge-base, commits on the branch, diffstat, working tree, work item,
# and ready-to-use PR links/commands for Azure Repos or GitHub. Read-only.
# Example: pwsh -NoProfile -File .github/skills/git-workflow/scripts/git-context.ps1 [-Base origin/develop]
[CmdletBinding()]
param([string]$Base, [int]$MaxFiles = 25)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$cfg = Get-KitConfig -Root $root
$probe = Invoke-KitGit -Root $root -Arguments @('rev-parse', '--is-inside-work-tree')
if ($probe.ExitCode -ne 0) { Write-Output 'Not a git repository.'; exit 1 }

$out = New-Object System.Collections.Generic.List[string]
$branch = Get-KitGitBranch -Root $root

$upstream = ''
$up = Invoke-KitGit -Root $root -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
if ($up.ExitCode -eq 0 -and $up.StdOut.Count -gt 0) { $upstream = $up.StdOut[0].Trim() }
$line = "Branch: $branch"
if ($upstream) {
    $ab = Invoke-KitGit -Root $root -Arguments @('rev-list', '--left-right', '--count', ($upstream + '...HEAD'))
    if ($ab.ExitCode -eq 0 -and $ab.StdOut.Count -gt 0) {
        $parts = $ab.StdOut[0].Trim() -split '\s+'
        $line += " (upstream $upstream, ahead $($parts[1]), behind $($parts[0]))"
    }
} else { $line += ' (no upstream yet)' }
if (Test-KitProtectedBranch -Branch $branch -Patterns $cfg.guard.protectedBranches) { $line += ' [PROTECTED: create a feature branch before committing]' }
$out.Add($line)

$baseRef = Get-KitBaseRef -Root $root -Config $cfg -Explicit $Base
$mergeBase = ''
if ($baseRef) {
    $mb = Invoke-KitGit -Root $root -Arguments @('merge-base', 'HEAD', $baseRef)
    if ($mb.ExitCode -eq 0 -and $mb.StdOut.Count -gt 0) { $mergeBase = $mb.StdOut[0].Trim() }
}
if ($mergeBase) {
    $cnt = Invoke-KitGit -Root $root -Arguments @('rev-list', '--count', ($mergeBase + '..HEAD'))
    $out.Add(('Base: {0} (merge-base {1}) - {2} commit(s) on this branch' -f $baseRef, $mergeBase.Substring(0, [math]::Min(8, $mergeBase.Length)), ($cnt.StdOut | Select-Object -First 1)))
    $log = Invoke-KitGit -Root $root -Arguments @('log', '--oneline', '-n', '15', ($mergeBase + '..HEAD'))
    if ($log.StdOut.Count -gt 0) { $out.Add('Commits on this branch:'); foreach ($l in $log.StdOut) { $out.Add("  $l") } }
    $stat = Invoke-KitGit -Root $root -Arguments @('diff', '--stat=110', $mergeBase)
    $lines = @($stat.StdOut)
    if ($lines.Count -gt 0) {
        $out.Add('Diff vs base (committed + uncommitted):')
        foreach ($l in ($lines | Select-Object -First $MaxFiles)) { $out.Add("  $l") }
        if ($lines.Count -gt ($MaxFiles + 1)) { $out.Add('  ...'); $out.Add('  ' + $lines[$lines.Count - 1]) }
    }
    $style = Invoke-KitGit -Root $root -Arguments @('log', '-n', '5', '--format=%s', $baseRef)
    if ($style.StdOut.Count -gt 0) { $out.Add('Recent commit messages on base (follow this style):'); foreach ($l in $style.StdOut) { $out.Add("  $l") } }
} else {
    $out.Add('Base: unknown (pass -Base origin/<branch> or set git.baseBranch in .github/kit/config.json)')
}

$st = Invoke-KitGit -Root $root -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
$staged = 0; $modified = 0; $untracked = 0; $conflicted = 0
foreach ($l in $st.StdOut) {
    if ($l.Length -lt 3) { continue }
    $xy = $l.Substring(0, 2)
    if ($xy -eq '??') { $untracked++; continue }
    if ($xy -match '^(DD|AU|UD|UA|DU|AA|UU)$') { $conflicted++; continue }
    if ($xy[0] -ne [char]' ') { $staged++ }
    if ($xy[1] -ne [char]' ') { $modified++ }
}
$out.Add("Working tree: $staged staged, $modified modified, $untracked untracked, $conflicted conflicted")
foreach ($l in ($st.StdOut | Select-Object -First $MaxFiles)) { $out.Add("  $l") }
if ($conflicted -gt 0) { $out.Add('Conflicts in progress: use the merge-conflicts skill (conflict-report.ps1).') }

$wi = ''
if ($branch -match '(?:^|[/_-])(\d{3,7})(?:[/_-]|$)') { $wi = $Matches[1] }
if ($wi) {
    $style = 'AB#' + $wi
    if ($cfg.git.workItemStyle) { $style = ([string]$cfg.git.workItemStyle).Replace('{id}', $wi) }
    $out.Add("Work item (from branch name): $wi -> reference it as $style")
}

$u = Invoke-KitGit -Root $root -Arguments @('remote', 'get-url', 'origin')
if ($u.ExitCode -eq 0 -and $u.StdOut.Count -gt 0) {
    $ri = Get-KitRemoteInfo -Url $u.StdOut[0]
    $out.Add("Remote: $($ri.Provider) $($ri.WebUrl)")
    $baseName = ($baseRef -replace '^origin/', '')
    if ($branch -and $baseName -and $ri.WebUrl -and $branch -ne 'HEAD') {
        if ($ri.Provider -like 'azure-devops*') {
            $out.Add('Create PR (web): ' + $ri.WebUrl + '/pullrequestcreate?sourceRef=' + [System.Uri]::EscapeDataString($branch) + '&targetRef=' + [System.Uri]::EscapeDataString($baseName))
            $cli = "az repos pr create --draft --source-branch $branch --target-branch $baseName --title `"<title>`" --description `"<description>`""
            if ($wi) { $cli += " --work-items $wi" }
            $out.Add("Create PR (CLI, needs the azure-devops extension): $cli")
        } elseif ($ri.Provider -like 'github*') {
            $out.Add('Create PR (web): ' + $ri.WebUrl + '/compare/' + $baseName + '...' + $branch + '?expand=1')
            $out.Add("Create PR (CLI): gh pr create --draft --base $baseName --head $branch")
        }
    }
} else { $out.Add('Remote: none (origin not configured)') }

$out | ForEach-Object { Write-Output $_ }
