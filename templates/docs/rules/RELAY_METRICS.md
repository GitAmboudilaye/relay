# RELAY_METRICS.md — [LLM-AGNOSTIC] Définit ce qu'on mesure pour piloter la qualité du relais.
# Données via `relay-stats.sh` + `relay-check.sh`.
# [INSTANCE — seed-once] relay-init dépose ce fichier UNE fois ; il devient propriété du projet.
#    relay-update.sh ne le propage JAMAIS (les COMPTEURS §0 sont des données du projet).
#    La LOGIQUE de scoring (portable) vit dans relay-check.sh (moteur, lui propagé) ; ce .md la documente.

> But : rendre visible la santé du relais, pas produire des chiffres pour eux-mêmes.

---

## 0. Compteurs (lus par `relay-brief.sh`) — À METTRE À JOUR PAR LE PROJET

- **Sessions totales** : 0
- **Features déjà implémentées** (à ne pas refaire — voir STATE.md) : 0
- **Régressions majeures** : 0

---

## 1. Health Score NEXT_SESSION.md (0-100) — `relay-check.sh`

| Composant | Max | Mesure |
|---|---|---|
| Sections obligatoires | 35 | Plan / Ce qui reste / Retour / Règles absolues présentes |
| Taille | 15 | ≤ 130 lignes = 15 · 130-150 = 12 · 150-200 = 8 · > 200 = 0 + erreur |
| Ratio confiance MRS | 35 | `verified / (verified+assumed+stale)` × 35, pénalité −5/tâche `[stale?]`. `verified` = somme de `[verified]` (legacy=run) + `[verified-build]` + `[verified-run]` |
| Commits des tâches done | 15 | chaque `~~TASK[]~~` done référence un hash de commit valide |

**Seuil de commit : Health Score ≥ 80.** En-dessous → corriger NEXT_SESSION.md avant de committer.

### Gating sécurité du LABEL (TASK[RELAY-SCORE-HONEST])

Le **score numérique** ci-dessus mesure l'**hygiène du handoff** (`NEXT_SESSION.md`) et reste
calculé à l'identique. Mais le **LABEL** affiché (`🟢 Sain` / `🟡 Attention` / `🔴 Dégradé`) est
**gaté par la sécurité** : tant qu'il existe un **finding P0/P1 ouvert** dans `KNOWN_ISSUES.md`,
le label `🟢 Sain` **ne s'affiche pas** — il est remplacé par `⚠️ <N> P0/P1 ouvert(s)`.
Cela résout la contradiction « 100/100 🟢 Sain alors qu'un P0 est ouvert » (§intro « santé du
relais » + §8 « sécurité d'abord »). **On ne fusionne pas les deux notions** : le score d'hygiène
et l'état sécurité restent distincts ; seul l'affichage du label est conditionné.

- **Définition « P0/P1 ouvert » (déterministe)** : toute entrée `### KI-xxx` sous une section
  `## … P0` ou `## … P1` de `KNOWN_ISSUES.md` dont le titre **ne contient pas** `✅ RÉSOLU`.
  Les entrées `🟡` (partielles) comptent comme **ouvertes**.
- **Cas limites** : `KNOWN_ISSUES.md` absent ou 0 finding ouvert → label inchangé (pas de crash) ;
  détection tolérante au format des titres (n'extrait que les sections P0/P1, ignore P2/✅).
- **Portée** : gating appliqué dans `relay-check.sh` ; `relay-brief.sh` hérite du label gaté car
  il relit la ligne « Health Score » de `relay-check.sh --score-only` (ligne `[10]`).
- **Exit code** : **inchangé**. Le gating est *signal-only* (n'ajoute ni erreur ni warning au
  compteur, ne modifie pas le code de sortie de `--strict`) — il rend la sécurité **visible**,
  pas bloquante au niveau du commit handoff (l'enforcement sécurité reste porté par les KI eux-mêmes).

---

## 2. Métriques de relais (santé du processus)

| Métrique | Définition | Cible |
|---|---|---|
| **Temps de reprise** | délai entre l'ouverture de session et le 1ᵉʳ « go » du plan | < 10 min |
| **Ratio verified** | part des TASK[] `[verified]` au moment du commit | ↑ session après session |
| **Respect du budget 70 %** | tâches planifiées vs réellement bouclées | ≥ 80 % bouclées, 30 % réservé clôture |
| **Densité du ruleset** | `relay-check.sh --density` (univers/récent vN.N) | 🟢 ≤ 1.30 · 🟡 ≤ 1.80 · 🔴 au-delà |
| **Hypothèses corrigées par MRS** | nb de `[assumed]` invalidés à l'ouverture | tracé en §Retour (signal de valeur du MRS) |

---

## 3. Métriques produit (qualité du code livré) — À RENSEIGNER PAR LE PROJET

| Métrique | Source | État |
|---|---|---|
| Build | `[commande build du projet]` | [à renseigner] |
| Analyse statique | `[linter du projet]` | [à renseigner] |
| Findings sécurité ouverts | `KNOWN_ISSUES.md` | [compté par relay-check.sh : P0/P1] |
| Couverture tests | — | [à renseigner] |
| Preuve des fix sécurité | `relay-check.sh` (build-only) | un fix KI en `[verified-build]` est prouvé par compile/lecture, **pas** par run ; `[verified-run]` (attaque jouée) requis pour clore honnêtement |

> **`[verified-build]` vs `[verified-run]`** (cf. `RELAY_PROTOCOL §1`) : tant qu'aucune suite de
> tests ne permet de **jouer** un scénario (ex. attaque cross-tenant), un fix reste `[verified-build]`.
> `relay-check.sh` émet un warning « build-only » sur les tâches référençant un KI sécurité en
> `[verified-build]` → la dette de vérification runtime devient visible.

> **Regression Shield** : chaque bug corrigé doit référencer son entrée `KI-xxx` dans le message de commit.
> Un bug sans entrée KI = trou de traçabilité.

---

## 4. Anti-objectifs (ce qu'on NE mesure PAS)

- Nombre de lignes de code écrites (volume ≠ valeur).
- Vélocité brute en tâches/session (inciterait à fractionner artificiellement).
- Réduire les warnings à 0 « pour le score » au détriment d'une feature ou d'un fix sécurité.
