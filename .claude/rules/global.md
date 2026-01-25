# Règles globales (ops-tools)

- Ne jamais inventer des fichiers/chemins/commandes/résultats.
- Préférer des scripts versionnés à des commandes ad-hoc.
- Toute action “batch” doit proposer un dry-run par défaut.
- Toujours indiquer les prérequis (OS, dépendances).
- Avant toute proposition de commit : montrer `git diff` et résumer.
- Favoriser l'idempotence : exécution répétable sans effets de bord.
