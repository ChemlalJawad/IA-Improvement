# test-hooks.ps1 - Self-test of the kit hooks on this machine.
# Runs each hook exactly as configured in .github/hooks/kit-hooks.json (same launcher, same working directory)
# with sample payloads in the VS Code, Copilot and Claude formats, checks the decisions and measures latency.
# Usage:  pwsh -NoProfile -File .github/hooks/scripts/test-hooks.ps1
#    or:  powershell -NoProfile -ExecutionPolicy Bypass -File .github/hooks/scripts/test-hooks.ps1
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\kit\lib\KitCore.ps1')
$root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 3
$hookFile = Join-Path $root '.github/hooks/kit-hooks.json'
$hooks = Read-KitJsonFile -Path $hookFile
if ($null -eq $hooks) { Write-Host "FAIL: cannot parse $hookFile"; exit 1 }
$onWindows = ($env:OS -eq 'Windows_NT')

function Get-KitHookCommandLine {
    param([string]$EventName)
    $entry = @($hooks.hooks.$EventName) | Select-Object -First 1
    if ($null -eq $entry) { return $null }
    if ($onWindows) { return [string](Get-KitProp -Object $entry -Names @('windows', 'powershell', 'command')) }
    return [string](Get-KitProp -Object $entry -Names @('linux', 'osx', 'bash', 'command'))
}

function Invoke-KitHookProcess {
    param([string]$CommandLine, [string]$Json, [hashtable]$Environment)
    $parts = $CommandLine.Trim() -split '\s+', 2
    $exe = Get-Command -Name $parts[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $exe) { return [pscustomobject]@{ Exit = 127; Out = ''; Err = "launcher not found: $($parts[0])"; Ms = 0 } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe.Path
    if ($parts.Count -gt 1) { $psi.Arguments = $parts[1] }
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:KitUtf8
    $psi.StandardErrorEncoding = $script:KitUtf8
    if ($Environment) { foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = [string]$Environment[$k] } }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$p.Start()
    $bytes = $script:KitUtf8.GetBytes($Json)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(120000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ Exit = 124; Out = ''; Err = 'timeout'; Ms = 120000 }
    }
    $sw.Stop()
    [void]$o.Wait(5000)
    [void]$e.Wait(5000)
    return [pscustomobject]@{ Exit = $p.ExitCode; Out = [string]$o.Result; Err = [string]$e.Result; Ms = [int]$sw.Elapsed.TotalMilliseconds }
}

function New-KitCase {
    param([string]$Name, [string]$EventName, $Payload, [string]$Expect)
    return [pscustomobject]@{ Name = $Name; Event = $EventName; Payload = $Payload; Expect = $Expect }
}

$domainCsproj = 'src/Acme.Shop.Domain/Acme.Shop.Domain.csproj'
$cases = @(
    (New-KitCase 'safe build command is allowed' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'dotnet build'; explanation = 'build' } } 'allow'),
    (New-KitCase 'git status is allowed' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'git status --short' } } 'allow'),
    (New-KitCase 'force push is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'git push --force origin feature/123-x' } } 'deny'),
    (New-KitCase 'push to protected branch is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'git push origin main' } } 'deny'),
    (New-KitCase 'push of a feature branch asks' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'git push -u origin feature/123-add-claims' } } 'ask'),
    (New-KitCase 'git reset --hard asks' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'git reset --hard HEAD~1' } } 'ask'),
    (New-KitCase 'forced worktree removal asks' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'git worktree remove --force ../Shop.worktrees/123-x' } } 'ask'),
    (New-KitCase 'dotnet add package asks' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'dotnet add src/Acme.Shop.Application/Acme.Shop.Application.csproj package Foo.Bar' } } 'ask'),
    (New-KitCase 'nuget push is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = 'dotnet nuget push bin/x.nupkg -s intranet' } } 'deny'),
    (New-KitCase 'layer-breaking reference command is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'run_in_terminal'; tool_input = @{ command = "dotnet add $domainCsproj reference src/Acme.Shop.Infrastructure/Acme.Shop.Infrastructure.csproj" } } 'deny'),
    (New-KitCase 'layer-breaking csproj edit is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'replace_string_in_file'; tool_input = @{ filePath = $domainCsproj; oldString = '</Project>'; newString = '<ItemGroup><ProjectReference Include="..\Acme.Shop.Infrastructure\Acme.Shop.Infrastructure.csproj" /></ItemGroup></Project>' } } 'deny'),
    (New-KitCase 'private key in a new file is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'create_file'; tool_input = @{ filePath = 'src/keys.txt'; content = "-----BEGIN RSA PRIVATE KEY-----`nMIIEpAIBAAKCAQEA" } } 'deny'),
    (New-KitCase 'password in appsettings asks' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'create_file'; tool_input = @{ filePath = 'src/Api/appsettings.Development.json'; content = '{ "ConnectionStrings": { "Db": "Server=.;Database=x;User Id=sa;Password=Sup3rSecret!" } }' } } 'ask'),
    (New-KitCase 'placeholder password is allowed' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'create_file'; tool_input = @{ filePath = 'src/Api/appsettings.json'; content = '{ "ConnectionStrings": { "Db": "Server=.;Database=x;Password=<from-key-vault>" } }' } } 'allow'),
    (New-KitCase 'Belgian national number in test data asks' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'create_file'; tool_input = @{ filePath = 'tests/Data.cs'; content = 'var insured = new Insured("85.07.30-033.28");' } } 'ask'),
    (New-KitCase 'reading a .pfx is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'read_file'; tool_input = @{ filePath = 'certs/dev.pfx' } } 'deny'),
    (New-KitCase 'editing generated code is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'replace_string_in_file'; tool_input = @{ filePath = 'src/Acme.Shop.Api/obj/Debug/Api.g.cs'; oldString = 'a'; newString = 'b' } } 'deny'),
    (New-KitCase 'apply_patch on a normal file is allowed' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'apply_patch'; tool_input = @{ input = "*** Begin Patch`n*** Update File: src/Acme.Shop.Domain/Order.cs`n@@`n-    old`n+    new`n*** End Patch" } } 'allow'),
    (New-KitCase 'Copilot format (toolArgs as JSON string) force push is denied' 'PreToolUse' @{ toolName = 'bash'; toolArgs = '{"command":"git push -f"}' } 'deny'),
    (New-KitCase 'Claude format Bash rm -rf / is denied' 'PreToolUse' @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = @{ command = 'rm -rf /' } } 'deny'),
    (New-KitCase 'str_replace_editor view of generated file is allowed' 'PreToolUse' @{ toolName = 'str_replace_editor'; toolArgs = @{ command = 'view'; path = 'src/Acme.Shop.Api/obj/Debug/Api.g.cs' } } 'allow'),
    (New-KitCase 'session start returns context' 'SessionStart' @{ hook_event_name = 'SessionStart'; source = 'new'; session_id = 'kit-selftest' } 'context'),
    (New-KitCase 'stop gate returns valid JSON (dry-run)' 'Stop' @{ hook_event_name = 'Stop'; stop_hook_active = $false; session_id = 'kit-selftest' } 'json')
)

Write-Host ''
Write-Host ('AI kit hooks self-test - ' + $root)
Write-Host ('PowerShell ' + $PSVersionTable.PSVersion + ' | OS: ' + $(if ($onWindows) { 'Windows' } else { 'non-Windows' }))
if ($onWindows) {
    try { Write-Host ('Execution policy (effective): ' + (Get-ExecutionPolicy)) } catch { }
}
Write-Host ''

$failed = 0
$latencies = New-Object System.Collections.Generic.List[int]
foreach ($c in $cases) {
    $cmdLine = Get-KitHookCommandLine -EventName $c.Event
    if (-not $cmdLine) { Write-Host ('  SKIP  ' + $c.Name + ' (no ' + $c.Event + ' hook configured)'); continue }
    $json = ConvertTo-Json -InputObject $c.Payload -Depth 8 -Compress
    $r = Invoke-KitHookProcess -CommandLine $cmdLine -Json $json -Environment @{ KIT_GATE_DRYRUN = '1' }
    $actual = 'allow'
    if ($r.Exit -eq 2) { $actual = 'deny' }
    elseif ($r.Exit -ne 0) { $actual = "error(exit $($r.Exit))" }
    elseif ($r.Out -match '"permissionDecision"\s*:\s*"ask"') { $actual = 'ask' }
    elseif ($r.Out -match 'additionalContext') { $actual = 'context' }
    $validJson = $true
    if ($r.Exit -eq 0) { try { $null = ConvertFrom-Json -InputObject $r.Out } catch { $validJson = $false } }
    $pass = ($actual -eq $c.Expect) -and $validJson
    if ($c.Expect -eq 'json') { $pass = ($r.Exit -eq 0 -and $validJson) }
    if ($c.Event -eq 'PreToolUse') { $latencies.Add($r.Ms) }
    if ($pass) {
        if (-not $Quiet) { Write-Host ('  PASS  {0}  [{1} ms]' -f $c.Name, $r.Ms) }
    } else {
        $failed++
        Write-Host ('  FAIL  {0}: expected {1}, got {2}{3} [{4} ms]' -f $c.Name, $c.Expect, $actual, $(if (-not $validJson) { ' (stdout is not valid JSON)' } else { '' }), $r.Ms)
        if ($r.Err) { Write-Host ('        stderr: ' + ($r.Err.Trim() -replace "\r?\n", ' | ')) }
        if ($r.Out) { Write-Host ('        stdout: ' + $r.Out.Trim()) }
    }
}

$avg = 0
if ($latencies.Count -gt 0) { $avg = [int](($latencies | Measure-Object -Average).Average) }
Write-Host ''
Write-Host ('Result: {0}/{1} passed. PreToolUse latency: ~{2} ms per tool call.' -f ($cases.Count - $failed), $cases.Count, $avg)
if ($avg -gt 1500) { Write-Host 'Note: hooks are slow on this machine (antivirus scanning, slow PowerShell start). See the troubleshooting section of the kit guide.' }
if ($failed -gt 0) {
    Write-Host 'Some hooks misbehave. Common causes: execution policy enforced by GPO, scripts blocked (run Unblock-File), PowerShell not on PATH.'
    exit 1
}
exit 0
