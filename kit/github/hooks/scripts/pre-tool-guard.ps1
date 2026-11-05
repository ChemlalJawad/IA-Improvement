# pre-tool-guard.ps1 - PreToolUse hook: deterministic guardrails for every agent tool call.
#   deny  -> exit code 2 + reason on stderr (blocks the call in VS Code Local, the Copilot runtime and Claude formats)
#   ask   -> JSON permissionDecision "ask" (the user confirms in the chat UI; the cloud agent treats it as deny)
#   allow -> {} (the normal approval flow continues)
# Any internal error fails OPEN ({} + exit 0): a bug here must never brick the agent.
# Rules are configured in .github/kit/config.json (guard section). Windows PowerShell 5.1 / PowerShell 7+. ASCII-only.

$ErrorActionPreference = 'Stop'

function New-KitDecision {
    param([string]$Kind, [string]$Rule, [string]$Reason)
    return [pscustomobject]@{ Kind = $Kind; Rule = $Rule; Reason = $Reason }
}

function Get-KitCommandRules {
    param($Guard)
    $r = New-Object System.Collections.Generic.List[object]
    $defs = @(
        @('deny', 'git-force-push', '\bgit\b[^|;&]*\bpush\b[^|;&]*(\s--force(?!-with-lease)\b|\s-f\b|\s\+\S+)', 'Force-push rewrites shared history. Use --force-with-lease on your own feature branch, and only when the user explicitly asks.'),
        @('ask', 'git-push', '\bgit\b[^|;&]*\bpush\b', 'Pushing publishes commits to the remote. Confirm with the user first.'),
        @('ask', 'git-discard', '\bgit\b[^|;&]*\b(reset\s+--hard|clean\s+-[a-zA-Z]*[fdx]|checkout\s+--\s+\.|restore\s+(--staged\s+)?(--worktree\s+)?\.(\s|$)|stash\s+(drop|clear))', 'This discards local changes irreversibly.'),
        @('ask', 'git-worktree-force', '\bgit\b[^|;&]*\bworktree\s+remove\b[^|;&]*\s(--force|-f)\b', 'Force-removing a worktree discards its uncommitted changes.'),
        @('ask', 'git-branch-delete', '\bgit\b[^|;&]*\b(branch\s+-D|push\s+\S+\s+(--delete|:))', 'Deleting branches is irreversible.'),
        @('ask', 'pr-complete', '(\bgh\s+pr\s+merge\b|\baz\s+repos\s+pr\s+update\b[^|;&]*--(status\s+completed|auto-complete))', 'Completing or merging a pull request is an explicit human decision.'),
        @('deny', 'rm-root', '(\brm\s+-[a-zA-Z]*r[a-zA-Z]*\s+(/|~|\$HOME|\*|/\*)(\s|$))|(\b(Remove-Item|ri|rm|del|rd|rmdir)\b[^|;&]*\s([A-Za-z]:\\?|~|\$HOME|\$env:USERPROFILE|\\)(\s|$))', 'Recursive deletion of a drive, root or home directory.'),
        @('ask', 'rm-recursive', '(\brm\s+-[a-zA-Z]*r)|(\b(Remove-Item|ri)\b[^|;&]*-Recurse)|(\b(rd|rmdir)\b[^|;&]*\s/s\b)|(\bdel\b[^|;&]*\s/s\b)', 'Recursive deletion. Confirm the target first.'),
        @('deny', 'disk', '\b(Format-Volume|Clear-Disk|diskpart|mkfs(\.\w+)?|format\s+[a-zA-Z]:)|\bdd\s+if=', 'Disk-level operations are never run by the agent.'),
        @('deny', 'power', '\b(shutdown(\.exe)?\s|Stop-Computer|Restart-Computer)', 'System power operations are never run by the agent.'),
        @('deny', 'download-exec', '\b(curl|wget|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)\b[^|]*\|\s*(iex|Invoke-Expression|sh|bash|pwsh|powershell)\b', 'Download-and-execute is not allowed.'),
        @('ask', 'invoke-expression', '\b(iex|Invoke-Expression)\b', 'Invoke-Expression executes arbitrary strings.'),
        @('deny', 'nuget-push', '\b(dotnet\s+nuget\s+push|nuget(\.exe)?\s+push)\b', 'Publishing packages is a release decision for a human or a pipeline.'),
        @('ask', 'nuget-source', '\bdotnet\s+nuget\s+(add|remove|update|enable|disable)\s+source\b', 'Changing NuGet sources affects the intranet feed setup.'),
        @('ask', 'add-package', '\bdotnet\s+(add\b[^|;&]*\bpackage\b|package\s+add\b)', 'Adding a NuGet package needs explicit user approval (AGENTS.md).'),
        @('deny', 'db-drop', '\b(DROP\s+(DATABASE|SCHEMA|TABLE)|TRUNCATE\s+TABLE)\b|\bdotnet\s+ef\s+database\s+drop\b', 'Destructive database operation.'),
        @('ask', 'db-change', '\bdotnet\s+ef\s+(database\s+update|migrations\s+remove)\b', 'This changes a database or removes a migration. Check the connection first: never a shared environment.'),
        @('deny', 'cloud-delete', '\baz\s+[^|;&]*\b(delete|purge)\b|\bterraform\s+destroy\b|\bkubectl\s+delete\b|\bhelm\s+(uninstall|delete)\b', 'Deleting cloud or Azure DevOps resources is never done by the agent.'),
        @('ask', 'cloud-change', '\baz\s+[^|;&]*\b(create|update|set|deploy|start|stop|restart|run|import|add|remove|assign|queue)\b|\bterraform\s+apply\b|\bkubectl\s+(apply|scale|rollout|patch|edit)\b|\bhelm\s+(install|upgrade)\b', 'This changes Azure / Azure DevOps state (resources, PRs, pipelines). Confirm with the user.'),
        @('deny', 'secret-files', '\b(cat|type|Get-Content|gc|more|less|head|tail|Select-String|sls|findstr|grep)\b[^|;&]*\.(pfx|p12|pem|key|snk|publishsettings)\b|\b(cat|type|Get-Content|gc)\b[^|;&]*(^|[\s\\/])\.env(\s|$)', 'Reading private keys, certificates or .env files is not allowed.'),
        @('ask', 'user-secrets', '\bdotnet\s+user-secrets\s+(list|set|remove|clear)\b', 'User secrets contain credentials.'),
        @('ask', 'system-config', '\b(Set-ExecutionPolicy|reg(\.exe)?\s+(add|delete|import)|Set-ItemProperty\s+[^|;&]*HK(LM|CU):|Remove-ItemProperty\s+[^|;&]*HK(LM|CU):)', 'System configuration change.'),
        @('ask', 'kit-integrity', '(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Rename-Item|Copy-Item|\brm\b|\bmv\b|\bcp\b|\bdel\b|>)[^|;&]*\.github[\\/](hooks|kit)\b', 'This modifies the AI kit guardrails or configuration.')
    )
    foreach ($d in $defs) {
        $x = New-KitDecision $d[0] $d[1] $d[3]
        $x | Add-Member -NotePropertyName Pattern -NotePropertyValue $d[2]
        $r.Add($x)
    }
    foreach ($p in @($Guard.extraDenyCommands)) { if ($p) { $x = New-KitDecision 'deny' 'custom-deny' "Blocked by guard.extraDenyCommands ($p)."; $x | Add-Member -NotePropertyName Pattern -NotePropertyValue ([string]$p); $r.Add($x) } }
    foreach ($p in @($Guard.extraAskCommands)) { if ($p) { $x = New-KitDecision 'ask' 'custom-ask' "Confirmation required by guard.extraAskCommands ($p)."; $x | Add-Member -NotePropertyName Pattern -NotePropertyValue ([string]$p); $r.Add($x) } }
    return ,$r.ToArray()
}

function Get-KitPushTargets {
    param([string]$Command)
    $m = [regex]::Match($Command, '\bpush\b(?<rest>[^|;&]*)')
    if (-not $m.Success) { return ,@() }
    $tokens = @($m.Groups['rest'].Value.Trim() -split '\s+' | Where-Object { $_ -and -not $_.StartsWith('-') })
    if ($tokens.Count -le 1) { return ,@() }
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($t in $tokens[1..($tokens.Count - 1)]) {
        $dst = $t.TrimStart('+')
        if ($dst.Contains(':')) { $dst = $dst.Split(':')[-1] }
        $targets.Add(($dst -replace '^refs/heads/', ''))
    }
    return ,$targets.ToArray()
}

function Test-KitMod97 {
    param([string]$Digits11)
    $check = [int]$Digits11.Substring(9, 2)
    $base = [long]$Digits11.Substring(0, 9)
    if ((97 - ($base % 97)) -eq $check) { return $true }
    $base2 = [long]('2' + $Digits11.Substring(0, 9))
    return ((97 - ($base2 % 97)) -eq $check)
}

function Test-KitIbanBe {
    param([string]$Iban)
    $s = ($Iban -replace '\s', '').ToUpperInvariant()
    if ($s.Length -ne 16) { return $false }
    $rearranged = $s.Substring(4) + $s.Substring(0, 4)
    $numeric = New-Object System.Text.StringBuilder
    foreach ($ch in $rearranged.ToCharArray()) {
        if ([char]::IsLetter($ch)) { [void]$numeric.Append(([int][char]$ch - 55)) } else { [void]$numeric.Append($ch) }
    }
    $rem = 0
    foreach ($ch in $numeric.ToString().ToCharArray()) { $rem = ($rem * 10 + [int][string]$ch) % 97 }
    return ($rem -eq 1)
}

try {
    . (Join-Path $PSScriptRoot '..\..\kit\lib\KitCore.ps1')
    $root = Get-KitRootFromScript -ScriptDir $PSScriptRoot -Levels 3
    $payload = Read-KitHookInput
    if ($null -eq $payload) { Write-KitHookOutput @{}; exit 0 }
    $cfg = Get-KitConfig -Root $root
    $guard = $cfg.guard
    if (-not $guard.enabled) { Write-KitHookOutput @{}; exit 0 }

    $tool = Get-KitToolName -Payload $payload
    $toolInput = Get-KitToolInput -Payload $payload
    $leaves = Get-KitStringLeaves -Node $toolInput
    $decisions = New-Object System.Collections.Generic.List[object]

    # ------------------------------------------------------------- terminal commands
    $editorLike = $tool -match '(?i)(str_replace|editor|view|read|create|edit|write|replace|patch|insert|notebook|file)'
    $editorSubCommand = ''
    if ($editorLike) { foreach ($l in $leaves) { if ($l.Key -eq 'command' -and $l.Value -and $l.Value -notmatch '\s') { $editorSubCommand = [string]$l.Value; break } } }
    $terminalLike = $tool -match '(?i)(bash|powershell|pwsh|shell|terminal|execute|^exec|^cmd$|command)'
    $command = $null
    if (-not $editorLike -or $terminalLike) {
        foreach ($l in $leaves) { if ($l.Key -match '^(?i)(command|cmd|commandLine|script)$' -and $l.Value) { $command = [string]$l.Value; break } }
        if ($command -and -not $terminalLike -and $command -notmatch '\s') { $command = $null }
    }
    if ($command) {
        $allowed = $false
        foreach ($p in @($guard.allowCommands)) { if ($p -and $command -match [string]$p) { $allowed = $true; break } }
        if (-not $allowed) {
            foreach ($rule in (Get-KitCommandRules -Guard $guard)) {
                if ($command -match $rule.Pattern) { $decisions.Add((New-KitDecision $rule.Kind $rule.Rule $rule.Reason)) }
            }
            if ($command -match '\bgit\b[^|;&]*\bpush\b') {
                $targets = Get-KitPushTargets -Command $command
                if ($targets.Count -eq 0 -or $targets -contains 'HEAD') { $b = Get-KitGitBranch -Root $root; if ($b) { $targets += $b } }
                foreach ($t in $targets) {
                    if ($t -ne 'HEAD' -and (Test-KitProtectedBranch -Branch $t -Patterns $guard.protectedBranches)) {
                        $decisions.Add((New-KitDecision 'deny' 'protected-branch-push' "Pushing to protected branch '$t' is not allowed. Push a feature branch and open a pull request."))
                    }
                }
            }
            if ($command -match '\bgit\b[^|;&]*\bcommit\b') {
                $b = Get-KitGitBranch -Root $root
                if ($b -and (Test-KitProtectedBranch -Branch $b -Patterns $guard.protectedBranches)) {
                    $decisions.Add((New-KitDecision 'ask' 'protected-branch-commit' "You are on protected branch '$b'. Create a feature branch first (git switch -c feature/<workitem>-<slug>) unless the user explicitly wants this."))
                }
            }
            # Layering check for 'dotnet add <proj> reference <ref>' and 'dotnet reference add <ref> --project <proj>'
            $projToken = $null
            $refTokens = @()
            $m1 = [regex]::Match($command, '\bdotnet\s+add\s+(?:(?<proj>"[^"]+"|\S+?\.(?:cs|fs|vb)proj)\s+)?reference\s+(?<refs>[^|;&]+)')
            $m2 = [regex]::Match($command, '\bdotnet\s+reference\s+add\s+(?<refs>[^|;&]+)')
            if ($m1.Success) { $projToken = $m1.Groups['proj'].Value.Trim('"'); $refTokens = @($m1.Groups['refs'].Value -split '\s+') }
            elseif ($m2.Success) {
                $all = @($m2.Groups['refs'].Value -split '\s+')
                for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -eq '--project' -and ($i + 1) -lt $all.Count) { $projToken = $all[$i + 1].Trim('"') } }
                $refTokens = $all
            }
            if ($m1.Success -or $m2.Success) {
                if (-not $projToken) {
                    $decisions.Add((New-KitDecision 'ask' 'reference-unknown-project' 'Adding a project reference without naming the project: name it explicitly so layering can be checked.'))
                } else {
                    $fromName = [System.IO.Path]::GetFileNameWithoutExtension(($projToken -replace '\\', '/').Split('/')[-1])
                    $from = Get-KitLayerOf -ProjectName $fromName -Layers $cfg.architecture.layers
                    foreach ($rt in $refTokens) {
                        $rt = $rt.Trim('"')
                        if ($rt -notmatch '(?i)\.(cs|fs|vb)proj$' -or $rt -eq $projToken) { continue }
                        $toName = [System.IO.Path]::GetFileNameWithoutExtension(($rt -replace '\\', '/').Split('/')[-1])
                        $to = Get-KitLayerOf -ProjectName $toName -Layers $cfg.architecture.layers
                        if ($cfg.architecture.enabled -and -not (Test-KitLayerReferenceAllowed -FromLayer $from -ToLayer $to)) {
                            $decisions.Add((New-KitDecision 'deny' 'layering' "Layering: $fromName ($($from.name)) must not reference $toName ($($to.name)). Keep dependencies pointing inward; if it is really needed, propose an ADR."))
                        }
                    }
                }
            }
        }
    }

    # ------------------------------------------------------------- file paths
    $rawPaths = Get-KitToolPaths -Leaves $leaves
    $paths = @($rawPaths | ForEach-Object { Get-KitRelativePath -Path $_ -Root $root } | Where-Object { $_ })
    $isWrite = ($tool -match '(?i)(create|edit|write|replace|patch|insert|delete|remove|rename|move|notebook|apply|multi)') -and -not ($tool -match '(?i)^(read|view|get|list|search|find|grep|glob)')
    if ($editorSubCommand -match '^(?i)view$') { $isWrite = $false }
    foreach ($p in $paths) {
        if ($p -match '(?i)\.(example|sample|template|dist)$') { continue }
        $hit = Find-KitGlobMatch -Path $p -Globs $guard.denyReadPaths
        if ($hit) { $decisions.Add((New-KitDecision 'deny' 'secret-path' "Access to secret material is blocked ($p matches $hit). Use user-secrets, Key Vault or pipeline variable groups instead.")) }
    }
    if ($isWrite) {
        foreach ($p in $paths) {
            if (Test-KitPathOutsideRepo -RelativePath $p) { $decisions.Add((New-KitDecision 'ask' 'outside-repo' "Writing outside the repository ($p).")); continue }
            $d = Find-KitGlobMatch -Path $p -Globs $guard.denyWritePaths
            if ($d) { $decisions.Add((New-KitDecision 'deny' 'protected-write' "Do not edit $p by hand (rule $d): it is generated or version-control data. Regenerate it with the proper tool.")); continue }
            $a = Find-KitGlobMatch -Path $p -Globs $guard.askWritePaths
            if ($a) { $decisions.Add((New-KitDecision 'ask' 'sensitive-write' "Sensitive file $p (rule $a): confirm this change.")) }
        }

        # --------------------------------------------------------- content scans
        $content = Get-KitNewContent -Leaves $leaves
        if ($content -and $guard.secretScan) {
            $secretRules = @(
                @('deny', 'private key', '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY-----'),
                @('deny', 'Azure storage account key', '(?i)AccountKey\s*=\s*[A-Za-z0-9+/]{40,}={0,2}'),
                @('deny', 'Azure shared access key', '(?i)SharedAccessKey\s*=\s*[A-Za-z0-9+/]{30,}={0,2}'),
                @('deny', 'Entra ID client secret', '(?<![A-Za-z0-9_~.\-])[A-Za-z0-9_~.\-]{3}\dQ~[A-Za-z0-9_~.\-]{31,34}(?![A-Za-z0-9_~.\-])'),
                @('deny', 'GitHub token', '\bgh[pousr]_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{60,}\b'),
                @('deny', 'AWS access key', '\bAKIA[0-9A-Z]{16}\b'),
                @('deny', 'Slack token', '\bxox[baprs]-[A-Za-z0-9-]{10,}'),
                @('ask', 'password in a connection string', '(?i)\b(password|pwd)\s*=\s*(?![\s;"''<{$%#]|\*{3}|__)[^;"''\s]{4,}'),
                @('ask', 'hard-coded credential', '(?i)\b(api[_-]?key|client[_-]?secret|secret[_-]?key|access[_-]?token|auth[_-]?token)\b\s*["'']?\s*[:=]\s*["''][A-Za-z0-9_\-+/=.~]{16,}["'']'),
                @('ask', 'JWT', '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}')
            )
            foreach ($sr in $secretRules) {
                if ($content -match $sr[2]) {
                    $decisions.Add((New-KitDecision $sr[0] 'secret' "Possible $($sr[1]) in the content being written. Never commit secrets: use user-secrets locally, Key Vault or pipeline variable groups, and placeholders in config files."))
                }
            }
        }
        if ($content -and $guard.piiScan) {
            foreach ($m in [regex]::Matches($content, '(?<!\d)\d{2}\.\d{2}\.\d{2}-\d{3}\.\d{2}(?!\d)')) {
                $digits = $m.Value -replace '\D', ''
                if (Test-KitMod97 -Digits11 $digits) { $decisions.Add((New-KitDecision 'ask' 'pii' 'Content contains what looks like a real Belgian national register number. Use synthetic test data (GDPR).')); break }
            }
            foreach ($line in ($content -split "\r?\n")) {
                if ($line -match '(?i)(rijksregister|registre\s*national|national.?(number|register)|\bnrn\b|\bniss\b|\binsz\b|\bssin\b)') {
                    foreach ($m in [regex]::Matches($line, '(?<!\d)\d{11}(?!\d)')) {
                        if (Test-KitMod97 -Digits11 $m.Value) { $decisions.Add((New-KitDecision 'ask' 'pii' 'Content contains what looks like a real Belgian national register number. Use synthetic test data (GDPR).')); break }
                    }
                }
            }
            foreach ($m in [regex]::Matches($content, '\bBE\d{2}(?:\s?\d{4}){3}\b')) {
                if (Test-KitIbanBe -Iban $m.Value) { $decisions.Add((New-KitDecision 'ask' 'pii' 'Content contains a valid Belgian IBAN. Use clearly fake data in code and tests (GDPR).')); break }
            }
        }

        # --------------------------------------------------------- layering on project file edits
        if ($cfg.architecture.enabled) {
            foreach ($p in @($paths | Where-Object { $_ -match '(?i)\.(cs|fs|vb)proj$' })) {
                $projName = [System.IO.Path]::GetFileNameWithoutExtension($p)
                $from = Get-KitLayerOf -ProjectName $projName -Layers $cfg.architecture.layers
                if ($null -eq $from) { continue }
                $existing = Read-KitTextFile -Path (Join-Path $root $p)
                foreach ($m in [regex]::Matches($content, '<ProjectReference\s+Include\s*=\s*"(?<inc>[^"]+)"')) {
                    $refName = [System.IO.Path]::GetFileNameWithoutExtension(($m.Groups['inc'].Value -replace '\\', '/').Split('/')[-1])
                    $to = Get-KitLayerOf -ProjectName $refName -Layers $cfg.architecture.layers
                    if (-not (Test-KitLayerReferenceAllowed -FromLayer $from -ToLayer $to)) {
                        $decisions.Add((New-KitDecision 'deny' 'layering' "Layering: $projName ($($from.name)) must not reference $refName ($($to.name)). Keep dependencies pointing inward; if it is really needed, propose an ADR."))
                    }
                }
                foreach ($m in [regex]::Matches($content, '<PackageReference\s+Include\s*=\s*"(?<id>[^"]+)"')) {
                    $id = $m.Groups['id'].Value
                    $hit = Find-KitForbiddenPackage -Layer $from -PackageId $id
                    if ($hit) {
                        $decisions.Add((New-KitDecision 'deny' 'layering-package' "Layering: package $id is not allowed in $($from.name) projects (rule $hit)."))
                    } elseif (-not $existing -or $existing -notmatch ('Include\s*=\s*"' + [regex]::Escape($id) + '"')) {
                        $decisions.Add((New-KitDecision 'ask' 'add-package' "Adding NuGet package $id to $projName needs explicit user approval."))
                    }
                }
            }
        }
    }

    # ------------------------------------------------------------- decide
    $final = $null
    foreach ($d in $decisions) { if ($d.Kind -eq 'deny') { $final = $d; break } }
    if ($null -eq $final -and $decisions.Count -gt 0) { $final = $decisions[0] }
    $kind = 'allow'
    $ruleId = ''
    if ($final) { $kind = $final.Kind; $ruleId = $final.Rule }
    $logData = @{ tool = $tool; decision = $kind; rule = $ruleId }
    if ($command) { $logData['cmd'] = Get-KitRedacted -Text $command -Max 120 }
    if ($paths.Count -gt 0) { $logData['paths'] = @($paths | Select-Object -First 3) }
    Write-KitLog -Root $root -EventName 'pre' -Data $logData -Config $cfg

    if ($kind -eq 'deny') {
        Write-KitHookError -Message ('[kit guard] BLOCKED (' + $final.Rule + '): ' + $final.Reason)
        exit 2
    }
    if ($kind -eq 'ask') {
        $reason = '[kit guard] ' + $final.Reason
        Write-KitHookOutput @{ permissionDecision = 'ask'; permissionDecisionReason = $reason; hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'ask'; permissionDecisionReason = $reason } }
        exit 0
    }
    Write-KitHookOutput @{}
    exit 0
} catch {
    # Must not depend on the library: it may be the part that failed to load.
    try { [Console]::Error.WriteLine('[kit guard] internal error ignored (fail-open): ' + $_.Exception.Message) } catch { }
    try { [Console]::Out.Write('{}'); [Console]::Out.Flush() } catch { }
    exit 0
}
