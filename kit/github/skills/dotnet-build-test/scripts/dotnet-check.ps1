# dotnet-check.ps1 - Build and/or test with compact, token-efficient output (dotnet-build-test skill).
# Default: build the solution, then run only the test projects affected by the current changes.
# Examples:
#   pwsh -NoProfile -File .github/skills/dotnet-build-test/scripts/dotnet-check.ps1
#   ... dotnet-check.ps1 -Test -Scope all
#   ... dotnet-check.ps1 -Test -Filter "FullyQualifiedName~OrderTests"
#   ... dotnet-check.ps1 -Build -Architecture
#   ... dotnet-check.ps1 -Base origin/develop          (affected = changes since the base branch)
#   ... dotnet-check.ps1 -Build -Test -Architecture -Ci (Azure Pipelines: annotate errors on the run and the PR)
# Exit code: 0 = all requested checks passed, 1 = something failed.
[CmdletBinding()]
param(
    [switch]$Build,
    [switch]$Test,
    [ValidateSet('affected', 'all')][string]$Scope = 'affected',
    [string]$Target,
    [string]$Filter,
    [string]$Configuration = 'Debug',
    [switch]$NoRestore,
    [string]$Base,
    [switch]$Architecture,
    [int]$Max = 20,
    [int]$TimeoutSec = 1800,
    [switch]$Json,
    [switch]$Ci
)

function Write-KitCiIssue {
    # Azure Pipelines logging command: shows the problem on the run summary and the pull request checks.
    param([string]$Message, [string]$File, [int]$Line = 0, [int]$Col = 0, [string]$Code = '')
    $props = New-Object System.Collections.Generic.List[string]
    $props.Add('type=error')
    if ($File -and $File -match '[\\/.]' -and $File -notmatch '[;\]]') { $props.Add('sourcepath=' + $File) }
    if ($Line -gt 0) { $props.Add('linenumber=' + $Line) }
    if ($Col -gt 0) { $props.Add('columnnumber=' + $Col) }
    if ($Code -and $Code -notmatch '[;\]]') { $props.Add('code=' + $Code) }
    Write-Output ('##vso[task.logissue ' + ($props -join ';') + ';]' + (([string]$Message) -replace '\r?\n', ' '))
}

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitDotnet.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$cfg = Get-KitConfig -Root $root
if (-not $Build -and -not $Test) { $Build = $true; $Test = $true }

$changed = $null
if ($Base) {
    $d = Invoke-KitGit -Root $root -Arguments @('diff', '--name-only', ($Base + '...HEAD')) -TimeoutSec 60
    if ($d.ExitCode -ne 0) { Write-Output ("Cannot diff against '$Base': " + ($d.StdErr -join ' ')); exit 1 }
    $wt = Get-KitChangedFiles -Root $root
    $changed = @(@($d.StdOut) + $wt | Where-Object { $_ } | Select-Object -Unique)
}

$res = Invoke-KitDotnetCheck -Root $root -Config $cfg -Build:$Build -Test:$Test -Scope $Scope -Target $Target -Filter $Filter -TestArgs @($cfg.qualityGate.testArgs) -Configuration $Configuration -NoRestore:$NoRestore -ChangedFiles $changed -TimeoutSec $TimeoutSec -CheckArchitecture:$Architecture -Max $Max

$failedTests = 0
if ($res.Tests) { $failedTests = $res.Tests.Failed }
$errors = 0
if ($res.Build) { $errors = @($res.Build.Errors).Count }
Write-KitLog -Root $root -EventName 'check' -Data @{ ok = $res.Ok; errors = $errors; failedTests = $failedTests; seconds = $res.DurationSec } -Config $cfg

if ($Json) {
    $res | Select-Object Ok, Target, Architecture, Build, Tests, DurationSec | ConvertTo-Json -Depth 6
} else {
    if ($res.Target) { Write-Output ('Target: ' + (Get-KitRelativePath -Path $res.Target -Root $root)) }
    Write-Output $res.Report
    if ($Ci -or $env:TF_BUILD -eq 'True') {
        foreach ($v in @($res.Architecture)) { if ($v) { Write-KitCiIssue -Message ('Layer rule: ' + $v) -Code 'KIT-ARCH' } }
        if ($res.Build) { foreach ($e in @($res.Build.Errors)) { Write-KitCiIssue -Message $e.Message -File $e.File -Line $e.Line -Col $e.Col -Code $e.Code } }
        if ($res.Tests) {
            foreach ($f in @($res.Tests.Failures)) {
                $file = ''
                $line = 0
                $lm = [regex]::Match([string]$f.Location, '^(?<f>.+):(?<l>\d+)$')
                if ($lm.Success) { $file = $lm.Groups['f'].Value; $line = [int]$lm.Groups['l'].Value }
                Write-KitCiIssue -Message ('Test failed: ' + $f.Name + ' - ' + $f.Message) -File $file -Line $line -Code 'KIT-TEST'
            }
        }
    }
}
if ($res.Ok) { exit 0 }
exit 1
