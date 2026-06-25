# Adaptateur sans-agent — git pre-commit / CI (RELAY-NOAGENT)

**3ᵉ adaptateur** du RELAY Core « actif » (après Claude Code et Cline), pour le scénario **dégradé** où
il n'y a **pas d'agent** : un dev qui code sans LLM, ou la CI (cf. `docs/RELAY-CORE-ACTIF.md §1.1/§1.2/§3`).
Il câble le **même** noyau agnostique `relay-context.sh` — 0 couplage, comme les deux autres adaptateurs.

> **Pourquoi « dégradé » ?** Sans agent, il n'existe **aucun contexte LLM** où injecter la règle *avant*
> l'écriture (le shift-left des hooks d'agent). La seule barrière possible est **en aval**, au commit ou
> dans la CI. Le canal d'enforcement n'est donc plus un JSON de décision mais le **code de sortie**.

## Mécanique

`relay-precommit.sh` liste les fichiers touchés, pipe le **contenu proposé** de chacun à
`relay-context.sh --path=<fichier> --stdin --strict`, et agrège :

| Sortie noyau | Effet |
|---|---|
| ≥1 pattern **ERROR** (proscrit ; `--strict` → exit 3) | accumulé → **exit 1** final → **bloque** le commit / fait échouer le job CI. |
| Seulement **WARN/INFO** | texte affiché, **non-bloquant** (advisory). |
| Rien | silence (token-négatif, §1.3). |

### Deux modes, un seul script

| Mode | Déclencheur | Fichiers | Contenu analysé |
|---|---|---|---|
| **pre-commit** (défaut) | aucun env | stagés (`git diff --cached --diff-filter=ACMR`) | **blob d'index** (`git show :file`) = ce qui va être committé |
| **CI / range** | `RELAY_RANGE` défini (ex. `origin/main...HEAD`) | diff de la plage | **arbre courant** (le checkout CI est sur la pointe) |

### Mode diff-only (opt-in) — pour le brownfield

Par défaut, l'adaptateur juge le **contenu entier** du fichier touché. Sur un dépôt **légataire**, cela
bloque dès qu'on édite un fichier qui contient *déjà* un pattern proscrit (ex. un `.Result`/`localhost:7285`
historique) — même si on n'a pas touché à cette ligne. Le mode **diff-only** ne fait juger que les
**lignes AJOUTÉES** (`git diff -U0`, lignes `+`, préfixe retiré), donc seul **ce qu'on ajoute** compte.

| Activation | Effet |
|---|---|
| `RELAY_DIFF_ONLY=1` (env) **ou** `--diff-only` (flag) | ne pipe au noyau que les lignes ajoutées des fichiers touchés (les deux modes pre-commit et range le respectent). |
| *(rien — défaut)* | contenu entier — posture sécurité maximale. |

C'est un **pré-filtre 100 % adaptateur** : `relay-context.sh` reste agnostique (§1.2), il grep le contenu
reçu sur `--stdin` qu'il provienne du fichier ou du diff.

> **⚠️ Compromis sécurité (raison de l'OPT-IN, décision user 2026-06-24).** En diff-only, une clé AKIA /
> un secret **préexistant** dans un fichier touché mais **non modifié** n'est plus flagué. Le **défaut**
> reste donc le scan plein-fichier : greenfield et CI stricte ne changent rien ; le brownfield active
> explicitement le mode et accepte ce compromis. Le fail-closed sur un finding **neuf** (pattern ajouté)
> est, lui, **préservé** dans les deux modes.

## La différence structurante : fail-OPEN sur l'outillage, fail-CLOSED sur le finding

Les adaptateurs d'**agent** (`relay-hook.sh`, `relay-precheck.sh`) sont **purement fail-open** : un hook
cassé ne bloque **jamais** une édition. Ici, le **but même** est de bloquer sur un pattern proscrit, donc :

- **bug d'outillage** (git absent, hors dépôt, `rules.conf`/noyau introuvable) → **exit 0** : on ne coince
  **jamais** un commit pour un bug d'outil ;
- **vrai pattern PROSCRIT** dans le contenu → **exit 1** : on **bloque**.

Échappatoire explicite : `RELAY_SKIP=1` (ou `git commit --no-verify`, qui court-circuite tout pre-commit).

## Pas de ledger token-saved (volontaire)

Cet adaptateur **n'écrit pas** dans `docs/.relay/token-ledger.log`. La métrique `relay-tokens` modélise
l'économie de **réécriture LLM** ; un commit humain bloqué n'est **pas** une réécriture LLM évitée →
l'y inscrire **corromprait** la métrique. Même discipline que « token-saved = contrefactuel, jamais
inventé ». Les firings d'agent (Claude Code / Cline) restent la seule source du ledger.

## Câblage

### a) Hook git pre-commit (poste du dev, sans agent)

Depuis la racine du dépôt — un wrapper qui **n'écrase pas** un hook existant :

```sh
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/docs/adapters/no-agent/relay-precommit.sh"
EOF
chmod +x .git/hooks/pre-commit
```

> Sur le dépôt canonique RELAY (dogfood), pointer vers `engine/adapters/no-agent/relay-precommit.sh`.

### b) Step CI

```yaml
- name: RELAY guard (patterns proscrits sur le diff)
  run: |
    git fetch origin "${{ github.base_ref }}" --depth=1 || true
    RELAY_RANGE="origin/${{ github.base_ref }}...HEAD" \
      docs/adapters/no-agent/relay-precommit.sh
```

Un ERROR sur le diff fait sortir le step en **exit 1** → job rouge. Tant que le projet n'a pas de
`docs/.relay/rules.conf`, le noyau reste silencieux → l'adaptateur est inoffensif (exit 0).

## Prérequis

- **`git`** (liste des fichiers / contenu d'index). Absent → fail-open.
- **Aucun `python3`** : contrairement aux adaptateurs d'agent, il n'y a pas de frontière JSON →
  **pur Bash**. Le noyau l'est déjà.
- `RELAY_CONTEXT_BIN` (optionnel) force le chemin du noyau — utilisé par le smoke test.
