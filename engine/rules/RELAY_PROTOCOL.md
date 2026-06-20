# RELAY_PROTOCOL.md — [LLM-AGNOSTIC]
# Source canonique du protocole de relais. Le fichier d'instructions LLM (CLAUDE.md/SYSTEM.md/…) §7 en est le résumé.
# [ENGINE] Portable — se propage via relay-update.sh. §8 « Spécificités projet » = à remplir localement.

> Ce fichier est la référence ; en cas de divergence, il prime sur le résumé du fichier d'instructions LLM.

---

## 0. But du protocole

Permettre à des sessions LLM successives, **sans mémoire partagée**, de travailler sur le même projet
brownfield comme une équipe stable : reprendre l'état réel, ne rien casser, ne pas réinventer, et laisser
le projet dans un état où la session suivante repart en < 10 min.

Le support unique de passation est **`NEXT_SESSION.md`** (≤ 200 lignes, idéal ≤ 130). Tout le reste
(`STATE.md`, `SESSIONS_LOG.md`, `KNOWN_ISSUES.md`, ce fichier) est consulté **à la demande**, jamais chargé en entier.

---

## 1. MRS — Memory Reconciliation Step (à l'ouverture)

Le projet est brownfield non audité : ce qu'une session précédente a écrit peut avoir vieilli.

Niveaux de confiance :
| Niveau | Signification |
|---|---|
| `[verified-run]` | **comportement runtime observé** OU **test exécuté** cette session (le plus fort) |
| `[verified-build]` | confirmé par compile / grep / lecture statique cette session — **pas** d'exécution du chemin |
| `[verified]` | **alias historique de `[verified-run]`** (rétro-compat, zéro churn) — preuve runtime |
| `[assumed]` | hérité d'une session précédente, non revérifié cette session |
| `[stale?]` | hérité depuis > 2 sessions sans vérification |
| `[external]` | état système externe non vérifiable par grep (build, DB, déploiement) |

> **Pourquoi scinder `[verified]` (*verified-by-run*)** : « prouvé par build » ≠ « prouvé par run ».
> Un fix sécurité (ex. IDOR) lu + compilé n'est **pas** prouvé tant que l'attaque n'a pas été jouée
> (le comportement attendu — 404, 403… — n'est jamais observé si l'environnement runtime n'est pas
> câblé). `[verified-build]` rend cette limite **explicite** au lieu de la masquer sous `[verified]`.
> **Backward-compat** : tout `[verified]` legacy reste valide = `[verified-run]` (pas de migration).
> Pour un **fix sécurité marqué corrigé**, `[verified-run]` est attendu — sinon `relay-check.sh` le
> signale « build-only ».

Procédure :
1. Pour chaque `[assumed]`/`[stale?]`/`[external]` cité dans le plan → exécuter le grep/find/build de vérification.
2. Promouvoir → `[verified]`, ou marquer `[stale? → absent]` si la chose a disparu.
3. **Ne jamais planifier de travail sur une base non vérifiée.**
4. `./docs/scripts/stale-detector.sh` aide à repérer les tâches vieillissantes.

> **Règle « MRS d'import »** : à l'amorçage depuis un projet jumeau (RELAY copié depuis un autre repo),
> tout fait hérité du jumeau est `[assumed-cross-project]` et doit être re-vérifié sur CE code avant usage.
> Une hypothèse vraie sur le projet source peut être fausse sur le nouveau.

---

## 2. Règle des 70 %

Le contexte LLM est fini. On en réserve 30 % pour la clôture documentaire propre.

1. Lire `NEXT_SESSION.md` (section courante) — max 10 min.
2. MRS → ajuster les tâches.
3. Ancrage métier (§4) pour les tâches à logique métier.
4. **Estimer** : S = ~30 min (0.5 pt) · M = ~1 h (1 pt) · L = ~2 h+ (2 pts). Additionner les tâches
   `owner=session status=pending`. **Viser ≤ 2-3 pts** → annoncer un `BUDGET SESSION` explicite.
   > **Mécanisé** (Scope-Creep Alert, `relay-check.sh §10`, v1.12.0) : `relay-check` somme l'effort des
   > `TASK[]` **retenables** (`pending`+`owner=session`+`depends=[]`) et émet un WARNING signal-only si le
   > total dépasse le budget (défaut **3.5 pts**, surcharge `RELAY_SCOPE_BUDGET`). Un backlog **bloqué**
   > ne déclenche pas (≠ creep). Détail → `CHANGELOG [1.12.0]`.
5. **Exposer le plan → attendre « go » explicite avant de coder.**
6. Coder dans l'ordre strict des priorités.
7. Sauvegarder `NEXT_SESSION.md` après **chaque** tâche terminée.

---

## 3. Format des tâches

```
TASK[ID] status=pending|done effort=S|M|L depends=[ID,...] owner=session|user|external [verified|assumed|stale?|external]
> Description technique.
> ANCRAGE: acteur=... conforme=[§ref ou "non documenté"] permissions=... cas_limite=...   ← si logique métier
> # ESCALADE_METIER: [question métier précise]   ← si règle absente/ambiguë
> # REPONSE_HUMAINE: [réponse 1 ligne]            ← obligatoire si ESCALADE_METIER présent
```

- `done` → barrer la ligne `~~TASK[...]~~` et y inscrire le hash de commit (vérifié par `relay-check.sh`).
- `depends=[X]` non vide → tâche bloquée, l'ancrage peut attendre le déblocage.

---

## 4. Ancrage métier (Pilier — anti-robot)

Avant toute implémentation à logique métier, écrire dans le `TASK[]` :
1. **Acteur réel** — qui déclenche, a-t-il accès dans son workflow ?
2. **Réalité terrain** — concept réel du domaine ? conforme aux docs métier ?
3. **Cas limites** — données manquantes, concurrence, **accès cross-tenant / IDOR** si multi-tenant.
4. **Matrice permissions** si endpoint multi-acteurs.

`relay-check.sh` **bloque** le commit si une tâche `owner=session` débloquée contient des mots-clés
métier sans bloc `ANCRAGE:`.

### 4b. Ancrage sécu SÉLECTIF (rôle cybersécurité — Couches 2 & 4)

Le LLM est la couche faible : on ne lui demande **pas** de juger sa propre sécurité en permanence (excès
de confiance + inflation de tokens). À la place, un **grep déterministe** (`[security_surface]` de
`rules.conf`) détecte quand le diff touche une **surface sensible** (authN, authZ/IDOR, secrets, crypto,
SQL, upload, désérialisation). `relay-check.sh` (§9b) émet alors **un avertissement signal-only** invitant
à charger la checklist **`docs/rules/SECURITY_RULES.md`** et à écrire `SECURITY_ANCHOR:` dans le `TASK[]`.

- **Sélectif = token-négatif** : la checklist n'est chargée **que** si la surface est touchée — jamais en
  permanence. Le grep fait gratuitement le tri que le LLM ferait en lisant.
- **WARNING, pas bloquant** : la détection de surface est heuristique (faux positifs) → elle guide, ne gate
  pas. Le verdict reste humain. *(Le gate dur, lui, est la Couche 1 `[security_forbidden]` — secrets évidents.)*
- **Lucidité** : gate commit/CI, **pas** un IDS/WAF runtime ; ne remplace pas un pentest.
- **Couche 4 — auto-feed (mémoire des patterns)** : après avoir corrigé une faille (un finding sécu de
  `KNOWN_ISSUES.md` passé `✅ RÉSOLU`), enregistre **un pattern concret appris** dans la section
  `Patterns appris` de `SECURITY_RULES.md`, pour que la session suivante ne le réintroduise pas.
  `relay-check.sh` (§9c) le rappelle par un WARNING signal-only si le fix sécu atterrit sans pattern
  enregistré ; le déclencheur est déterministe, la puce reste **curatée** (jamais auto-écrite).

### 4c. Trace des décisions architecturales (rôle « Architecte connaissance »)

Une **décision archi** (nouvelle dépendance, nouveau projet, nouvelle interface/abstraction, câblage DI)
est souvent prise **implicitement** dans un commit, sans être tracée → la connaissance se perd (*pourquoi*
ce choix, *quelles alternatives rejetées*, *sous quelle condition réviser*). Même famille de trigger que
§4b : un **grep déterministe** (`[decision_surface]` de `rules.conf`) détecte un changement structurel dans
le diff stagé ; si **aucune** entrée `## DEC-` n'a été ajoutée à `docs/context/DECISIONS.md` dans le même
commit, `relay-check.sh` (§11) émet **un WARNING signal-only** « trace cette décision ».

- **Signal-only, calibration étroite** : l'architecture est un jugement → le déterministe **rappelle**,
  l'humain **décide** et **rédige** la décision (jamais auto-écrite). Les marqueurs excluent la routine
  (migration, test, refacto) pour éviter le bruit. **Token-négatif** (grep, miroir §9b/§9c).

---

## 5. Escalade métier (Pilier 9)

Si une règle métier est absente/ambiguë dans la doc : poser `ESCALADE_METIER:` dans le `TASK[]` et
**s'arrêter**. Le commit reste bloqué tant que `REPONSE_HUMAINE:` n'est pas renseignée. On ne devine pas une
règle métier sensible (paie, congé, facturation, sécurité…).

---

## 6. Clôture de session — checklist obligatoire

```
□1 Build → 0 erreur (commande build du projet)   si code modifié
□2 relay-brief.sh → Senior Brief à jour
□3 STATE.md + SESSIONS_LOG.md mis à jour
□4 §Retour expérience + §Suggestion amélioration rédigés (1 amélioration OU 1 règle retirée — anti-inflation)
□5 NEXT_SESSION.md §fait / §reste / §plan à jour, et ≤ 200 lignes (archiver dans SESSIONS_ARCHIVE.md si besoin)
□6 relay-check.sh → Health Score ≥ 80
□7 git commit (+ push si l'user le demande)
□8 si bump VERSION (canonique uniquement) → entrée CHANGELOG.md ajoutée (Keep a Changelog)
```

> **□8 ne concerne que le dépôt canonique RELAY** : tout bump de `VERSION` doit s'accompagner d'une
> entrée `CHANGELOG.md` (source unique du delta affiché par `relay-update.sh --check` aux consommateurs).
> Les projets consommateurs ne bumpent pas `VERSION` (ils la reçoivent par propagation) → □8 = N/A.

---

## 7. Anti-inflation (Pilier 11)

Chaque §Suggestion ajoute **au plus une** règle, OU en retire/fusionne une. `relay-check.sh --density`
mesure le ratio règles-univers / règles-récentes : une règle « dormante » est soit un garde-fou silencieux
(à garder), soit une règle situationnelle oubliée (à retirer) — décision humaine, jamais automatique.

### 7.1 Pool « candidat » — promotion sur 2ᵉ déclencheur (human-gated)

> **Problème résolu** : « au plus une règle par §Suggestion » n'empêche pas une règle d'entrer dès le
> **1ᵉʳ** cas vécu (une règle née d'un seul incident). Une règle situationnelle d'une session unique
> peut s'auto-promouvoir en règle du ruleset. Le pool impose un **2ᵉ déclencheur indépendant**.

**Cycle de vie d'une règle versionnée `vN.N` :**

1. **Candidate** (`trigger-count=1`) — toute §Suggestion entre ici, **jamais** directement au ruleset
   actif. Elle reste un *acquis de session* tant qu'un seul cas la justifie.
2. **Promotion** — une candidate ne rejoint le **ruleset actif** (= règle formalisée dans ce protocole,
   §1-§8) qu'à la réunion de **deux conditions** :
   - **2ᵉ déclencheur indépendant** : un second finding/cas vécu dans **une autre session** (ou un autre
     contexte) confirme le besoin — pas une re-citation du même cas.
   - **+ confirmation humaine explicite** : la vision RELAY **interdit l'auto-promotion**. Aucun script
     ne promeut ; seul un humain valide le passage candidate → ruleset.
3. **Retrait/fusion** — orthogonal (cf. jauge de densité ci-dessus) : décision humaine, jamais auto.

**Pool des candidates** (registre) → `docs/rules/RELAY_RULE_POOL.md`. Chaque entrée :
`vN.N | trigger-count=N | sessions=[…] | statut=candidate|promue | résumé`.

**Garde `--density`** : `relay-check.sh --density` émet un **warning** (exit 0, **jamais** bloquant) si
un `vN.N` est cité comme **règle du ruleset actif** (présent dans `RELAY_PROTOCOL.md` §1-§8) **sans**
entrée `promue` correspondante dans le pool. C'est un signal « règle entrée sans franchir le pool »,
pas un enforcement — la décision reste humaine.

---

## 8. Spécificités projet → fichier d'instance (PAS ici)

> Ce protocole (§0-§7) est **100 % portable** et entièrement propagé par `relay-update.sh`.
> Les particularités du projet courant (repos mono/multi, stack, priorités absolues) vivent dans
> **`docs/context/RELAY_PROJECT_DNA.md`** (instance, jamais propagé) — **jamais dans ce fichier**,
> afin que la propagation du moteur n'écrase aucune donnée de projet.
>
> Rappel `relay-check.sh` : mono-repo → `--strict` sans `--companion-repo` ; multi-repo →
> `--companion-repo=<path>` (hash commits du 2ᵉ repo).
