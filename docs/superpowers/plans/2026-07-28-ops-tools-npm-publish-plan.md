# Publication npm @fdiene/ops-tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preparer `@fdiene/ops-tools` pour une publication npm propre : allowlist stricte de fichiers, licence, changelog, documentation de la double distribution - sans executer la publication elle-meme.

**Architecture:** Modifications de metadonnees (`package.json`) et de documentation (`README.md`, `CHANGELOG.md`, `LICENSE`) uniquement. Aucune logique metier touchee (`scripts/ops/doctor.ts` reste intact).

**Tech Stack:** npm (champ `files`, `npm pack --dry-run`), Markdown.

## Global Constraints

- Le champ `files` de `package.json` doit contenir exactement `["scripts/ops/doctor.ts", "tsconfig.json"]` - pas le dossier `scripts/ops/` entier (exclurait sinon `doctor.ps1` et `doctor.test.ts` du tarball, ce qui est le but recherche, mais l'allowlist doit cibler le fichier precis, pas le dossier).
- `package.json` et `README.md` sont toujours inclus par npm independamment du champ `files` (comportement npm documente) - ne pas les ajouter au tableau `files`, ce serait sans effet et pourrait suggerer a tort que leur presence en depend.
- Licence : `"license": "MIT"` dans `package.json`, fichier `LICENSE` avec le texte MIT standard, copyright "Fadel Diene", annee 2026.
- Aucun tiret cadratin dans la redaction (commentaires, messages, documentation).
- Avant tout commit : montrer `git diff` et resumer.
- Pas de suite de tests automatisee pour ce chantier (metadonnees/documentation, pas de logique metier) - verification manuelle avec preuve dans le rapport de tache, meme discipline que les chantiers precedents.

---

### Task 1 : Securisation du package (`package.json` + `LICENSE`)

**Files:**
- Modify: `ops-tools/package.json`
- Create: `ops-tools/LICENSE`

**Interfaces:**
- Consumes : rien (premiere tache).
- Produces : `package.json` avec `license` et `files` corrects, consomme par la verification finale de Task 2.

- [ ] **Step 1 : Reecrire `package.json` avec `license` et `files`**

Lire `ops-tools/package.json` (etat actuel connu, 25 lignes), puis le reecrire integralement avec ce contenu exact :

```json
{
  "name": "@fdiene/ops-tools",
  "version": "0.1.0",
  "license": "MIT",
  "packageManager": "bun@1.3.14",
  "type": "module",
  "bin": {
    "fadel-ops": "scripts/ops/doctor.ts"
  },
  "files": [
    "scripts/ops/doctor.ts",
    "tsconfig.json"
  ],
  "scripts": {
    "doctor": "bun scripts/ops/doctor.ts",
    "build:doctor": "bun build --compile --outfile dist/fadel-ops scripts/ops/doctor.ts",
    "test": "bun test"
  },
  "dependencies": {
    "zod": "^4.4.3"
  },
  "devDependencies": {
    "@types/bun": "^1.3.14",
    "@types/node": "^26.1.1",
    "typescript": "^7.0.2"
  },
  "engines": {
    "bun": ">=1.3.14"
  }
}
```

Si les versions reelles de `zod`/`@types/bun`/`@types/node`/`typescript` installees sur la machine different de celles ci-dessus (verifier avec `cat package.json` avant d'ecraser), conserver les versions reellement installees - ne pas downgrader/upgrader les dependances dans le cadre de ce chantier, seuls `license` et `files` sont des ajouts nets.

- [ ] **Step 2 : Creer `LICENSE`**

Creer `ops-tools/LICENSE` avec le texte MIT standard :

```
MIT License

Copyright (c) 2026 Fadel Diene

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3 : Verifier que `package.json` reste valide et que les champs resolvent correctement**

Depuis `ops-tools/` :
```bash
npm pkg get license files
```
Attendu :
```json
{"license":"MIT","files":["scripts/ops/doctor.ts","tsconfig.json"]}
```

- [ ] **Step 4 : Verifier l'absence de regression sur le tooling existant**

```bash
bun test scripts/ops/doctor.test.ts
bunx tsc --noEmit
```
Attendu : `14 pass, 0 fail` (ou le compte de tests actuel si different - aucune baisse par rapport a l'etat avant ce chantier), et `tsc --noEmit` sans sortie (exit 0). Ces deux commandes ne touchent aucun fichier modifie par cette tache, elles confirment simplement que la modification de `package.json` n'a rien casse par effet de bord (ex. un champ mal forme qui romprait la resolution `bunx`).

- [ ] **Step 5 : Commit**

```bash
cd ops-tools
git add package.json LICENSE
git diff --cached
git commit -m "$(cat <<'EOF'
feat(ops): allowlist files + licence MIT pour publication npm

package.json : ajout license (MIT) et files (allowlist stricte,
scripts/ops/doctor.ts + tsconfig.json uniquement - exclut doctor.ps1
V1 et doctor.test.ts du tarball public). Fichier LICENSE cree, le
README annoncait deja MIT sans fichier ni champ license reels.

Trouve pendant le spike npm pack : sans allowlist, npm retombe sur
.gitignore et embarque roadmap/backlog/topologie VPS dans le tarball.
EOF
)"
```

---

### Task 2 : Documentation (CHANGELOG + README) et verification finale du tarball

**Files:**
- Create: `ops-tools/CHANGELOG.md`
- Modify: `ops-tools/README.md`

**Interfaces:**
- Consumes : `package.json` avec `license`/`files` corrects (Task 1) - la verification finale de cette tache depend du resultat cumule des deux taches.
- Produces : rien consomme par une tache ulterieure (derniere tache du plan).

- [ ] **Step 1 : Creer `CHANGELOG.md`**

Creer `ops-tools/CHANGELOG.md` :

```markdown
# Changelog

Toutes les modifications notables de ce projet sont documentees ici.
Format inspire de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [0.1.0] - 2026-07-28

### Ajoute
- `ops doctor` : preflight check infra/MCP/env/backlogs, port TypeScript (Bun) config-driven via `fadel-os.config.json`.
- Packaging : binaire compile (`bun build --compile`) et package npm `@fdiene/ops-tools`.
```

- [ ] **Step 2 : Ajouter les sections `## ops doctor` et `## Release` dans `README.md`**

Dans `ops-tools/README.md`, localiser ce bloc exact (fin de la section `## Claude Commands`, juste avant `## Security`) :

```markdown
| `/prepush-readme` | Prepare push: update README, check secrets |

---

## Security
```

Le remplacer par :

```markdown
| `/prepush-readme` | Prepare push: update README, check secrets |

---

## ops doctor

Preflight check unique pour l'ecosysteme (infra VPS/Docker, statut MCP, completude .env, avancement backlogs).

### Deux canaux de distribution

| Canal | Usage | Prerequis | Commande |
|---|---|---|---|
| **Binaire compile** | Usage interne quotidien | Aucun (binaire autonome) | `make doctor` |
| **Package npm** | Ecosysteme JS externe | [Bun](https://bun.sh) installe sur la machine | `npm install -g @fdiene/ops-tools` puis `fadel-ops` |

Le canal npm ne remplace pas le binaire compile : le shim genere par npm invoque `bun` directement au runtime (`bun` n'est pas une dependance npm resolue automatiquement). Sans `bun` installe, `fadel-ops` installe via npm ne demarre pas.

### Configuration

Les deux canaux lisent `fadel-os.config.json` a la racine du monorepo cible, localisee via la variable d'environnement `WORKSPACES_ROOT` (repli : `~/git/Workspaces`).

## Release (processus manuel)

1. Mettre a jour `CHANGELOG.md` : nouvelle section `## [X.Y.Z] - AAAA-MM-JJ` avec les changements notables.
2. Mettre a jour `"version"` dans `package.json` (semver manuel : patch/minor/major selon le changement).
3. `npm pack` et inspecter le contenu du tarball genere (voir section Security ci-dessous pour la liste exacte attendue).
4. `git commit` du bump de version + changelog, `git tag vX.Y.Z` (tag local, aucun workflow CI ne s'y declenche).
5. `npm publish --access public`.

---

## Security
```

- [ ] **Step 3 : Verification manuelle de la documentation**

Relire les deux nouvelles sections dans `ops-tools/README.md` : confirmer que rien ne laisse penser que les deux canaux (binaire compile / package npm) sont interchangeables - chacun a un public et un prerequis different, enonces explicitement. Confirmer que la procedure `## Release` est executable telle quelle par quelqu'un qui ne connait pas l'historique de ce chantier (chaque etape nomme un fichier ou une commande precise, pas de renvoi implicite).

- [ ] **Step 4 : Verification finale du tarball (valide le cumul des deux taches)**

Depuis `ops-tools/` :
```bash
npm pack --dry-run
```
Lire attentivement la sortie `npm notice Tarball Contents`. Attendu : **exactement 5 entrees** - `package.json`, `README.md`, `LICENSE`, `scripts/ops/doctor.ts`, `tsconfig.json`. Aucune autre entree (en particulier : ni `meta/`, ni `docs/`, ni `.claude/`, ni `infra/`, ni `doctor.ps1`, ni `doctor.test.ts`, ni `bun.lock`, ni `.env.example`). Si une entree inattendue apparait, c'est un echec de cette tache a diagnostiquer avant de continuer - ne pas commiter en presence d'une fuite de perimetre.

- [ ] **Step 5 : Re-verification du spike d'installation globale (confirme que `files` n'exclut pas `doctor.ts` lui-meme)**

```bash
npm pack
ls *.tgz
npm install -g ./fdiene-ops-tools-0.1.0.tgz
cd /c/Temp 2>/dev/null || mkdir -p /c/Temp && cd /c/Temp
fadel-ops
```
Attendu : execution reussie depuis un repertoire exterieur au repo (findings infra/mcp/env/backlog affiches, pas d'erreur "file not found" ou equivalent), confirmant que l'allowlist stricte n'a pas accidentellement exclu le fichier dont le `bin` a besoin pour fonctionner.

Nettoyer apres verification :
```bash
npm uninstall -g @fdiene/ops-tools
cd c:/Users/delfa/git/Workspaces/ops-tools
rm -f fdiene-ops-tools-*.tgz
git status --short
```
Confirmer que `git status --short` ne montre plus que les fichiers de ce chantier (aucun artefact de test residuel).

- [ ] **Step 6 : Commit**

```bash
cd ops-tools
git add CHANGELOG.md README.md
git diff --cached
git commit -m "$(cat <<'EOF'
docs(ops): CHANGELOG + doc double distribution + release manuelle

CHANGELOG.md cree (format Keep a Changelog, entree 0.1.0). README.md :
nouvelle section ops doctor documentant explicitement les deux
canaux de distribution (binaire compile zero-dependance vs package
npm necessitant bun) et la procedure de release manuelle (bump
version, npm pack de verification, tag local, npm publish).

Verification finale : npm pack --dry-run confirme exactement 5
entrees dans le tarball (package.json, README.md, LICENSE,
scripts/ops/doctor.ts, tsconfig.json). Installation globale simulee
depuis un repertoire externe confirmee fonctionnelle.
EOF
)"
```

---

## Self-Review (effectue par l'auteur du plan avant remise)

**Couverture du spec** : les 4 piliers (allowlist `files`, licence, double distribution documentee, changelog + release manuelle) sont chacun couverts. La publication npm elle-meme (`npm publish --access public`) reste explicitement hors perimetre de ce plan, comme actee dans le spec - aucune tache ne l'execute.

**Coherence** : le contenu de `package.json` (Task 1) et la liste attendue par `npm pack --dry-run` (Task 2, Step 4) correspondent exactement (memes 2 entrees dans `files`, plus les 3 fichiers toujours inclus par npm). La section README `## Release` (Task 2) reference `npm pack` et `npm publish --access public`, coherents avec le Pilier 4 du spec.

**Pas de placeholder** : chaque step contient le contenu exact a ecrire (JSON complet, texte MIT complet, sections Markdown completes) - rien a completer ulterieurement.
