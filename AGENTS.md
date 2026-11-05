# AGENTS.md - maintaining the IA-Improvement kit

This repository is the source of a reusable AI kit. `kit/` is the payload copied into target .NET repositories by
`install.ps1`; files under `kit/` describe a TARGET project (e.g. `kit/AGENTS.md`), not this repository.
`kit/github/` and `kit/vscode/` are installed as `.github/` and `.vscode/` in the target (dot-folders are not stored
here, so this repository never activates the kit on itself). Paths inside the payload files always use the target form (`.github/...`).

## Layout
- `kit/github/{agents,skills,instructions,hooks,kit}`, `kit/vscode`, `kit/.azuredevops`, `kit/docs`, `kit/specs`, `kit/AGENTS.md`: the payload.
- `install.ps1`: installer. `tests/Test-Kit.ps1`: self-test (static checks, sandbox, .NET sample). `docs/GUIDE.md`: user guide (French).

## Rules
- Agent-facing files are written in English; the README and the guide are in French.
- Respect the budgets and formats of `kit/github/skills/kit-authoring/SKILL.md` (it is the reference for every customization file).
- PowerShell scripts: compatible with Windows PowerShell 5.1 and PowerShell 7, ASCII only, dot-source `.github/kit/lib/*.ps1` (stored in `kit/github/kit/lib/`).
  Functions that return arrays with `return ,$array` must be called by assignment or in parentheses, never inside `@(...)` or piped directly.
- Hook scripts fail open, read the JSON payload from stdin, write exactly one JSON object to stdout; deny = exit code 2.
- Verify every change: `pwsh -NoProfile -File tests/Test-Kit.ps1` (or `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Kit.ps1`).
- Record user-visible changes in `CHANGELOG.md` and bump `kitVersion` in `kit/github/kit/config.json` and in the `KitCore.ps1` defaults.
