# Publication npm @fdiene/ops-tools : design

Statut : décisions actées avec l'utilisateur le 2026-07-28 (Fractional CTO / Staff Architect, périmètre ops-tools). Fait suite au chantier packaging (`2026-07-27-ops-tools-packaging-design.md`, livré et poussé) et à un spike réel (pas supposé) sur le comportement du shim npm global sous Windows.

## Résultats du spike (fait, pas supposé)

Séquence exécutée : ajout du shebang `#!/usr/bin/env bun` à `scripts/ops/doctor.ts`, `npm pack`, `npm install -g` du tarball généré, exécution de `fadel-ops` depuis `C:\Temp` (répertoire totalement extérieur au repo).

**Résultat positif** : `npm`'s `cmd-shim` lit correctement la ligne shebang et génère un `.cmd` Windows qui invoque `bun` directement (`"%_prog%" "%dp0%\node_modules\@fdiene\ops-tools\scripts\ops\doctor.ts" %*`). Exécution réelle réussie depuis un répertoire externe : 36 findings, aucune erreur. Le shebang est committé (`1e44d4c`), sans régression sur `bun run`/`bun test`/`bun build --compile`.

**Découverte critique (la vraie raison d'être de ce spec)** : en l'absence de `.npmignore` ou de champ `files` dans `package.json`, `npm pack` retombe sur `.gitignore` pour décider quoi inclure - et `.gitignore` n'a jamais été pensé pour filtrer une publication publique. Le tarball généré par le spike contenait **76 fichiers, 97 Ko**, incluant `meta/roadmap-v1.md`, `meta/BACKLOG-META.md` (stratégie produit complète), `infra/vps-prod.env` (topologie VPS), tous les specs/plans `docs/superpowers/`, `.claude/commands/`, `inpi/`. Rien de tout ça n'est un secret au sens gitleaks (déjà audité en amont), mais rien de tout ça n'est destiné à un registre public non plus. C'est ce constat qui motive le pilier 1 ci-dessous.

**Confirmé également** : le shim npm global exige que l'utilisateur final ait `bun` installé sur sa machine (le shim invoque `bun` directement, ce n'est pas une dépendance npm résolue automatiquement). Le binaire compilé (`dist/fadel-ops.exe`, zéro dépendance) et le package npm (source, nécessite `bun`) sont deux canaux de distribution différents, pas un canal qui en remplace un autre - d'où le pilier 2.

## Décisions actées

1. **Sécurité & périmètre** : allowlist stricte via le champ `files` de `package.json`, pas un `.npmignore` (blocklist). Raison actée par l'utilisateur : une allowlist ne fuit jamais par accident si un dossier sensible est ajouté plus tard ; un `.npmignore` doit être mis à jour à chaque ajout, sous peine d'oubli.
2. **Double distribution assumée et documentée** : canal interne (binaire compilé, zéro dépendance) et canal public (package npm, dépendance `bun` requise) coexistent, chacun pour un public différent. Transparence dans le `README.md`, pas de tentative de masquer la contrainte `bun`.
3. **Processus de release KISS** : pas de CI/CD de publication (pas de semantic-release, pas de workflow GitHub Actions déclenché sur tag). Version bump (`0.1.0` → `0.1.1`) et mise à jour de `CHANGELOG.md` faits manuellement avant chaque publication. Cohérent avec le principe déjà appliqué à l'ensemble du chantier packaging : ne jamais automatiser un processus qui n'a pas encore été fait à la main au moins une fois.
4. **Publication manuelle** : `npm publish --access public` lancé manuellement par le développeur, après un `npm pack` de vérification (inspection du contenu du tarball avant publication réelle, pas seulement avant la première fois).

---

## Pilier 1 : Sécurité & périmètre (`files` allowlist)

### Contenu exact du champ `files`

```json
{
  "files": [
    "scripts/ops/doctor.ts",
    "tsconfig.json"
  ]
}
```

Note sur le périmètre exact, un raffinement par rapport à la demande initiale (`scripts/ops/` en tant que dossier) : `scripts/ops/` contient aussi `doctor.ps1` (V1 PowerShell, obsolète pour un consommateur npm qui utilise forcément la V2 TypeScript) et `doctor.test.ts` (fichier de test, jamais nécessaire à l'exécution). Lister le fichier exact `scripts/ops/doctor.ts` plutôt que le dossier entier applique la même logique d'allowlist stricte à l'intérieur même du dossier, pas seulement à la racine du repo - cohérent avec le principe de sécurité déjà validé ("si tu ajoutes un fichier demain, il ne fuira pas par accident").

`package.json` et `README.md` n'ont pas besoin d'être listés explicitement : npm les inclut toujours dans le tarball indépendamment du champ `files` (comportement documenté de npm, avec `LICENSE`/`LICENCE` et le fichier référencé par `main`/`bin`). Les lister quand même serait sans effet, ni positif ni négatif - ce spec ne les ajoute pas au tableau pour éviter de suggérer que leur présence dépend de ce champ.

### Gap connexe découvert en préparant ce spec : absence de licence

`package.json` n'a pas de champ `"license"` et aucun fichier `LICENSE` n'existe dans le repo, alors que le `README.md` affiche déjà "License: MIT" en pied de page. `npm publish` émet un avertissement sans champ `license`, et publier sans fichier `LICENSE` réel sous une licence pourtant annoncée est une incohérence à corriger avant une publication publique réelle - un ajout mineur mais bloquant pour une publication propre, donc inclus dans ce chantier :
- Ajouter `"license": "MIT"` à `package.json`.
- Créer `ops-tools/LICENSE` (texte MIT standard, copyright à l'utilisateur/organisation).

### Vérification

`npm pack --dry-run` (ou `npm pack` réel suivi d'une inspection du tarball, sans publication) doit lister exactement : `scripts/ops/doctor.ts`, `tsconfig.json`, `package.json`, `README.md`, `LICENSE` - rien d'autre. Toute autre entrée dans la sortie `npm notice Tarball Contents` est un signal d'échec de cette tâche.

---

## Pilier 2 : Stratégie de double distribution (documentation README)

### Nouvelle section dans `README.md`

Le `README.md` actuel ne mentionne pas encore `ops doctor` du tout (ni la V1 PowerShell ni la V2 TypeScript) - aucune section dédiée n'existe. Ajouter une section `## ops doctor` (après la section `## Claude Commands`, avant `## Security`) couvrant :

```markdown
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
```

### Vérification

Relecture manuelle : la table ne doit pas laisser croire que les deux canaux sont interchangeables ou que l'un est "meilleur" dans l'absolu - chacun a un public et un prérequis différents, énoncés explicitement.

---

## Pilier 3 : Processus de release (KISS, manuel)

### `CHANGELOG.md`

Créer `ops-tools/CHANGELOG.md` (format [Keep a Changelog](https://keepachangelog.com/), sans outillage de génération automatique) :

```markdown
# Changelog

Toutes les modifications notables de ce projet sont documentees ici.
Format inspire de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [0.1.0] - 2026-07-28

### Ajoute
- `ops doctor` : preflight check infra/MCP/env/backlogs, port TypeScript (Bun) config-driven via `fadel-os.config.json`.
- Packaging : binaire compile (`bun build --compile`) et package npm `@fdiene/ops-tools`.
```

### Procédure manuelle de version bump (documentée, pas automatisée)

Ajouter une section `## Release` dans `README.md`, juste après la nouvelle section `## ops doctor` du Pilier 2 : le README actuel (232 lignes) reste d'une taille raisonnable pour une section de plus, un fichier séparé serait une abstraction prématurée pour ce volume de contenu.

```markdown
## Release (processus manuel)

1. Mettre a jour `CHANGELOG.md` : nouvelle section `## [X.Y.Z] - AAAA-MM-JJ` avec les changements notables.
2. Mettre a jour `"version"` dans `package.json` (semver manuel : patch/minor/major selon le changement).
3. `npm pack` et inspecter le contenu du tarball genere (voir Pilier 1 - Verification).
4. `git commit` du bump de version + changelog, `git tag vX.Y.Z` (tag local, aucun workflow CI ne s'y declenche).
5. `npm publish --access public` (voir Pilier 4).
```

Pas de workflow GitHub Actions déclenché sur push de tag - le tag `vX.Y.Z` reste un marqueur git local/manuel dans cette version du processus, pas un déclencheur d'automatisation.

---

## Pilier 4 : Publication manuelle

### Commande

```bash
cd ops-tools
npm pack                          # verification du contenu avant publication reelle
# inspecter la sortie "Tarball Contents", confirmer qu'elle correspond exactement au Pilier 1
rm fdiene-ops-tools-*.tgz          # nettoyer le tarball de verification, ne pas le committer
npm publish --access public
```

`--access public` est requis pour un package scope (`@fdiene/...`) : sans ce flag, npm tente de publier en privé par défaut pour un scope, ce qui échoue sur un compte npm sans plan payant.

### Pas de publication dans ce chantier

Ce spec prépare la publication (fichiers, documentation, processus) mais n'exécute pas `npm publish` elle-même - cohérent avec la doctrine déjà appliquée à `ops doctor` V1 et V2 ("jamais de publication sans revue finale, jamais de rupture avant preuve"). La première exécution réelle de `npm publish` reste une action manuelle explicite du développeur, hors du périmètre de ce document.

---

## Fichiers impactés

| Fichier | Action |
|---|---|
| `ops-tools/package.json` | Modifier (ajout `files`, `license`) |
| `ops-tools/LICENSE` | Créer (texte MIT) |
| `ops-tools/CHANGELOG.md` | Créer |
| `ops-tools/README.md` | Modifier (section `## ops doctor` avec la table double-canal, section `## Release`) |

---

## Stratégie de test / vérification

Pas de test automatisé applicable (ce chantier touche des métadonnées de packaging et de la documentation, pas de logique métier). Vérification manuelle en trois temps, chacune avec une preuve observable :
1. **Contenu du tarball** : `npm pack --dry-run` (ou `npm pack` + inspection + suppression), sortie comparée exactement à la liste du Pilier 1.
2. **Installation globale simulée** : reproduire le spike (`npm pack`, `npm install -g` du tarball, exécution depuis un répertoire externe), confirmer que `fadel-ops` fonctionne toujours après l'ajout du champ `files` (le champ `files` ne doit pas exclure par erreur `scripts/ops/doctor.ts` lui-même).
3. **Lisibilité de la documentation** : relecture humaine de la nouvelle section README - la frontière entre les deux canaux doit être compréhensible sans connaître l'historique de ce spec.

---

## Hors périmètre

- `npm publish` réel n'est pas exécuté dans ce chantier (décision actée, action manuelle future explicite).
- Pas de CI/CD de publication (pas de semantic-release, pas de workflow GitHub Actions sur tag) - décision actée, KISS.
- Pas de retrait de `doctor.ps1` (V1) - reste hors périmètre de tous les chantiers ops doctor jusqu'à nouvelle décision explicite.
- Pas de renseignement de `links.repo` dans `master_data` (Profile Engine) tant que le badge `ops-tools` n'est pas passé à `live` sur la base d'un usage réel publié - décision différée, hors périmètre technique de ce spec.
