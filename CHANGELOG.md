# Changelog

Toutes les évolutions notables du **moteur canonique RELAY** sont documentées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et le projet respecte le [Semantic Versioning](https://semver.org/lang/fr/).

Ce fichier est la **source unique** de la « description des améliorations » affichée par
`relay-update.sh --check` quand un projet consommateur est en retard sur le canonique.
Chaque bump de `VERSION` doit ajouter une entrée ici (étape de clôture — `RELAY_PROTOCOL.md §6`).

## [Non publié]

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

[Non publié]: https://github.com/GitAmboudilaye/relay/compare/v1.6.0...HEAD
[1.6.0]: https://github.com/GitAmboudilaye/relay/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/GitAmboudilaye/relay/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/GitAmboudilaye/relay/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/GitAmboudilaye/relay/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/GitAmboudilaye/relay/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/GitAmboudilaye/relay/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/GitAmboudilaye/relay/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/GitAmboudilaye/relay/releases/tag/v1.0.0
