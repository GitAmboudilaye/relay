# NEXT_SESSION.md — {{PROJECT_NAME}}

> Dernière mise à jour : {{TODAY}} (initialisation RELAY Framework)
> Sessions archivées → `docs/context/SESSIONS_ARCHIVE.md`

---

## ⚡ PROTOCOLE DE RELAIS — À lire ET appliquer à chaque session

> **Ce protocole s'applique à CHAQUE session sans exception.**
> Source canonique : `docs/rules/RELAY_PROTOCOL.md`

### Étape 0 — MRS (Memory Reconciliation Step)

1. Pour chaque tâche `[assumed]` ou `[stale?]` dans §Ce qui reste ❌ : exécuter le grep/find de vérification
2. Promouvoir à `[verified]` si trouvé, marquer `[stale? → absent]` si non trouvé
3. **NE JAMAIS planifier du travail sur une base `[stale?]` non vérifiée**
4. Lancer `./docs/scripts/stale-detector.sh` pour détecter les tâches vieillissantes

Niveaux de confiance :
- `[verified-run]` — comportement runtime observé OU test exécuté cette session (le plus fort)
- `[verified-build]` — confirmé par compile/grep/lecture statique cette session (pas d'exécution)
- `[verified]` — alias historique de `[verified-run]` (rétro-compat)
- `[assumed]` — hérité session précédente, non revérifié
- `[stale?]` — hérité depuis > 2 sessions sans vérification
- `[external]` — état système externe non vérifiable par grep

### Règle des 70%

1. Lire cette section (max 10 min)
2. MRS → ajuster les tâches
3. Estimer S=~30min / M=~1h / L=~2h+ — **viser 2-3 tâches max**
   Calcul : additionner S(0.5)+M(1)+L(2) des tâches `owner=session status=pending`
4. Exposer le plan AVANT de coder → **attendre validation explicite**
5. Coder dans l'ordre strict des priorités
6. Sauvegarder NEXT_SESSION.md après chaque tâche terminée

### Checklist fin de session — OBLIGATOIRE

```
□ 1. Build → 0 erreur (si code modifié)
□ 2. Tests → 0 régression (si tests disponibles)
□ 3. STATE.md + SESSIONS_LOG.md mis à jour
□ 4. §Retour expérience + §Suggestion rédigés
□ 5. NEXT_SESSION.md §fait/reste/plan mis à jour
□ 6. relay-check.sh → Health Score ≥ 80 avant commit
□ 7. git commit + push
```

---

## ⚡ Plan session suivante (70% contexte)

### Ce qui a été fait ✅ (session {{TODAY}} — initialisation)

TASK[RELAY-INIT] status=done effort=S depends=[] owner=session
> Structure RELAY initialisée : relay-check.sh, stale-detector.sh, pre-commit hook, NEXT_SESSION.md, {{INSTR_FILE}}, docs/ structure.

### Ce qui reste ❌

TASK[SETUP-ENV] status=pending effort=M depends=[] owner=session [assumed]
> Configurer l'environnement de développement. §TODO : remplacer par les vraies tâches.

TASK[SETUP-DB] status=pending effort=M depends=[SETUP-ENV] owner=session [assumed]
> Initialiser la base de données / infrastructure.

### Plan session suivante (70%)

MRS : vérifier que SETUP-ENV et SETUP-DB ne sont pas déjà faits.
Calcul 70% : SETUP-ENV(M=1) + SETUP-DB(M=1) = 2 → tient dans une session.
BUDGET SESSION : 2 pts.

Tâches retenues (70%) : SETUP-ENV → SETUP-DB
Reporté (30%) : rien pour l'instant.

---

## Retour expérience — INITIALISATION ({{TODAY}})

### Ce qui a été fait
- Structure RELAY initialisée. Remplacer cette section par les vrais retours à la fin de la première session.

### Suggestion amélioration protocole
- [À remplir : 1 amélioration OU 1 règle retirée/fusionnée par session — anti-inflation]

---

## Règles absolues rappel

- [À remplir : règles projet-spécifiques]
- relay-check.sh → lancer avant chaque commit
- `[stale?]` → jamais planifier sans grep de vérification
- 70% = réserver du contexte pour la clôture (STATE, LOG, §Retour, push)
