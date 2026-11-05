# new-spec.ps1 - Creates a numbered spec folder from specs/_templates (spec skill),
# or adds plan.md + tasks.md to an existing spec (spec-plan skill).
# Examples:
#   pwsh -NoProfile -File .github/skills/spec/scripts/new-spec.ps1 -Title "Broker claim declaration" -WorkItem "AB#1234"
#   pwsh -NoProfile -File .github/skills/spec/scripts/new-spec.ps1 -Spec 012 -AddPlan
[CmdletBinding()]
param([string]$Title, [string]$WorkItem = '', [string]$Spec, [switch]$AddPlan)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 4
$specsDir = Join-Path $root 'specs'
$tplDir = Join-Path $specsDir '_templates'
$today = (Get-Date).ToString('yyyy-MM-dd')

function Expand-KitTemplate {
    param([string]$Name, [hashtable]$Values)
    $t = Read-KitTextFile -Path (Join-Path $tplDir $Name)
    if (-not $t) { throw "Template not found: specs/_templates/$Name" }
    foreach ($k in $Values.Keys) { $t = $t.Replace('{{' + $k + '}}', [string]$Values[$k]) }
    return $t
}

if ($AddPlan) {
    if (-not $Spec) { throw 'Use -Spec <NNN | NNN-slug | specs/NNN-slug> together with -AddPlan.' }
    $name = ($Spec -replace '\\', '/').TrimEnd('/').Split('/')[-1]
    $dir = Get-ChildItem -Path $specsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name -or $_.Name.StartsWith($name + '-') } | Select-Object -First 1
    if (-not $dir) { throw "Spec not found: $Spec" }
    $specText = Read-KitTextFile -Path (Join-Path $dir.FullName 'spec.md')
    $specTitle = ''
    $wi = ''
    $m = [regex]::Match([string]$specText, '(?m)^title:\s*"?(.*?)"?\s*$')
    if ($m.Success) { $specTitle = $m.Groups[1].Value }
    $m = [regex]::Match([string]$specText, '(?m)^workItem:\s*"?(.*?)"?\s*$')
    if ($m.Success) { $wi = $m.Groups[1].Value }
    $values = @{ ID = $dir.Name.Substring(0, 3); TITLE = $specTitle; TITLE_YAML = ($specTitle -replace '"', '\"'); DATE = $today; WORKITEM = $wi; SLUG = $dir.Name }
    foreach ($f in @('plan.md', 'tasks.md')) {
        $target = Join-Path $dir.FullName $f
        if (Test-Path -LiteralPath $target) { Write-Output "kept (already exists): specs/$($dir.Name)/$f" }
        else { Write-KitTextFile -Path $target -Text (Expand-KitTemplate -Name $f -Values $values); Write-Output "created: specs/$($dir.Name)/$f" }
    }
    exit 0
}

if (-not $Title) { throw 'Use -Title "<feature title>" (or -Spec <id> -AddPlan).' }
$max = 0
foreach ($d in @(Get-ChildItem -Path $specsDir -Directory -ErrorAction SilentlyContinue)) {
    if ($d.Name -match '^(\d{3})-') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
}
$id = '{0:D3}' -f ($max + 1)
$dirName = $id + '-' + (ConvertTo-KitSlug -Text $Title)
$dirPath = Join-Path $specsDir $dirName
New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
$values = @{ ID = $id; TITLE = $Title; TITLE_YAML = ($Title -replace '"', '\"'); DATE = $today; WORKITEM = $WorkItem; SLUG = $dirName }
Write-KitTextFile -Path (Join-Path $dirPath 'spec.md') -Text (Expand-KitTemplate -Name 'spec.md' -Values $values)
Write-Output "created: specs/$dirName/spec.md"
