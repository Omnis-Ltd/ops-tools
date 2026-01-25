# maintenance-normalize-eol

Normalise les fins de ligne (LF) dans tous les repositories Git sous ~/git/Workspaces
en utilisant un script batch sécurisé (dry-run par défaut).

## Objectif
- Éviter les diffs parasites CRLF/LF
- Garantir la cohérence multi-OS
- Appliquer un standard reproductible (.gitattributes + .editorconfig)

## Préconditions
- Les repos sont sous ~/git/Workspaces
- Le script normalize-eol-batch.sh est présent et exécutable
- Aucun repo critique n’est modifié sans validation

## Étapes
1) Lancer un dry-run pour inspecter les changements potentiels
2) Si le résultat est conforme, appliquer les règles
3) Renormaliser les fichiers texte
4) Committer uniquement les repos propres (non dirty)

## Commandes
- bash: ./normalize-eol-batch.sh --dry-run
- bash: ./normalize-eol-batch.sh --apply --renormalize --commit --skip-dirty

## Vérifications
- Aucun repo dirty modifié
- Les commits sont limités aux changements EOL
- Message de commit standardisé
