# Changelog

Toutes les évolutions notables du **moteur canonique RELAY** sont documentées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et le projet respecte le [Semantic Versioning](https://semver.org/lang/fr/).

Ce fichier est la **source unique** de la « description des améliorations » affichée par
`relay-update.sh --check` quand un projet consommateur est en retard sur le canonique.
Chaque bump de `VERSION` doit ajouter une entrée ici (étape de clôture — `RELAY_PROTOCOL.md §6`).

## [Non publié]

## [1.10.0] — 2026-06-19

### Added
- **Security Surface Trigger** — rôle « Spécialiste cybersécurité », **Couche 2** (ancrage sécu sélectif,
  `SEC-2`). `relay-check.sh` (§9b) lit une 3ᵉ section `rules.conf` `[security_surface]` : des **marqueurs**
  de surface sensible (authN, authZ/IDOR, secrets, crypto, + per-stack commentés — **pas** des dangers).
  Touchés dans le diff stagé → **un avertissement signal-only** « ancrer `SECURITY_RULES.md` ». C'est le
  déclencheur **déterministe** qui rend l'ancrage sécu **sélectif** : la checklist n'est chargée **que** si
  une surface est touchée → **token-négatif** (`VISION.md §4`), jamais en permanence. Réutilise le grep de
  la Couche 1 (`parse_security_section`).
- **`templates/docs/rules/SECURITY_RULES.md`** — checklist d'ancrage (5 axes : authN / authZ-IDOR /
  validation / secrets / moindre-privilège + exemples per-stack .NET/Flutter/JS/Python + section
  `Patterns appris` réservée à la Couche 4 `SEC-4`). Fichier d'**instance** (propriété du projet).
- `relay-init.sh` — `render` de `SECURITY_RULES.md` au bootstrap.
- `relay-update.sh` (§2f, migration v1.10.0) — **seede** la section `[security_surface]` **et** dépose
  `SECURITY_RULES.md` dans les projets existants si absents (miroir des migrations §2b→§2e). Idempotent.
- `RELAY_PROTOCOL.md §4b` — formalise l'ancrage sécu sélectif (sélectif = token-négatif ; WARNING, pas
  bloquant car détection heuristique ; le gate dur reste la Couche 1).
- `.github/workflows/ci.yml` (canonique) — le smoke-test vérifie que `relay-init` dépose `SECURITY_RULES.md`
  et seede la section `[security_surface]` dans `rules.conf`.

### Lucidité
- Couche 2 reste un **gate commit/CI**, **pas** un IDS/WAF runtime — ne remplace pas un pentest. WARNING
  signal-only (heuristique → guide, ne gate pas). Le verdict reste humain.

## [1.9.0] — 2026-06-19

### Added
- **Workflow CI RELAY** (`templates/.github/workflows/relay-ci.yml`) — rôle « Spécialiste cybersécurité »,
  **Couche 3** (outillage CI, `SEC-3`). Gate déposé dans chaque projet : `relay-check --strict` (verdict
  **structure/protocole** mécanique) + **gitleaks** (verdict **outil** sur les secrets, scan PR + historique,
  0 token LLM). Division honnête : le Security Shield (§9) scanne le diff **stagé** → il vit au commit (hook
  pre-commit local), pas en CI ; la CI ajoute le scan secrets sur tout le dépôt. **Lucidité** : gate CI, **pas**
  un IDS/WAF runtime — ne remplace pas un pentest.
- `relay-init.sh` — dépose `.github/workflows/relay-ci.yml` au bootstrap (copie-si-absente ; fichier
  d'**instance**, jamais écrasé). Pas via `render()` : le YAML GitHub Actions contient `${{ }}`.
- `relay-update.sh` (§2e, migration v1.9.0) — **seede le workflow dans les projets existants** s'il est
  absent (miroir des migrations §2b/§2c/§2d). Idempotent : un workflow déjà présent reste intact. Sans ce
  seeding, seuls les **nouveaux** projets auraient eu la CI.
- `.github/workflows/ci.yml` (repo canonique) — le smoke-test vérifie désormais que `relay-init` dépose le
  workflow, que c'est un **YAML valide**, et qu'il invoque bien `relay-check --strict` + `gitleaks`.

## [1.8.1] — 2026-06-19

### Added
- `relay-update.sh` (§2d, migration v1.8.0) — **seeding des sections sécu dans les `rules.conf` existants**
  (`SEC-1b`). Un projet initialisé **avant** v1.8.0 n'avait pas `[security_forbidden]`/`[security_warn]` ;
  à la prochaine mise à jour, ces sections sont **ajoutées** (patterns universels actifs + per-stack
  commentés), idempotent au niveau section (si déjà présentes → intactes, données d'instance). Sans ce
  seeding, le Security Shield ne touchait que les **nouveaux** projets. Miroir exact des migrations
  v1.3.0 (`[forbidden_patterns]`) et v1.4.0 (`[design_warn_*]`).

## [1.8.0] — 2026-06-19

### Added
- **Security Shield** (`relay-check.sh` §9, piloté par `rules.conf`) — rôle « Spécialiste cybersécurité »,
  Couche 1 (gate déterministe). Scanne le diff stagé (code **et** config) contre deux sections d'instance :
  `[security_forbidden]` (sévérité **ERREUR** → bloque le commit) et `[security_warn]` (WARNING). Format
  `<regex> | msg=<remédiation> | exclude=<regex contenu> | exclude-path=<fragment>`. **0 token LLM** : pur
  `grep` déterministe — fait le travail que le LLM ferait en lisant (token-négatif, `VISION.md §4`).
- `templates/docs/.relay/rules.conf` — sections `[security_forbidden]`/`[security_warn]` seedées :
  **patterns universels actifs** (clé privée en clair, clé AWS `AKIA…`, hash faible MD5/SHA1, secret en clair,
  identifiant en query string = risque IDOR) + **exemples per-stack commentés** (.NET/Python/Go/Node/React).
  Le moteur ne fournit que le **mécanisme** ; les patterns vivent dans l'instance (« moteur = 0 donnée projet »).
- `docs/SECURITY-ROLE-PLAN.md` — cadrage des 4 couches du rôle (gate déterministe · ancrage sélectif · CI
  outillée · `SECURITY_RULES.md` auto-alimenté) + test tokens par couche + séquencement + découpage `TASK[SEC-*]`.

### Notes
- **Lucidité** : gate commit/CI, **pas** un IDS/WAF runtime — ne remplace pas un pentest.
- Section sécu absente/vide → Shield inactif **annoncé** (jamais muet), miroir des Regression/Design Shields.
- Reste à faire (suite du fil) : `SEC-1b` (seeding des sections sécu dans les `rules.conf` existants via
  `relay-update`), `SEC-3` (CI gitleaks/semgrep), `SEC-2`/`SEC-4` (ancrage sélectif + auto-feed).

## [1.7.0] — 2026-06-19

### Added
- `relay-update.sh` : **prompt accept/décline** (T6-3) en run normal. Quand une mise à jour est
  disponible et que l'on est en terminal (TTY), le script affiche le delta de `CHANGELOG.md`
  (réutilise `print_changelog_delta`) **avant d'appliquer**, puis attend `[o/N]` ; un refus sort
  `0` sans modifier le moindre fichier. Le prompt est placé **avant** le self-update §1c — rien,
  pas même `relay-update.sh` lui-même, n'est touché sans consentement.
- `relay-update.sh` : bypass non-interactif `--yes` / `-y` / `--non-interactive`, **et** auto-détection
  `[ -t 0 ]` → application automatique sans blocage en CI, hooks et pipelines (jamais de prompt
  suspendu). La confirmation obtenue est propagée à travers le re-exec du self-update
  (`RELAY_UPDATE_CONFIRMED=1`) → jamais de double demande.

## [1.6.0] — 2026-06-19

### Fixed
- **Self-update bootstrapping de `relay-update.sh` (angle mort §1b)** : le script de mise à jour
  ne se propageait pas lui-même (la boucle de copie ne traite que `engine/scripts/*.sh`, or
  `relay-update.sh` vit dans `bin/`). Un consommateur lançant son ancien
  `docs/scripts/relay-update.sh` copiait le moteur récent mais rejouait son **ancienne** logique
  de migration (`rules.conf` non seedé, shields inactifs jusqu'à un 2ᵉ run).

### Added
- `relay-update.sh` : étage de **self-update « stage 1 → re-exec stage 2 »**. Stage 1 détecte que
  le script courant diffère du `bin/relay-update.sh` canonique, le copie sur lui-même, puis
  `exec` stage 2 (garde `RELAY_SELFUPDATE_STAGE2`) qui rejoue la migration avec la logique à jour
  — correct en **un seul run**. Idempotent (script déjà à jour → aucun saut, aucune boucle),
  jamais déclenché depuis le canonique (`bin/`, on n'écrase pas la source) ni en `--check`.

## [1.5.0] — 2026-06-19

### Added
- `CHANGELOG.md` (ce fichier) : journal machine-lisible des versions au format Keep a Changelog,
  source unique du delta d'améliorations affiché à l'utilisateur lors d'une mise à jour.
- `relay-update.sh --check` : **Update Advisor** en lecture seule (dry-run, non bloquant).
  Localise le canonique (y compris clone `--depth 1` d'une URL git), compare la version moteur
  installée à la version canonique et, en cas de retard, affiche les entrées de changelog entre
  les deux. N'écrit aucun fichier d'instance, sort `0` — scriptable et offline-safe.
- `RELAY_PROTOCOL.md §6` : étape de clôture □8 — tout bump de `VERSION` (canonique) ajoute une
  entrée `CHANGELOG.md`.

## [1.4.0] — 2026-06-18

### Changed
- **Externalisation du Design System Shield** (§8 du moteur) : les patterns, messages et
  exclusions de design vivent désormais dans `docs/.relay/rules.conf`
  (sections `[design_warn_flutter]` / `[design_warn_css]`) au lieu de tableaux codés en dur.
  Pureté moteur **totale** (aucune donnée de projet en dur ne subsiste).
- Sévérité du Design System Shield conservée à `WARNING` (ne bloque jamais le commit) ;
  section absente → shield inactif annoncé explicitement (pas de silence).

### Added
- `relay-update.sh` : migration v1.4.0 **idempotente au niveau section** — ajoute les sections
  DS à un `rules.conf` existant (projet déjà migré en v1.3.0) sans rien réécrire → zéro perte.

## [1.3.0] — 2026-06-18

### Changed
- **Externalisation des règles du Regression Shield** : les motifs interdits, jusque-là codés
  en dur et spécifiques à AgriConnect, quittent le moteur. Chaque projet déclare désormais ses
  propres motifs dans `docs/.relay/rules.conf` (instance, committé).

### Added
- `relay-update.sh` : migration v1.3.0 qui seede l'ancienne liste de motifs au premier update
  → zéro perte de garde pour les projets existants.

### Fixed
- Un projet sans `rules.conf` voit le Regression Shield **inactif + avertissement explicite**
  (jamais d'assouplissement silencieux).

## [1.2.0] — 2026-06-18

### Added
- `relay-run.sh` : wrapper de preuve transparent qui exécute une commande et émet un reçu
  (`docs/.relay/receipts/<hash>.log`) à citer sous la forme `[verified-run:<hash>]`.
- `relay-check.sh` : porte de reçu — un `[verified-run:<hash>]` sans reçu existant devient une
  **erreur** (preuve falsifiée) ; un `[verified-run]` nu reste un avertissement signal-only.

### Changed
- Rétrocompatibilité prouvée par exécution : une instance existante (runs nus, aucun reçu)
  conserve exactement le même exit code, score et set d'erreurs qu'en v1.1.1.

## [1.1.1] — 2026-06-12

### Added
- GitHub Action (`.github/workflows/ci.yml`) : `shellcheck --severity=error` sur `engine` + `bin`,
  garde de **pureté moteur** (aucune identité de projet en dur) et smoke test (bootstrap
  `relay-init` → `relay-check` produit un Health Score, zéro placeholder résiduel).

### Fixed
- `relay-brief.sh` : SC1087 (`$LAST_DATE[[:space:]]` → `${LAST_DATE}`), bug latent capté par la CI.

## [1.1.0] — 2026-06-12

### Added
- `relay-split.sh` : fractionne automatiquement `NEXT_SESSION.md` au-delà de 150 lignes
  (déjà référencé par l'avertissement de taille de `relay-check.sh`, manquait au canonique).
  Agnostique, propagé à tous les consommateurs.
- `docs/VISION.md` + `docs/FRAMEWORK_SPEC.md` : vision/feuille de route et spécification de
  robustesse (référence du framework, non propagées aux consommateurs).

## [1.0.0] — 2026-06-12

### Added
- Moteur canonique RELAY : séparation **MOTEUR** (propagé) / **INSTANCE** (jamais touché) /
  **TEMPLATE** (seed-once).
- `relay-init.sh` (bootstrap d'un nouveau projet), `relay-update.sh` (propage le moteur seul),
  `docs/.relay-version` + avertissement de skew dans `relay-check.sh`.
- Durcissement de la frontière : seul `RELAY_PROTOCOL.md` se propage ; `RELAY_METRICS.md`
  (compteurs) et `RELAY_RULE_POOL.md` (registre human-gated) reclassés TEMPLATE seed-once
  → un update n'écrase plus aucune donnée de projet.

[Non publié]: https://github.com/GitAmboudilaye/relay/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/GitAmboudilaye/relay/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/GitAmboudilaye/relay/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/GitAmboudilaye/relay/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/GitAmboudilaye/relay/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/GitAmboudilaye/relay/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/GitAmboudilaye/relay/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/GitAmboudilaye/relay/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/GitAmboudilaye/relay/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/GitAmboudilaye/relay/releases/tag/v1.0.0
