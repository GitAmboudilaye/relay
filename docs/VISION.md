# RELAY Framework — Vision & Feuille de Route
> Document de référence pour toutes les sessions contribuant à l'évolution de RELAY
> Basé sur les échanges d'analyse et d'évaluation du 2026-06-09
> Implémentation : Claude Code. Ce document : vision et orientation uniquement.

---

## Positionnement officiel

> La plupart des outils IA résolvent : **"Comment rendre le modèle plus intelligent ?"**
> RELAY résout : **"Comment rendre le projet plus mémorisable ?"**

> **RELAY = un système de gouvernance permettant à plusieurs IA et à un humain de collaborer sur un même projet pendant des mois sans perdre le contexte métier.**

---

## Évaluation de référence

**Note par rapport à l'objectif réel : 8.5 — 9/10**

L'objectif de RELAY n'est pas de remplacer totalement l'humain. Son objectif est de permettre à un ou plusieurs LLMs de collaborer sur un projet complexe pendant des mois, en conservant l'architecture, les décisions, les règles métier, l'historique et la continuité. Par rapport à cet objectif, RELAY est déjà très avancé.

**La vraie innovation n'est pas un fichier ou un script pris individuellement. C'est la combinaison :**

```
Décision → Documentation → Validation → Transmission → Reprise
```

C'est ce cycle complet qui constitue une mémoire projet. Aucune alternative existante ne couvre les cinq étapes de façon intégrée et vérifiable.

**Preuve terrain — AgriConnect :**
Plus de 50 sessions sur un projet multi-stack (Flutter, ASP.NET Core, SaaS Web, marketplace, QR, AgriScore, tarifications, stock, livraisons, notifications, multi-tenant, abonnements) avec des règles métier qui évoluent au contact du terrain — le pire scénario pour un LLM. Résultat : pas de réécriture majeure, peu de régressions, architecture conservée, continuité métier maintenue.

> Un développeur seul, bien organisé et assisté par des IA, peut désormais construire un produit qui demandait auparavant une petite équipe. C'est la validation la plus forte que RELAY a obtenue.

---

## 1. Qu'est-ce que RELAY ?

### Définition courte (30 secondes)
RELAY est un protocole open source qui permet à un LLM de reprendre un projet complexe exactement là où il l'a laissé — sans perdre le contexte, sans recoder ce qui existe déjà, sans oublier les décisions prises. C'est la mémoire structurée et vérifiable d'un projet de développement entre les sessions.

### Définition technique (pour un développeur)
Quand tu travailles sur un projet complexe avec un LLM, chaque nouvelle session repart de zéro. Le LLM ne sait plus ce qui est fait, ce qui est en cours, pourquoi tel choix architectural a été fait. RELAY résout ça avec des fichiers markdown versionnés dans git, des scripts de validation qui bloquent le commit si la documentation n'est pas à jour, et un système de niveaux de confiance qui distingue ce qui est vérifié de ce qui est peut-être obsolète. Pas de base de données, pas d'infrastructure — juste git et bash.

### Définition grand public
Imagine que tu travailles avec un expert consultant sur un projet très complexe. Chaque fois qu'il revient, il a tout oublié — tu dois tout réexpliquer depuis le début. RELAY c'est le carnet de bord structuré que cet expert lit en arrivant et met à jour en partant — pour que la prochaine session reparte exactement là où on s'est arrêté, sans perte.

### La phrase qui résume tout
> RELAY ne rend pas le LLM plus intelligent. Il l'empêche de devenir amnésique sur la durée.

---

## 2. Pourquoi RELAY existe — Le problème réel

### Le cold-start LLM
Sur un projet simple, perdre le contexte entre sessions est gérable. Sur un projet complexe avec 3 stacks, des règles métier légales, des dépendances entre features et des décisions architecturales qui datent de 15 sessions — c'est là que tout casse.

### RELAY vs un bon CLAUDE.md — Le delta réel

| Période | Delta RELAY vs CLAUDE.md seul | Raison |
|---|---|---|
| Sessions 1-15 | ~20% | CLAUDE.md statique couvre l'essentiel |
| Sessions 20-50 | ~45% | CLAUDE.md diverge de la réalité sans mécanisme de mise à jour |
| Sessions 50-200+ | ~65% et s'accélère | Trois problèmes structurels irréductibles |

**Les trois problèmes structurels qu'un CLAUDE.md ne peut pas résoudre :**

1. **Le fichier grossit ou se dégrade** — après 50 sessions, soit il est énorme (coût token élevé), soit il a été élagué et est devenu partiel. RELAY a `relay-split.sh`, l'archivage automatique, `NEXT_SESSION.md` ≤ 200 lignes.

2. **Les décisions architecturales s'accumulent sans traçabilité** — `DECISIONS.md` + `RELAY_PROJECT_DNA.md` capturent le *pourquoi*, pas juste le *quoi*. Sans protocole de mise à jour obligatoire, cette section est absente ou obsolète après 100 sessions.

3. **Les assertions vieillissent sans signal** — un CLAUDE.md à la session 150 peut contenir des affirmations vraies à la session 30. RELAY a `[verified]` / `[assumed]` / `[stale?]` avec datation git. C'est la différence entre "je me souviens que X était vrai" et "je sais quand X a été vérifié pour la dernière fois".

### L'insight central
> La vraie différence entre RELAY et un bon CLAUDE.md n'est pas ce que le LLM lit. C'est ce que le développeur est **contraint d'écrire** après chaque session. RELAY compense la dégradation naturelle de la discipline humaine avec de l'outillage — `relay-check.sh` bloque le commit si la clôture n'est pas faite.

---

## 3. Ce qui différencie RELAY de toutes les alternatives

| Approche | Mémoire | Enforcement | Vérifiabilité | Ancrage métier | Coût infra |
|---|---|---|---|---|---|
| RAG / mem0 | Riche | Aucun | Aucune | Non | Élevé |
| CLAUDE.md seul | Statique | Aucun | Aucune | Non | Nul |
| TokenMizer | Graphe | Proxy | Aucune | Non | Moyen |
| /compress-session | Ad hoc | Aucun | Aucune | Non | Nul |
| **RELAY** | Structurée | Git hook | Hash git | Oui | Nul |

**La contribution conceptuelle originale de RELAY :** `[verified hash:abc1234]` vs `[stale?]` — aucune solution existante ne distingue une assertion vraie d'une assertion obsolète avec preuve cryptographique dans le fichier de contexte.

---

## 4. Principe fondamental — Optimisation des tokens avant tout

> **RELAY doit optimiser l'utilisation des tokens LLM, pas l'augmenter.**

C'est un principe de conception non négociable. Chaque règle, chaque fichier, chaque mécanisme de RELAY doit être évalué à cette aune :

- `NEXT_SESSION.md` ≤ 200 lignes — contexte dense et actuel, pas exhaustif
- `relay-split.sh` et archivage automatique — le LLM ne lit jamais plus que nécessaire
- MRS ciblé — grep avant de lire, lire avant de planifier, planifier avant de coder
- Règle 70% — sessions courtes et complètes, pas longues et incomplètes

Un RELAY qui augmente la consommation de tokens pour "mieux se souvenir" est un RELAY qui a échoué dans sa mission.

---

## 5. Les rôles actuels de RELAY dans le cycle de développement

### Rôle 1 — Chef de projet technique (7/10 aujourd'hui)
Maintient le backlog, séquence les tâches, estime les efforts, gère les dépendances, s'assure que rien ne se perd entre les sessions.

**Chemin vers 9.5/10 :**
- `relay-forecast.sh` — projette "à ce rythme, le projet finit dans X sessions" basé sur l'historique réel
- Alerte scope creep automatique — si tâches ajoutées / tâches fermées > 1.5 sur 5 sessions, alerte déclenchée

### Rôle 2 — Scrum Master (8/10 aujourd'hui — rôle le plus fort)
Enforce le processus — règle 70%, clôture obligatoire, MRS avant de planifier. `relay-check.sh` refuse le commit si le protocole n'est pas respecté. Ne fatigue jamais.

**Chemin vers 9.5/10 :**
- Détection de dérive en cours de session — pas seulement au commit
- Vélocité prédictive intégrée au health score

### Rôle 3 — Architecte de la connaissance (6/10 aujourd'hui)
Capture pourquoi les décisions ont été prises via `RELAY_PROJECT_DNA.md` + `DECISIONS.md`. Le rôle le plus difficile à faire progresser car il demande du jugement.

**Chemin vers 9.5/10 :**
- Trigger décision implicite — tout commit touchant un fichier d'architecture déclenche : "cette modification invalide-t-elle une décision dans DECISIONS.md ?"
- Graphe de dépendances des décisions — si D3 dépend de D1 et D1 change, alerte automatique

### Rôle 4 — Auditeur qualité (7/10 aujourd'hui)
`relay-check.sh` joue le rôle du QA gate au commit. Fort sur les patterns connus, limité sur les bugs nouveaux.

**Chemin vers 9.5/10 :**
- Regression Shield auto-alimenté — chaque bug corrigé génère automatiquement un pattern dans `KNOWN_ISSUES.md` depuis les commits de correction, sans intervention manuelle

---

## 6. Règle anti-inflation — Non négociable

> ✅ **Implémentée le 2026-06-11** — Pilier 11 (RELAY_PROTOCOL.md). Règle clôture changée, jauge de densité
> ajoutée à `relay-check.sh --density`, pruning signal-only. 1ère mesure : ratio 1.36 🟡. Détail : RELAY_METRICS.md §5.

Observé à la session 49-50 : v4.2 puis v4.3 en deux sessions consécutives. La règle "1 amélioration obligatoire par session" fabrique des règles.

**Correction implémentée dans `TASK[RELAY-ANTI-INFLATION]` :**

1. Remplacer "1 amélioration **obligatoire**/session" par "1 amélioration **OU** 1 règle retirée/fusionnée" — force la consolidation, stoppe l'inflation de versions

2. Ajouter au health score une métrique **densité** = règles actives / règles réellement déclenchées sur les 10 dernières sessions. Une règle jamais déclenchée est candidate au retrait.

> Le correctif à un problème d'inflation ne doit pas être appliqué de façon inflationniste.

---

## 7. Configuration de départ pour un nouveau projet

### Principe
`relay-init.sh` génère automatiquement RELAY sur un nouveau projet sans grande configuration. Le développeur ajoute uniquement son contexte projet. Les anti-patterns universels sont embarqués dès le départ.

### Fichiers de configuration fondamentaux à ancrer dès le départ

Pour que RELAY joue pleinement ses rôles sur toute la durée du projet, ces fichiers doivent être configurés à l'initialisation :

**Architecture logicielle**
```
RELAY_PROJECT_DNA.md    — stack, patterns, conventions absolues du projet
BACKEND_ARCHITECTURE.md — couches, dépendances, règles de structure
FRONTEND_ARCHITECTURE.md — si applicable
DECISIONS.md            — décisions architecturales + raisons + date
```

**Règles métier**
```
BUSINESS_RULES.md       — règles métier non négociables (légales, domaine, client)
ESCALADE_METIER.md      — qui valide quoi avant implémentation
```

**Design system**
```
DESIGN_SYSTEM.md        — tokens, composants, conventions UI/UX
                          (si Flutter : thème, couleurs, typographie, spacing)
                          (si Web : CSS variables, composants, breakpoints)
```

**Sécurité**
```
SECURITY_RULES.md       — règles de sécurité absolues du projet
                          (authentification, autorisation, données sensibles)
                          alimenté automatiquement par chaque correction de sécurité
```

**Anti-patterns**
```
KNOWN_ISSUES.md         — anti-patterns universels (hérités de relay-init.sh)
                        + anti-patterns projet (découverts en session)
```

### Protocole de démarrage de session — Inchangé
```
Lis NEXT_SESSION.md et applique le protocole.
```
RELAY sait quels fichiers lire selon le contexte. Le développeur n'a pas à spécifier.

---

## 8. Rôles futurs crédibles

### Court terme (après AgriConnect stabilisé)

**Gestionnaire de dette technique**
RELAY a déjà toutes les données dans `SESSIONS_LOG`, `KNOWN_ISSUES`, et l'historique git. Il manque un mécanisme qui agrège et priorise automatiquement ce qui se dégrade. `relay-debt.sh` — rapport de dette classé par ancienneté et fréquence d'apparition.

**Onboarder / Knowledge Transfer**
`relay-onboard.sh` génère un document "état du projet en 10 minutes" pour un nouveau développeur ou un nouveau LLM arrivant sans contexte. Ce que les équipes paient des consultants seniors pour faire.

### Moyen terme

**Gestionnaire de release**
`relay-release.sh` agrège les tâches `done` depuis le dernier tag git et génère un changelog structuré par version. RELAY trace déjà tout — la distance est courte.

**Mentor de développeur junior**
Un développeur junior qui rejoint un projet RELAY démarre avec toutes les leçons apprises encodées. Avec un mécanisme "pourquoi cette règle existe", c'est de la formation passive intégrée au projet.

### Long terme

**Compliance officer technique**
Dans des domaines régulés (finance, santé, agriculture subventionnée), `COMPLIANCE.md` + checks automatiques sur les patterns réglementaires. Garde-fou légal automatisé intégré au commit.

---

## 9. Positionnement dans l'écosystème

### Le trou que RELAY occupe
Les outils LLM existants se répartissent en deux catégories :
- **Génération** — GitHub Copilot, Cursor, Claude Code
- **Mémoire** — mem0, RAG, memory files natifs

Personne n'occupe sérieusement : **la gouvernance du processus de développement sur la durée**. C'est l'espace de RELAY.

### La valeur par niveau d'utilisateur

**Développeur solo**
RELAY est le chef de projet, le Scrum Master, l'architecte et l'auditeur que le développeur solo n'a pas les moyens de payer. Démocratisation d'une rigueur réservée aux équipes avec budget.

**Petites équipes**
Quand deux développeurs travaillent sur le même projet avec des LLMs différents, RELAY est le protocole commun qui garantit que les deux LLMs ont le même contexte, les mêmes règles, les mêmes anti-patterns. Coordination sans réunion.

**Entreprise**
La rotation d'équipe détruit le contexte à chaque départ. RELAY transforme la connaissance tacite en connaissance explicite et vérifiable dans git. Rétention de savoir institutionnel automatisée.

**Communauté open source**
Standard de gouvernance LLM pour projets multi-contributeurs et multi-LLMs.

### Le fossé défensif face aux plateformes
Les grandes plateformes (Anthropic, OpenAI, GitHub) travaillent sur la mémoire native cross-session. Si dans 18 mois cette mémoire est parfaite, une partie de la valeur de RELAY diminue.

Ce qui ne disparaît pas : **l'enforcement mécanique, la vérifiabilité git, et l'ancrage métier**. Ces trois éléments répondent à un problème de gouvernance, pas de mémoire. Un LLM avec mémoire parfaite mais sans RELAY peut toujours prendre de mauvaises décisions métier sans validation humaine explicite.

### Phrase de positionnement (horizon 2 ans)
> RELAY est le système d'exploitation du développement logiciel assisté par LLM — il ne remplace pas le développeur, il structure tout ce qui entoure le développement pour que le LLM reste utile, rigoureux et cohérent sur la durée.

### Le positionnement dans une organisation logicielle moderne

| Rôle traditionnel | Ce que RELAY fait |
|---|---|
| Chef de projet technique | Maintient le plan et les priorités |
| Architecte mémoire | Préserve les décisions importantes |
| Scrum Master | Prépare et clôture chaque session |
| Knowledge Manager | Centralise le savoir du projet |
| QA Process | Vérifie le respect du protocole au commit |
| Technical Writer | Génère la documentation de continuité |
| Agent de transmission | Assure le relais entre LLMs et sessions |

**Titre émergent le plus précis :**
> **AI Development Coordinator** — organise le travail des IA, préserve le contexte métier, garantit la continuité entre sessions, réduit les régressions, permet le changement de modèle sans perte de connaissance.

**Dans 5 ans, la question que tout le monde posera :**
> "Comment faire collaborer plusieurs modèles et plusieurs humains sur le même projet pendant 2 ans ?"
RELAY est déjà une réponse à cette question.

---

## 10. Vision communauté et site web

### Principe de la communauté
RELAY doit être perfectionné progressivement par sa communauté, quelle que soit la technologie, l'architecture logicielle, le domaine métier ou le niveau de sécurité requis. La communauté est le mécanisme d'enrichissement des anti-patterns universels.

### Ce que la communauté contribue
- **Anti-patterns par stack** — Node.js, Python/Django, Ruby on Rails, etc.
- **Anti-patterns par domaine** — fintech, santé, e-commerce, agriculture, etc.
- **Anti-patterns par architecture** — microservices, monolithe, serverless, etc.
- **Adaptations multi-LLM** — DeepSeek, GPT-4, Gemini, Mistral, etc.
- **Scripts complémentaires** — extensions de `relay-check.sh`, nouveaux `relay-*.sh`

### Structure du site web dédié

**Accueil**
- Définition en 30 secondes
- La courbe delta (20% → 45% → 65%) visualisée
- Démarrage en 5 minutes avec `relay-init.sh`

**Documentation**
- Guide complet par stack (ASP.NET, Node.js, Python, etc.)
- Guide par LLM (Claude Code, DeepSeek, GPT, etc.)
- Référence des fichiers RELAY et leur rôle
- FAQ anti-patterns

**Communauté**
- Bibliothèque d'anti-patterns contributifs — filtrés par stack / domaine / LLM
- Galerie de projets RELAY avec métriques publiées (sessions, health score, ROI estimé)
- Forum de discussion sur les cas limites et décisions de protocole

**Métriques publiques**
- Health Score moyen de la communauté
- Anti-patterns les plus déclenchés par stack
- Vélocité moyenne par type de projet

### Question ouverte sur le code source
La question du code source complet disponible à la communauté n'est pas tranchée dans ce document — c'est une décision stratégique qui appartient au créateur de RELAY. Les options possibles :

- **Open source complet** — adoption maximale, contribution maximale, monétisation indirecte (services, support, formation)
- **Core open source + extensions premium** — modèle hybride, communauté active + revenus directs
- **Protocole ouvert + implémentation propriétaire** — RELAY comme standard, l'outil comme produit

Cette décision doit être prise avant la publication, avec son propre ancrage sur les objectifs de valorisation à court et long terme.

---

## 11. Évaluation honnête — État actuel vs potentiel

### Scores actuels (basés sur 50+ sessions, 1 projet, 1 développeur)

| Rôle | Score actuel | Potentiel | Bloqueur principal |
|---|---|---|---|
| Scrum Master | 8/10 | 9.5/10 | Enforcement in-session |
| Chef de projet | 7/10 | 9.5/10 | Gestion risques externes |
| Auditeur qualité | 7/10 | 9.5/10 | Patterns auto-appris |
| Architecte connaissance | 6/10 | 9.5/10 | Détection décisions implicites |

**Note globale honnête :**
- Qualité intrinsèque du protocole comme artefact : **7.5/10**
- Preuve de généralisation : **5/10** *(2026-06-25 — relevée de 4/10 par l'examen cross-LLM DeepSeek, voir ci-dessous)*

### Preuve de généralisation 4/10 → 5/10 — l'examen cross-LLM DeepSeek (2026-06-25)
Le second test annoncé (« le projet RH avec DeepSeek ») **a eu lieu** : un lot de sessions Cline+DeepSeek sur un projet RH brownfield, examinées en croisant **les logs (écrits par DeepSeek) contre le git réel** (examen interne, non publié).

- **Ce qui monte le score (portabilité prouvée)** : DeepSeek, **sans coaching**, adopte le format `NEXT_SESSION.md`, exécute le MRS, et produit une vraie architecture DDD/Strangler Fig. Le protocole **se transmet** à un LLM non-Claude — c'est le fait neuf qui justifie +1.
- **Ce qui plafonne à 5 et pas 7 (thèse cassée)** : « ne pas croire le log sur parole » a révélé qu'un module entier déclaré « fait » sur ~10 sessions n'avait **jamais été committé** (des dizaines de fichiers restés untracked). Le gate `relay-check` **ne mord qu'au commit** → rendu **inerte par omission**, sans même un `--no-verify`. La thèse « l'enforcement passif compense la discipline » **ne tient pas** : un LLM peut produire hors-git et le gate ne le voit jamais.
- **Caveat décisif** : le hook **actif** Cline n'a été câblé qu'**après** ces sessions → cet examen ne teste que la couche **passive**. Le cas DeepSeek est donc le **meilleur argument empirique POUR la couche active** et fait émerger un besoin neuf : une **garde de clôture d'état-git** (R1, feuille de route §12).

### Ce qui ferait passer la preuve de 5/10 à 7/10
Mesurer un **avant/après hook actif** sur un LLM non-Claude (la couche active était absente du test DeepSeek) ; et qu'un développeur **tiers** (pas l'auteur) tienne 5 sessions conformes sans coaching. Tant que l'auteur reste le seul opérateur, le plafond structurel est ~5-6.

### Les limites architecturales non réductibles
1. **Enforcement in-session** — RELAY ne peut pas forcer le LLM pendant qu'il travaille. MRS, ANCRAGE, règle 70% s'appliquent avant le premier `git add`. Repose sur la discipline du LLM en cours de session.
2. **Compliance-by-convention** — `relay-check.sh` bloque au commit, pas pendant. 80% du protocole s'auto-applique ou ne s'applique pas.
3. **Qualité dépendante du LLM** — RELAY structure le processus mais ne compense pas un LLM qui raisonne mal sur les hypothèses risquées.

---

## 12. Feuille de route priorisée

> **Mise à jour 2026-06-25.** Trois jalons majeurs depuis la v1.15.0 :
> 1. **La couche « RELAY actif » est LIVRÉE et câblée** (canonique **v1.23.0**) — 3 adaptateurs temps-réel publics, **tous branchés sur un consommateur réel** : hook Claude Code + git pre-commit/CI (no-agent) → AgriConnect ; hook Cline → DeepManagment. Détail → [`RELAY-CORE-ACTIF.md`](RELAY-CORE-ACTIF.md) + [`RELAY-CAPABILITIES.md`](RELAY-CAPABILITIES.md).
> 2. **L'examen cross-LLM DeepSeek est fait** (examen interne ; preuve 4/10→5/10, §11). Il a fait émerger **R1**.
> 3. **R1 — garde de clôture d'état-git est LIVRÉ** (v1.23.0, `relay-uncommitted-guard.sh`) — ferme le trou « produit hors-git » révélé par l'examen DeepSeek (ci-dessous).

### Priorité 1 — AgriConnect en production ✅ FAIT
Prod alignée au code local (PROD-UPGRADE, 3 surfaces), domaine `ecoagriconnect.com` LIVE (TLS, Azure B1), marque EcoAgriConnect/VraiKilo/AgriScore déployée. Reste = décisions user (paiement, query-filter, lancement) — hors RELAY.

### Priorité 2 — Second projet pilote (projet RH) ✅ FAIT (partiel)
- RELAY appliqué sur projet existant à dette technique (`DeepManagment`/GPEntreprises) ✅
- Testé avec **DeepSeek** comme LLM alternatif (via Cline) ✅ — examen cross-LLM fait (§11, examen interne non publié)
- **Verdict** : portabilité du protocole prouvée ; thèse « l'enforcement passif compense la discipline » cassée → motive la couche active. **Reste** : mesurer l'avant/après **hook actif** sous DeepSeek (le test n'a porté que sur le passif).

### Priorité 2bis — R1 : garde de clôture d'état-git ✅ FAIT (v1.23.0, issu de l'examen DeepSeek)
Le trou révélé chez DeepSeek (produit hors-git → gate au commit inerte par omission) appelait un garde-fou neuf : **`git status --porcelain` vide = condition de clôture**, outillé par **`relay-uncommitted-guard.sh`** lançable aussi en CI. Ferme exactement ce trou : un LLM ne peut plus déclarer « fait » en laissant des fichiers untracked. **Livré v1.23.0** — portée porcelain littéral (untracked + modifiés + stagés ; gitignorés exclus), bloquant `exit 1` par défaut (`--warn` signal-only, `--json`), fail-open outillage / fail-closed finding, propagé via `relay-init`, step CI miroir (décisions de conception tranchées user `AskUserQuestion`).

### Priorité 3 — RELAY-ANTI-INFLATION (après AgriConnect)
- Remplacer règle "1 amélioration obligatoire" par "1 amélioration OU 1 retrait"
- Ajouter métrique densité au health score
- Instrumenter `relay-check.sh` pour capturer l'historique de déclenchement

### Priorité 4 — Publication open source
- Nettoyer `relay-init.sh` des références AgriConnect/chemins locaux
- Séparer anti-patterns universels vs anti-patterns projet dans `KNOWN_ISSUES.md`
- Rédiger README avec courbe delta + getting started
- Publier sur GitHub avec `RELAY-EVALUATION` comme preuve terrain
- Article DEV.to / Medium basé sur l'évaluation existante

### Priorité 5 — Rôles vers 9.5/10
- `relay-forecast.sh` (Scrum Master)
- Alerte scope creep (Chef de projet)
- Trigger décision implicite (Architecte connaissance)
- Regression Shield auto-alimenté (Auditeur qualité)

### Priorité 6 — Trois axes d'évolution structurels

**Axe 1 — CI/CD connecté à RELAY (court terme, haute valeur)**
Aujourd'hui le LLM dit "c'est terminé" et RELAY le prend en compte. Demain : build OK + tests OK + migration OK = RELAY autorise la clôture. Moins de confiance implicite, plus de preuves mécaniques. Implémentation : GitHub Actions + `relay-check.sh`. Quelques lignes de YAML — l'évolution la plus rapide et la plus impactante disponible.

**Axe 2 — Mémoire métier structurée / ADR métier (moyen terme)**
Passer de `DECISIONS.md` monolithique à `DECISION_001.md`, `DECISION_002.md` avec références croisées. Quand une décision change, toutes les décisions dépendantes sont immédiatement identifiées. `relay-init.sh` génère le template, `relay-check.sh` vérifie que toute décision architecturale crée un fichier ADR. Pattern inspiré des Architecture Decision Records, étendu au domaine métier.

**Axe 3 — Multi-agents (long terme — après validation single-agent multi-LLM)**
La vision finale :
```
Agent Architecture
Agent Backend
Agent Flutter
Agent Audit
Agent Documentation
        ↓
      RELAY
        ↓
  Humain métier
```
Une véritable équipe virtuelle coordonnée par RELAY. Prérequis non négociable : RELAY doit être parfait en single-agent sur plusieurs LLMs avant d'attaquer la coordination multi-agents. Le projet RH avec DeepSeek est l'étape intermédiaire obligatoire.

### Priorité 7 — Nouveaux rôles
- `relay-debt.sh` (Gestionnaire de dette technique)
- `relay-onboard.sh` (Onboarder)
- `relay-release.sh` (Gestionnaire de release)

### Priorité 8 — Communauté et site web
- Décision sur le modèle open source (complet / hybride / protocole ouvert)
- Site web avec bibliothèque d'anti-patterns contributifs
- Mécanisme de contribution par stack / domaine / LLM
- Métriques publiques de la communauté

---

---

*Document généré le 2026-06-09 — à injecter dans RELAY comme référence de vision pour toutes les sessions contribuant à l'évolution du framework.*

*Sources : échanges d'analyse multi-LLM (Claude.ai + Claude Code) sur AgriConnect — 50+ sessions documentées.*

*Implémentation : Claude Code. Vision : ce document. Décisions stratégiques : créateur de RELAY.*
