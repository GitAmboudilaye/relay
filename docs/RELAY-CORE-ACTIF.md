# RELAY Core « actif » — cadrage d'architecture

> **Référence non propagée** (comme `VISION.md` / `RELAY-CAPABILITIES.md`). Fige la direction
> « RELAY actif » validée par l'user le **2026-06-23**, à exécuter en sessions post-mise-en-production.
> Sources : décision user 2026-06-23, `VISION.md §4` (token-discipline non négociable), `RELAY-CAPABILITIES.md`
> (phase passive close à v1.15.0). Ce doc **fige le contrat**, il n'implémente rien.

---

## 0. Le problème (formulé du rôle)

RELAY à v1.15.0 est **passif** : `relay-check.sh` est exécuté **par le LLM à la clôture**. L'enforcement
(style en dur, `NEXT_SESSION.md > 200`, surface sécu touchée…) arrive donc **a posteriori** = le code est
déjà écrit → il faut le **réécrire** = tokens gaspillés.

Objectif **shift-left** : injecter le bon contexte **avant** l'écriture, pas après. Le coût d'un rappel
ciblé en amont (~40 tokens) est sans commune mesure avec une réécriture en aval (~2000 tokens). C'est
l'angle produit chiffrable de RELAY (`VISION.md §4`).

---

## 1. Décisions d'architecture (validées user 2026-06-23)

### 1.1 — Le canal temps réel d'un agent = le HOOK, pas un démon

Un démon `inotifywait` qui écrit sur stdout **n'atteint jamais le contexte du LLM**. Un agent ne voit que :
les résultats des outils qu'il appelle, la sortie des **hooks** que le harnais injecte (PreToolUse /
PostToolUse), et les system-reminders. Donc « RELAY actif » dans Claude Code = **hook `PreToolUse` sur
Edit/Write** (matcher sur le chemin) déclaré dans `settings.json`.

→ Un éventuel `relay-watch.sh` (démon) est **dégradé** : réservé au scénario *sans agent* (éditeur, CI),
jamais le canal principal.

### 1.2 — Noyau portable + adaptateurs par harnais

| Couche | Rôle | Exemples |
|---|---|---|
| **NOYAU** | scripts Bash à **sortie texte structurée** = le « contrat RELAY ». Agnostique, 0 dépendance harnais. | `relay-scan.sh`, `relay-context.sh`, `relay-check.sh` |
| **ADAPTATEUR** | câblage par harnais qui *appelle* le noyau et place sa sortie là où l'agent la voit. | Claude Code = hook `settings.json` · Cline = hook `PreToolUse` (v3.36+ ; ⚠️ « = MCP » périmé, voir RELAY-CLINE v1.20.0) · sans agent = git hook |

**Ne jamais coupler le noyau à un harnais.** C'est ce qui garde RELAY agnostique (déjà prouvé cross-stack
en sandbox) et donc réutilisable/vendable. Un adaptateur peut disparaître sans toucher le noyau.

### 1.3 — Linter terse et conditionnel (Pilier 11 — anti-inflation)

L'adaptateur grep le fichier qu'on **vient** d'éditer et ne signale que la **violation probable détectée**
(ex. `AppDbContext` direct dans un Controller), **jamais** un mur de règles statique à chaque Edit. Bruit
= saturation du contexte = tokens brûlés = l'inverse du but. Silence quand rien n'est détecté.

### 1.4 — Angle produit = économie de tokens chiffrable

Métrique à ajouter (`relay-forecast.sh` ou outil dédié) : **token-in** (coût de l'injection amont) vs
**token-saved** (réécriture aval évitée). Un RELAY qui consomme *plus* de tokens pour « mieux faire » a
échoué (`VISION.md §4`, `§105`).

---

## 2. Le « contrat RELAY » (sortie texte structurée du noyau)

Tout script noyau émet une **sortie déterministe, parsable, bornée** — consommable aussi bien par un
humain que par un adaptateur (hook/MCP). Conventions communes (alignées sur le moteur existant) :

- Préfixe de ligne `[RELAY] …` en mode humain ; **`--json`** pour l'usage programmatique (adaptateurs).
- `set -uo pipefail`, portabilité GNU/BSD (fallbacks `date`), `shellcheck` CLEAN.
- **Exit 0 par défaut** (outil informatif) ; un `--strict` peut passer à exit≠0 si et seulement si l'outil
  est branché dans un gate (jamais imposé par le noyau lui-même).
- **Borné** : top-N + total, jamais un dump intégral (un dump = tokens = anti-but). Le détail complet
  reste derrière un flag explicite.

---

## 3. Roadmap

| Étape | Livrable | Nature | Dépend |
|---|---|---|---|
| **RELAY-1** ✅ v1.16.0 | `relay-scan.sh` — recherche ciblée projet-wide, sortie structurée (cas d'usage : rename `AgriConnect→EcoAgriConnect`, `app→VraiKilo` ; preview d'impact). | **pur noyau**, 0 dépendance harnais, valeur immédiate | — |
| **RELAY-2** ✅ v1.17.0 | `relay-context.sh` — émet le contexte/règle pertinent pour un chemin donné (script d'abord, puis branché en hook). Réutilise `rules.conf`, déclenché par contenu (§1.3) + `--stdin` (contenu proposé). | noyau (script) → puis adaptateur | RELAY-1 |
| **RELAY-3** ✅ v1.18.0 | **Adaptateur hook PreToolUse Claude Code** — `engine/adapters/claude-code/relay-hook.sh` câble `relay-context.sh --path=<édité> --stdin` dans `.claude/settings.json` (matcher `Edit\|Write\|MultiEdit`). ERROR→`deny`, WARN/INFO→`additionalContext`, rien→silence. FAIL-OPEN absolu. Propagé en `docs/adapters/`. | adaptateur | RELAY-2 |
| **+** ✅ v1.19.0 | Métrique **token-saved** — outil dédié `relay-tokens.sh` (choix user vs `--tokens` : sources orthogonales). L'adaptateur hook appende un **ledger d'instance** (`docs/.relay/token-ledger.log`, gitignoré, fail-open) ; l'outil chiffre `token-in` (Σ firings × 40) vs `token-saved` (Σ deny × 2000, conservateur), constantes overridables. token-saved = **contrefactuel → modélisé**, jamais inventé sans données. | mesure | RELAY-3 |
| **RELAY-CLINE** ✅ v1.20.0 | **2ᵉ adaptateur — hook `PreToolUse` Cline** — `engine/adapters/cline/relay-precheck.sh` câble le **même** `relay-context.sh` dans Cline (v3.36+). Première preuve de **généralisation N>1** de la couche actif. ERROR→`{"cancel":true,"errorMessage"}`, WARN/INFO→`{"cancel":false,"contextModification"}`, rien→`{"cancel":false}` (ALLOW explicite). **Parité d'enforcement** (deny réel) : rectifie l'hypothèse « Cline = MCP » (les hooks Cline ont rendu MCP inutile ici). Résolution symlink-safe, FAIL-OPEN, ledger token-saved partagé. | adaptateur | RELAY-3 |

**Principe de séquencement** : on livre d'abord le **noyau** (valeur même sans agent), puis on le **câble**.
Jamais l'inverse — un adaptateur sans noyau testable n'est pas vérifiable.

---

## 4. Hors périmètre / garde-fous

- Le **gel** des nouveaux rôles/gates **passifs** (décision 2026-06-20) tient. « RELAY actif » est une
  direction d'archi **distincte et postérieure** (validée 2026-06-23), pas un nouveau rôle passif.
- Chaque livrable doit passer « **optimise les tokens, ne les augmente pas** » (`VISION.md §4`) — sinon il
  ne ship pas.
- **0 couplage noyau↔harnais** : si un script noyau a besoin d'un détail Claude-Code-spécifique, c'est un
  signe qu'il faut un adaptateur, pas une dépendance dans le noyau.
- Tests des scripts moteur en **sandbox isolée** : `git -C "$D"` + `( cd "$D" && … )` en sous-shell,
  **jamais** un `cd` nu vers `mktemp` (ne s'isole pas dans ce sandbox → pollue le repo courant ; incident
  réel RELAY-FORECAST 2026-06-20).
