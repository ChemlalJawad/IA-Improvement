# Changelog

## 1.1.0 - 2026-11-05
Ce qui manquait par rapport à la façon de travailler des équipes d'Anthropic.
- **Tutoriel** : `docs/TUTORIEL.md`, prise en main pas à pas sur un exemple complet (AB#1234), du bootstrap à la retro.
- **Travail en parallèle** : skill `parallel-work` et `worktree.ps1` (`-New`, `-List`, `-Remove`, `-Prune`) : une tâche,
  un worktree git, une branche au format de l'équipe, une session. Jamais de suppression forcée (nouvelle règle du guard).
- **Formatage automatique** : `qualityGate.format` accepte `whitespace`, `csharpier` ou `auto` ; la découverte détecte
  si le dépôt impose déjà un formatage et `/bootstrap` l'active alors avec `configure-kit.ps1 -Format auto`.
- **Contrôles sur chaque PR** : `.azuredevops/pipelines/ai-kit-pr-checks.yml` (couches, build, tests impactés par la PR,
  publication des résultats, formatage optionnel) ; `dotnet-check.ps1 -Ci` annote les erreurs sur le run et la PR.
- **Boucles d'amélioration** : le reviewer propose des « leçons à encoder », `/retro` transforme un bug passé entre les
  mailles en scénario d'évaluation, nouveaux scénarios S11 (parallèle) et S12 (vérification de bout en bout de l'API).
- **Modèles** : stratégie « qualité max » (le modèle le plus fort partout sauf la recherche) documentée.
- Corrections : lecture des erreurs de build dont le chemin contient des parenthèses ou un préfixe `3>`, lecture de tous
  les feeds de `project.assets.json`, résumé des tests en mode Microsoft.Testing.Platform, `-nologo` réservé à VSTest.

## 1.0.0 - 2026-11-04
Première version du kit.
- 8 agents (planner, implementer, reviewer, debugger, devops, context-engineer, researcher, conductor) avec handoffs et sous-agents.
- 17 skills dont `bootstrap` (création depuis le template `dotnet new` d'entreprise + adaptation automatique), `internal-packages`
  (digests des paquets NuGet intranet depuis le cache local), spec-driven development (`spec`, `spec-plan`, `spec-implement`),
  `code-review`, `retro`, `azure-pipelines`, `git-workflow`, `merge-conflicts`.
- Hooks portables (VS Code Local, moteur Copilot, Copilot CLI) : contexte de session, guard (commandes, chemins, secrets,
  données personnelles belges, règles de couches), quality gate (architecture, build, tests impactés).
- Instructions par couche Clean Architecture / DDD, tests, pipelines Azure DevOps.
- Mémoire projet : `specs/`, `docs/ai/` (contexte, glossaire, paquets internes, apprentissages, évaluations), `docs/adr/`.
- Routage des modèles (Auto ou par niveaux) via `configure-kit.ps1`.
- `install.ps1`, `tests/Test-Kit.ps1`, guide d'utilisation en français.
