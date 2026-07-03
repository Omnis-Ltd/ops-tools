# Runbook — Maintenance infra SEOmnix prod

## Topologie VPS

| Alias SSH  | IP              | Path déploiement    |
|------------|-----------------|---------------------|
| `seo-prod` | 178.16.130.102  | `/opt/seo-empire/`  |

Clé SSH : `~/.ssh/omnis.key` (RSA, passphrase requise)
Agent SSH Windows : `Start-Service ssh-agent` puis `ssh-add ~/.ssh/omnis.key`

## Containers et credentials DB

| Container | Service | DB host | DB user | DB name |
|---|---|---|---|---|
| `prod-n8n` | n8n | `prod-n8n-postgres` | `n8n` | `n8n` |
| `prod-seo-directus` | Directus | `prod-seo-postgres` | `seouser` | `seo_empire` |
| `prod-seo-qdrant` | Qdrant | — | — | — |
| `prod-seo-redis` | Redis | — | — | — |
| `prod-traefik` | Traefik | — | — | — |
| `prod-seo-agents` | FastAPI agents | — | — | — |

## Process de mise à jour (mensuel)

### Étape 1 — Audit local

```powershell
.\ops-tools\infra\audit-images.ps1
# Avec pull des nouvelles images :
.\ops-tools\infra\audit-images.ps1 -Pull
```

### Étape 2 — Mettre à jour les compose files

Modifier les tags dans :
- `AI_agents/seomnix/n8n-projects/n8n-core/docker-compose.yml`
- `Infra/infra-local/docker-compose.seo.yml`
- `Infra/infra-prod/docker-compose.yml`

### Étape 3 — Envoyer le compose prod sur le VPS

```powershell
scp Infra\infra-prod\docker-compose.yml seo-prod:/opt/seo-empire/docker-compose.yml
```

### Étape 4 — Lancer la mise à jour prod

```powershell
# Option A : passer le script via stdin (pas de scp nécessaire)
ssh seo-prod "bash -s" < ops-tools\infra\update-prod.sh

# Option B : copier puis exécuter
scp ops-tools\infra\update-prod.sh seo-prod:/tmp/
ssh seo-prod "bash /tmp/update-prod.sh"
```

### Étape 5 — Vérifier et committer

```powershell
# Vérifier l'UI n8n
# https://n8n.seomnix.com

# Committer les compose files mis à jour
git -C AI_agents\seomnix\n8n-projects\n8n-core commit -am "chore: pin n8n X.Y.Z"
git -C Infra\infra-local commit -am "chore: pin directus/qdrant versions"
git -C Infra\infra-prod commit -am "chore: pin all versions YYYY-MM-DD"
```

## Rollback n8n

```bash
# Sur le VPS
gunzip -c /opt/backups/<date>/n8n-<timestamp>.sql.gz \
  | docker exec -i prod-n8n-postgres psql -U n8n n8n

docker compose -f /opt/seo-empire/docker-compose.yml up -d n8n
```

## Ordre de mise à jour impératif

```
1. Backup PostgreSQL (n8n + Directus/seo_empire)
2. Qdrant     ← sans état critique, safe
3. Directus   ← migrations auto, attendre healthy
4. n8n        ← le plus critique (migrations DB, stop/start)
```

⚠️ Ne jamais mettre à jour n8n sans backup préalable — les migrations DB sont irréversibles.

## Traefik prod (v2.11 → v3.x)

Migration à planifier séparément — breaking changes sur les labels Docker et middlewares.
Test en local obligatoire avant prod.
Voir : https://doc.traefik.io/traefik/migration/v2-to-v3/

## Historique des mises à jour

| Date | n8n | Directus | Qdrant | Notes |
|---|---|---|---|---|
| 2026-07-03 | 2.12.3 → 2.28.6 | 11.16.1 → 11.17.4 | v1.17.0 → v1.18.2 | Première session infra-as-code |
