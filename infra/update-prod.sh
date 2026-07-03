#!/usr/bin/env bash
# =============================================================================
# update-prod.sh — Mise a jour services prod SEOmnix
# A executer sur le VPS : ssh seo-prod "cd /opt/seo-empire && bash /tmp/update-prod.sh"
# Ou depuis local  : ssh seo-prod "bash -s" < ops-tools/infra/update-prod.sh
#
# Ordre imperatif : backup → Qdrant → Directus → n8n
# Topologie documentee dans ops-tools/infra/vps-prod.env
# =============================================================================

set -euo pipefail

DEPLOY_PATH="/opt/seo-empire"
COMPOSE_FILE="$DEPLOY_PATH/docker-compose.yml"
BACKUP_DIR="/opt/backups/$(date +%Y-%m-%d)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Containers
N8N_POSTGRES_CONTAINER="prod-n8n-postgres"
N8N_POSTGRES_USER="n8n"
N8N_POSTGRES_DB="n8n"
SEO_POSTGRES_CONTAINER="prod-seo-postgres"
SEO_POSTGRES_USER="seouser"
SEO_POSTGRES_DB="seo_empire"

cd "$DEPLOY_PATH"
mkdir -p "$BACKUP_DIR"

# =============================================================================
# [0] Etat actuel
# =============================================================================
echo "=== [0] Etat actuel ==="
docker compose -f "$COMPOSE_FILE" ps
echo ""
echo "n8n     : $(docker exec prod-n8n n8n --version 2>/dev/null || echo 'non demarre')"
echo "directus: $(docker exec prod-seo-directus node -e "console.log(require('/directus/package.json').version)" 2>/dev/null || echo 'non demarre')"

# =============================================================================
# [1] Backup PostgreSQL
# =============================================================================
echo ""
echo "=== [1] Backup PostgreSQL ==="

docker exec "$N8N_POSTGRES_CONTAINER" pg_dump -U "$N8N_POSTGRES_USER" "$N8N_POSTGRES_DB" \
  | gzip > "$BACKUP_DIR/n8n-$TIMESTAMP.sql.gz"
echo "  ✅ n8n      : $BACKUP_DIR/n8n-$TIMESTAMP.sql.gz ($(du -sh $BACKUP_DIR/n8n-$TIMESTAMP.sql.gz | cut -f1))"

docker exec "$SEO_POSTGRES_CONTAINER" pg_dump -U "$SEO_POSTGRES_USER" "$SEO_POSTGRES_DB" \
  | gzip > "$BACKUP_DIR/directus-$TIMESTAMP.sql.gz"
echo "  ✅ directus : $BACKUP_DIR/directus-$TIMESTAMP.sql.gz ($(du -sh $BACKUP_DIR/directus-$TIMESTAMP.sql.gz | cut -f1))"

# =============================================================================
# [2] Qdrant
# =============================================================================
echo ""
echo "=== [2] Mise a jour Qdrant ==="
docker compose -f "$COMPOSE_FILE" pull seo-qdrant
docker compose -f "$COMPOSE_FILE" up -d seo-qdrant
sleep 10
docker compose -f "$COMPOSE_FILE" ps seo-qdrant
echo "  ✅ Qdrant mis a jour"

# =============================================================================
# [3] Directus (migrations auto)
# =============================================================================
echo ""
echo "=== [3] Mise a jour Directus ==="
docker compose -f "$COMPOSE_FILE" pull seo-directus
docker compose -f "$COMPOSE_FILE" up -d seo-directus

echo "  Attente migrations Directus..."
for i in $(seq 1 12); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' prod-seo-directus 2>/dev/null || echo "unknown")
  echo "    health: $STATUS ($i/12)"
  [ "$STATUS" = "healthy" ] && break
  sleep 10
done
echo "  ✅ Directus mis a jour"

# =============================================================================
# [4] n8n (migrations DB auto — le plus critique)
# =============================================================================
echo ""
echo "=== [4] Mise a jour n8n ==="
docker compose -f "$COMPOSE_FILE" pull n8n
docker compose -f "$COMPOSE_FILE" stop n8n
docker compose -f "$COMPOSE_FILE" up -d n8n

echo "  Attente migrations n8n..."
for i in $(seq 1 18); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' prod-n8n 2>/dev/null || echo "unknown")
  echo "    health: $STATUS ($i/18)"
  [ "$STATUS" = "healthy" ] && break
  sleep 10
done

echo "  Logs n8n (derniers 10) :"
docker logs prod-n8n --tail 10 2>&1 | sed 's/^/    /'
echo "  ✅ n8n mis a jour"

# =============================================================================
# [5] Verification finale
# =============================================================================
echo ""
echo "=== [5] Verification finale ==="
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "  n8n     : $(docker exec prod-n8n n8n --version 2>/dev/null)"
echo "  directus: $(docker exec prod-seo-directus node -e "console.log(require('/directus/package.json').version)" 2>/dev/null)"
echo ""
echo "=== Mise a jour terminee ==="
echo ""
echo "Rollback n8n si besoin :"
echo "  gunzip -c $BACKUP_DIR/n8n-$TIMESTAMP.sql.gz | docker exec -i $N8N_POSTGRES_CONTAINER psql -U $N8N_POSTGRES_USER $N8N_POSTGRES_DB"
echo "Rollback directus si besoin :"
echo "  gunzip -c $BACKUP_DIR/directus-$TIMESTAMP.sql.gz | docker exec -i $SEO_POSTGRES_CONTAINER psql -U $SEO_POSTGRES_USER $SEO_POSTGRES_DB"
