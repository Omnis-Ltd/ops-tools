#!/usr/bin/env bash
# =============================================================================
# update-prod-2026-07-03-resume.sh
# Reprise après échec backup Directus — repart de l'étape 1b
# Backup n8n DB déjà OK : /opt/backups/2026-07-03/n8n-postgres-20260703_184806.sql.gz
# =============================================================================

set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
BACKUP_DIR="/opt/backups/$(date +%Y-%m-%d)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# =============================================================================
# ÉTAPE 1b — Backup Directus (user corrigé : seouser)
# =============================================================================
echo "=== [1b/5] Backup Directus PostgreSQL ==="
docker exec prod-seo-postgres pg_dump -U seouser directus \
  | gzip > "$BACKUP_DIR/directus-postgres-$TIMESTAMP.sql.gz"
echo "✅ Backup Directus DB : $BACKUP_DIR/directus-postgres-$TIMESTAMP.sql.gz"
ls -lh "$BACKUP_DIR/"

# =============================================================================
# ÉTAPE 2 — Qdrant v1.17.0 → v1.18.2
# =============================================================================
echo ""
echo "=== [2/5] Mise à jour Qdrant ==="
docker compose -f "$COMPOSE_FILE" pull seo-qdrant
docker compose -f "$COMPOSE_FILE" up -d seo-qdrant
sleep 10
docker compose -f "$COMPOSE_FILE" ps seo-qdrant
echo "✅ Qdrant mis à jour"

# =============================================================================
# ÉTAPE 3 — Directus 11.16.1 → 11.17.4
# =============================================================================
echo ""
echo "=== [3/5] Mise à jour Directus ==="
docker compose -f "$COMPOSE_FILE" pull seo-directus
docker compose -f "$COMPOSE_FILE" up -d seo-directus

echo "Attente démarrage Directus..."
sleep 30
for i in {1..10}; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' prod-seo-directus 2>/dev/null || echo "unknown")
  echo "  Health: $STATUS ($i/10)"
  if [ "$STATUS" = "healthy" ]; then break; fi
  sleep 10
done
echo "✅ Directus mis à jour"

# =============================================================================
# ÉTAPE 4 — n8n 2.12.3 → 2.28.6 (migrations DB auto)
# =============================================================================
echo ""
echo "=== [4/5] Mise à jour n8n ==="
docker compose -f "$COMPOSE_FILE" pull n8n
docker compose -f "$COMPOSE_FILE" stop n8n
docker compose -f "$COMPOSE_FILE" up -d n8n

echo "Attente n8n + migrations (saut 2.12→2.28)..."
sleep 60
for i in {1..15}; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' prod-n8n 2>/dev/null || echo "unknown")
  echo "  Health n8n: $STATUS ($i/15)"
  if [ "$STATUS" = "healthy" ]; then break; fi
  sleep 15
done

echo "Derniers logs n8n :"
docker logs prod-n8n --tail 15 2>&1

echo "✅ n8n mis à jour"

# =============================================================================
# ÉTAPE 5 — Vérification finale
# =============================================================================
echo ""
echo "=== [5/5] État final ==="
docker compose -f "$COMPOSE_FILE" ps

echo ""
docker exec prod-n8n n8n --version 2>/dev/null && echo "(n8n attendu: 2.28.6)"
docker exec prod-seo-directus node -e "const p=require('/directus/package.json'); console.log('Directus', p.version)" 2>/dev/null

echo ""
echo "=== Terminé ==="
echo "Rollback n8n si besoin :"
echo "  gunzip -c $BACKUP_DIR/n8n-postgres-*.sql.gz | docker exec -i prod-n8n-postgres psql -U n8n n8n"
