#!/usr/bin/env bash
# =============================================================================
# update-prod-2026-07-03.sh
# Mise à jour composants prod — n8n 2.12.3→2.28.6, Directus 11.16.1→11.17.4, Qdrant v1.17.0→v1.18.2
#
# PRÉREQUIS : exécuter depuis le dossier de déploiement sur le VPS
#   cd /opt/seo-empire   (ou chemin du docker-compose prod)
#
# ORDRE : 1) backup DB  2) Qdrant  3) Directus  4) n8n (migrations auto)
# =============================================================================

set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
BACKUP_DIR="/opt/backups/$(date +%Y-%m-%d)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# =============================================================================
# ÉTAPE 0 — Vérifications
# =============================================================================
echo "=== [0/5] Vérification de l'état actuel ==="
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "Versions actuelles dans les containers :"
docker exec prod-n8n n8n --version 2>/dev/null && echo "(n8n)" || echo "n8n non démarré"
docker exec prod-seo-directus node -e "const p=require('/directus/package.json'); console.log('Directus', p.version)" 2>/dev/null || echo "directus non démarré"

# =============================================================================
# ÉTAPE 1 — Backup PostgreSQL (OBLIGATOIRE avant n8n 2.12→2.28)
# =============================================================================
echo ""
echo "=== [1/5] Backup PostgreSQL ==="
mkdir -p "$BACKUP_DIR"

# Backup base n8n
docker exec prod-n8n-postgres pg_dump -U n8n n8n \
  | gzip > "$BACKUP_DIR/n8n-postgres-$TIMESTAMP.sql.gz"
echo "✅ Backup n8n DB : $BACKUP_DIR/n8n-postgres-$TIMESTAMP.sql.gz"

# Backup base Directus (SEO)
docker exec prod-seo-postgres pg_dump -U "${SEO_POSTGRES_USER:-seo}" "${SEO_POSTGRES_DB:-directus}" \
  | gzip > "$BACKUP_DIR/directus-postgres-$TIMESTAMP.sql.gz"
echo "✅ Backup Directus DB : $BACKUP_DIR/directus-postgres-$TIMESTAMP.sql.gz"

ls -lh "$BACKUP_DIR/"

# =============================================================================
# ÉTAPE 2 — Mise à jour Qdrant (v1.17.0 → v1.18.2, sans migration DB)
# =============================================================================
echo ""
echo "=== [2/5] Mise à jour Qdrant v1.17.0 → v1.18.2 ==="
docker compose -f "$COMPOSE_FILE" pull seo-qdrant
docker compose -f "$COMPOSE_FILE" up -d seo-qdrant
sleep 10
docker compose -f "$COMPOSE_FILE" ps seo-qdrant
echo "✅ Qdrant mis à jour"

# =============================================================================
# ÉTAPE 3 — Mise à jour Directus (11.16.1 → 11.17.4, migrations auto)
# =============================================================================
echo ""
echo "=== [3/5] Mise à jour Directus 11.16.1 → 11.17.4 ==="
docker compose -f "$COMPOSE_FILE" pull seo-directus
docker compose -f "$COMPOSE_FILE" up -d seo-directus

echo "Attente démarrage Directus (migrations auto)..."
sleep 30

# Vérifier healthcheck
for i in {1..10}; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' prod-seo-directus 2>/dev/null || echo "unknown")
  echo "  Health Directus: $STATUS (tentative $i/10)"
  if [ "$STATUS" = "healthy" ]; then break; fi
  sleep 10
done
echo "✅ Directus mis à jour"

# =============================================================================
# ÉTAPE 4 — Mise à jour n8n (2.12.3 → 2.28.6, migrations DB auto)
# =============================================================================
echo ""
echo "=== [4/5] Mise à jour n8n 2.12.3 → 2.28.6 ==="
echo "⚠️  Saut de 16 versions — migrations DB automatiques au démarrage"

docker compose -f "$COMPOSE_FILE" pull n8n
docker compose -f "$COMPOSE_FILE" stop n8n
docker compose -f "$COMPOSE_FILE" up -d n8n

echo "Attente démarrage n8n + migrations..."
sleep 45

# Vérifier que n8n démarre correctement
for i in {1..15}; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' prod-n8n 2>/dev/null || echo "unknown")
  echo "  Health n8n: $STATUS (tentative $i/15)"
  if [ "$STATUS" = "healthy" ]; then break; fi
  sleep 15
done

# Afficher les derniers logs pour confirmer les migrations
echo ""
echo "Derniers logs n8n (migrations) :"
docker logs prod-n8n --tail 20 2>&1

echo "✅ n8n mis à jour"

# =============================================================================
# ÉTAPE 5 — Vérification finale
# =============================================================================
echo ""
echo "=== [5/5] État final ==="
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "Versions déployées :"
docker exec prod-n8n n8n --version 2>/dev/null && echo "(n8n attendu: 2.28.6)"
docker exec prod-seo-directus node -e "const p=require('/directus/package.json'); console.log('Directus', p.version, '(attendu: 11.17.4)')" 2>/dev/null
docker exec prod-seo-qdrant ./qdrant --version 2>/dev/null || true

echo ""
echo "=== Mise à jour terminée ==="
echo "En cas de problème, restaurer n8n DB :"
echo "  gunzip -c $BACKUP_DIR/n8n-postgres-$TIMESTAMP.sql.gz | docker exec -i prod-n8n-postgres psql -U n8n n8n"
