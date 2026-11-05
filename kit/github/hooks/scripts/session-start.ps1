# session-start.ps1 - SessionStart hook: injects a few lines of live context (kit status, branch, active specs).
# Keep the output short: it is added to every new session. Fails open. Windows PowerShell 5.1 / PowerShell 7+. ASCII-only.

$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot '..\..\kit\lib\KitCore.ps1')
    $root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 3
    $null = Read-KitHookInput
    $cfg = Get-KitConfig -Root $root

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('[AI kit] Live session context:')
    $lines.Add('- Today: ' + (Get-Date).ToString('yyyy-MM-dd'))
    if ([string]$cfg.bootstrap.status -ne 'done') {
        $lines.Add('- IMPORTANT: the AI kit is not adapted to this repository yet (docs/ai/project-context.md is a template). Before substantial work, recommend that the user runs /bootstrap once.')
    }

    $branch = Get-KitGitBranch -Root $root
    if ($branch) {
        $msg = "- Git branch: $branch"
        if (Test-KitProtectedBranch -Branch $branch -Patterns $cfg.guard.protectedBranches) { $msg += ' (protected: create a feature branch before committing)' }
        $lines.Add($msg)
        $changed = Get-KitChangedFiles -Root $root
        if ($changed.Count -gt 0) { $lines.Add("- Uncommitted changes: $($changed.Count) file(s)") }
    }

    $specsDir = Join-Path $root 'specs'
    if (Test-Path -LiteralPath $specsDir) {
        $active = New-Object System.Collections.Generic.List[string]
        $dirs = @(Get-ChildItem -Path $specsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{3}-' } | Sort-Object Name -Descending)
        foreach ($d in $dirs) {
            $file = $null
            foreach ($candidate in @('tasks.md', 'spec.md')) {
                $f = Join-Path $d.FullName $candidate
                if (Test-Path -LiteralPath $f) { $file = $f; break }
            }
            if (-not $file) { continue }
            $text = Read-KitTextFile -Path $file
            $status = 'unknown'
            $m = [regex]::Match($text, '(?m)^status:\s*([A-Za-z-]+)')
            if ($m.Success) { $status = $m.Groups[1].Value.ToLowerInvariant() }
            if (@('done', 'cancelled', 'superseded') -contains $status) { continue }
            $doneCount = [regex]::Matches($text, '(?m)^\s*- \[[xX]\]').Count
            $openCount = [regex]::Matches($text, '(?m)^\s*- \[ \]').Count
            $info = "specs/$($d.Name) ($status"
            if (($doneCount + $openCount) -gt 0) { $info += ", tasks $doneCount/$($doneCount + $openCount)" }
            $active.Add($info + ')')
            if ($active.Count -ge 3) { break }
        }
        if ($active.Count -gt 0) { $lines.Add('- Open specs: ' + ($active -join '; ') + '. To resume one, read its tasks.md progress log first.') }
    }

    # Housekeeping (cheap): drop old logs and test results.
    try {
        $days = [int]$cfg.logging.retentionDays
        if ($days -gt 0) {
            $limit = (Get-Date).AddDays(-$days)
            $logDir = Join-Path $root '.ai-local/logs'
            if (Test-Path -LiteralPath $logDir) { Get-ChildItem -Path $logDir -Filter '*.jsonl' -File | Where-Object { $_.LastWriteTime -lt $limit } | Remove-Item -Force -ErrorAction SilentlyContinue }
        }
        $tr = Join-Path $root '.ai-local/test-results'
        if (Test-Path -LiteralPath $tr) { Get-ChildItem -Path $tr -Directory | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    } catch { }

    $ctx = $lines -join "`n"
    Write-KitLog -Root $root -EventName 'session' -Data @{ branch = $branch; bootstrapped = ([string]$cfg.bootstrap.status -eq 'done') } -Config $cfg
    Write-KitHookOutput @{ additionalContext = $ctx; hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $ctx } }
    exit 0
} catch {
    try { [Console]::Error.WriteLine('[kit session-start] internal error ignored: ' + $_.Exception.Message) } catch { }
    try { [Console]::Out.Write('{}'); [Console]::Out.Flush() } catch { }
    exit 0
}
