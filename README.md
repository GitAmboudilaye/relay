# RELAY

> **Protocole de relais inter-sessions pour agents LLM.** Permet à des sessions LLM successives —
> **sans mémoire partagée** — de travailler sur un même projet brownfield comme une équipe stable :
> reprendre l'état réel, ne rien casser, ne pas réinventer, laisser le projet repartable en < 10 min.

État : **v1.7.0** · éprouvé sur **2 projets** (AgriConnect, où RELAY est né, et Tempow/DeepManagment)
\+ **agnosticité de stack prouvée par exécution** (sandbox Python) · moteur portable, **pur** (zéro donnée
projet en dur) et **auto-distribué** (Update Advisor avec consentement). Lis **[Forces & Limites](#forces--limites-lecture-honnête)** avant de te faire une idée.

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
│   ├── scripts/   # relay-check, relay-brief, relay-stats, relay-forecast, stale-detector, relay-split, audit
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
- 🟠 **« LLM-agnostique » est REVENDIQUÉ, pas (encore) prouvé comportementalement.** RELAY n'a tourné en
  session réelle **qu'avec Claude**. Un audit d'agnosticité *statique* existe (`docs/AGNOSTIC-SMOKE-TEST.md` :
  zéro dépendance à un fournisseur dans le moteur), mais **aucune session agentique réelle sous
  GPT/Gemini/DeepSeek** — **prévue après la stabilisation d'AgriConnect**. La portabilité multi-LLM reste
  une hypothèse outillée, pas un fait. → la contribution la plus utile (voir CONTRIBUTING).
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
- ⚪ **Jeune (v1.7), bash + Markdown, français-centré.** Le modèle de propagation a mûri (Update Advisor +
  self-update + CHANGELOG) mais reste récent ; angles connus dans le backlog. i18n absente.

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
1.7.0
PROJECT=MonProjet
CANONICAL_URL=https://github.com/GitAmboudilaye/relay.git
INSTALLED=2026-06-12
```
