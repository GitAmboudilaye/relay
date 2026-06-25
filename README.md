# RELAY

> **Protocole de relais inter-sessions pour agents LLM.** Permet à des sessions LLM successives —
> **sans mémoire partagée** — de travailler sur un même projet brownfield comme une équipe stable :
> reprendre l'état réel, ne rien casser, ne pas réinventer, laisser le projet repartable en < 10 min.

État : **v1.23.0** · **5 rôles mécanisés** (couche **passive**, garde-fous au commit — cybersécurité · chef
de projet · architecte connaissance · auditeur qualité · scrum master) **+ une couche ACTIVE temps-réel**
(3 adaptateurs qui injectent le contexte *avant* l'écriture — voir [La couche active](#la-couche-active-temps-réel-shift-left)) ·
éprouvé en continu sur **2 projets** du même auteur (AgriConnect, où RELAY est né, et Tempow/DeepManagment)
\+ **agnosticité de stack prouvée par exécution** (sandbox Python) · moteur portable, **pur** (zéro donnée
projet en dur) et **auto-distribué** (Update Advisor avec consentement).
**Lucidité** : les rôles passifs tournent désormais **en projet réel** (3 adaptateurs câblés, firing live
observé) ; la **portabilité cross-LLM** est passée de revendiquée à **partiellement prouvée** (examen
DeepSeek, preuve de généralisation **5/10**). Lis **[Forces & Limites](#forces--limites-lecture-honnête)** avant de te faire une idée.

---

## Le problème

Un agent LLM démarre chaque session **sans mémoire** de la précédente. Sur un projet réel (brownfield,
non documenté), ça produit : du travail refait, des régressions réintroduites, des décisions oubliées,
des règles métier inventées. RELAY externalise l'état dans des **fichiers texte versionnés** et impose
un **protocole d'ouverture/clôture** + des **garde-fous exécutables** (`relay-check.sh`).

## Ce que RELAY fait concrètement

- **MRS (Memory Reconciliation Step)** : tout fait hérité d'une session passée est `[assumed]` jusqu'à
  re-vérification (`grep`/`build`/exécution) → on ne planifie jamais sur du non-vérifié.
- **Ancrage métier obligatoire** : avant toute logique métier, écrire acteur / réalité terrain / cas
  limites (dont IDOR multi-tenant). `relay-check.sh` **bloque** le commit si l'ancrage manque.
- **Escalade métier** : une règle métier absente/ambiguë → `ESCALADE_METIER:` dans la tâche + **arrêt**.
  Commit bloqué tant que `REPONSE_HUMAINE:` n'est pas fournie. On ne devine pas une règle de paie/RGPD.
- **Health Score + label honnête** : `relay-check.sh` note l'hygiène de passation ; le label « Sain »
  est **gaté** tant qu'un P0/P1 sécurité est ouvert (un score vert ne ment pas sur la dette critique).
- **Anti-inflation (pool candidat)** : une règle proposée reste *candidate* ; elle ne rejoint le
  protocole qu'au **2ᵉ déclencheur indépendant + validation humaine**. Empêche le protocole de gonfler.
- **Niveaux de confiance** : `[verified-run]` (exécuté) > `[verified-build]` (compilé/lu) — un fix
  sécurité « build-only » est signalé, pas maquillé.
- **Update Advisor (l'humain décide)** : `relay-update.sh --check` prévisualise la mise à jour moteur
  disponible **avec le delta de CHANGELOG** (les améliorations, pas juste un numéro) ; en terminal,
  l'update normal **demande consentement** (`[o/N]`) avant d'appliquer — auto-bypassé en CI. Jamais
  d'auto-update silencieux.
- **Garde-fous externalisés à ta stack** : patterns de régression et règles de design-system vivent dans
  `docs/.relay/rules.conf` (instance) — le moteur n'embarque **aucune** donnée projet, donc une mise à
  jour ne peut jamais écraser ton état.

## Les 5 rôles mécanisés (garde-fous exécutables)

> Depuis v1.8, RELAY transforme cinq « rôles » d'équipe en **garde-fous déterministes** (`grep`, 0 token LLM).
> Principe constant : **le LLM est la couche faible** → le déterministe *rappelle/mesure/bloque*, l'humain
> *décide*. Détail par version → [`CHANGELOG.md`](CHANGELOG.md). **Lucidité** : ce sont des gates commit/CI,
> **pas** un IDS/WAF runtime ni un substitut aux tests — et ils sont **prouvés en sandbox, pas encore éprouvés
> sur un projet tiers**.

| Rôle | Ce qu'il fait | Mécanisme | Depuis |
|---|---|---|---|
| **Spécialiste cybersécurité** | Bloque les patterns dangereux (clé privée, secret en clair, IDOR `?id=`, hash faible) ; ancre une checklist sécu **seulement** quand une surface sensible est touchée ; mémorise le pattern après un fix | `relay-check §9/§9b/§9c` (`rules.conf` `[security_*]`) + CI `gitleaks` (`relay-ci.yml`) | v1.8→v1.11 (4 couches) |
| **Chef de projet** | Mécanise la règle des 70% : somme l'effort des tâches retenables (S/M/L), alerte si le périmètre dépasse le budget | `relay-check §10` (Scope-Creep Alert) | v1.12 |
| **Architecte connaissance** | Rappelle de tracer une décision archi (dépendance/projet/interface) dans `DECISIONS.md` quand le diff en touche une | `relay-check §11` (Decision Trigger) | v1.13 |
| **Auditeur qualité** | Après un bug `✅ RÉSOLU`, rappelle d'enregistrer le pattern de non-régression pour qu'il ne revienne pas | `relay-check §12` (`rules.conf` `[regression_warn]`) | v1.14 |
| **Scrum Master** | Projette « à ce rythme, le backlog se vide dans ~X sessions » + alerte de dérive (scope-creep tendanciel) | `relay-forecast.sh` (informatif, hors gate) | v1.15 |

> Tous sont **token-négatifs** (un `grep` fait le travail que le LLM ferait en lisant) et **signal-only** sauf
> le gate sécu Couche 1 (qui **bloque**). Les patterns/marqueurs vivent dans `rules.conf` (instance) → adaptables
> à ta stack, jamais écrasés par une mise à jour.

## La couche active (temps-réel, shift-left)

> Depuis v1.18, RELAY ne se contente plus de **bloquer au commit** (a posteriori = code déjà écrit = tokens à
> réécrire). Il injecte le contexte/la règle pertinents **avant l'écriture**, via des **adaptateurs** qui
> appellent le **même noyau** (`relay-context.sh`) et placent sa sortie là où l'agent la voit. Cadrage complet →
> [`docs/RELAY-CORE-ACTIF.md`](docs/RELAY-CORE-ACTIF.md).

| Canal | Adaptateur | Comment ça enforce | Depuis |
|---|---|---|---|
| **Claude Code** | hook `PreToolUse` (`settings.json`) | ERROR→`deny`, WARN/INFO→`additionalContext`, rien→silence | v1.18 |
| **Cline** | hook `PreToolUse` (v3.36+) | ERROR→`{"cancel":true}`, sinon ALLOW explicite | v1.20 |
| **Sans agent** | git pre-commit / CI | code de sortie : ERROR→exit 1 ; fail-**open** outillage / fail-**closed** finding | v1.21 |

- **Noyau jamais couplé à un harnais** : un adaptateur peut disparaître sans toucher le noyau (c'est ce qui
  garde RELAY portable). Un adaptateur Cline a prouvé la **généralisation N>1** de cette couche.
- **Économie de tokens chiffrée** : `relay-tokens.sh` lit un ledger d'instance et oppose **token-in**
  (~40/injection) à **token-saved** (~2000/réécriture évitée, contrefactuel modélisé — jamais inventé).
- **Faux positifs durcis par les données runtime** : le ledger live a révélé puis fait corriger 2 faux
  positifs au noyau (prose `.md`, ligne 100 %-commentaire dans du code).
- **Brownfield** : mode `--diff-only` (no-agent) ne juge que les **lignes ajoutées** → le code légataire ne
  bloque pas.

## Démarrage rapide

### Installer RELAY sur un **nouveau** projet (bootstrap)

```bash
git clone https://github.com/GitAmboudilaye/relay ~/relay     # le canonique
cd /chemin/vers/mon-projet
~/relay/bin/relay-init.sh \
  --project-name MonProjet --stack "FastAPI+React" --lang "Python/TS" \
  --domain "marketplace" --actors "acheteur,vendeur,admin" --llm gpt
```

Effets : copie le moteur dans `docs/scripts/` + `docs/rules/`, génère les fichiers d'instance depuis
`templates/`, écrit `docs/.relay-version`, installe le hook pre-commit. **N'écrase jamais** un fichier
d'instance déjà présent. Ensuite : remplis `CLAUDE.md` (ou `SYSTEM.md`) + `docs/context/RELAY_PROJECT_DNA.md`.

### Mettre à jour le moteur (propager les corrections)

```bash
cd /chemin/vers/mon-projet
./docs/scripts/relay-update.sh --check   # dry-run : montre la version dispo + le CHANGELOG, n'écrit rien
./docs/scripts/relay-update.sh           # applique : en terminal, montre le delta puis demande [o/N]
```

Localisation du canonique : `$RELAY_CANONICAL` → cache `~/.relay/canonical` (clone/pull depuis
`CANONICAL_URL` de `docs/.relay-version`) → chemin local → sinon erreur explicite. En mode normal et en
**terminal**, si une mise à jour existe, RELAY affiche les entrées de CHANGELOG entre ta version et la
nouvelle, puis attend **`[o/N]`** avant d'appliquer (bypass `--yes` / auto en CI). Le script **se met à
jour lui-même** d'abord (bootstrapping), puis copie le **MOTEUR seul** — **aucun fichier d'instance touché**.

### Utiliser RELAY dans une session (la boucle quotidienne)

```bash
./docs/scripts/relay-brief.sh     # Senior Brief — 10 lignes, l'état en 30 s
./docs/scripts/relay-check.sh     # Health Score + garde-fous (validation NEXT_SESSION.md)
./docs/scripts/relay-stats.sh     # vélocité, bugs vs features (depuis git)
./docs/scripts/relay-forecast.sh  # projette "à ce rythme, le backlog se vide dans X sessions" + alerte de dérive
./docs/scripts/relay-split.sh     # fractionne NEXT_SESSION.md s'il dépasse 150 lignes
```

Le protocole complet (MRS, règle des 70 %, format des tâches, clôture) → `docs/rules/RELAY_PROTOCOL.md`.

## Architecture : MOTEUR / INSTANCE / TEMPLATE

```
relay/
├── engine/
│   ├── scripts/   # relay-check, relay-brief, relay-stats, relay-forecast, relay-scan, relay-context, relay-tokens, relay-uncommitted-guard, ...
│   ├── adapters/  # couche ACTIVE : claude-code/ (hook) · cline/ (hook) · no-agent/ (pre-commit/CI) — câblent relay-context.sh
│   └── rules/     # RELAY_PROTOCOL.md  (§0-§7 portables, §8 = pointeur statique)
├── templates/     # graines des fichiers d'instance ({{PLACEHOLDERS}})
├── bin/           # relay-init.sh (bootstrap) · relay-update.sh (propagation)
├── docs/          # VISION.md, FRAMEWORK_SPEC.md (réf. du framework, NON propagées)
├── CHANGELOG.md    # Keep a Changelog — source du delta affiché par relay-update --check
└── VERSION
```

| Catégorie | Fichiers | Propagé par `relay-update.sh` ? |
|---|---|---|
| **MOTEUR** | `engine/scripts/*.sh`, `engine/rules/RELAY_PROTOCOL.md` | ✅ écrasé à chaque update |
| **INSTANCE** | `NEXT_SESSION.md`, `CLAUDE.md`, `docs/context/*`, `docs/rules/{KNOWN_ISSUES,*_ARCHITECTURE}.md` | ❌ jamais touché |
| **TEMPLATE (seed-once)** | `templates/*` — dont `RELAY_METRICS.md`, `RELAY_RULE_POOL.md` | déposé au bootstrap, jamais en update |

> **Règle de sûreté : un fichier MOTEUR ne contient AUCUNE donnée de projet.** C'est ce qui garantit
> qu'une mise à jour ne peut **jamais écraser** tes données (compteurs, registre de règles, KI, état).
> Prouvé par test : un `update` qui change le protocole laisse `NEXT_SESSION`, `KNOWN_ISSUES` et le
> registre de règles **intacts**.

## Forces & Limites (lecture honnête)

> RELAY est un outil utile, pas une garantie magique. Lis ceci avant de l'adopter — pour éviter
> les illusions.

**Forces (observées) :**
- Résout réellement la perte de contexte inter-sessions : l'état vit en texte versionné, pas dans la
  mémoire volatile d'un agent.
- Les garde-fous **tirent vraiment** : le label « Sain » gaté a révélé des P0 sous-comptés ; l'escalade
  métier a forcé une vraie décision d'auth avant un fix risqué ; le pool anti-inflation freine la dérive.
- Discipline brownfield (`[assumed]→[verified]`, MRS) qui empêche de bâtir sur du faux.
- L'ancrage métier empêche un agent d'**inventer** une règle métier sensible (paie, RGPD, facturation).
- Portable : moteur canonique + propagation par script ; les corrections atteignent tous les projets
  sans copier-coller (le mode de fonctionnement *avant* ce repo, qui faisait diverger les copies).
- Moteur **pur + auto-distribué** : zéro donnée projet en dur (garde-fous dans `rules.conf` d'instance) ;
  une correction de protocole se propage à tous les projets, et l'Update Advisor montre *ce qui change*
  (CHANGELOG) avant d'appliquer avec consentement — la distribution n'est plus un copier-coller à l'aveugle.

**Limites (à connaître pour ne pas surpromettre) :**
- 🟠 **« LLM-agnostique » est PARTIELLEMENT prouvé (2026-06-25), pas encore complet.** RELAY a maintenant
  tourné en session réelle sous **DeepSeek** (via Cline) sur un projet RH brownfield : un lot de sessions
  examinées en croisant logs vs git réel (examen interne). **Acquis** : le protocole se transmet
  (format, MRS, archi DDD adoptés **sans coaching**) → portabilité réelle. **Limite restante** : ces sessions
  n'ont testé que la couche **passive** (le hook actif Cline a été câblé après) ; et le passif s'est révélé
  **contournable par omission** (produit hors-git → gate au commit jamais déclenché). La portabilité de la
  couche **active** sous un LLM non-Claude reste à mesurer (avant/après). → la contribution la plus utile
  (voir CONTRIBUTING).
- 🟠 **N=2 projets, même auteur ; cross-stack prouvé en *sandbox*, pas en projet réel.** Éprouvé en continu
  sur 2 projets du même auteur (ASP.NET + Flutter). L'**agnosticité de stack** est désormais prouvée *par
  exécution reproductible* sur un bac à sable Python/FastAPI (le moteur n'impose aucune règle .NET/Flutter ;
  des règles Python custom s'appliquent) — mais **pas encore** sur un projet multi-sessions complet d'une
  autre stack, ni cross-équipe / cross-domaine.
- 🟠 **Les gates réduisent le risque, ils ne le suppriment pas.** Un agent *peut* bâcler un ancrage ou
  contourner par `--no-verify`. RELAY rend la triche **visible et coûteuse** ; il ne l'empêche pas
  mécaniquement. La qualité dépend de l'honnêteté de l'agent + de la vigilance humaine.
  *Depuis v1.2.0, `[verified-run]` peut être **adossé à une preuve** : `relay-run.sh "<cmd>"` émet un
  reçu (stdout/stderr/exit-code) et `relay-check.sh` **rejette** un `[verified-run:<hash>]` dont le reçu
  est introuvable. La triche par run cité devient donc fabriquée, pas seulement affirmée. Reste opt-in :
  un `[verified-run]` **nu** est encore toléré (warning), donc l'honnêteté reste requise pour les claims
  non adossés.*
- 🔴 **Pas un substitut aux tests / à la CI.** `[verified-run]` est un *label de discipline*, pas de la
  couverture. RELAY ne lance pas tes tests, ne build pas, ne déploie rien.
- 🟠 **Le Health Score mesure l'hygiène de passation** (+ un peu de fond via le gating P0/P1), **pas la
  santé du produit.** 97/100 peut coexister avec un produit cassé.
- 🟠 **Rien ne force l'exécution du protocole.** Si une session n'ouvre pas `relay-brief.sh` ou saute le
  MRS, RELAY ne sert à rien. C'est un protocole, pas un runtime. *(v1.2.0 amorce le glissement : `relay-run.sh`
  + la porte de reçu apportent une preuve mécanique sur `[verified-run]` ; l'auto-déclenchement par hooks
  reste hors core — voir backlog T1, volontairement non livré car spécifique à Claude Code, donc en tension
  avec l'agnosticité revendiquée.)*
- 🟠 **Les rôles tournent maintenant en projet réel, mais N reste = l'auteur.** Le bootstrap a eu lieu :
  AgriConnect + DeepManagment sont à **v1.22.1** (canonique **v1.23.0**), le hook actif a **firé en session sur de vrais Edit** (deny
  live), et le ledger runtime a même révélé 2 faux positifs corrigés au noyau. Ce qui manque encore : un
  **développeur tiers** (pas l'auteur) qui tient 5 sessions conformes sans coaching, et l'avant/après de la
  couche **active** sous un LLM non-Claude (détail → [`docs/RELAY-CAPABILITIES.md`](docs/RELAY-CAPABILITIES.md)).
- ⚪ **Jeune (v1.23), bash + Markdown, français-centré.** Le modèle de propagation a mûri (Update Advisor +
  self-update + CHANGELOG + migrations `rules.conf` idempotentes) mais reste récent ; angles connus dans le
  backlog. i18n absente.

## Contribuer

RELAY se durcit par l'usage. La contribution la plus précieuse : **le faire tourner sous un LLM non-Claude**
et rapporter ce qui casse (cf. limite #1). Voir **[CONTRIBUTING.md](CONTRIBUTING.md)** pour le modèle
anti-inflation (toute nouvelle règle entre comme *candidate*, promue au 2ᵉ déclencheur + validation
humaine), la discipline moteur/instance, et comment tester une modif.

## Licence

[MIT](LICENSE) — usage/modification/redistribution libres (y compris commerciaux), garder la
mention de copyright, fourni « tel quel » sans garantie.

## `docs/.relay-version` (manifeste d'instance)

```
1.23.0
PROJECT=MonProjet
CANONICAL_URL=https://github.com/GitAmboudilaye/relay.git
INSTALLED=2026-06-12
```
