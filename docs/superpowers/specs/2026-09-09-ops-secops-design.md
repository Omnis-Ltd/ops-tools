# ops secops : design

Statut : décisions actées avec l'utilisateur le 2026-09-09 (Fractional CTO / Staff Architect, périmètre ops-tools). Deuxième script autonome après `ops doctor` (V1 PowerShell + V2 TypeScript/Bun, livrées et publiées sur npm `@fdiene/ops-tools@0.1.0`). Fait suite à un brainstorming qui a d'abord tranché une question d'architecture partagée avec un futur `ops deploy` (voir "Décisions actées").

## Contexte vérifié avant rédaction (pas supposé)

Exploration réelle du VPS `seo-prod` (même hôte que `infra.sshHost` dans `fadel-os.config.json`, déjà surveillé par `doctor`) :

- **fail2ban absent** : `which fail2ban-client` ne retourne rien, aucun jail actif. Ce constat a directement écarté un scope initial ("vérifier le statut fail2ban") au profit d'un scope plus large ("détecter les échecs SSH indépendamment de fail2ban").
- **Ports publics ouverts** : `ss -tln` montre exactement `22`, `80`, `443` en IPv4 et IPv6 (plus des binds loopback-only sans intérêt sécurité : `127.0.0.53`/`127.0.0.54` DNS interne, `127.0.0.1:6010` X11 forwarding d'une session SSH). Base saine et cohérente avec un VPS Traefik + SSH.
- **0 échec SSH sur les dernières 24h** (`journalctl -u ssh --since '24 hours ago' | grep -c 'Failed password\|Invalid user'`). Confirme qu'on n'a aucune donnée historique pour calibrer un seuil "normal vs inquiétant" - décision actée plus bas : ne pas inventer de seuil.
- **Accès SSH en root** (confirmé par les logs `journalctl`, `session opened for user root(uid=0) by root(uid=0)`) : aucune élévation de privilège nécessaire pour lire les logs d'auth ou l'état fail2ban.
- **`acme.json` (certificats Traefik) accessible** à deux emplacements (`/var/lib/docker/volumes/prod-acme-data/_data/acme.json`, `/opt/seo-empire/acme.json`) : techniquement faisable pour une future vérification d'expiration TLS, mais explicitement hors périmètre V1 (voir plus bas).

## Décisions actées

1. **Pas de squelette CLI commander.js maintenant.** Avec `secops` et un futur `ops deploy` qui arrivent, la question s'est posée de construire `ops run|repo|setup|doctor|secops|deploy` tout de suite plutôt que d'empiler des scripts. Décision : non - cohérent avec la doctrine anti-scope-creep déjà appliquée à `doctor.ts` ("le squelette CLI complet reste un chantier ultérieur distinct, à faire quand les autres commandes existeront réellement"). `secops` reste un script autonome de plus.
2. **Pas de module partagé entre `doctor.ts` et `secops.ts`.** Même moteur de findings (Finding/addFinding/toShellPath/génération de rapport) dupliqué dans les deux fichiers, comme `doctor.ts` l'a fait pour la V1. Une abstraction à 2 scripts est prématurée ; extraire un module commun seulement si un 3ᵉ script confirme le besoin.
3. **Lecture seule, comme `doctor`.** Aucune action corrective (installer fail2ban, bannir une IP, fermer un port) dans ce chantier. Cohérent avec la doctrine déjà établie ailleurs dans l'écosystème ("jamais d'action destructive sans confirmation humaine explicite") et avec le fait que `doctor` lui-même n'écrit jamais rien sur le parc surveillé.
4. **Périmètre V1 : 3 sections, pas 4.** TLS/expiration certificats exclu de la V1 (complexité réelle de parsing de la structure JSON interne de Traefik, pas un blocage technique - `acme.json` est accessible, juste reporté).
5. **`secops.ts` réutilise `infra.sshHost` du manifeste existant**, ne redéclare pas de champ `secops.sshHost` séparé - évite une valeur dupliquée qui pourrait diverger de celle que `doctor` utilise déjà pour le même VPS.
6. **Aucun seuil numérique inventé pour les échecs SSH.** Faute de données historiques (0 échec sur 24h au moment de l'audit), le chiffre réel est affiché sans jugement de sévérité forte (voir Section 2).

---

## Pilier 1 : Section fail2ban

Commande : `fail2ban-client status` via SSH natif (même pattern que `checkInfra`/`checkMcp` de `doctor.ts` : chemin `C:/Windows/System32/OpenSSH/ssh.exe` en slashs, jamais de backslash interpolé dans un template `Bun.$`).

Logique :
- Commande échoue (binaire absent, ou service inactif) → **WARN** "fail2ban absent ou inactif sur `<sshHost>`" (pas FAIL : c'est un manque de durcissement, pas une panne active - le VPS peut très bien tourner sans, comme c'est le cas aujourd'hui).
- Commande réussit → parser la ligne `Jail list:` de la sortie, **PASS** "fail2ban actif (`N` jail(s) : `liste`)".

## Pilier 2 : Section échecs SSH récents

Commande : `journalctl -u ssh --since '24 hours ago' --no-pager | grep -c 'Failed password\|Invalid user'` via SSH.

**Piège technique déjà rencontré dans ce projet, à respecter ici aussi** : `grep -c` retourne le code de sortie 1 quand le compte est 0 (convention grep : "aucune correspondance trouvée"), même si `-c` affiche bien `0` sur stdout. Combiné à `Bun.$` qui lève une exception sur un code de sortie non nul (comportement déjà documenté dans `doctor.ts`, section MCP, pour l'appel `git log`), un compte de 0 échec **lèverait une exception** si le code ne la gère pas explicitement. Le `try/catch` autour de cet appel doit distinguer "grep n'a rien trouvé" (compte = 0, cas normal) d'un vrai échec de connexion SSH (traité comme la section Infra de `doctor.ts` : un seul finding `FAIL`, section interrompue).

Logique :
- SSH injoignable → **FAIL** "VPS `<sshHost>` injoignable", section interrompue (même comportement que `checkInfra`).
- SSH joignable, `grep` échoue avec code 1 (pas de correspondance) → compte = 0, **PASS** "0 échec SSH sur les dernières 24h".
- SSH joignable, `grep` réussit avec un compte > 0 → **WARN** "`N` échec(s) SSH sur les dernières 24h" (pas de FAIL : sans historique pour calibrer, on ne sait pas distinguer un bruit de fond normal d'une vraie attaque - le chiffre est affiché, la décision reste humaine).

## Pilier 3 : Section ports exposés

Commande : `ss -tln` via SSH.

Fonction pure `parseListeningPorts(ssOutput: string): number[]` (testable via `bun test`, même philosophie que `parseChecklist`/`parseBacklogTable` de `doctor.ts` - séparer le parsing de l'I/O) : extrait les ports des lignes dont l'adresse locale est un bind public (`0.0.0.0:PORT` ou `[::]:PORT`), ignore explicitement les binds loopback-only (`127.x.x.x:PORT`, `[::1]:PORT`) qui ne sont jamais atteignables depuis l'extérieur.

Nouvelle clé de manifeste `secops.expectedPorts` (dans `fadel-os.config.json`) :
```json
"secops": {
  "expectedPorts": [22, 80, 443]
}
```

Logique de comparaison (fonction pure `comparePortLists`, testable indépendamment) :
- port réellement ouvert absent de `expectedPorts` → **WARN** "port inattendu ouvert : `PORT`".
- port de `expectedPorts` non trouvé ouvert → **WARN** "port attendu absent : `PORT`" (défense en profondeur : un service qui tombe, même si `doctor` a sa propre vue sur les conteneurs, n'est pas exactement la même question ici - une port scan externe est le point de vue de l'attaquant, pas celui de Docker).
- tout correspond → **PASS** "ports conformes (`22, 80, 443`)".

## Fichiers impactés

| Fichier | Action |
|---|---|
| `ops-tools/scripts/ops/secops.ts` | Créer |
| `ops-tools/scripts/ops/secops.test.ts` | Créer (tests sur `parseListeningPorts` et `comparePortLists`, fonctions pures) |
| `fadel-os.config.json` (racine du monorepo, hors repo git `ops-tools/`) | Modifier (ajout de la clé `secops.expectedPorts`) |
| `ops-tools/Makefile` | Modifier (nouveau target `secops`, miroir de `doctor`) |
| `ops-tools/package.json` | Modifier (script `"secops": "bun scripts/ops/secops.ts"`, éventuellement `"build:secops"` si un binaire compilé séparé est voulu - à trancher à l'implémentation, pas structurant pour ce spec) |

## Stratégie de test

Même philosophie que `doctor.ts` : `bun test` uniquement sur les fonctions pures (`parseListeningPorts`, `comparePortLists`), aucun mock pour SSH/journalctl/fail2ban - ces checks restent vérifiés manuellement contre le VPS réel, avec preuve dans un rapport de tâche, pas une suite automatisée dessus.

Cas de test à couvrir pour `parseListeningPorts` : ports IPv4 et IPv6 publics extraits, binds loopback-only ignorés, sortie vide gérée sans erreur.

Cas de test à couvrir pour `comparePortLists` : port inattendu détecté, port attendu manquant détecté, correspondance parfaite (aucun finding warn), les deux problèmes simultanés.

## Hors périmètre (V1)

- Expiration des certificats TLS (`acme.json` accessible, parsing reporté).
- Toute action corrective (installation/configuration fail2ban, bannissement d'IP, fermeture de port).
- Seuil de sévérité calibré sur les échecs SSH (pas de données historiques pour le justifier aujourd'hui).
- Squelette CLI commander.js unifiant `doctor`/`secops`/`deploy` - décision actée séparément, reste un chantier ultérieur distinct.
- Module de code partagé entre `doctor.ts` et `secops.ts` - à réévaluer si un 3ᵉ script confirme le besoin.
