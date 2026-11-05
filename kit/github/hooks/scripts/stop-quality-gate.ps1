# stop-quality-gate.ps1 - Stop hook: before the agent finishes a turn that changed code, verify it.
# Checks: optional formatting of the changed files -> architecture (layer rules) -> build -> tests affected by the change.
# Failing checks block the stop with a compact report so the agent fixes them (evaluator-optimizer loop).
# Cost control: skipped when no code changed, cached per working-tree fingerprint, capped at qualityGate.maxBlocks.
# Fails open. Windows PowerShell 5.1 / PowerShell 7+. ASCII-only.

$ErrorActionPreference = 'Stop'

function Get-KitFingerprint {
    param([string]$Root, [string[]]$Files)
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in @($Files | Sort-Object)) {
        $full = Join-Path $Root $f
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $i = Get-Item -LiteralPath $full
            [void]$sb.Append($f).Append('|').Append($i.Length).Append('|').Append($i.LastWriteTimeUtc.Ticks).Append(';')
        } else {
            [void]$sb.Append($f).Append('|deleted;')
        }
    }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha.ComputeHash($script:KitUtf8.GetBytes($sb.ToString()))
    return ([System.BitConverter]::ToString($hash) -replace '-', '')
}

try {
    . (Join-Path $PSScriptRoot '..\..\kit\lib\KitCore.ps1')
    . (Join-Path $PSScriptRoot '..\..\kit\lib\KitDotnet.ps1')
    $root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 3
    $payload = Read-KitHookInput
    $cfg = Get-KitConfig -Root $root
    $qg = $cfg.qualityGate
    if (-not $qg.enabled) { Write-KitHookOutput @{}; exit 0 }

    $changed = Get-KitChangedFiles -Root $root
    $relevant = @($changed | Where-Object { $_ -match '(?i)\.(cs|csproj|fs|fsproj|vb|vbproj|props|targets|razor|cshtml|resx|sln|slnx)$' -or $_ -match '(?i)(^|/)(global\.json|\.editorconfig)$' })
    if ($relevant.Count -eq 0) { Write-KitHookOutput @{}; exit 0 }
    if ($env:KIT_GATE_DRYRUN -eq '1') { Write-KitHookOutput @{ systemMessage = "[kit] quality gate dry-run: $($relevant.Count) relevant changed file(s)" }; exit 0 }

    # Formatting runs once per turn, here, rather than after every edit: rewriting files while VS Code still tracks the
    # agent's pending edits would conflict with them. Enabled only where the repository is already formatted.
    $fmt = [string]$qg.format
    if ($fmt -and $fmt -ne 'off') { try { [void](Invoke-KitDotnetFormat -Root $root -Files $relevant -Mode $fmt) } catch { } }

    $fp = Get-KitFingerprint -Root $root -Files $relevant
    $statePath = Join-Path (Get-KitStateDir -Root $root -Sub 'state') 'quality-gate.json'
    $state = Read-KitJsonFile -Path $statePath
    $lastPass = [string](Get-KitProp -Object $state -Names @('lastPassFingerprint'))
    if ($fp -eq $lastPass) { Write-KitHookOutput @{}; exit 0 }

    $sessionId = [string](Get-KitProp -Object $payload -Names @('session_id', 'sessionId'))
    if (-not $sessionId) { $sessionId = 'unknown' }
    $blocks = 0
    if ([string](Get-KitProp -Object $state -Names @('sessionId')) -eq $sessionId) { $blocks = ConvertTo-KitInt (Get-KitProp -Object $state -Names @('blocks')) }
    $max = [int]$qg.maxBlocks
    if ($max -lt 1) { $max = 1 }
    if ($blocks -ge $max) {
        Write-KitLog -Root $root -EventName 'gate' -Data @{ result = 'gave-up'; blocks = $blocks } -Config $cfg
        Write-KitHookOutput @{ systemMessage = "[kit] Quality gate still failing after $max attempt(s): the agent is allowed to stop. Review the failures before committing." }
        exit 0
    }

    $lastFail = [string](Get-KitProp -Object $state -Names @('lastFailFingerprint'))
    if ($fp -eq $lastFail -and [string](Get-KitProp -Object $state -Names @('lastFailReport'))) {
        # Nothing changed since the last failed run: reuse the report instead of rebuilding.
        $check = [pscustomobject]@{ Ok = $false; Report = [string](Get-KitProp -Object $state -Names @('lastFailReport')); DurationSec = 0 }
    } else {
        $testsMode = [string]$qg.tests
        if (-not $testsMode) { $testsMode = 'affected' }
        $check = Invoke-KitDotnetCheck -Root $root -Config $cfg -Build:([bool]$qg.build) -Test:($testsMode -ne 'none') -Scope $testsMode -Filter ([string]$qg.testFilter) -TestArgs @($qg.testArgs) -ChangedFiles $changed -TimeoutSec ([int]$qg.timeoutSec) -CheckArchitecture -Max 15
    }

    if ($check.Ok) {
        Write-KitJsonFile -Path $statePath -Object ([ordered]@{ lastPassFingerprint = $fp; lastFailFingerprint = ''; lastFailReport = ''; sessionId = $sessionId; blocks = 0; updatedAt = (Get-Date).ToString('o') })
        Write-KitLog -Root $root -EventName 'gate' -Data @{ result = 'pass'; seconds = $check.DurationSec } -Config $cfg
        $summary = (@($check.Report -split "`n" | Where-Object { $_ -match '^(BUILD|TESTS|ARCHITECTURE):' }) -join ' | ')
        Write-KitHookOutput @{ systemMessage = "[kit] Quality gate passed. $summary" }
        exit 0
    }

    $blocks++
    Write-KitJsonFile -Path $statePath -Object ([ordered]@{ lastPassFingerprint = $lastPass; lastFailFingerprint = $fp; lastFailReport = $check.Report; sessionId = $sessionId; blocks = $blocks; updatedAt = (Get-Date).ToString('o') })
    $codes = @([regex]::Matches($check.Report, '\b(CS|NU|MSB|CA|IDE|SA|S)\d{3,5}\b') | ForEach-Object { $_.Value } | Select-Object -Unique -First 10)
    Write-KitLog -Root $root -EventName 'gate' -Data @{ result = 'fail'; attempt = $blocks; codes = $codes; seconds = $check.DurationSec } -Config $cfg
    $reason = "[kit quality gate] Checks FAILED (attempt $blocks of $max). Fix the problems below, re-run the checks, then finish. If a failure is pre-existing or unrelated to your change, say so explicitly in your final answer instead of hiding it.`n`n" + $check.Report
    Write-KitHookOutput @{ decision = 'block'; reason = $reason; hookSpecificOutput = @{ hookEventName = 'Stop'; decision = 'block'; reason = $reason } }
    exit 0
} catch {
    try { [Console]::Error.WriteLine('[kit quality gate] internal error ignored (fail-open): ' + $_.Exception.Message) } catch { }
    try { [Console]::Out.Write('{}'); [Console]::Out.Flush() } catch { }
    exit 0
}
