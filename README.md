# RELAY — moteur canonique

> Moteur de relais inter-sessions LLM, **versionné et séparé des données d'instance**.
> Un projet consomme ce moteur via `relay-init.sh` (bootstrap) puis le met à jour via
> `relay-update.sh` (propagation). Le moteur est **copié** aux chemins `docs/scripts/` et
> `docs/rules/` du projet (pas de submodule) → toutes les références `./docs/scripts/relay-*.sh`
> restent valides.

## Quoi / Pourquoi

RELAY permet à des sessions LLM successives **sans mémoire partagée** de travailler sur un même
projet brownfield comme une équipe stable : reprendre l'état réel (MRS), ne rien casser
(Regression/Design-System Shields), ne pas réinventer, et laisser le projet repartable en < 10 min.

Avant ce repo, le moteur était **copié-collé** entre projets et les copies **divergeaient**
(ex. `audit.sh` hardcodait un ancien nom de projet). Ici, **moteur** (portable) et **instance**
(propre au projet) sont séparés ; la propagation est un script, pas un copier-coller manuel.

## Arborescence

```
relay/
├── engine/
│   ├── scripts/   # relay-check.sh, relay-brief.sh, relay-stats.sh, stale-detector.sh, audit.sh
│   └── rules/     # RELAY_PROTOCOL.md, RELAY_METRICS.md, RELAY_RULE_POOL.md
├── templates/     # graines des fichiers d'instance (placeholders {{PROJECT_NAME}}, {{STACK}}…)
├── bin/
│   ├── relay-init.sh    # BOOTSTRAP d'un nouveau projet
│   └── relay-update.sh  # PROPAGATION du moteur dans un projet existant
├── VERSION              # version sémantique du moteur (ex. 1.0.0)
└── README.md
```

## Classification MOTEUR vs INSTANCE

| Catégorie | Fichiers | Propagé par `relay-update.sh` ? |
|---|---|---|
| **MOTEUR** | `engine/scripts/*.sh`, `engine/rules/RELAY_PROTOCOL.md` (§0-§7 portables ; §8 = pointeur statique) | ✅ oui — écrasé à chaque update |
| **INSTANCE** | `NEXT_SESSION.md`, `CLAUDE.md`/`SYSTEM.md`/…, `docs/context/*`, `docs/rules/{KNOWN_ISSUES,*_ARCHITECTURE}.md` | ❌ jamais touché |
| **TEMPLATE (seed-once)** | `templates/*` — dont `docs/rules/{RELAY_METRICS,RELAY_RULE_POOL}.md` | déposés **au bootstrap uniquement**, jamais en update |

> **Principe de sûreté de la propagation : un fichier moteur ne contient AUCUNE donnée de projet.**
> Les **compteurs** de `RELAY_METRICS.md §0` et le **registre** human-gated de `RELAY_RULE_POOL.md`
> sont des données d'instance → ils sont des **templates seed-once** (posés une fois par `relay-init`,
> ensuite propriété du projet), **jamais** propagés. La **logique** de scoring/anti-inflation, elle,
> vit dans `relay-check.sh` (moteur) et se propage. Ainsi un `update` ne peut écraser aucune donnée projet.

## Usage

### Bootstrap d'un nouveau projet

```bash
cd /chemin/vers/mon-projet
/chemin/vers/relay/bin/relay-init.sh \
  --project-name MonProjet --stack "FastAPI+React" --lang "Python/TS" \
  --domain "marketplace" --actors "acheteur,vendeur,admin" --llm gpt
```

Effets : copie le moteur dans `docs/scripts/` + `docs/rules/`, génère les fichiers d'instance
depuis `templates/`, écrit `docs/.relay-version`, installe le hook pre-commit.
**N'écrase jamais** un fichier d'instance déjà présent.

### Propagation d'un fix moteur

```bash
cd /chemin/vers/mon-projet
RELAY_CANONICAL=/chemin/vers/relay ./docs/scripts/relay-update.sh
```

Localisation du canonique : `$RELAY_CANONICAL` → cache `~/.relay/canonical` (clone/pull depuis
`CANONICAL_URL` de `docs/.relay-version`) → chemin local → sinon erreur explicite.
Copie **uniquement** les fichiers moteur, met à jour `.relay-version`, ne touche **aucun** fichier
d'instance, et imprime le diff (fichiers changés + `ancienne → nouvelle` version).

### Détection de skew (signal-only)

`relay-check.sh` compare la version moteur installée (`docs/.relay-version`) à la `VERSION` du
canonique localisable et émet un avertissement « moteur vN en retard sur canonique vM → lance
relay-update.sh ». **N'altère ni le Health Score ni l'exit code.** No-op si le canonique est
introuvable.

## `docs/.relay-version` (manifeste d'instance)

```
1.0.0
PROJECT=MonProjet
CANONICAL_URL=/home/me/projects/relay   # chemin local ou URL git
INSTALLED=2026-06-12
```
