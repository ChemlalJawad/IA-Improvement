# conflict-report.ps1 - Summarizes an in-progress merge, rebase or cherry-pick conflict (merge-conflicts skill).
# Operation and sides, conflicted files with hunk locations and a handling hint per file, commits involved. Read-only.
# Example: pwsh -NoProfile -File .github/skills/merge-conflicts/scripts/conflict-report.ps1
[CmdletBinding()]
param([int]$MaxCommits = 15)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$gd = Invoke-KitGit -Root $root -Arguments @('rev-parse', '--git-dir')
if ($gd.ExitCode -ne 0) { Write-Output 'Not a git repository.'; exit 1 }
$gitDir = $gd.StdOut[0].Trim()
if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $root $gitDir }

$op = 'none'
if (Test-Path -LiteralPath (Join-Path $gitDir 'MERGE_HEAD')) { $op = 'merge' }
elseif ((Test-Path -LiteralPath (Join-Path $gitDir 'rebase-merge')) -or (Test-Path -LiteralPath (Join-Path $gitDir 'rebase-apply'))) { $op = 'rebase' }
elseif (Test-Path -LiteralPath (Join-Path $gitDir 'CHERRY_PICK_HEAD')) { $op = 'cherry-pick' }
elseif (Test-Path -LiteralPath (Join-Path $gitDir 'REVERT_HEAD')) { $op = 'revert' }

$out = New-Object System.Collections.Generic.List[string]
$branch = Get-KitGitBranch -Root $root
$out.Add("Operation: $op | current branch: $branch")
switch ($op) {
    'merge' {
        $mh = Invoke-KitGit -Root $root -Arguments @('log', '-1', '--format=%h %s', 'MERGE_HEAD')
        $out.Add('  ours = HEAD (' + $branch + '); theirs = MERGE_HEAD: ' + ($mh.StdOut | Select-Object -First 1))
    }
    'rebase' {
        $rh = Invoke-KitGit -Root $root -Arguments @('log', '-1', '--format=%h %s', 'REBASE_HEAD')
        $onto = ''
        foreach ($d in @('rebase-merge', 'rebase-apply')) { $f = Join-Path $gitDir ($d + '/onto'); if (Test-Path -LiteralPath $f) { $onto = (Get-Content -LiteralPath $f -TotalCount 1).Trim() } }
        $out.Add('  WARNING rebase semantics: ours = the branch being rebased ONTO (' + $onto + '); theirs = YOUR commit being replayed: ' + ($rh.StdOut | Select-Object -First 1))
    }
    'cherry-pick' {
        $ch = Invoke-KitGit -Root $root -Arguments @('log', '-1', '--format=%h %s', 'CHERRY_PICK_HEAD')
        $out.Add('  ours = HEAD; theirs = picked commit: ' + ($ch.StdOut | Select-Object -First 1))
    }
}

$st = Invoke-KitGit -Root $root -Arguments @('status', '--porcelain=v1')
$meaning = @{ UU = 'both modified'; AA = 'both added'; DU = 'deleted by us'; UD = 'deleted by them'; AU = 'added by us'; UA = 'added by them'; DD = 'both deleted' }
$files = New-Object System.Collections.Generic.List[object]
foreach ($l in $st.StdOut) {
    if ($l.Length -lt 4) { continue }
    $xy = $l.Substring(0, 2)
    if (-not $meaning.ContainsKey($xy)) { continue }
    $files.Add([pscustomobject]@{ Code = $xy; Path = $l.Substring(3).Trim().Trim('"') })
}
if ($files.Count -eq 0) {
    $out.Add('No conflicted files.')
    if ($op -ne 'none') { $out.Add('All conflicts resolved: build + tests, then ask the user before running git ' + $op + ' --continue.') }
    $out | ForEach-Object { Write-Output $_ }
    exit 0
}

$out.Add("Conflicted files ($($files.Count)):")
foreach ($f in $files) {
    $hint = 'source: understand both intents, combine, keep both behaviours when compatible'
    if ($f.Path -match '(?i)ModelSnapshot\.cs$') { $hint = 'EF MODEL SNAPSHOT: do not hand-merge; take the target side, then re-create your migration (ef-core skill)' }
    elseif ($f.Path -match '(?i)/Migrations/') { $hint = 'EF MIGRATION: keep both migrations if independent; check ordering and the snapshot (ef-core skill)' }
    elseif ($f.Path -match '(?i)(\.Designer\.cs|\.g\.cs|packages\.lock\.json)$') { $hint = 'GENERATED: regenerate it (restore/build/tool), never hand-merge' }
    elseif ($f.Path -match '(?i)(Directory\.Packages\.props|\.csproj)$') { $hint = 'PROJECT/PACKAGES: union of references; for versions keep the higher one, ask on major bumps; re-check layering' }
    elseif ($f.Path -match '(?i)(azure-pipelines.*\.ya?ml|\.github/workflows/)') { $hint = 'PIPELINE: merge carefully, keep both changes, validate the YAML (azure-pipelines skill)' }
    elseif ($f.Path -match '(?i)Tests?[/\\.]') { $hint = 'TESTS: usually keep both sides tests; fix names/fixtures' }
    $hunks = @()
    $full = Join-Path $root $f.Path
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $lines = [System.IO.File]::ReadAllLines($full)
        $start = 0
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i].StartsWith('<<<<<<< ')) { $start = $i + 1 }
            elseif ($lines[$i].StartsWith('>>>>>>> ') -and $start -gt 0) { $hunks += ('{0}-{1}' -f $start, ($i + 1)); $start = 0 }
        }
    }
    $hunkText = 'no markers (binary, deleted or already edited)'
    if ($hunks.Count -gt 0) { $hunkText = "$($hunks.Count) hunk(s) at lines " + ($hunks -join ', ') }
    $out.Add(('  {0} [{1}] {2}' -f $f.Path, $meaning[$f.Code], $hunkText))
    $out.Add('      -> ' + $hint)
}

$lg = Invoke-KitGit -Root $root -Arguments @('log', '--merge', '--oneline', '-n', [string]$MaxCommits)
if ($lg.ExitCode -eq 0 -and $lg.StdOut.Count -gt 0) {
    $out.Add('Commits touching the conflicted files on both sides (git log --merge):')
    foreach ($l in $lg.StdOut) { $out.Add("  $l") }
}
$out.Add('Inspect one file: git diff <file> | base/ours/theirs: git show :1:<file> / :2:<file> / :3:<file>')
$out.Add('After resolving: no markers left (git diff --check), build + affected tests, then ask the user before --continue.')
$out | ForEach-Object { Write-Output $_ }
