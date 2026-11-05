# Tutoriel : bien utiliser le kit au quotidien

Ce tutoriel fait pratiquer la méthode, étape par étape, sur un exemple concret. Le [guide](GUIDE.md) explique le
*pourquoi* et sert de référence ; ici, on fait.

- **Durée** : 45 minutes pour la mise en route (partie 1) ; chaque autre partie se lit en 5 minutes.
- **Fil rouge** : le work item `AB#1234` « Un courtier déclare un sinistre pour le compte d'un assuré ».
- **Commandes** : elles sont écrites avec `pwsh -NoProfile -File`. Sans PowerShell 7, remplacez par
  `powershell -NoProfile -ExecutionPolicy Bypass -File` (`/bootstrap` le fait automatiquement dans la documentation du kit).

## Les 6 réflexes

1. **Une session = une tâche ou une phase.** Les fichiers (`specs/`, `docs/ai/`) portent la mémoire, pas la conversation.
2. **Plan avant code.** Spec, puis plan, puis tâches, avec votre validation entre chaque étape.
3. **L'agent prouve que ça marche.** Il lance build et tests et montre le résultat ; le quality gate revérifie.
4. **Vous décidez aux points irréversibles.** Push, PR, base de données, nouveaux paquets : l'agent demande.
5. **Plusieurs tâches indépendantes = plusieurs sessions en parallèle**, chacune dans son worktree.
6. **Chaque erreur corrigée devient une règle** (`/retro`), pour toute l'équipe.

---

## Partie 1 - Mise en route (une fois par projet)

### 1.1 Récupérer et tester le kit
```powershell
git clone https://github.com/ChemlalJawad/IA-Improvement.git C:\outils\IA-Improvement
cd C:\outils\IA-Improvement
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Kit.ps1
```
Attendu : `Result: N/N checks passed.` Une ligne `FAIL` : lisez la section Dépannage du guide avant d'aller plus loin.

### 1.2 Installer le kit dans le projet
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\outils\IA-Improvement\install.ps1 -Target C:\src\MonService
```
Rien n'est écrasé. Si le projet a déjà un `AGENTS.md` ou des réglages VS Code, la version du kit est posée à côté
(`*.kit.*`) et `/bootstrap` les fusionne. Un dossier vide convient aussi : `/bootstrap` créera la solution depuis le
template `dotnet new` de l'entreprise.

### 1.3 Lancer `/bootstrap`
1. Ouvrez `C:\src\MonService` dans VS Code et faites confiance au workspace.
2. Dans Copilot Chat, choisissez le modèle **Auto** (ou le plus fort disponible), puis tapez `/bootstrap`.
3. Répondez à son lot de questions : préfixes des paquets internes (ex. `Contoso.*`), informations du MCP de la société,
   stratégie de modèles, 5 à 10 termes métier FR / NL.
4. Il cartographie la solution, résume vos paquets intranet, remplit `AGENTS.md`, `docs/ai/project-context.md`, les
   instructions par couche et les règles d'architecture, et active le formatage si votre dépôt l'impose déjà.

Comptez 20 à 30 minutes.

### 1.4 Relire et valider (10 minutes)
Il termine par une checklist. Vérifiez surtout :
- les commandes build / test de `AGENTS.md` : lancez-les vous-même dans un terminal ;
- les exemples de référence de `docs/ai/project-context.md` : ce sont eux que les agents imitent, ils doivent être bons ;
- les règles de couches : la découverte doit afficher « Layer violations: none ».

Puis commitez : `chore(ai): bootstrap AI kit context`. Vos collègues héritent du contexte au prochain `git pull`.

### 1.5 Vérifier les garde-fous
```powershell
pwsh -NoProfile -File .github/hooks/scripts/test-hooks.ps1
```
Attendu : 23/23 et une latence par appel d'outil idéalement sous la seconde.

### 1.6 Premier exercice (10 minutes)
Pour voir la boucle complète sur un cas sans risque :
1. Agent `implementer`, nouvelle session : « Ajoute un test unitaire manquant pour <une règle métier simple du Domain>.
   Suis l'exemple de référence des tests. »
2. Observez : il ouvre l'exemple de référence, écrit le test, lance `dotnet-check` et cite le résultat. Quand il veut
   s'arrêter, le quality gate relance build et tests impactés.
3. Testez un garde-fou : « Pousse directement sur main. » La demande est refusée et l'agent propose une branche et une PR.

---

## Partie 2 - Le cycle d'une fonctionnalité (fil rouge AB#1234)

Une session de chat par étape. Changez d'agent avec le sélecteur d'agent de Copilot Chat. Avec le moteur Local, des
boutons de *handoff* proposent l'étape suivante ; avec le moteur Copilot, changez simplement d'agent.

### Étape 1 - Spécifier (agent `planner`, nouvelle session)
```
/spec AB#1234 Déclaration de sinistre par un courtier
```
Il lit le work item (MCP), fait explorer le code existant par des sous-agents, puis crée
`specs/001-declaration-de-sinistre-par-un-courtier/spec.md` (le numéro suit les specs existantes). Il pose **un seul lot**
de questions, chacune avec une réponse proposée.

Vous vérifiez :
- chaque critère `AC-n` est testable de l'extérieur (Given / When / Then) ;
- le hors-périmètre est écrit ;
- il ne reste aucun `[NEEDS CLARIFICATION]`.

Répondez « ok » ou corrigez : il passe la spec en `status: approved`.

### Étape 2 - Planifier (agent `planner`, nouvelle session)
```
/spec-plan specs/001-declaration-de-sinistre-par-un-courtier
```
Il produit `plan.md` (conception par couche, risques, stratégie de tests) et `tasks.md` (tâches ordonnées, chacune avec
sa commande de vérification), puis fait critiquer le plan par un sous-agent.

Vous vérifiez : des tâches petites, une couche à la fois, un test prévu pour chaque `AC-n`, aucun nouveau paquet ni
nouvelle référence de projet non discutés.

### Étape 3 - Implémenter (agent `implementer`, une ou plusieurs sessions)
```
/spec-implement specs/001-declaration-de-sinistre-par-un-courtier
```
Il prend une tâche, écrit d'abord le test qui échoue, puis le code, lance `dotnet-check`, coche la tâche et ajoute une
ligne au journal de `tasks.md`.

- **La session s'allonge** : ouvrez-en une nouvelle avec la même commande ; il reprend là où le journal s'arrête.
- **Il part dans une mauvaise direction** : interrompez-le tout de suite et recadrez-le avec le plan.
- **Deux corrections ratées sur le même point** : nouvelle session, avec une demande plus précise.
- **Quality gate rouge** : il reçoit un rapport compact et doit corriger avant de rendre la main.

### Étape 4 - Relire (agent `reviewer`, nouvelle session)
```
/code-review specs/001-declaration-de-sinistre-par-un-courtier
```
Il relance lui-même les contrôles et classe ses constats (Blocker, Major, Minor, Nit) avec `fichier:ligne`. Les Blocker et
Major repartent vers l'implementer (handoff « Fix the findings », ou nouvelle session implementer avec le rapport).

Regardez la fin du rapport, les **« leçons à encoder »** : si une erreur risque de se répéter, gardez-la pour `/retro`.
Astuce : faites tourner le reviewer sur un autre modèle que l'implementer ; leurs angles morts diffèrent.

### Étape 5 - Pull request (agent `devops`)
```
/git-workflow pr
```
Commits Conventional Commits liés au work item (`AB#1234`), description tirée du template de PR, PR créée en
**brouillon** après votre accord. Le push vous est toujours demandé.

### Étape 6 - Rétrospective (2 minutes, si quelque chose a coincé)
```
/retro
```
Il propose de petites modifications ciblées : une règle dans `AGENTS.md`, une puce dans une instruction, un exemple de
référence. Vous validez, vous commitez : la prochaine session ne refera pas l'erreur.

---

## Partie 3 - Quel agent pour quelle situation ?

| Situation | Agent | Ce que vous tapez |
|---|---|---|
| Petit changement clair (1-2 fichiers) | `implementer` | « Ajoute le champ `DateOfLoss` à `ClaimDto` et au mapping ; teste-le. » |
| Nouvelle fonctionnalité | `planner` puis `implementer` | `/spec ...` (partie 2) |
| Grosse demande à dérouler seul | `conductor` | « Livre AB#1234 de bout en bout. » (partie 6) |
| Test rouge, exception, bug | `debugger` | « Le test `Cannot_declare_claim_after_cancellation` échoue : <message>. » |
| Pipeline Azure DevOps en échec | `devops` | « Le run 4521 échoue au stage Test : <extrait du log>. » |
| Conflits de merge ou de rebase | `devops` | `/merge-conflicts` |
| Relire une branche ou une PR | `reviewer` | `/code-review origin/develop` |
| Utiliser un paquet interne | n'importe lequel | « Publie un événement quand le sinistre est déclaré » : il lit le digest du paquet avant de coder |
| Template ou paquets internes mis à jour | `context-engineer` | `/bootstrap refresh` |

---

## Partie 4 - Bien formuler ses demandes

Une bonne demande dit **où**, **quoi**, **comment**, et **comment savoir que c'est fini**.

| À éviter | À préférer |
|---|---|
| « Ajoute la validation. » | « Dans specs/001, tâche T004 : valide le numéro de police (format `AA-000000`, sinon 400 + ProblemDetails). Suis `CreatePolicyCommandValidator.cs`. Termine par `dotnet-check`. » |
| « Ça ne marche pas. » | « `POST /claims` renvoie 500 quand `brokerId` est absent. Stack trace : ... Reproduis avec un test avant de corriger. » |
| « Refais le module paiement. » | « Spike de 30 minutes : propose deux options pour ... avec leurs risques. Ne modifie aucun fichier. » |

- Montrez les fichiers avec `#` (ex. `#CreatePolicyCommandValidator.cs`) plutôt que de les décrire.
- Un exemple de référence vaut mieux que dix règles : « fais comme dans ... ».
- Dites ce qui ne doit **pas** changer (API publique, migrations existantes, contrats d'événements).
- Ne collez que l'étape qui échoue d'un log, jamais le log entier.

---

## Partie 5 - Travailler en parallèle (worktrees)

Pendant que l'implementer avance sur la spec 001, un bug arrive : AB#1240 « un montant négatif est accepté ». Inutile
d'attendre :
```powershell
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -New "Montant négatif accepté" -WorkItem 1240 -Open
```
- Une nouvelle fenêtre VS Code s'ouvre sur `MonService.worktrees\1240-montant-negatif-accepte`, branche
  `feature/1240-montant-negatif-accepte`, créée depuis la branche de base à jour.
- Dans cette fenêtre : agent `debugger`, une session, une tâche. Premier build : `dotnet restore`.
- Les deux sessions ne se touchent jamais : dossiers, branches, `bin/obj` et état des garde-fous séparés.

Suivre et ranger :
```powershell
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -List
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -Remove 1240-montant-negatif-accepte -DeleteBranch
```
Règles : 2 à 4 sessions au maximum quand vous relisez tout ; jamais deux tâches sur les mêmes fichiers, ni deux
migrations EF Core en même temps ; une session qui dérive s'abandonne, elle ne se rattrape pas.

---

## Partie 6 - Le mode autonome (`conductor`)

Pour une fonctionnalité bien cadrée que vous voulez voir avancer pendant que vous faites autre chose :
```
Livre AB#1234 (déclaration de sinistre par un courtier) de bout en bout.
```
Il enchaîne recherche, spec, plan, implémentation et revue avec des sous-agents, et **s'arrête deux fois** : après la
spec et après le plan. Il ne commite ni ne pousse rien sans vous.

- Validez soigneusement aux deux checkpoints : c'est là que se joue la qualité.
- Sur une grosse demande, il propose de la découper en specs indépendantes à lancer en parallèle (partie 5).
- Pour le recadrer : interrompez-le et donnez la correction ; l'état est dans `specs/`, rien n'est perdu.

---

## Partie 7 - Vivre avec les garde-fous

- **Refus** (force-push, `DROP TABLE`, lecture d'un `.pfx`...) : l'agent reçoit la raison et doit proposer autre chose.
  Ne contournez pas : si la règle est mauvaise, changez-la.
- **Demande de confirmation** (`git push`, ajout de paquet, `dotnet ef database update`, IBAN ou numéro de registre
  national dans un fichier...) : lisez ce que l'agent veut faire, puis acceptez ou refusez dans le chat.
- **Quality gate rouge deux fois de suite** : l'agent a le droit de s'arrêter. Relisez alors l'échec vous-même avant de
  commiter.
- **Ajuster** : section `guard` de `.github/kit/config.json` (branches protégées, chemins, commandes), puis `test-hooks.ps1`.
- **Interrupteur d'urgence** : renommez `.github/hooks/kit-hooks.json` en `kit-hooks.json.off`.

---

## Partie 8 - Économiser sans perdre en qualité

- **Ce qui coûte, c'est un changement terminé et correct**, pas une requête : un modèle faible qui demande deux tours de
  correction de plus revient plus cher.
- **Commencez en Auto.** Après deux semaines, passez au routage par niveaux si vous connaissez les modèles autorisés
  (`configure-kit.ps1 -ApplyModels`), ou à la stratégie « qualité max » si le budget le permet (guide, §6.1).
- **Une nouvelle session à chaque phase** : une conversation géante coûte plus cher et devient moins précise.
- **Laissez les sous-agents lire** : ils explorent beaucoup et ne rapportent que l'essentiel.
- **Passez par les scripts à sortie compacte** (`dotnet-check`, `git-context`, `discover-solution`) plutôt que par des
  sorties brutes de milliers de lignes.

---

## Partie 9 - Faire progresser le kit (15 minutes par semaine)

1. `/retro` : il lit les journaux des hooks (commandes refusées, échecs du quality gate, erreurs récurrentes) et la
   session, puis propose des corrections. Gardez les règles qui ont évité une vraie erreur, supprimez les autres.
2. Les « leçons à encoder » des revues de la semaine passent par le même `/retro`.
3. Un bug est passé à travers la revue : ajoutez-le comme scénario « bug planté » dans `docs/ai/evals/scenarios.md`.
4. Après une modification d'instruction, de skill ou d'agent : rejouez 2 ou 3 scénarios dans une session neuve.
5. Commitez `chore(ai): retro <date>` : toute l'équipe en profite.

Une amélioration utile à tous vos projets : faites-la dans le dépôt du kit, puis dans chaque projet
`install.ps1 -Target <projet> -Force` suivi de `/bootstrap refresh`.

---

## Partie 10 - Brancher les contrôles de PR (optionnel, 10 minutes)

Pour que chaque pull request passe les mêmes contrôles que l'agent en local (couches, build, tests impactés) :
1. Azure DevOps : Pipelines > New pipeline > Azure Repos Git > Existing Azure Pipelines YAML file >
   `.azuredevops/pipelines/ai-kit-pr-checks.yml`.
2. Repos > Branches > branche de base > Branch policies > **Build validation** > ajoutez ce pipeline.
3. Ouvrez une PR de test : les erreurs s'affichent sur la PR.

---

## Aide-mémoire

| Quand | Quoi |
|---|---|
| Début de journée | Branches à jour (`/git-workflow sync`) ; choisir 1 à 3 tâches indépendantes |
| Nouvelle tâche | Une session, le bon agent (partie 3) ; en parallèle : `worktree.ps1 -New` |
| Avant de dire « fini » | `dotnet-check` (l'agent le lance, le quality gate le revérifie) |
| Avant la PR | `/code-review`, puis `dotnet-check -Base origin/<branche de base>` |
| Fin de semaine | `/retro` et 2 scénarios d'évaluation |

```powershell
pwsh -NoProfile -File .github/skills/dotnet-build-test/scripts/dotnet-check.ps1          # build + tests impactés
pwsh -NoProfile -File .github/skills/dotnet-build-test/scripts/dotnet-check.ps1 -Test -Scope all
pwsh -NoProfile -File .github/skills/git-workflow/scripts/git-context.ps1                # branche, base, diff, lien de PR
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -List           # sessions parallèles
pwsh -NoProfile -File .github/skills/project-discovery/scripts/discover-solution.ps1    # carte de la solution
pwsh -NoProfile -File .github/skills/internal-packages/scripts/inspect-package.ps1 -ListOnly
pwsh -NoProfile -File .github/skills/bootstrap/scripts/configure-kit.ps1 -Show           # réglages du kit
pwsh -NoProfile -File .github/hooks/scripts/test-hooks.ps1                               # santé des garde-fous
```

Pour aller plus loin : le [guide](GUIDE.md) (principes, patterns, modèles, compatibilité VS Code, dépannage).
