# Guide de l'écosystème agentique

Ce guide explique **comment travailler** avec le kit : les principes, l'architecture, les workflows du quotidien, les
modèles et les coûts, les garde-fous, l'amélioration continue et le dépannage. Il vise VS Code + GitHub Copilot sur des
projets .NET / Azure en Clean Architecture + DDD, avec Azure DevOps pour le code et le CI/CD.
Pour apprendre par la pratique, commencez par le [tutoriel](TUTORIEL.md).

---

## 1. La philosophie : ce que font les équipes d'Anthropic, transposé à Copilot

| # | Principe | Pourquoi | Où c'est dans le kit |
|---|---|---|---|
| 1 | **Donner à l'agent un moyen de vérifier son travail** | C'est le levier n°1 de qualité : un agent qui peut compiler et tester se corrige seul | `dotnet-check.ps1` (sortie compacte), hook Stop « quality gate », agent `reviewer` |
| 2 | **Explorer → planifier → coder → vérifier → commit** | Un bon plan évite les allers-retours coûteux | agent `planner`, skills `spec` / `spec-plan` |
| 3 | **Un contexte minimal mais à fort signal** (*context engineering*) | Le contexte est une ressource finie : trop d'instructions = instructions ignorées | `AGENTS.md` court, instructions ciblées (`applyTo`), skills chargés à la demande, sous-agents de recherche |
| 4 | **Les fichiers sont la mémoire, pas la conversation** | Une nouvelle session repart des fichiers sans réexpliquer | `specs/` + journal de progression, `docs/ai/`, ADR |
| 5 | **Le déterministe pour ce qui doit toujours / jamais arriver** | Une instruction peut être oubliée, un hook non | hooks `pre-tool-guard` et `stop-quality-gate` |
| 6 | **Un agent écrit, un autre relit** | Contextes séparés = angles morts différents (encore mieux avec un autre modèle) | `implementer` ↔ `reviewer`, skill `code-review` |
| 7 | **Corriger tôt, repartir propre** | Après deux corrections ratées, le contexte est pollué | nouvelle session + meilleur prompt, plan dans `tasks.md` |
| 8 | **Amélioration composée** (*compounding*) | Chaque erreur corrigée une fois l'est pour toute l'équipe | `/retro`, `docs/ai/learnings.md`, règles versionnées dans git |
| 9 | **Mesurer avant de changer** | Sans évaluation, on ne sait pas si une règle aide | `docs/ai/evals/scenarios.md`, journaux des hooks |
| 10 | **L'humain aux points irréversibles** | Push, merge, déploiement, base de données : décision humaine | garde-fou « ask / deny », checkpoints du `conductor` |
| 11 | **Plusieurs sessions en parallèle** | Une session qui attend un build ou une relecture ne bloque pas la tâche suivante | skill `parallel-work` : une tâche = un *worktree* git = une session |
| 12 | **Les mêmes contrôles sur chaque PR** | Ce que l'agent vérifie en local est revérifié pour tout le monde, sans dépendre de la discipline de chacun | pipeline `ai-kit-pr-checks.yml` (couches, build, tests impactés, annotations sur la PR) |

---

## 2. Architecture de l'écosystème

```
 Toujours chargé        AGENTS.md (≤ 120 lignes) + contexte de session injecté par le hook SessionStart
 Chargé si pertinent    .github/instructions/*.instructions.md (applyTo : couche Domain, tests, pipelines...)
 Chargé à la demande    .github/skills/*/SKILL.md (+ scripts/ + references/) : savoir-faire et workflows
 Rôles                  .github/agents/*.agent.md : planner, implementer, reviewer, debugger, devops,
                        context-engineer, researcher (sous-agent), conductor (orchestrateur)
 Garde-fous             .github/hooks/kit-hooks.json → SessionStart / PreToolUse (guard) / Stop (quality gate)
 CI                     .azuredevops/pipelines/ai-kit-pr-checks.yml → mêmes contrôles sur chaque pull request
 Outils                 scripts PowerShell (sortie compacte), serveurs MCP (société, Azure DevOps, Microsoft Learn)
 Mémoire                specs/ (spec, plan, tâches, journal), docs/adr/, docs/ai/ (contexte, glossaire,
                        paquets internes, apprentissages, évals), .ai-local/ (local : logs, découverte)
 Configuration          .github/kit/config.json (couches, garde-fous, quality gate, modèles)
```

Coût en contexte : seuls `AGENTS.md`, les quelques lignes du hook SessionStart et les **descriptions** des skills et
agents sont chargés à chaque requête. Tout le reste arrive seulement quand la tâche le demande.

---

## 3. Les patterns agentiques et leur place dans le kit

| Pattern (Anthropic, « Building effective agents ») | Implémentation |
|---|---|
| **Prompt chaining** | spec → plan → tâches → implémentation → review, chaque étape produit un fichier validé |
| **Routing** | le `conductor` trie (petit changement, bug, feature) ; les descriptions des skills orientent le modèle |
| **Parallelization** | sous-agents `researcher` en parallèle (bootstrap, plan, grosse review) ; sessions parallèles, une par *worktree* (`parallel-work`) |
| **Orchestrator-workers** | agent `conductor` qui délègue à planner / implementer / reviewer / debugger |
| **Evaluator-optimizer** | boucle reviewer ↔ implementer ; hook Stop qui bloque tant que build et tests sont rouges |
| **Agent autonome avec garde-fous** | mode autonome (conductor, Autopilot) encadré par le guard et le quality gate |
| **Harness pour tâches longues** | `tasks.md` + journal de progression + rituel de début de session + état propre en fin de session |
| **Spec-driven development** | dossier `specs/` avec gabarits et statuts |
| **Context engineering** | divulgation progressive, sorties de scripts compactes, sous-agents qui résument |
| **Auto-amélioration** | `/retro` + journaux des hooks + scénarios d'évaluation |

---

## 4. Mise en route

### 4.1 Prérequis sur le PC de travail
- **VS Code** récent avec **GitHub Copilot Chat**. Depuis VS Code 1.142 (octobre 2026), le moteur (*harness*) « Copilot »
  est celui par défaut ; « Local » reste disponible dans le sélecteur. Le kit fonctionne avec les deux (voir §9).
- **Politiques Copilot de l'organisation** : certaines fonctions (hooks en preview, serveurs MCP, choix des modèles)
  peuvent être désactivées par l'admin. Le kit se dégrade proprement : sans hooks, plus de garde-fous automatiques ;
  sans MCP, les agents utilisent la CLI `az` ou vous demandent de coller les logs.
- **.NET SDK**, **git**, accès au **feed NuGet intranet** (credential provider Azure Artifacts configuré).
- **PowerShell 7** recommandé (listing complet des API des paquets internes, scripts plus rapides).
  Windows PowerShell 5.1 suffit pour tout le reste.

### 4.2 Installer le kit dans un projet
Récupérer ce dépôt sur le PC de travail (idéalement via git, pas en zip : les fichiers zip téléchargés sont marqués
« internet » et bloqués par certaines politiques d'exécution), puis :

```powershell
# Projet existant ou dossier vide (le template sera créé par /bootstrap)
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Target C:\src\MonService
```

- Rien n'est écrasé sans `-Force` (sauvegardes dans `.ai-local/backup/`).
- Si `AGENTS.md`, `.vscode/settings.json`, `.vscode/mcp.json` ou le template de PR existent déjà, la version du kit est
  écrite à côté (`*.kit.*`) pour fusion.

### 4.3 Lancer `/bootstrap`
Ouvrir le dossier dans VS Code (faire confiance au workspace), puis dans Copilot Chat : **`/bootstrap`**.

- **Dossier vide** : il trouve votre template `dotnet new` d'entreprise (ou vous demande son package id), affiche ses
  paramètres, vous pose **une** question avec des valeurs proposées, fait un *dry run* pour détecter les conflits avec
  les fichiers du kit, génère la solution, restaure depuis l'intranet, compile et teste.
- **Adaptation** (toujours) : cartographie de la solution (couches, références, paquets, pipelines, exemples de
  référence), digests des **paquets internes** à partir du cache NuGet local (doc XML + API + usages réels), conventions
  extraites en parallèle par des sous-agents, puis écriture de `docs/ai/project-context.md`, d'`AGENTS.md`, des
  instructions par couche et des règles d'architecture.
- **Il vous demandera** : les préfixes des paquets internes, les infos du **MCP de la société**, la stratégie de modèles
  (Auto ou par niveaux), quelques termes métier FR / NL, et la validation finale.
- À la fin : une checklist de relecture humaine (10 minutes) et le commit proposé `chore(ai): bootstrap AI kit context`.

### 4.4 Vérifier l'installation
- Dans le projet : `pwsh -NoProfile -File .github/hooks/scripts/test-hooks.ps1` (23 cas : refus, demandes, formats
  VS Code / Copilot / Claude, latence par appel d'outil).
- Dans ce dépôt du kit : `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Kit.ps1` (contrôles statiques,
  dépôt bac à sable, et avec le SDK .NET : solution Clean Architecture d'exemple + faux paquet intranet).

---

## 5. Les workflows du quotidien

> Règle d'or : **une session de chat = une tâche ou une phase**. Les fichiers (`specs/`, `docs/ai/`) portent le
> contexte d'une session à l'autre. Une conversation longue coûte plus cher et devient moins précise.

### 5.1 Nouvelle fonctionnalité (spec-driven)
1. **Session 1** - agent `planner` : `/spec <titre ou AB#1234>`. Il lit le work item (MCP), fait explorer le code par des
   sous-agents, vous pose un seul lot de questions avec des réponses proposées, écrit `specs/NNN-.../spec.md`.
   → Vous validez les critères d'acceptation (`AC-n`).
2. **Session 2** - agent `planner` : `/spec-plan specs/NNN-...`. Plan par couche, stratégie de tests, tâches ordonnées
   avec une commande de vérification chacune, auto-critique par un sous-agent `reviewer`. → Vous validez.
3. **Session 3+** - agent `implementer` : `/spec-implement specs/NNN-...`. Une tâche à la fois, test d'abord, checks
   après chaque tâche, cases cochées et journal de progression. Si la session s'allonge : nouvelle session, il reprend
   depuis `tasks.md`.
4. **Review** - agent `reviewer` : `/code-review`. Il relance lui-même build et tests et classe les constats
   (Blocker / Major / Minor / Nit). Bouton *handoff* « Fix the findings » vers l'implementer si besoin.
5. **PR** - agent `devops` : `/git-workflow pr`. Commit(s) Conventional Commits liés au work item, PR **brouillon**
   avec la description du template, après votre accord.
6. **Fin** : `/retro` si quelque chose a coincé.

### 5.2 Mode autonome
Agent `conductor` + votre demande. Il enchaîne les sous-agents et **s'arrête deux fois** pour validation (spec, plan).
Pour avancer sur autre chose pendant ce temps, voir §5.9.

### 5.3 Petit changement
Agent `implementer` directement (« renomme… », « ajoute un champ… »). Même discipline : test si comportement, `dotnet-check`.

### 5.4 Bug ou test rouge
Agent `debugger` : reproduction (idéalement un test qui échoue), hypothèses, preuve, correction de la cause racine,
test de non-régression. Jamais d'assertion affaiblie.

### 5.5 Pipeline Azure DevOps en échec
Agent `devops` + lien du run ou nom du stage. Il récupère les logs (MCP, sinon `az`, sinon vous les collez), classe
l'échec (compilation, test, authentification au feed, agent, flaky, configuration), reproduit localement avec la
commande équivalente, propose le correctif minimal. Relancer un pipeline = votre accord.

### 5.6 Conflits de merge
Agent `devops` : `/merge-conflicts`. Rapport des conflits (attention : pendant un *rebase*, « ours » et « theirs » sont
inversés), stratégie par type de fichier (le snapshot EF Core se régénère, ne se fusionne pas), build + tests, puis il
vous demande avant `--continue`.

### 5.7 Mise à jour du template ou d'un paquet interne
Agent `context-engineer` : `/bootstrap refresh`. Il relance la découverte et les digests (les « Notes for agents »
écrites à la main sont conservées) et ne met à jour que ce qui a changé.

### 5.8 Amélioration continue
`/retro` en fin de tâche difficile ou chaque semaine : il lit les journaux des hooks (commandes refusées, échecs du
quality gate, codes d'erreur récurrents) et la session, puis propose de petites modifications ciblées : une règle dans
`AGENTS.md`, une puce dans une instruction, une étape de skill, un exemple de référence, une ligne de glossaire, un
scénario d'évaluation. Il élague aussi les règles inutiles. Vous validez, vous commitez, toute l'équipe en profite.
Deux sources alimentent cette boucle en continu : les « leçons à encoder » que le reviewer ajoute à la fin de chaque
revue, et les bugs passés entre les mailles, qui deviennent des scénarios d'évaluation (« bug planté ») pour que la
revue soit retestée dessus.

### 5.9 Travailler en parallèle (worktrees)
Comme chez Anthropic, où l'on fait tourner plusieurs sessions à la fois : **une tâche = un worktree git = une session**.
Un worktree est un deuxième dossier de travail du même dépôt, sur sa propre branche : les sessions ne se marchent jamais
dessus (fichiers, `bin/obj`, état des hooks).

```powershell
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -New "Déclaration de sinistre" -WorkItem 1234 -Open
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -List
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -Remove 1234-declaration-de-sinistre -DeleteBranch
```

- Le worktree est créé dans `<dépôt>.worktrees/`, sur une branche au format de l'équipe (`feature/1234-...`), à partir
  de la branche de base fraîchement récupérée. `-Open` ouvre une nouvelle fenêtre VS Code : une session de chat par fenêtre.
- À paralléliser : des specs ou bugs indépendants, un *spike*, deux designs à comparer. À séquencer : deux tâches sur les
  mêmes fichiers ou le même agrégat, deux migrations EF Core en même temps.
- 2 à 4 sessions suffisent quand vous relisez tout. Une session qui dérive s'abandonne, elle ne se rattrape pas.
- .NET : `dotnet restore` au premier build ; deux API ne peuvent pas écouter sur le même port (`--urls`) ; une base de
  données locale par worktree pour les tests d'intégration.
- `-Remove` refuse un worktree qui a des modifications non commitées et ne supprime jamais une branche non fusionnée.
- Alternative intégrée : démarrer la session en isolation *worktree* depuis le sélecteur de session de VS Code.

### 5.10 Les mêmes contrôles sur chaque pull request
`.azuredevops/pipelines/ai-kit-pr-checks.yml` exécute sur chaque PR ce que l'agent exécute en local : règles de
couches, build, tests des projets impactés par la PR, publication des résultats, formatage en option. Les erreurs sont
annotées sur le run et visibles depuis la PR. C'est déterministe : aucun modèle, aucune clé d'API.
1. Pipelines > New pipeline > Azure Repos Git > Existing YAML file > ce fichier (adapter le pool si besoin).
2. Repos > Branches > branche de base > Branch policies > **Build validation** > ajouter ce pipeline. Azure Repos
   ignore les déclencheurs `pr:` du YAML : c'est la politique de branche qui le lance.
3. S'il existe déjà un pipeline de validation de PR, y ajouter plutôt l'étape « AI kit checks ».

La revue par IA reste locale et à votre initiative : agent `reviewer` (`/code-review`) avant d'ouvrir la PR.

---

## 6. Modèles et coûts

### 6.1 Deux stratégies (choisies pendant `/bootstrap`)
- **Auto (adaptatif)** : les agents n'imposent pas de modèle ; vous choisissez « Auto » dans le sélecteur et Copilot
  choisit selon la requête. Zéro maintenance.
- **Par niveaux** (recommandé quand on connaît les modèles autorisés et leurs multiplicateurs) :

| Niveau | Travail | Agents | Choix typique |
|---|---|---|---|
| reasoning | specs, plans, architecture, review, bugs difficiles | planner, reviewer, debugger | le modèle le plus fort disponible (classe Claude Opus) |
| balanced | implémentation, DevOps, bootstrap, orchestration | implementer, devops, context-engineer, conductor | classe Claude Sonnet |
| fast | recherche et résumés pour les autres agents | researcher | classe Claude Haiku ou un modèle « mini » peu coûteux |

Configuration : `.github/kit/config.json` → section `models` (noms exacts du sélecteur, liste ordonnée avec repli),
puis `configure-kit.ps1 -ApplyModels`. Le reviewer sur une autre famille de modèles que l'implementer détecte plus.

- **Qualité max** (si le budget de requêtes premium le permet) : le créateur de Claude Code utilise le modèle le plus fort
  pour tout le code ; plus lent par réponse, plus rapide au total parce qu'il faut moins le corriger. Dans le kit : le
  modèle le plus fort dans `reasoning` **et** `balanced`, un modèle rapide pour `researcher` seulement. Surveillez la
  consommation une semaine ; redescendez `balanced` en classe Sonnet si le budget ne suit pas.

Ce qui compte, c'est le coût d'un changement terminé et correct, pas le prix par requête : un modèle plus faible qui
demande deux tours de correction de plus revient plus cher.

### 6.2 Hygiène des coûts (quelle que soit la stratégie)
- Une session par tâche ou phase ; ne pas « continuer » une conversation géante.
- Laisser les sous-agents `researcher` lire beaucoup et ne rapporter que l'essentiel.
- Toujours passer par les scripts à sortie compacte (`dotnet-check`, `discover-solution`, `git-context`) plutôt que
  des sorties brutes de plusieurs milliers de lignes.
- Le quality gate ne tourne que si du code a changé, met en cache les résultats et plafonne les tours supplémentaires
  (`qualityGate.maxBlocks`).
- Avant de changer le niveau d'un agent : comparer deux modèles sur deux ou trois scénarios d'évaluation (VS Code permet
  de comparer des modèles).

---

## 7. Gérer le contexte comme une ressource

- **Nouvelle session** dès que la tâche change, ou quand la conversation dépasse quelques dizaines d'échanges.
- **Deux corrections ratées sur le même point** : arrêter, repartir d'une session neuve avec un prompt plus précis
  (le plan et le journal de `tasks.md` évitent de tout réexpliquer).
- **Ne pas coller de gros logs** : demander à l'agent d'utiliser les scripts, ou ne coller que l'étape en échec.
- **Pointer des fichiers** plutôt que les décrire ; les exemples de référence de `project-context.md` valent mieux que
  dix règles.
- **Interrompre tôt** quand l'agent part dans une mauvaise direction ; revenir au plan.

---

## 8. Garde-fous et qualité

### 8.1 Le guard (hook PreToolUse) : vérifié avant chaque appel d'outil
- **Refus** (exit 2, raison renvoyée à l'agent) : force-push, push vers une branche protégée, `rm -rf /` et
  équivalents, `nuget push`, suppression de ressources Azure / Azure DevOps, `DROP`/`TRUNCATE`, téléchargement + exécution,
  lecture de clés privées / certificats / `.env`, écriture dans du code généré, `bin/`, `obj/` ou `.git/`, référence de
  projet qui casse les couches (ex. Domain → Infrastructure), paquet interdit dans une couche, secrets à forte
  confiance (clé privée, clé de compte de stockage, secret Entra ID, tokens GitHub...).
- **Demande de confirmation** : `git push`, `reset --hard`, suppressions récursives, ajout d'un paquet NuGet,
  `dotnet ef database update`, modifications Azure (`az ... create/update/...`), complétion de PR, mot de passe dans une
  chaîne de connexion, **numéro de registre national belge ou IBAN valides** (RGPD : données synthétiques uniquement),
  modification des hooks ou de la config du kit.
- Personnalisation : section `guard` de `.github/kit/config.json` (branches protégées, chemins, commandes en plus,
  liste d'autorisation). Après modification : `test-hooks.ps1`.

### 8.2 Le quality gate (hook Stop) : vérifié quand l'agent veut terminer
Si du code a changé : formatage des fichiers modifiés (si activé) → règles d'architecture → build → tests des projets
**impactés** par le changement. En cas d'échec, l'agent reçoit un rapport compact et doit corriger (ou dire
explicitement qu'un échec est préexistant). Après `maxBlocks` tentatives, il est autorisé à s'arrêter et vous êtes
prévenu. Réglages : section `qualityGate` (tests `affected` / `all` / `none`, filtre, format, timeout).

**Formatage** (`qualityGate.format`) : `off`, `whitespace` (`dotnet format`, rapide, sans charger les projets),
`csharpier` (outil local du dépôt) ou `auto` (CSharpier s'il est déclaré dans `.config/dotnet-tools.json`, sinon
`whitespace`). `/bootstrap` l'active quand le dépôt impose déjà un formatage (CI ou CSharpier) ; sur un code non
formaté, laissez `off`, sinon chaque fichier touché arrive dans la PR entièrement reformaté. Le formatage a lieu une
fois par tour, à la fin, et non après chaque modification : réécrire les fichiers pendant que VS Code suit encore les
modifications en attente de l'agent créerait des conflits. Changer le réglage : `configure-kit.ps1 -Format auto`.

### 8.3 Interrupteur d'urgence
Renommer `.github/hooks/kit-hooks.json` en `kit-hooks.json.off` désactive tous les hooks. Pour un seul garde-fou :
`guard.enabled` ou `qualityGate.enabled` à `false`.

---

## 9. Compatibilité selon le moteur (harness)

| Élément | Local | Copilot (défaut depuis 1.142) | Copilot CLI |
|---|---|---|---|
| `AGENTS.md`, `.github/instructions` | oui | oui | oui |
| Agents `.github/agents` | oui | oui | oui |
| `handoffs`, `agents` (liste de sous-agents), `argument-hint` | oui | ignorés | ignorés |
| Sous-agents | outil `agent` | outil natif de délégation | oui |
| Skills `.github/skills` (+ commande `/nom`) | oui | oui | oui |
| Hooks `.github/hooks/*.json` | oui (réglage `chat.useHooks`, workspace de confiance) | oui | oui |
| Prompt files | oui | **non** (d'où le choix des skills) | non |
| MCP `.vscode/mcp.json` | oui | transmis par VS Code (sauf serveurs à saisie interactive) | non : `.mcp.json` |

---

## 10. Faire évoluer le kit

- **Où changer quoi** : skill `kit-authoring` (budgets, formats exacts, style). Instructions courtes, exemples plutôt
  que règles, pas de doublon avec les analyseurs ou les garde-fous.
- **Tester** : `test-hooks.ps1` pour les hooks et la config ; scénarios de `docs/ai/evals/scenarios.md` pour le
  comportement ; `tests/Test-Kit.ps1` dans ce dépôt.
- **Deux niveaux** : ce dépôt (`IA-Improvement`) est le kit générique et versionné (`CHANGELOG.md`) ; chaque projet
  garde ses adaptations (contexte, conventions, règles apprises). Pour propager une amélioration générique :
  `install.ps1 -Target <projet> -Force` (sauvegarde automatique), puis `/bootstrap refresh` dans le projet.
- **Partager** : tout est dans git (`.github/`, `AGENTS.md`, `docs/ai/`, `specs/`) ; vos collègues ont les mêmes agents,
  skills et garde-fous dès le clone. `.ai-local/` reste local.

---

## 11. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Les hooks ne se déclenchent pas | workspace non approuvé, `chat.useHooks` désactivé (Local), politique d'organisation | approuver le workspace, activer `chat.useHooks` dans les réglages utilisateur, vérifier avec `test-hooks.ps1` |
| Tous les appels d'outil sont refusés | un script de hook ne démarre pas (politique d'exécution imposée par GPO, PowerShell absent) : le moteur Copilot refuse alors l'appel | renommer `kit-hooks.json` en `.off`, lancer `test-hooks.ps1`, voir la ligne « Execution policy » ; demander à l'IT ou signer les scripts |
| Scripts bloqués « not digitally signed » | fichiers issus d'un zip téléchargé | `Get-ChildItem -Recurse *.ps1 | Unblock-File`, ou cloner via git |
| Chaque appel d'outil est lent | démarrage de PowerShell (antivirus) | regarder la latence de `test-hooks.ps1` ; installer PowerShell 7 ; au besoin retirer le hook PreToolUse |
| Un skill n'est jamais utilisé | `name` différent du dossier, description vague | corriger le front matter, ou l'appeler explicitement avec `/nom-du-skill` |
| Un agent n'apparaît pas | mauvais dossier ou extension, moteur différent | fichier `.github/agents/<nom>.agent.md`, sélectionner le bon moteur |
| Serveur MCP absent | politique MCP de l'organisation, saisie interactive non transmise au moteur Copilot | utiliser OAuth / variables d'environnement, ou passer par la CLI `az` |
| Modèle d'agent introuvable | nom différent de celui du sélecteur | corriger `models.tiers` puis `configure-kit.ps1 -ApplyModels` |
| `dotnet restore` 401 / 403 | authentification au feed intranet | `dotnet restore --interactive`, vérifier le credential provider |
| Projet « sans couche » dans la découverte | motifs `projectPattern` trop stricts | adapter `architecture.layers` dans la config puis relancer la découverte |
| `worktree.ps1 -Remove` refuse | modifications non commitées dans le worktree | commiter ou annuler dans ce worktree, puis relancer ; le script ne force jamais |
| Deuxième API en parallèle : port déjà utilisé | deux worktrees lancent l'API sur le même port | `dotnet run --urls http://localhost:<port libre>` |
| Le pipeline de contrôles ne se lance pas sur les PR | Azure Repos ignore les déclencheurs `pr:` du YAML | l'ajouter en *Build validation* dans la politique de la branche de base |

---

## 12. Sources

- Anthropic - [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- Anthropic - [Claude Code: best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
- Anthropic - [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- Anthropic - [Writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- Anthropic - [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- Anthropic - [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Anthropic - [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- Anthropic - [How AI is transforming work at Anthropic](https://www.anthropic.com/research/how-ai-is-transforming-work-at-anthropic) (étude interne, décembre 2025)
- Anthropic - [How Anthropic teams use Claude Code](https://claude.com/blog/how-anthropic-teams-use-claude-code)
- InfoQ - [Inside the Development Workflow of Claude Code's Creator](https://www.infoq.com/news/2026/01/claude-code-creator-workflow/) (sessions parallèles, plan d'abord, CLAUDE.md partagé, vérification)
- Simon Willison - [A Fireside Chat with Cat and Thariq from the Claude Code team](https://simonwillison.net/2026/Jul/21/cat-and-thariq/) (revue automatisée, évals, auto mode)
- VS Code - [Custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents), [référence des fichiers d'agent](https://code.visualstudio.com/docs/agents/reference/custom-agent-file-reference), [Agent skills](https://code.visualstudio.com/docs/agent-customization/agent-skills), [Custom instructions](https://code.visualstudio.com/docs/agent-customization/custom-instructions), [Prompt files](https://code.visualstudio.com/docs/agent-customization/prompt-files), [Hooks](https://code.visualstudio.com/docs/copilot/customization/hooks), [Approvals](https://code.visualstudio.com/docs/agents/run/approvals), [Agent harnesses](https://code.visualstudio.com/docs/agents/concepts/agent-harnesses), [MCP configuration](https://code.visualstudio.com/docs/agents/reference/mcp-configuration)
- GitHub - [Copilot CLI hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference)
- Microsoft - [Azure DevOps MCP server](https://github.com/microsoft/azure-devops-mcp)
