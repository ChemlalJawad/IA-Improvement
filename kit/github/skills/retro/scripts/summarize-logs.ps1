# summarize-logs.ps1 - Evidence for the retro skill: what the hooks observed over the last days.
# Sessions, tool usage, guard decisions (denied / asked commands), quality gate results and recurring error codes.
# Logs live in .ai-local/logs/*.jsonl (machine-local, never committed).
# Example: pwsh -NoProfile -File .github/skills/retro/scripts/summarize-logs.ps1 -Days 7
[CmdletBinding()]
param([int]$Days = 7, [int]$Top = 8)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$logDir = Join-Path $root '.ai-local/logs'
if (-not (Test-Path -LiteralPath $logDir)) { Write-Output 'No hook logs yet (.ai-local/logs). They appear once the hooks run in agent sessions.'; exit 0 }
$since = (Get-Date).AddDays(-$Days)

$events = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -Path $logDir -Filter '*.jsonl' -File | Where-Object { $_.LastWriteTime -ge $since })) {
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        if (-not $line) { continue }
        try { $events.Add((ConvertFrom-Json -InputObject $line)) } catch { }
    }
}
if ($events.Count -eq 0) { Write-Output "No events in the last $Days day(s)."; exit 0 }

function Get-TopCounts {
    param($Items, [int]$N)
    $map = @{}
    foreach ($i in @($Items)) { if ($null -eq $i -or [string]$i -eq '') { continue }; $k = [string]$i; if ($map.ContainsKey($k)) { $map[$k] = $map[$k] + 1 } else { $map[$k] = 1 } }
    return @($map.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $N | ForEach-Object { '{0} ({1})' -f $_.Key, $_.Value })
}

$pre = @($events | Where-Object { $_.event -eq 'pre' })
$gate = @($events | Where-Object { $_.event -eq 'gate' })
$checks = @($events | Where-Object { $_.event -eq 'check' })
$sessions = @($events | Where-Object { $_.event -eq 'session' })
$denied = @($pre | Where-Object { $_.decision -eq 'deny' })
$asked = @($pre | Where-Object { $_.decision -eq 'ask' })

Write-Output "# Agent activity - last $Days day(s)"
Write-Output ('- Sessions: {0} | tool calls seen by the guard: {1}' -f $sessions.Count, $pre.Count)
Write-Output ('- Most used tools: ' + ((Get-TopCounts -Items ($pre | ForEach-Object { $_.tool }) -N $Top) -join ', '))
Write-Output ('- Guard: {0} denied, {1} asked. Top rules: {2}' -f $denied.Count, $asked.Count, ((Get-TopCounts -Items (@($denied) + @($asked) | ForEach-Object { $_.decision + ':' + $_.rule }) -N $Top) -join ', '))
foreach ($d in ($denied | Select-Object -Last 5)) { if ($d.cmd) { Write-Output ('  - denied ' + $d.rule + ': ' + $d.cmd) } elseif ($d.paths) { Write-Output ('  - denied ' + $d.rule + ': ' + (@($d.paths) -join ', ')) } }
$pass = @($gate | Where-Object { $_.result -eq 'pass' }).Count
$fail = @($gate | Where-Object { $_.result -eq 'fail' }).Count
$gaveUp = @($gate | Where-Object { $_.result -eq 'gave-up' }).Count
Write-Output ('- Quality gate: {0} passed, {1} failed, {2} gave up after max attempts' -f $pass, $fail, $gaveUp)
$codes = @($gate | Where-Object { $_.codes } | ForEach-Object { @($_.codes) })
if ($codes.Count -gt 0) { Write-Output ('  - Recurring diagnostics: ' + ((Get-TopCounts -Items $codes -N $Top) -join ', ')) }
$secs = @($gate | Where-Object { $_.seconds } | ForEach-Object { [double]$_.seconds })
if ($secs.Count -gt 0) { Write-Output ('  - Average gate duration: {0:N1}s' -f (($secs | Measure-Object -Average).Average)) }
if ($checks.Count -gt 0) { Write-Output ('- Manual dotnet-check runs: {0} ({1} failed)' -f $checks.Count, @($checks | Where-Object { -not $_.ok }).Count) }
Write-Output ''
Write-Output 'Read as signals: repeated denials = an instruction is missing or unclear; repeated diagnostics = add a rule or a golden example; many gate failures = verify earlier (skills) or fix flaky tests.'
