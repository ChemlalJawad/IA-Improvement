# INIT: create the solution from the company `dotnet new` template

The kit files are already in the folder; the solution is not. Goal: instantiate the company Clean Architecture template
without losing kit files, restore from the intranet feed, and get a green baseline.

1. **Prerequisites**
   - `dotnet --info`: SDK present (and matching `global.json` if the template pins one).
   - `dotnet nuget list source`: the intranet feed is listed and enabled. If not, STOP and ask the user for the feed
     name / URL or the nuget.config to use. Never guess a URL, never write credentials into a file.
2. **Find the template**
   - If `.github/kit/config.json` has `bootstrap.template.packageId` / `shortName`, use them.
   - `dotnet new list` shows installed templates. Company templates are usually recognizable by author, tags or short name.
   - Not installed: ask the user for the package id, then `dotnet new install <PackageId>` (add `::<version>` to pin,
     `--add-source <feed-name-or-url>` if the default sources do not contain it, `--interactive` if the feed needs a login;
     warn the user that a browser or device login may appear).
3. **Parameters**: `dotnet new <shortName> --help` lists the options and defaults. Ask the user ONE question with all of
   them (project name, company/product names, options), proposing sensible defaults. Save the answers in the config
   (`bootstrap.template`: packageId, shortName, version, parameters).
4. **Dry run**: `dotnet new <shortName> -n <Name> -o . <options> --dry-run`.
   - No conflict: generate for real with the same command without `--dry-run`.
   - Conflicts with existing files (AGENTS.md, .vscode, .github, .editorconfig, README...): generate into
     `.ai-local/template-out` instead, move every non-conflicting file to the root, then merge each conflict by hand:
     template content wins for build and code files, kit content wins for AI files (AGENTS.md, .github/agents, skills, hooks,
     instructions). Report every merge decision.
5. **Restore, build, test**: `dotnet restore` (401/403 on the intranet feed: ask the user to run
   `dotnet restore --interactive` in a terminal, or to check the Azure Artifacts credential provider), then
   `dotnet-check.ps1 -Test -Scope all`. A fresh template must be green; if it is not, report it before going on.
6. **Git**: not a repository yet? Ask before `git init -b <default-branch>`. Propose the first commit
   `chore: scaffold from <template> <version>` (do not commit without approval).
7. Continue with ADAPT (section C of the bootstrap skill).
