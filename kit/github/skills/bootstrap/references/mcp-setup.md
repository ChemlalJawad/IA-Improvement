# MCP servers setup

MCP servers give agents live access to company systems. Configure them in `.vscode/mcp.json` (VS Code format, top-level
`servers`). VS Code forwards eligible servers to Copilot harness sessions; servers that need interactive `${input:...}`
prompts are NOT forwarded, so prefer OAuth / Entra ID sign-in or `${env:NAME}` variables.
The agent tool lists reference servers by name: `company/*`, `ado/*`, `microsoft-learn/*`. Keep those names (or update the
`tools:` of the agents in `.github/agents/` if you choose other names).

## 1. Company MCP server (key `company`)
Ask the user, in one message:
- What it gives access to (documentation, internal packages, Azure DevOps, tickets, data...)?
- Transport: an HTTPS URL (`"type": "http"`) or a command to start (`"type": "stdio"`, e.g. `npx`, `dotnet tool run`, an exe)?
- Authentication: Entra ID / OAuth (handled by VS Code), a header token, environment variables?
Then add it, e.g.:
```json
"company": { "type": "http", "url": "https://<company-mcp-host>/mcp" }
```
or
```json
"company": { "type": "stdio", "command": "<command>", "args": ["<arg>"], "env": { "TOKEN": "${env:COMPANY_MCP_TOKEN}" } }
```
Never write a secret in the file. Ask the user to start and trust the server (Command Palette: "MCP: List Servers"),
then list its tools and document in `docs/ai/project-context.md` (section "Tools and MCP servers") which tool to use for what.

## 2. Azure DevOps (key `ado`) - only if the company server does not already cover it
Organization name from `git remote -v` (`https://dev.azure.com/<org>/...`). Remote server (recommended by Microsoft):
```json
"ado": { "type": "http", "url": "https://mcp.dev.azure.com/<org>" }
```
Local alternative (needs Node.js and npm registry access): `"command": "npx", "args": ["-y", "@azure-devops/mcp", "<org>", "-d", "core", "work", "work-items", "repositories", "pipelines"]`.
It gives work items, pull requests, builds, pipeline logs and wikis to the devops and reviewer agents.
Check that the organization policy allows MCP servers before adding it.

## 3. Microsoft Learn (key `microsoft-learn`) - already configured
Official .NET and Azure documentation search. If the company proxy blocks it, remove it.

## Copilot CLI
The CLI does not read `.vscode/mcp.json`: it uses `.mcp.json` at the repository root (top-level `mcpServers`, no `${input:...}`)
or `~/.copilot/mcp-config.json`. Create it only if the user works with the CLI.
