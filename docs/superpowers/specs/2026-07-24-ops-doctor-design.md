# ops doctor : design

Statut : approuvé par l'utilisateur le 2026-07-24 (Fractional CTO / Staff Architect, périmètre ops-tools).

## 1. Objectif et architecture globale

Outil de "preflight check" (`ops doctor`) qui valide en une seule commande la santé technique de l'écosystème Fadel OS : est-ce que ça tourne, et où en est l'exécution des backlogs actifs. Ne couvre pas la carrière/les compétences (frontière avec la vue admin Profile Engine, hors périmètre de ce document).

- **Invocation** : `make doctor`, nouveau target Makefile aligné avec `repo-health` / `normalize-eol-*`.
- **Emplacement** : `ops-tools/scripts/ops/doctor.ps1`.
- **Techno** : PowerShell autonome, zéro dépendance externe nouvelle.
- **Pattern de sortie** : accumulation de findings `(Severity: PASS|WARN|FAIL, Category, Message)`, même pattern `Add-Finding` que `meta/audit-editors.ps1`.
- **Sortie** : affichage console coloré + score final `PASS=x WARN=y FAIL=z`, plus génération automatique d'un rapport Markdown dans `meta/rex/doctor_<timestamp>.md` (même convention que `audit-editors-*.md`, aucun flag requis).
- **Résilience** : chaque section est isolée par `try/catch`. L'échec d'une section ne bloque jamais les autres. Le script ne doit jamais crasher silencieusement ; en cas d'exception imprévue dans une section, un finding `FAIL` "section <nom> : erreur inattendue (<message>)" est émis et l'exécution continue sur la section suivante.
- **Contraintes non négociables** (héritées de la décision produit) : pas de nouvelle UI web, pas de nouvelle base de données, pas de nouveau service permanent. V1 = CLI local uniquement.

## 2. Section 1 : Santé infra (catégorie `infra`)

- **Outil** : SSH natif Windows obligatoire, `C:\Windows\System32\OpenSSH\ssh.exe` (jamais le `ssh` de Git Bash/MSYS — piège documenté dans la mémoire `reference-windows-ssh-agent-gotcha`, revalidé le 2026-07-19 sur ce même repo pour `git push`).
- **Commande** :
  ```
  ssh -o BatchMode=yes -o ConnectTimeout=5 seo-prod "docker ps --filter network=seo-prod-network --format '{{json .}}'"
  ```
- **Logique** :
  - Timeout ou injoignable → 1 finding `FAIL` ("VPS seo-prod injoignable"), le reste de la section est marqué `SKIP` (pas de findings supplémentaires pour cette section), les sections suivantes s'exécutent normalement.
  - Joignable → parse la sortie JSON lignes-par-ligne, compare contre la liste attendue codée en dur :
    `prod-traefik, prod-n8n, prod-seo-directus, prod-seo-agents, prod-seo-postgres, prod-seo-redis, prod-seo-qdrant, prod-n8n-postgres, profile-api`
    (vérifié dans le repo : `profile-api`, définit dans `my-curriculum/infra/docker-compose.yml`, rejoint le même réseau externe `seo-prod-network` que la stack `Infra/infra-prod` — un seul appel `docker ps` suffit pour couvrir les deux stacks).
  - Par conteneur attendu, lecture précise des champs JSON réels de `docker ps --format '{{json .}}'` (pas de champ `Health` séparé : l'état de santé est encodé dans la chaîne `Status`, ex. `"Up 3 days (healthy)"`) :
    - Absent de la liste retournée → `FAIL` ("conteneur introuvable").
    - Présent avec `State != "running"` → `FAIL` ("conteneur arrêté : état=<State>").
    - Présent avec `State == "running"` et `Status` contient `(unhealthy)` → `WARN` ("running mais unhealthy").
    - Présent avec `State == "running"` et `Status` contient `(healthy)` ou n'a pas de healthcheck (pas de `(...)` dans `Status`) → `PASS`.

## 3. Section 2 : Statut MCP (catégorie `mcp`)

Cible V1 : serveur `harness` uniquement (Trading/Radar : pas encore de serveur MCP réel, rien à checker).

- **Logique de build** : `PASS` si `harness/mcp-server/dist/index.js` existe ET que son `LastWriteTime` est postérieur au `LastWriteTime` le plus récent parmi les fichiers sous `harness/mcp-server/src/` ; sinon `WARN` ("build obsolète : dist/ plus ancien que src/").
- **Logique de config** : `PASS`/`WARN` selon que `harness/.cursor/mcp.json` référence un chemin `dist/index.js` qui existe réellement sur disque.
- **Télémétrie** : "dernière activité" = `git log -1 --format=%cd -- harness/mcp-server/`, affichée en `PASS` informatif (pas de seuil d'ancienneté qui déclenche un `WARN` en V1 — pas de règle métier pour définir "trop vieux").
- Pas de smoke test runtime réel en V1 (décision actée : les serveurs MCP tournent en stdio, pas de port/daemon à sonder ; un vrai smoke test est un chantier séparé s'il devient nécessaire).

## 4. Section 3 : Complétude .env (catégorie `env`)

- **Cibles** (liste en dur, 7 couples repo → `.env.example`) :
  `harness`, `Infra/infra-local`, `Infra/infra-prod`, `Interface/frontend-astro`, `my-curriculum`, `ops-tools`, `personal-tech-board`.
- **Logique** : extraction des clés par regex `^([A-Z0-9_]+)=` appliquée à `<repo>/.env.example` puis à `<repo>/.env` (si présent). Comparaison des noms de clés uniquement.
- **Contrainte de sécurité** : les valeurs ne sont jamais lues au-delà de l'extraction de la partie avant le premier `=` (la regex ne capture que le nom de clé) ; aucune valeur n'apparaît jamais dans un finding, un log, ou le rapport Markdown.
- **Notation** : `FAIL` si `<repo>/.env` est absent ; sinon un `WARN` par clé présente dans `.env.example` et absente de `.env` ; `PASS` si toutes les clés de `.env.example` sont présentes dans `.env`.

## 5. Section 4 : Avancement backlogs (catégorie `backlog`)

Deux parseurs distincts, un résultat par fichier (pas d'agrégat inventé entre formats différents) :

- **Parseur A (cases markdown)** sur `docs/UPSKILLING.md` (chemin réel : `my-curriculum/docs/UPSKILLING.md`) : compte les lignes `- [x]` vs `- [ ]`, un total par section de projet (titres `## <Projet>`).
- **Parseur B (statuts table)**, ciblé précisément sur UNE table par fichier (ces fichiers contiennent d'autres tables non pertinentes, ex. la table "Zone | Verdict" de `harness/BACKLOG.md` § Post DA-1, à ignorer) :
  - `harness/BACKLOG.md` : uniquement la table sous le titre `## Vue priorisée (ordre d'exécution)` (colonnes `# | ID | Priorité | Statut | Effort | Dépend de | Livrable`).
  - `ops-tools/meta/BACKLOG-META.md` : uniquement la table sous le titre `## Sprint S1 — Mise en service harness (juillet 2026)` (colonnes `P | ID | Statut | Action`).
  Dans la colonne `Statut` de la table ciblée : compte les cellules `✅` vs le total de lignes ; `🔄`/`⬜`/`🔒` comptent comme non terminé.
- **Rendu** : un finding `PASS` par fichier avec le ratio (ex. `docs/UPSKILLING.md : 12/34 complété`). Le contenu texte des tâches n'est jamais extrait ni affiché (frontière stricte avec la vue admin Profile Engine, qui seule traite le contenu narratif carrière/compétences).

## 6. Stratégie de test

- Pas de suite Pester en V1 : aucun précédent Pester dans `ops-tools` (les 3 scripts d'audit existants — `audit-editors.ps1`, `audit-env-compose.ps1`, `audit-images.ps1` — n'ont pas de tests automatisés non plus), cohérence avec les conventions actuelles du repo.
- **Validation manuelle (smoke test)** : exécuter `make doctor` sur l'état réel du parc et vérifier visuellement que le score reflète la réalité connue au moment du run (ex. VPN/VPN coupé → `infra` en `FAIL` ; une clé retirée d'un `.env` local → `env` en `WARN` sur ce repo). Documenté dans le rapport de fin d'implémentation, pas dans une suite de tests automatisée.

## Hors périmètre (V1)

- Pas de smoke test MCP runtime réel.
- Pas de seuil d'ancienneté sur "dernière activité" MCP.
- Pas de découverte automatique des `.env.example` (liste en dur, volontairement).
- Pas d'agrégation inter-formats des backlogs (un ratio par fichier, jamais un chiffre unique fusionné).
- Pas de CI pour `ops doctor` lui-même (c'est un outil de diagnostic local, pas un gate de build).
