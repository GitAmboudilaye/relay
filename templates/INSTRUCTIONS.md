# {{INSTR_FILE}} — {{PROJECT_NAME}}
# [LLM-AGNOSTIC] Ce fichier fonctionne avec Claude Code, GPT, Gemini, ou tout LLM agentique.
# [LLM: {{INSTR_LABEL}}]

> **[LLM-AGNOSTIC] Protocole de démarrage obligatoire :**
> 0. Lancer `./docs/scripts/relay-brief.sh` pour le Senior Brief (10 lignes, 30s de lecture)
> 1. Lire `NEXT_SESSION.md` — section courante en premier
> 2. Appliquer MRS (§Étape 0) sur les tâches [assumed]/[stale?]
> 3. Lire `docs/rules/KNOWN_ISSUES.md`
> 4. Exposer l'analyse + plan de session → attendre validation avant de coder

---

## 1. PROJET [LLM-AGNOSTIC]

**{{PROJECT_NAME}}** — Stack : {{STACK}}

```
./
├── [structure à documenter]
└── docs/
    ├── scripts/    # relay-check.sh, relay-brief.sh, relay-stats.sh, stale-detector.sh
    ├── context/    # STATE.md, SESSIONS_LOG.md, SESSIONS_ARCHIVE.md, RELAY_PROJECT_DNA.md
    └── rules/      # RELAY_PROTOCOL.md, RELAY_METRICS.md, RELAY_RULE_POOL.md, KNOWN_ISSUES.md
```

---

## 2. ENVIRONNEMENT [À REMPLIR — spécifique au projet]

| Élément | Valeur |
|---|---|
| [Commande run] | `[à remplir]` |
| [Commande build] | `[à remplir]` |
| [Commande test] | `[à remplir]` |

---

## 3. RÈGLES ABSOLUES [À REMPLIR — spécifique au projet]

**[Interdictions spécifiques au projet]**

---

## 4. COMMANDES UTILES [LLM-AGNOSTIC]

```bash
# RELAY — Démarrage session (Senior Brief)
./docs/scripts/relay-brief.sh

# RELAY — Validation NEXT_SESSION.md + Health Score
./docs/scripts/relay-check.sh
./docs/scripts/relay-check.sh --score-only

# RELAY — Métriques projet (vélocité, effort, bugs vs features)
./docs/scripts/relay-stats.sh

# RELAY — Détecter tâches vieillissantes
./docs/scripts/stale-detector.sh
./docs/scripts/stale-detector.sh --auto-mark

# RELAY — Mettre à jour le moteur depuis le canonique
./docs/scripts/relay-update.sh   # si présent, sinon bin/relay-update.sh du canonique
```

---

## 5. RÈGLES MÉTIER [À REMPLIR — spécifique au domaine]

**Domaine :** {{DOMAIN}}
**Acteurs :** {{ACTORS_PIPE}}

[Règles métier par section — ex: §Transactions, §Permissions, §Workflow]

---

## 6. ANCRAGE MÉTIER — Obligatoire avant toute implémentation [LLM-AGNOSTIC]

> **Objectif : être acteur du projet, pas robot.**
> Coder vite une chaîne technique correcte sur une mauvaise fondation ne sert pas l'utilisateur.
> L'ancrage n'est PAS une réflexion mentale — il doit être **écrit dans le TASK[]** avant de coder.

### Questions d'ancrage — pour chaque tâche touchant une logique métier

**1. Acteur réel**
- Quel acteur ({{ACTORS_PIPE}}) déclenche cette action dans la réalité ?
- L'acteur a-t-il *physiquement* accès à cette information dans son workflow quotidien ?
- Si un autre acteur tente d'accéder → 403 explicite / filtre silencieux / redirect ?

**2. Réalité terrain**
- Ce concept existe-t-il réellement dans le domaine "{{DOMAIN}}" ?
- Est-ce conforme aux règles métier documentées (§BUSINESS_RULES ou équivalent) ?

**3. Cas limites obligatoires**
- Que se passe-t-il si les données sont manquantes ou l'état est transitoire ?
- Que se passe-t-il si deux acteurs agissent simultanément sur la même entité ?
- Accès cross-tenant / IDOR si l'app est multi-tenant ?

**4. Matrice permissions** (obligatoire si endpoint multi-acteurs ou logique conditionnelle)

| Action | {{ACTORS_PIPE}} | Code actuel | Écart ? |
|---|---|---|---|
| [action 1] | ? | [code actuel] | [écart] |

Si écart détecté → corriger AVANT de coder.

### Format TASK[] avec ANCRAGE

```
TASK[MON-FEATURE] status=pending effort=M depends=[] owner=session [assumed]
> Description technique de la tâche.
> ANCRAGE:
>   acteur=[qui déclenche cette action]
>   conforme=[référence règle métier §XX ou "non documenté"]
>   permissions=[qui peut / qui ne peut pas + comportement si non autorisé]
>   cas_limite=[comportement si données manquantes ou état invalide]
> # ESCALADE_METIER: [optionnel — question précise si règle métier absente/ambiguë]
> # REPONSE_HUMAINE: [obligatoire si ESCALADE_METIER présent — 1 ligne, débloque le commit]
```

---

## 7. PROTOCOLE DE RELAIS (source : docs/rules/RELAY_PROTOCOL.md)

> Lire NEXT_SESSION.md §Protocole pour le détail complet.

### Règle des 70%
- Lire NEXT_SESSION.md → MRS → Ancrage métier → Exposer plan → Attendre validation → Coder
- Calcul 70% : S(0.5)+M(1)+L(2) pour tâches `owner=session status=pending`
- Ne jamais tenter plus de 2-3 tâches M par session

### MRS
- Pour chaque `[assumed]` / `[stale?]` → grep avant de planifier
- `./docs/scripts/stale-detector.sh` → promotion automatique
- Jamais planifier sur base `[stale?]` non vérifiée

### Fin de session — checklist [LLM-AGNOSTIC]
```
□1 Build → 0 erreur (si code modifié)
□2 relay-brief.sh → Senior Brief mis à jour
□3 STATE.md + SESSIONS_LOG.md mis à jour
□4 §Retour expérience + §Suggestion rédigés
□5 NEXT_SESSION.md §fait/reste/plan mis à jour
□6 relay-check.sh → Health Score ≥ 80
□7 git commit + push
```
