---
name: 'Azure Pipelines YAML'
description: 'Rules for Azure DevOps YAML pipelines: shared templates, pinned tasks, intranet feed authentication, secrets, test publishing, no unrequested trigger or approval changes.'
applyTo: '**/azure-pipelines*.yml,**/*.pipeline.yml,**/pipelines/**/*.yml,**/.azuredevops/**/*.yml,**/templates/**/*.yml'
---
# Azure Pipelines rules

- Reuse the shared templates (`template:`, `extends:`) this repository already uses; do not inline what a template provides.
- Pin task major versions (`DotNetCoreCLI@2`, `NuGetAuthenticate@1`). Install the SDK with `UseDotNet@2` and `useGlobalJson: true`.
- Authenticate to the intranet feed with `NuGetAuthenticate@1` before restore. Never put credentials or PATs in YAML.
- Secrets come from variable groups linked to Key Vault or from secure files. Never print a secret; mark secret outputs `issecret=true`.
- Stages stay explicit (build, test, publish, deploy). Deployments use `environment:` so approvals and checks apply.
- Publish test results (TRX, `PublishTestResults@2`) and coverage (`PublishCodeCoverageResults@2`) so failures are visible in the run.
- Do not change triggers, branch filters, pools, service connections, environments or approvals unless explicitly asked.
- CI parity: every pipeline step must have a local equivalent documented in `docs/ai/project-context.md`.

Troubleshooting a failed run: azure-pipelines skill.
