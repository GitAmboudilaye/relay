# RELAY Framework — Spec robustesse (session RELAY-ROBUSTE)

> **Contexte :** RELAY est le protocole de relais inter-session actuellement documenté dans `NEXT_SESSION.md` + `CLAUDE.md`. Il fonctionne, mais sa robustesse dépend entièrement de la rigueur d'exécution du LLM. Cette session le renforce en rendant 3 propriétés exécutables par la machine.

---

## Problèmes à résoudre (issus du diagnostic 2026-06-06)

| Problème | Symptôme observé | Priorité |
|---|---|---|
| Pas d'enforcement | Checklist sautée 2 sessions de suite (§Plan session suivante) | P1 |
| Assertions mémoire non datées | Un "fix appliqué" dans NEXT_SESSION peut être faux sans signal | P1 |
| Estimation effort non contrainte | Tâches M prennent L, biais optimiste systématique sans feedback | P2 |
| Tâches en prose non parseable | Impossible d'automatiser le calcul 70% ou de détecter les dépendances | P2 |

---

## Livrable 1 — `docs/scripts/relay-check.sh`

Script bash exécutable qui valide la structure de `NEXT_SESSION.md` avant tout commit.

**Ce qu'il vérifie :**
1. `## ⚡ Plan session suivante` présent
2. `### Ce qui reste ❌` présent
3. `### Ce qui a été fait ✅` présent (ou absent si session sans tâche)
4. `## Retour expérience` présent (obligatoire fin de session)
5. `## Règles absolues rappel` présent (ne pas l'effacer)
6. Taille ≤ 200 lignes (warning si > 200, bloquant si > 250)

**Output attendu :**
```
[RELAY] ✅ NEXT_SESSION.md — structure valide (198 lignes)
[RELAY] ✅ Sections obligatoires : 5/5 présentes
```
ou :
```
[RELAY] ❌ Section manquante : "## Retour expérience"
[RELAY] ❌ Taille : 267 lignes (max 250)
```

**Usage :**
```bash
chmod +x docs/scripts/relay-check.sh
./docs/scripts/relay-check.sh          # validation manuelle
./docs/scripts/relay-check.sh --strict # exit 1 si erreur (pour hook)
```

---

## Livrable 2 — `.git/hooks/pre-commit` (warning non bloquant)

Hook pre-commit qui appelle `relay-check.sh --strict` uniquement si des fichiers backend ou Flutter sont dans le staging.

**Logique :**
```bash
# Si le staging contient des fichiers .cs ou .dart → vérifier NEXT_SESSION.md
if git diff --cached --name-only | grep -qE '\.(cs|dart)$'; then
  if ! ./docs/scripts/relay-check.sh --strict; then
    echo "[RELAY] ⚠️  NEXT_SESSION.md invalide. Continuer quand même ? (y/N)"
    read answer
    [ "$answer" = "y" ] || exit 1
  fi
fi
```

Mode warning (pas blocage automatique) — le développeur peut passer outre avec "y". L'objectif est la visibilité, pas l'obstruction.

---

## Livrable 3 — Memory Reconciliation Step (MRS)

Nouveau step dans le protocole CLAUDE.md `§6 Protocole de relais → Étape 0`.

**Principe :** chaque assertion dans NEXT_SESSION.md qui parle d'un fait code vérifiable (fichier, fonction, migration, commit) doit être **vérifiée par grep/find avant d'être utilisée comme base de travail**.

### Format de marquage dans NEXT_SESSION.md

Ajouter un suffixe de confiance aux lignes de contexte :

```markdown
| `BUG-RECU-INCOMPLET` ✅ | Fix backend ThenInclude Produit appliqué. | `4b550cf` [verified] |
| `BUG-STOCK-NAVIGATION` ❌ | Backend endpoint manquant. | [assumed] |
| `STAB-2-DATA-CLEANUP` | Script SQL SSMS Windows. | [external] |
```

**Niveaux :**
- `[verified]` — grep/find confirmé cette session (ex: `grep -rn "ThenInclude(l => l.Produit)" TransactionRepository.cs` → trouvé)
- `[assumed]` — hérité de la session précédente, non vérifié cette session
- `[stale?]` — hérité depuis > 2 sessions sans vérification, à vérifier en priorité
- `[external]` — état d'un système externe (Windows SSMS, DB, déploiement) — non vérifiable par grep

### Règle MRS dans CLAUDE.md

> **Memory Reconciliation Step (MRS) — obligatoire à chaque session :**
> 1. Pour chaque tâche `[assumed]` ou `[stale?]` dans §Ce qui reste ❌ : exécuter le grep/find de vérification
> 2. Promouvoir à `[verified]` si trouvé, marquer `[stale? → absent]` si non trouvé et adapter le plan
> 3. NE JAMAIS planifier du travail sur une base `[stale?]` non vérifiée

---

## Livrable 4 — Task Graph Format (TGF)

Format machine-parseable minimal pour les tâches dans `§Ce qui reste ❌`.

**Syntaxe :**
```
TASK[ID] status=pending|in_progress|done effort=S|M|L depends=[] owner=session|windows|external
```

**Exemple dans NEXT_SESSION.md :**
```markdown
### Ce qui reste ❌

TASK[BUG-STOCK-NAVIGATION] status=pending effort=L depends=[] owner=session
> Carte produit cliquable → StockProduitDetailScreen. Backend: GET /stockclient/{produitId}/detail.

TASK[STAB-2-DATA-CLEANUP] status=pending effort=- depends=[] owner=windows
> Script SQL dans KNOWN_ISSUES.md — SSMS uniquement.

TASK[BUG-BASCULEMENT-SERVEUR] status=pending effort=L depends=[MODE-OFFLINE] owner=session
> Prérequis: mode hors ligne non implémenté.
```

Le LLM peut parser ces lignes avec un regex simple pour calculer automatiquement le 70% : additionner les efforts S(0.5)+M(1)+L(2) des tâches `owner=session`, comparer à la capacité de session (≈3M ou ≈2L).

---

## Plan d'implémentation pour la session RELAY-ROBUSTE

### Tâche 1 — relay-check.sh (S)
- Créer `docs/scripts/relay-check.sh`
- Tester sur le NEXT_SESSION.md courant
- Documenter usage dans CLAUDE.md §4 Commandes utiles

### Tâche 2 — pre-commit hook (S)
- Créer `.git/hooks/pre-commit` (warning non bloquant)
- Tester avec un commit de test `.cs` sans NEXT_SESSION.md modifié
- Note : fichier non commitable (`.git/` ignoré par git) — documenter la commande d'installation dans CLAUDE.md

### Tâche 3 — MRS dans CLAUDE.md et NEXT_SESSION.md (M)
- Ajouter Memory Reconciliation Step dans CLAUDE.md §6 Étape 0
- Migrer le NEXT_SESSION.md courant vers le format avec suffixes `[verified]`/`[assumed]`/`[stale?]`/`[external]`
- Documenter les niveaux de confiance dans CLAUDE.md §1 Projet

### Tâche 4 — Task Graph Format (S)
- Migrer §Ce qui reste ❌ vers le format TASK[]
- Ajouter règle de calcul 70% automatique dans CLAUDE.md §6 §3

### Règles absolues pour cette session
- Ne pas modifier les entités Domain/ sans autorisation
- Ne pas modifier Program.cs sans autorisation
- relay-check.sh doit être idempotent (relancer = même résultat)
- Le hook doit être warning, jamais bloquant par défaut

---

## Critères d'acceptation

Après RELAY-ROBUSTE :
1. `./docs/scripts/relay-check.sh` renvoie ✅ sur le NEXT_SESSION.md courant
2. Un commit de fichier `.cs` sans toucher NEXT_SESSION.md déclenche le warning
3. NEXT_SESSION.md a tous les `[verified]`/`[assumed]` sur les tâches
4. `§Ce qui reste ❌` utilise le format TASK[]
5. CLAUDE.md documente MRS comme étape obligatoire dans §6

---

## Ce que cette session NE fait PAS

- Ne refactorise pas RELAY de zéro
- Ne migre pas les SESSIONS_ARCHIVE (historique → laissé tel quel)
- Ne crée pas de CI/CD check (hors scope WSL)
- Ne touche pas au code métier AgriConnect
