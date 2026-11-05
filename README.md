# IA-Improvement - kit agentique pour .NET / Clean Architecture

Un écosystème prêt à l'emploi pour travailler avec **GitHub Copilot dans VS Code** sur des projets **.NET / Azure en
Clean Architecture + DDD**, avec **Azure DevOps** pour le code et le CI/CD. Il reprend les pratiques des équipes
d'Anthropic (vérification systématique, plan avant code, *context engineering*, garde-fous déterministes,
amélioration continue) et **s'adapte tout seul** à votre template d'entreprise et à vos paquets NuGet intranet via
`/bootstrap`.

## Ce que contient le kit

| Brique | Contenu |
|---|---|
| **8 agents** | `planner`, `implementer`, `reviewer`, `debugger`, `devops`, `context-engineer`, `researcher` (sous-agent rapide), `conductor` (orchestrateur avec checkpoints) |
| **18 skills** | `bootstrap`, `project-discovery`, `internal-packages`, `spec`, `spec-plan`, `spec-implement`, `code-review`, `retro`, `dotnet-build-test`, `clean-architecture`, `ddd-modeling`, `ef-core`, `azure-pipelines`, `git-workflow`, `merge-conflicts`, `parallel-work`, `debugging`, `kit-authoring` |
| **Instructions ciblées** | C#, tests, Domain, Application, Infrastructure, API, pipelines YAML, specs, édition du kit (`applyTo`) |
| **3 hooks** | contexte de session ; **guard** avant chaque appel d'outil (commandes dangereuses, branches protégées, secrets, données personnelles belges, règles de couches) ; **quality gate** avant la fin (formatage optionnel + architecture + build + tests impactés) |
| **Travail en parallèle** | une tâche = un *worktree* git = une session (`parallel-work`) |
| **Contrôles de PR** | pipeline Azure DevOps prêt à brancher en *build validation* : couches, build, tests impactés, annotations sur la PR |
| **Mémoire projet** | `specs/` (spec-driven development), `docs/ai/` (contexte, glossaire FR/NL/EN, paquets internes, apprentissages, évaluations), `docs/adr/` |
| **Scripts** | découverte de la solution, digests des paquets internes, build/test compacts, contexte git/PR, worktrees, rapport de conflits, analyse des logs, configuration (PowerShell 5.1 et 7) |
| **Config VS Code** | réglages (instructions, hooks, auto-approbation des commandes sûres, messages de commit/PR), MCP (Microsoft Learn + emplacements société / Azure DevOps) |

## Démarrage rapide

```powershell
# 1. Installer le kit dans un projet existant ou un dossier vide
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Target C:\src\MonService

# 2. Ouvrir C:\src\MonService dans VS Code, faire confiance au workspace, puis dans Copilot Chat :
/bootstrap
#    dossier vide  -> crée la solution depuis le template dotnet new de l'entreprise
#    dans tous les cas -> découvre l'architecture, les conventions et les paquets intranet,
#                         écrit le contexte du projet et configure garde-fous, MCP et modèles

# 3. Travailler : /spec, /spec-plan, /spec-implement, /code-review, /git-workflow, /retro ...
```

Vérifier le kit sur votre machine : `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Kit.ps1`
(`-Quick` pour ignorer la partie .NET).

## Structure

```
IA-Improvement/
├── install.ps1              installe kit/ dans un projet (sans rien écraser par défaut)
├── kit/                     contenu copié dans chaque projet
│   ├── AGENTS.md            contexte toujours chargé (≤ 120 lignes, complété par /bootstrap)
│   ├── github/              installé en .github/ dans le projet :
│   │   ├── agents/          rôles
│   │   ├── skills/          workflows et savoir-faire (+ scripts)
│   │   ├── instructions/    règles par type de fichier
│   │   ├── hooks/           garde-fous et quality gate
│   │   └── kit/             config.json + bibliothèque PowerShell partagée
│   ├── vscode/              installé en .vscode/ : settings, MCP, extensions recommandées
│   ├── .azuredevops/        template de pull request + pipeline de contrôles de PR
│   ├── docs/ai/  docs/adr/  contexte IA, glossaire, paquets internes, évaluations, décisions
│   └── specs/               spec-driven development (gabarits)
├── docs/TUTORIEL.md         prise en main pas à pas (à faire en premier)
├── docs/GUIDE.md            la méthode complète (référence)
└── tests/Test-Kit.ps1       auto-test du kit
```

Les dossiers `github/` et `vscode/` sont stockés sans le point dans ce dépôt : ils ne deviennent `.github/` et
`.vscode/` que dans le projet cible, au moment de `install.ps1` (le kit ne s'active donc jamais sur lui-même).

**Par où commencer : [docs/TUTORIEL.md](docs/TUTORIEL.md)** : mise en route, cycle complet d'une fonctionnalité,
choix de l'agent, demandes efficaces, travail en parallèle, mode autonome, coûts et amélioration continue.

**Référence : [docs/GUIDE.md](docs/GUIDE.md)** : philosophie, patterns, workflows quotidiens, modèles et coûts,
garde-fous, compatibilité VS Code (moteurs Local / Copilot), évolution du kit et dépannage.
