<#
.SYNOPSIS
    Installs the AI kit (the kit/ folder of this repository) into a target repository or an empty folder.
.DESCRIPTION
    Copies agents, skills, instructions, hooks, VS Code settings, docs/ai and specs templates.
    In this repository the payload keeps .github and .vscode as kit/github and kit/vscode; they are installed
    as .github and .vscode in the target.
    Existing files are never overwritten unless -Force (backups go to <target>/.ai-local/backup/<timestamp>).
    Files you may already have (AGENTS.md, .vscode/*.json, PR template) are written side by side as *.kit.* for merging.
    Then open the target in VS Code and run /bootstrap in Copilot Chat.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Target C:\src\MyService
.EXAMPLE
    pwsh -NoProfile -File ./install.ps1 -Target C:\src\MyService -Force
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'kit'
if (-not (Test-Path -LiteralPath $source)) { throw "Kit payload not found: $source" }
$source = (Resolve-Path -LiteralPath $source).Path.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $Target)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }
$targetFull = (Resolve-Path -LiteralPath $Target).Path.TrimEnd('\', '/')
if ($targetFull -eq $source -or $targetFull -eq (Split-Path -Path $source -Parent)) { throw 'The target must be another repository, not the kit itself.' }

$mergeFiles = @('AGENTS.md', '.vscode/settings.json', '.vscode/mcp.json', '.vscode/extensions.json', '.azuredevops/pull_request_template.md')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$created = 0
$overwritten = 0
$skipped = New-Object System.Collections.Generic.List[string]
$sideBySide = New-Object System.Collections.Generic.List[string]

foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File -Force)) {
    $srcRel = $file.FullName.Substring($source.Length).TrimStart('\', '/').Replace('\', '/')
    # The kit stores .github and .vscode as github/ and vscode/ (dot-folders are created only in the target).
    $relUnix = $srcRel -replace '^github/', '.github/' -replace '^vscode/', '.vscode/'
    $rel = $relUnix.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $dest = Join-Path $targetFull $rel
    $destDir = Split-Path -Path $dest -Parent
    if (Test-Path -LiteralPath $dest) {
        if ($Force) {
            $backup = Join-Path (Join-Path $targetFull ('.ai-local/backup/' + $stamp)) $rel
            if ($PSCmdlet.ShouldProcess($dest, 'Backup and overwrite')) {
                New-Item -ItemType Directory -Path (Split-Path -Path $backup -Parent) -Force | Out-Null
                Copy-Item -LiteralPath $dest -Destination $backup -Force
                Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
                $overwritten++
            }
        } elseif ($mergeFiles -contains $relUnix) {
            $ext = [System.IO.Path]::GetExtension($dest)
            $kitCopy = $dest.Substring(0, $dest.Length - $ext.Length) + '.kit' + $ext
            if ($PSCmdlet.ShouldProcess($kitCopy, 'Write side-by-side copy')) {
                Copy-Item -LiteralPath $file.FullName -Destination $kitCopy -Force
                $sideBySide.Add($relUnix)
            }
        } else {
            $skipped.Add($relUnix)
        }
        continue
    }
    if ($PSCmdlet.ShouldProcess($dest, 'Copy')) {
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $file.FullName -Destination $dest
        $created++
    }
}

# Files copied from a downloaded zip carry the "from the internet" mark, which RemoteSigned policies block.
if (Get-Command -Name Unblock-File -ErrorAction SilentlyContinue) {
    $gh = Join-Path $targetFull '.github'
    if (Test-Path -LiteralPath $gh) { Get-ChildItem -LiteralPath $gh -Recurse -File -Filter '*.ps1' | Unblock-File -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output ('AI kit installed into ' + $targetFull)
Write-Output ('  created: {0} file(s) | overwritten (backup in .ai-local/backup/{1}): {2} | kept existing: {3}' -f $created, $stamp, $overwritten, $skipped.Count)
if ($sideBySide.Count -gt 0) {
    Write-Output '  Existing files kept; the kit version was written next to them (*.kit.*). Merge them, or let /bootstrap do it:'
    foreach ($s in $sideBySide) { Write-Output ('    - ' + $s) }
}
if ($skipped.Count -gt 0 -and $skipped.Count -le 15) { foreach ($s in $skipped) { Write-Output ('  kept existing: ' + $s) } }
Write-Output ''
Write-Output 'Next steps:'
Write-Output '  1. Open the folder in VS Code and trust the workspace.'
Write-Output '  2. Copilot Chat: type /bootstrap (empty folder: it creates the solution from the company dotnet new template first).'
Write-Output '  3. Review the checklist it prints, then commit: chore(ai): bootstrap AI kit context'
