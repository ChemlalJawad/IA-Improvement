# configure-kit.ps1 - Deterministic kit configuration steps used by the bootstrap skill.
#   -Launcher auto|pwsh|powershell  rewrite script commands in agent/skill/instruction files for this machine
#   -ApplyModels                    write the model routing of .github/kit/config.json into .github/agents/*.agent.md
#   -MarkBootstrapped [-Solution x] record that the bootstrap is complete (and the solution path)
#   -Format off|whitespace|csharpier|auto  formatting of changed files by the Stop quality gate (qualityGate.format)
#   -Show                           print the current configuration summary
# Example: pwsh -NoProfile -File .github/skills/bootstrap/scripts/configure-kit.ps1 -Launcher auto -Show
[CmdletBinding()]
param(
    [ValidateSet('keep', 'auto', 'pwsh', 'powershell')][string]$Launcher = 'keep',
    [switch]$ApplyModels,
    [switch]$MarkBootstrapped,
    [string]$Solution,
    [ValidateSet('keep', 'off', 'whitespace', 'csharpier', 'auto')][string]$Format = 'keep',
    [switch]$Show
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$cfgPath = Get-KitConfigPath -Root $root
$cfg = Get-KitConfig -Root $root
$pwshForm = 'pwsh -NoProfile -File '
$psForm = 'powershell -NoProfile -ExecutionPolicy Bypass -File '

function Get-KitTextFiles {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @('AGENTS.md')) { $p = Join-Path $root $rel; if (Test-Path -LiteralPath $p) { $list.Add($p) } }
    foreach ($dir in @('.github/agents', '.github/skills', '.github/instructions', 'docs/ai', 'specs/_templates')) {
        $d = Join-Path $root $dir
        if (Test-Path -LiteralPath $d) { foreach ($f in (Get-ChildItem -Path $d -Recurse -File -Filter '*.md')) { $list.Add($f.FullName) } }
    }
    return ,$list.ToArray()
}

function Set-KitJsonValue {
    param($Obj, [string]$Path, $Value)
    $parts = $Path.Split('.')
    $cur = $Obj
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $p = $cur.PSObject.Properties[$parts[$i]]
        if ($null -eq $p -or $null -eq $p.Value) {
            $cur | Add-Member -NotePropertyName $parts[$i] -NotePropertyValue ([pscustomobject]@{}) -Force
            $p = $cur.PSObject.Properties[$parts[$i]]
        }
        $cur = $p.Value
    }
    $last = $parts[$parts.Count - 1]
    if ($cur.PSObject.Properties[$last]) { $cur.$last = $Value } else { $cur | Add-Member -NotePropertyName $last -NotePropertyValue $Value -Force }
}

# ---------------------------------------------------------------- launcher
if ($Launcher -ne 'keep') {
    $target = $Launcher
    if ($target -eq 'auto') {
        $target = 'powershell'
        if (Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue) { $target = 'pwsh' }
    }
    $from = $psForm
    $to = $pwshForm
    if ($target -eq 'powershell') { $from = $pwshForm; $to = $psForm }
    $changedFiles = 0
    foreach ($f in (Get-KitTextFiles)) {
        $t = Read-KitTextFile -Path $f
        if ($t.Contains($from)) { Write-KitTextFile -Path $f -Text $t.Replace($from, $to); $changedFiles++ }
    }
    Write-Output ("Launcher set to '$target' ($changedFiles file(s) updated): scripts run with: " + $to.Trim() + ' <script>')
}

# ---------------------------------------------------------------- models
if ($ApplyModels) {
    $mode = [string]$cfg.models.mode
    $agentsDir = Join-Path $root '.github/agents'
    foreach ($file in @(Get-ChildItem -Path $agentsDir -Filter '*.agent.md' -File)) {
        $key = $file.Name -replace '\.agent\.md$', ''
        $text = Read-KitTextFile -Path $file.FullName
        $m = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---')
        if (-not $m.Success) { continue }
        $fm = $m.Groups[1].Value
        $fmNew = [regex]::Replace($fm, '(?m)^model:.*(\r?\n)?', '')
        $note = 'picker (Auto or current)'
        if ($mode -eq 'tiered') {
            $tier = [string](Get-KitProp -Object $cfg.models.agents -Names @($key))
            $models = @()
            if ($tier) { $models = @(@(Get-KitProp -Object $cfg.models.tiers -Names @($tier)) | Where-Object { $_ }) }
            if ($models.Count -gt 0) {
                $line = 'model: [' + ((@($models | ForEach-Object { "'" + ([string]$_ -replace "'", "''") + "'" })) -join ', ') + ']'
                $fmNew = $fmNew.TrimEnd() + "`n" + $line
                $note = $tier + ' -> ' + ($models -join ' | ')
            } else { $note = "tier '$tier' has no models configured: picker" }
        }
        if ($fmNew -ne $fm) {
            $text = $text.Substring(0, $m.Groups[1].Index) + $fmNew + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
            Write-KitTextFile -Path $file.FullName -Text $text
        }
        Write-Output ('  {0,-18} {1}' -f $key, $note)
    }
    Write-Output "Model routing applied (mode: $mode)."
}

# ---------------------------------------------------------------- config values (bootstrap status, formatting)
if ($MarkBootstrapped -or $Solution -or $Format -ne 'keep') {
    $obj = Read-KitJsonFile -Path $cfgPath
    if ($null -eq $obj) { $obj = [pscustomobject]@{} }
    if ($Solution) { Set-KitJsonValue -Obj $obj -Path 'bootstrap.solution' -Value (Get-KitRelativePath -Path $Solution -Root $root) }
    if ($MarkBootstrapped) {
        Set-KitJsonValue -Obj $obj -Path 'bootstrap.status' -Value 'done'
        Set-KitJsonValue -Obj $obj -Path 'bootstrap.completedAt' -Value ((Get-Date).ToString('yyyy-MM-dd'))
    }
    if ($Format -ne 'keep') {
        Set-KitJsonValue -Obj $obj -Path 'qualityGate.format' -Value $Format
        $how = 'changed files are no longer formatted'
        if ($Format -ne 'off') { $how = "the quality gate formats the changed .cs files ($Format) before building, once per agent turn" }
        Write-Output "Formatting: $how."
    }
    Write-KitJsonFile -Path $cfgPath -Object $obj -Depth 12
    Write-Output 'Kit configuration updated (.github/kit/config.json).'
    $cfg = Get-KitConfig -Root $root
}

# ---------------------------------------------------------------- summary
if ($Show -or ($Launcher -eq 'keep' -and -not $ApplyModels -and -not $MarkBootstrapped -and -not $Solution -and $Format -eq 'keep')) {
    $sample = Read-KitTextFile -Path (Join-Path $root '.github/skills/dotnet-build-test/SKILL.md')
    $launcherNow = 'unknown'
    if ($sample -and $sample.Contains($pwshForm)) { $launcherNow = 'pwsh' } elseif ($sample -and $sample.Contains($psForm)) { $launcherNow = 'powershell' }
    Write-Output ('Kit version: ' + $cfg.kitVersion + ' | bootstrap: ' + $cfg.bootstrap.status + ' | solution: ' + $cfg.bootstrap.solution)
    Write-Output ('Script launcher in docs: ' + $launcherNow + ' | PowerShell 7 installed: ' + [bool](Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue))
    Write-Output ('Models: ' + $cfg.models.mode + ' | quality gate: build=' + $cfg.qualityGate.build + ', tests=' + $cfg.qualityGate.tests + ', format=' + $cfg.qualityGate.format)
    Write-Output ('Guard: ' + $cfg.guard.enabled + ' | protected branches: ' + (@($cfg.guard.protectedBranches) -join ', ') + ' | internal prefixes: ' + (@($cfg.internalPackages.prefixes) -join ', '))
}
