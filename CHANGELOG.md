# Changelog

Toutes les évolutions notables du **moteur canonique RELAY** sont documentées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et le projet respecte le [Semantic Versioning](https://semver.org/lang/fr/).

Ce fichier est la **source unique** de la « description des améliorations » affichée par
`relay-update.sh --check` quand un projet consommateur est en retard sur le canonique.
Chaque bump de `VERSION` doit ajouter une entrée ici (étape de clôture — `RELAY_PROTOCOL.md §6`).

## [Non publié]

## [1.25.0] — 2026-06-25

### Added
- **RELAY-CLAIM-GUARD (R1bis) — auditeur « déclaré-vs-committé », lançable en CI** (`engine/scripts/relay-claim-guard.sh`).
  Ferme **réellement** le trou « produit hors-git » que R1 (`relay-uncommitted-guard.sh`) ne ferme **pas en CI** :
  un checkout GitHub Actions est **toujours propre** (`git status --porcelain` vide), donc R1 en CI = **faux-vert** ;
  le travail jamais committé reste local et n'atteint jamais le dépôt. R1bis opère sur l'arbre **committé** (HEAD) :
  il lit ce que `NEXT_SESSION` déclare « fait/livré » et asserte via `git ls-files` que chaque **chemin déclaré**
  existe dans l'arbre committé. Absent = « déclaré fait, jamais committé ». Indépendant de l'arbre de travail →
  marche en CI, indépendant du LLM. Reproduit le cas réel observé : un répertoire déclaré « créé » → `git ls-files` vide.
  - **Source des claims (décision user)** : `NEXT_SESSION.md` seul (là où vit le smoking gun ; surface réduite = moins de faux-rouge).
  - **« Chemin déclaré » (décision user — coeur anti-faux-rouge)** : token backtick sur une ligne à marqueur DONE
    (`✅` / `~~barré~~` / `status=done` / `fait` / `livré`), ressemblant à un chemin (contient `/` **ou** une extension
    de code) ET **hors** formes ref-git/URL/version (`origin/…`, `feature/…` sans extension, `://`, `vX.Y.Z`, ranges `..`).
    Acceptation **étroite** : un livrable = **répertoire** (slash final) **ou** **fichier** (extension de code) ;
    `word/word` sans extension ni slash final = prose ambiguë → rejet. Filtres anti-bruit : globs, `.git/`, **gitignorés**
    (non-committés par design).
  - **Sévérité (décision user)** : **`--warn` par défaut** (signal-only — R1bis est *heuristique*, à la différence de R1
    déterministe → un faux-rouge ne doit pas casser une CI légitime), **`--strict`** pour opt-in bloquant (exit 1), `--json`.
    **Fail-OPEN** absolu sur l'outillage (hors repo git, git absent, pas de `NEXT_SESSION`).
  - **Limite inhérente documentée** : R1bis suppose que `NEXT_SESSION` décrit le repo où il vit ; un `NEXT_SESSION` « hôte »
    qui pilote du travail committé dans un **autre** repo sur-flague (un chemin cross-repo est indistinguable d'un livrable
    jamais committé) → câbler R1bis sur le repo dont le `NEXT_SESSION` décrit **son propre** travail.
  - Pur Bash, project-agnostic (pureté moteur 0 identité), propagé via `relay-init` (0 manifeste), **step CI miroir**,
    **shellcheck CLEAN**, smoke fixtures **7/7**, acceptance sur un vrai `NEXT_SESSION` consommateur (18/18 vrais positifs,
    0 faux), repro bootstrap `relay-init` 4/4.

## [1.24.0] — 2026-06-25

### Changed
- **RELAY-PAYLOAD-ENRICH — enrichir la *charge utile* de l'injection live, pas le nombre de règles.**
  Constat (injecteur testé en live) : la *pertinence* est bonne (déclenchement chemin+contenu, silence
  sur code propre), mais la *richesse* d'un deny vaut exactement le `msg=` de la règle déclenchée — et
  beaucoup de patterns sont **nus** : un `.Result` proscrit injectait la **regex nue** (`relay-context.sh`
  émet `${msg:-${pattern}}`) → deny opaque, ni *pourquoi* ni *fix*. **0 règle ajoutée, 0 code moteur**
  (`msg=` est déjà rendu génériquement par le noyau) — c'est une amélioration de **donnée** du seed
  `templates/docs/.relay/rules.conf`. Décisions user (`AskUserQuestion`) : ordre = PAYLOAD-ENRICH d'abord ;
  mécanisme levier 2 = **`msg=` enrichi inline** (donnée, token-borné) plutôt qu'extraction de fichier au
  firing (cohérent `VISION §4` token-optimal).
  - **Levier 1 — `[forbidden_patterns]` pédagogiques.** Les exemples du seed passent de la forme
    « regex + commentaire `#` de fin de ligne » (avalé par `exclude=` au décommentage → `msg=` vide) à la
    forme **`<regex> | msg=<pourquoi + fix>`** (ex. `.Result bloquant en contexte async — deadlock ; utiliser await`).
    En-tête de format mis à jour : « donnez TOUJOURS un `msg=` ». Corrige un **bug pédagogique** (le seed
    enseignait un format dont le deny live est aveugle).
  - **Levier 2 — surfaces (`[security_surface]`/`[decision_surface]`) : étiquette → snippet.** Les `msg=`
    passent d'une **étiquette** nue (`authZ (IDOR)`) à un **snippet ciblé 1-ligne** = le check le plus
    important de la catégorie **+ le `§ref`** vers la checklist complète (`SECURITY_RULES.md §N` / tracer
    en `DEC-`). L'étiquette devient **connaissance** sans injecter tout le fichier (token-borné, levier 3).
  - **Validation** : dogfood `relay-context.sh` 4/4 — `.Result` → deny pédagogique ; code propre → silence ;
    fichier auth → surfaces enrichies ; `context.Result =` → silence (exclusion préservée). Charge ~40 tok/firing.
  - **Limite découverte (candidat moteur, non corrigé ici)** : la `rules.conf` elle-même — méta-fichier qui
    *liste* ses patterns — est scannée comme du **code** par les adaptateurs (hook PreToolUse + pre-commit
    no-agent), donc éditer la `rules.conf` d'un consommateur **déclenche ses propres `[forbidden_patterns]`
    en `deny`** (faux positif méta, distinct des cas `.md`/commentaire déjà traités). Contournement : édition
    hors-Edit / `--no-verify`. → piste : exclure `docs/.relay/rules.conf` du scan-code (couche moteur, future tâche).

## [1.23.0] — 2026-06-25

### Added
- **R1 — `relay-uncommitted-guard.sh` : garde de clôture d'état-git.** Nouveau script **moteur** (couche
  active), issu de l'examen cross-LLM DeepSeek (`VISION §11`, `RELAY-CORE-ACTIF §3`). Ferme un trou de la
  couche **passive** : un LLM peut déclarer une tâche « faite » en laissant le produit **hors-git**
  (fichiers untracked jamais `git add`és) → le gate `relay-check` ne mord qu'au commit, donc **inerte par
  omission**. Le garde impose la règle inverse : **« `git status --porcelain` vide = condition de clôture »**,
  lançable aussi en **CI** (indépendant de la discipline du LLM).
  - **Portée (décision user `AskUserQuestion`)** : **porcelain LITTÉRAL** — untracked **+** modifiés **+**
    stagés non committés déclenchent tous (clôture = absolument tout committé). Les fichiers **gitignorés**
    (ex. `docs/session_logs/` internes) sont **nativement exclus** par porcelain → aucun faux positif sur
    l'interne.
  - **Sémantique (décision user `AskUserQuestion`)** : **BLOQUANT par défaut** (`exit 1` — c'est un gate de
    clôture) ; `--warn` = signal-only (`exit 0` + liste, adoption progressive/brownfield) ; `--json` pour
    l'outillage. **FAIL-OPEN absolu sur l'outillage** (hors d'un repo git ou `git` absent → `exit 0` : ne
    jamais casser un environnement) / **FAIL-CLOSED sur le finding** (arbre sale → `exit 1`). Pur Bash,
    offline-safe.
  - Propagé aux consommateurs via `relay-init` (`engine/scripts/*.sh`, aucun manifeste à éditer). Step CI
    miroir (présent+exécutable après bootstrap ; propre→0 / untracked→1 / `--warn`→0 / hors-git→0).
    shellcheck CLEAN, smoke 9/9, repro CI bootstrap OK.

## [1.22.1] — 2026-06-25

### Fixed
- **RELAY-COMMENT-FALSEPOS — le noyau ne flague plus un anti-pattern CITÉ dans un commentaire de code.**
  Patch du faux positif découvert **en live** (2026-06-25, session `RELAY-NOAGENT-WIRE` côté consommateur) :
  une ligne **100 %-commentaire** dans un fichier de code/shell (`# évite l'idiome bloquant`, `// note…`)
  qui *cite* un pattern proscrit déclenchait un `deny` → force la réécriture d'une ligne légitime = tokens
  gaspillés, l'inverse de la thèse RELAY (`VISION §4`). C'est la **même** logique que l'exception prose
  (`.md`/`.txt`, v1.19.1) mais à la **granularité ligne**.
  - `relay-context.sh` construit une variante **« code seul »** (`CONTENT_CODE`) en retirant les lignes dont
    le 1ᵉʳ caractère non-blanc est un marqueur de commentaire multi-langage (`#` `//` `/*` `*` `--` `<!--`).
    Les sections d'**idiome code** (`forbidden_patterns`, `regression_warn`, surfaces `security_surface`/
    `decision_surface`, `design_warn_*`) scannent cette variante ; **`security_forbidden` reste sur le contenu
    ENTIER** (une clé privée/AKIA littérale en commentaire = fuite réelle — posture sécu inchangée).
  - **Décision user 2026-06-25 (`AskUserQuestion`)** : lignes **100 %-commentaire UNIQUEMENT**. Un commentaire
    en **fin** d'une ligne de code laisse la ligne entièrement scannée (quasi-zéro faux-négatif : du vrai code
    commence rarement une ligne par un marqueur). Compromis écarté = strip des commentaires *inline* (ambigu :
    `//` dans une string, `https://`, `#` en couleur CSS → faux-négatifs sécu).
  - **0 dépendance harnais ajoutée** (§1.2). shellcheck CLEAN, **smoke jetable 6/6** (commentaire cité → silence ;
    code réel → ERROR ; secret en commentaire → ERROR ; idiome en fin de ligne → scanné ; tous marqueurs ;
    prose `.md` intacte), **repro CI vs `relay-init` réel 2/2**, assertion CI miroir ajoutée.

## [1.22.0] — 2026-06-24

### Added
- **RELAY-NOAGENT-DIFFONLY — mode diff-only (opt-in) de l'adaptateur sans-agent** : débloque le
  **brownfield**. Par défaut, `relay-precommit.sh` juge le **contenu entier** du fichier touché → sur un
  dépôt légataire, éditer un fichier qui contient *déjà* un pattern proscrit (`.Result`/`localhost:7285`
  historique) bloque le commit même quand on n'a pas touché cette ligne. Avec `RELAY_DIFF_ONLY=1` (env)
  ou `--diff-only` (flag), seules les **lignes AJOUTÉES** (`git diff -U0`, lignes `+`, préfixe retiré)
  sont pipées au noyau → seul ce qu'on ajoute est jugé. Les deux modes (pre-commit et range/CI) le
  respectent.
  - **Pré-filtre 100 % adaptateur** : `relay-context.sh` reste agnostique (§1.2) — il grep le contenu reçu
    sur `--stdin`, qu'il vienne du fichier ou du diff. **0 ligne de noyau touchée.**
  - **Compromis sécurité assumé → OPT-IN** (décision user 2026-06-24, `AskUserQuestion`) : en diff-only, un
    secret **préexistant** (AKIA/clé privée) dans un fichier touché mais non modifié n'est plus flagué. Le
    **défaut** reste donc le scan plein-fichier (greenfield/CI stricte inchangés). Le fail-closed sur un
    finding **neuf** (pattern ajouté) est préservé dans les deux modes.
  - shellcheck CLEAN, smoke jetable **11/11**, repro CI contre un vrai `relay-init` **3/3**, CI canonique
    étendue (miroir du bloc no-agent, via le pattern actif `security_forbidden`/AKIA).

## [1.21.0] — 2026-06-24

### Added
- **RELAY-NOAGENT — 3ᵉ adaptateur du framework : scénario SANS agent (git pre-commit / CI)**
  (`engine/adapters/no-agent/relay-precommit.sh`). Câble le **même** noyau `relay-context.sh`, 0 couplage
  (§1.2). C'est le canal **dégradé** prévu par `RELAY-CORE-ACTIF.md §1.1` : sans agent, il n'existe aucun
  contexte LLM où injecter la règle *avant* l'écriture → la seule barrière est **en aval**, au commit ou
  dans la CI, et le canal d'enforcement n'est plus un JSON de décision (comme les hooks d'agent) mais le
  **code de sortie**. Pipe le contenu **proposé** de chaque fichier touché à
  `relay-context.sh --path --stdin --strict` et agrège : **ERROR (proscrit) → exit 1** (bloque le commit /
  fait échouer le job), **WARN/INFO → advisory non-bloquant**, **rien → silence** (§1.3).
  - **Deux modes, un script** : *pre-commit* (défaut — fichiers stagés, contenu = blob d'index
    `git show :file` = ce qui va être committé) et *CI/range* (`RELAY_RANGE=base...HEAD` — diff de la plage,
    contenu = arbre courant).
  - **Sémantique d'enforcement INVERSE des adaptateurs d'agent** (décision user) : fail-**OPEN** sur
    l'OUTILLAGE (git absent, hors dépôt, `rules.conf`/noyau introuvable → exit 0 : ne jamais coincer un
    commit pour un bug d'outil) mais fail-**CLOSED** sur le FINDING (pattern proscrit → exit 1 : bloque —
    c'est tout l'intérêt du canal). Échappatoire explicite `RELAY_SKIP=1` / `git commit --no-verify`.
  - **Pur Bash, 0 python3** : aucune frontière JSON (git fournit la liste de fichiers, le noyau le texte +
    l'exit code) → plus portable encore que les adaptateurs d'agent.
  - **N'écrit PAS le ledger token-saved** (volontaire) : `relay-tokens` modélise l'économie de réécriture
    LLM ; un commit humain bloqué n'en est pas une → l'y inscrire corromprait la métrique (même discipline
    que « token-saved = contrefactuel, jamais inventé »).
  - Propagé en `docs/adapters/no-agent/` par `relay-init`/`relay-update` (mécanisme générique
    `engine/adapters/<h>/*`, 0 changement aux scripts de propagation). CI : assert propagé + exécutable +
    propre→exit 0 + clé AKIA stagée→exit 1, miroir RELAY-3/CLINE. shellcheck CLEAN, smoke jetable **10/10**.

## [1.20.0] — 2026-06-24

### Added
- **RELAY-CLINE — 2ᵉ adaptateur du framework : hook `PreToolUse` pour [Cline](https://cline.bot)**
  (`engine/adapters/cline/relay-precheck.sh`). Première preuve de **généralisation N>1** de la couche
  « actif » : un second harnais câble le **même** noyau `relay-context.sh`, 0 couplage (§1.2). Reçoit le
  JSON `PreToolUse` de Cline (`toolName` + `parameters.{path, content|diff}`), pipe le contenu **proposé**
  à `relay-context.sh --path --stdin`, et traduit : **ERROR → `{"cancel": true, "errorMessage": …}`**
  (bloque), **WARN/INFO → `{"cancel": false, "contextModification": …}`** (injecte), **rien/défaillance →
  `{"cancel": false}`** (ALLOW explicite — contrat Cline, ≠ le « silence sans sortie » de Claude Code).
  - **Parité d'enforcement avec Claude Code** : grâce aux **hooks bloquants de Cline (v3.36+)**, on obtient
    un `deny` réel, pas seulement de l'advisory. Cela **rectifie l'hypothèse « Cline = MCP »** des notes de
    cadrage (écrites avant que Cline n'ait des hooks) : le hook est strictement supérieur et plus simple
    (aucun serveur MCP). Voir `engine/adapters/cline/README.md` (§ « Mise à jour de cap »).
  - **Résolution de chemin symlink-safe** (`readlink -f` + repli racine git) — nécessaire car Cline impose
    un fichier nommé exactement `PreToolUse` (sans extension) qui pointe vers l'adaptateur par symlink.
  - **FAIL-OPEN absolu** (python3 absent, JSON illisible, noyau introuvable, contenu vide, outil
    non-écriture → ALLOW). **Ledger token-saved** au **même format** que l'adaptateur Claude Code →
    `relay-tokens.sh` agrège les **deux** harnais sans modification.
  - Propagé en `docs/adapters/cline/` par `relay-init`/`relay-update` (mécanisme générique
    `engine/adapters/<h>/*`, 0 changement aux scripts de propagation). CI : assert propagé + exécutable +
    fail-open (ALLOW explicite), miroir RELAY-1/2/3. shellcheck CLEAN, smoke jetable **9/9**.

## [1.19.1] — 2026-06-24

### Fixed
- **Faux positif du noyau `relay-context.sh` sur les fichiers PROSE** (`.md`/`.txt`/…), confirmé par le
  **ledger live** du premier déploiement du hook RELAY-3 (2026-06-24) : un `deny` parasite a bloqué un
  `SESSIONS_LOG.md` parce que sa prose **citait** des regex d'anti-pattern (`.Result`, `.Include().Select()`),
  + des `context` parasites sur tout `.md` mentionnant « auth »/« token ». Un `deny` à tort force la
  réécriture d'un doc légitime = **tokens gaspillés**, l'inverse exact de la thèse RELAY (`VISION.md §4`).
  - `applicable_sections()` traite désormais les extensions prose (`.md .markdown .txt .rst .adoc`) en
    cas spécial : seul **`security_forbidden`** y reste actif (une **vraie** clé privée/AKIA littérale
    collée dans un doc est une fuite réelle, et ces patterns sont quasi-zéro-faux-positif). Les sections
    d'idiome **code** (`forbidden_patterns`, `regression_warn`) et les surfaces par mot-clé
    (`security_surface`, `decision_surface`, `security_warn`) **sautent** sur prose.
  - **0 régression code** : les fichiers de code conservent toutes les sections (universelles + design).
    Décision user 2026-06-24 (garder la détection de secrets sur prose). Fix dans le **noyau** → tous les
    adaptateurs (hook Claude Code et suivants) en bénéficient sans modification (0 couplage harnais).

## [1.19.0] — 2026-06-24

### Added
- **RELAY Core « actif » — métrique `token-saved`** (livrable « + » de la roadmap, cf.
  `docs/RELAY-CORE-ACTIF.md §1.4/§3`). Matérialise l'angle produit chiffrable de RELAY (`VISION.md §4`) :
  l'économie de tokens du shift-left, mesurée au runtime.
  - **`engine/scripts/relay-tokens.sh`** — outil informatif **dédié** (pair de `relay-stats.sh` /
    `relay-forecast.sh` ; choix user vs `relay-forecast.sh --tokens` — sources de données orthogonales :
    ledger runtime vs backlog/git, unités tok vs pt). Lit le **ledger d'instance** et chiffre :
    `token-in` = Σ firings × `RELAY_TOKEN_IN` (déf. 40 — injection amont, deny **ou** context) ;
    `token-saved` = Σ deny × `RELAY_TOKEN_SAVED` (déf. 2000 — réécriture aval évitée, **deny seulement**,
    conservateur) ; `net` = saved − in. Sortie humaine + `--json`. **Honnête sans données** : ledger
    absent/vide → « pas encore de données », jamais un chiffre inventé (cohérent `relay-forecast`).
    **Informatif pur** : exit 0 toujours, offline-safe.
  - **Constantes overridables** (`RELAY_TOKEN_IN`, `RELAY_TOKEN_SAVED`) car `token-saved` est par nature
    **contrefactuel** (la réécriture évitée n'a, par définition, jamais eu lieu) → **modélisé**, jamais
    « mesuré » ; étiqueté comme estimation.
  - **Instrumentation de l'adaptateur** : `engine/adapters/claude-code/relay-hook.sh` appende désormais
    **1 ligne par firing** (`<ts> <deny|context> err=<n> total=<n> <fichier>`) dans
    `docs/.relay/token-ledger.log`. Source de la métrique que ni git ni `NEXT_SESSION.md` ne portent.
    **FAIL-OPEN préservé** : l'écriture du ledger est en sous-shell, un échec ne bloque jamais l'édition.
    **Gitignoré** (donnée d'instance, self-deposit `.gitignore` — même convention que `relay-run.sh` /
    `docs/.relay/receipts`).
  - **Propagation** : auto via `relay-init`/`relay-update` (`engine/scripts/*.sh` → `docs/scripts/`).
  - **CI** : assert `relay-tokens.sh` propagé + exécutable + exit 0 + `firings=0` honnête sans ledger,
    miroir de RELAY-1/2/3.

## [1.18.0] — 2026-06-24

### Added
- **RELAY Core « actif » — adaptateur hook `PreToolUse` Claude Code** (RELAY-3, 3ᵉ brique de la direction
  « actif », cf. `docs/RELAY-CORE-ACTIF.md §3`). C'est le **premier ADAPTATEUR** : il câble le noyau
  agnostique `relay-context.sh` (RELAY-2) dans Claude Code pour réaliser le **shift-left** — la règle
  pertinente est injectée **avant** l'écriture, au lieu d'être sanctionnée à la clôture par
  `relay-check.sh` (a posteriori = réécriture = tokens).
  - **`engine/adapters/claude-code/relay-hook.sh`** — reçoit le JSON `PreToolUse` sur stdin
    (`tool_input.file_path` + contenu **proposé** ; Edit `new_string` / Write `content`·`file_text` /
    MultiEdit `edits[]`), pipe ce contenu à `relay-context.sh --path=<édité> --stdin` et **traduit** la
    sortie du noyau en décision de hook :
    - ≥1 pattern **ERROR** (proscrit) → `permissionDecision:"deny"` + `permissionDecisionReason` →
      **bloque** l'écriture ; l'agent voit la raison et corrige **avant** d'écrire = réécriture aval évitée.
    - seulement **WARN/INFO** → `additionalContext` (non-bloquant) → l'agent est informé, terse (§1.3).
    - rien → **silence** (aucune sortie = flux de permission normal).
  - **FAIL-OPEN absolu** : python3 absent, JSON illisible, noyau introuvable, contenu vide → exit 0
    silencieux. L'édition n'est **jamais** bloquée par un bug d'outillage (un garde-fou qui casse
    l'éditeur est pire que pas de garde-fou). python3 sert **uniquement** aux 2 frontières JSON ; le noyau
    reste en Bash pur.
  - **0 couplage noyau↔harnais (§1.2)** : toute la spécificité Claude Code vit dans l'adaptateur ;
    `relay-context.sh` est inchangé. Un autre harnais (Cline = MCP, sans agent = git hook) recevra son
    propre adaptateur appelant le **même** noyau.
  - **Propagation** : `relay-init`/`relay-update` copient désormais `engine/adapters/<harnais>/*` →
    `docs/adapters/<harnais>/*` (script **inerte** tant que non câblé). Le câblage reste un **choix du
    projet** : snippet fourni dans `templates/.claude/settings.json` (matcher `Edit|Write|MultiEdit`),
    jamais écrasé par l'init. Le dépôt canonique se **dogfoode** via `.claude/settings.json`.
  - **CI** : assert `relay-hook.sh` propagé + exécutable + fail-open (exit 0), miroir de RELAY-1/2.

## [1.17.0] — 2026-06-23

### Added
- **RELAY Core « actif » — `relay-context.sh`** (RELAY-2, 2ᵉ brique de la direction « actif »,
  cf. `docs/RELAY-CORE-ACTIF.md §3`). Là où `relay-scan.sh` (RELAY-1) répond « où est ce terme ? »,
  `relay-context.sh` répond « quelle règle s'applique à CE fichier ? » — et l'émet **avant** l'écriture
  (shift-left) au lieu de `relay-check.sh` qui sanctionne le diff **à la clôture** (a posteriori =
  réécriture = tokens). C'est le **précurseur du hook PreToolUse** (RELAY-3) : un adaptateur appellera
  ce noyau avec le chemin édité et placera sa sortie là où l'agent la voit.
  - **Source de vérité = le MÊME `docs/.relay/rules.conf`** que `relay-check.sh` (0 règle dans le moteur,
    parseur byte-fidèle : sections `[…]`, séparateur ` | `, champs `msg=`/`exclude=`/`exclude-path=`).
    Pas de 2ᵉ convention à maintenir → anti-inflation (Pilier 11).
  - **Déclenché par CONTENU (§1.3)** : grep le contenu du fichier et ne signale **que les patterns
    réellement présents** — `[security_forbidden]`/`[forbidden_patterns]` (⛔ ERROR), `[regression_warn]`/
    `[security_warn]`/`[design_warn_*]` (⚠️ WARN), `[security_surface]`/`[decision_surface]` (ℹ️ INFO).
    **SILENCE total si rien** (token-négatif). Sections design **scopées par extension** (`.dart` /
    `.css`+`.cshtml`), comme `relay-check §8`.
  - **`--stdin`** : scanne le contenu *proposé* piped (le hook RELAY-3 lui passera l'édition à venir,
    `--path=` servant alors uniquement au typage) → couvre le cas « fichier neuf » au bon niveau, sans
    introduire de mur de règles statique.
  - `--json` (adaptateurs), `--top=N` (borné), **exit 0 informatif** par défaut ; **`--strict`** → exit 3
    si ≥1 hit ERROR (pour un gate, jamais imposé par le noyau).
  - **0 dépendance harnais.** shellcheck CLEAN. Smoke jetable 25/26 (sandbox isolée `git -C` + sous-shell ;
    le hit restant = faute d'accent du test, pas du script — assertion JSON `total=5` passée). Preuve
    réelle : Controller AgriConnect → `security_surface authZ` (ancrage sécu AVANT édition).
- **CI** : assert `relay-context.sh` propagé + informatif pur (exit 0, `--json`), miroir de RELAY-1.

## [1.16.0] — 2026-06-23

### Added
- **RELAY Core « actif » — `relay-scan.sh`** (RELAY-1, première brique de la direction « actif »
  validée user 2026-06-23, cf. `docs/RELAY-CORE-ACTIF.md`). Constat : RELAY est **passif** —
  `relay-check.sh` est joué *à la clôture, par le LLM* → l'enforcement arrive **après** l'écriture
  = réécriture = tokens gaspillés. La direction « actif » vise le **shift-left** (injecter le contexte
  *avant* l'écriture). `relay-scan.sh` est le **premier noyau** : un scan ciblé projet-wide à **sortie
  structurée et bornée** (« contrat RELAY »), **0 dépendance harnais**.
  - Cherche les fichiers **suivis** (`git grep`, respecte `.gitignore` ; repli `grep -r` hors dépôt).
  - Résumé : total occurrences + fichiers, **breakdown par surface** (code / markup / style / config /
    docs / other), **top-N fichiers**. Borné (jamais un dump = anti-tokens). Mode `--json` pour les
    adaptateurs (hook/MCP).
  - **`--replace=<new>`** : *preview d'impact de renommage* — heuristique séparant les occurrences
    **EMBARQUÉES** dans un identifiant/chemin (namespace, fichier, URL → risquées en remplacement
    aveugle) des **STANDALONE** (prose → probablement sûres). Pré-calcule l'intelligence qu'un
    `sed/perl` global confond (cas réels : `AgriConnect.Web`/`.apk` vs prose, cascade DS).
  - **Informatif pur** (exit 0), token-négatif (un résumé en amont vs N greps + lecture de dumps).
  - Propagé par le glob `engine/scripts/*.sh` ; assert CI ajouté ; smoke jetable **10/10 PASS**
    (total/files, surfaces, top, `--replace` embedded/standalone, `--json`, 0-occurrence, `--fixed`
    littéral, exit 0). shellcheck CLEAN.
- **`docs/RELAY-CORE-ACTIF.md`** — cadrage d'architecture de la phase « actif » (hook ≠ démon ; noyau
  portable + adaptateurs par harnais ; linter terse conditionnel ; métrique token-saved ; roadmap
  RELAY-1 `relay-scan.sh` → RELAY-2 `relay-context.sh` → RELAY-3 adaptateur hook PreToolUse).

## [1.15.0] — 2026-06-20

### Added
- **Backlog Forecast** — rôle « Scrum Master / Chef de projet » (`engine/scripts/relay-forecast.sh`,
  `RELAY-FORECAST`). Le Chef de projet savait **où on en est** (backlog `TASK[]`, effort S/M/L,
  règle 70% mécanisée par SCOPE-1 §10) mais pas **quand on arrive** : aucune projection « à ce
  rythme, le backlog retenable se vide dans X sessions » (`VISION.md §115`). C'est le **prolongement
  temporel** de SCOPE-1 (qui mesure la session COURANTE ; le forecast projette le RYTHME). Nouvel
  outil **on-demand séparé**, pair de `relay-stats.sh` (jamais dans le gate pre-commit) :
  - **Points restants** = somme effort des `TASK[]` **retenables** (pending + owner=session +
    depends=[]) au **barème SCOPE-1 S=0.5/M=1/L=2** — *même filtre, même unité* (zéro divergence
    avec la règle 70%).
  - **Vélocité** = points **done** récents ÷ **nb de sessions** récentes (points/session, **pas**
    commit) — fenêtre `--window=N` (défaut 5) ; sessions = `docs/session_logs/*.md` (canonique) ou,
    à défaut, dates distinctes des tâches done (instance).
  - **Projection** = `ceil(restants / vélocité)` en **fourchette** (meilleur → plus faible débit
    observé), jamais un faux point précis.
  - **Honnêteté de calibration** : < 2 sessions ou 0 tâche done → « historique insuffisant » (jamais
    un chiffre inventé) ; backlog retenable vide → « 0 session ».
  - **Alerte de dérive** (scope-creep *tendanciel*, `VISION.md §116`, distincte de SCOPE-1 qui mesure
    la session courante) : sur la fenêtre, points **ajoutés** au backlog vs points **fermés**
    (via `git diff`, offline) → backlog qui grossit plus vite qu'il ne se vide.
  - **Informatif pur** : `exit 0` TOUJOURS — ne bloque ni n'alourdit aucun commit (n'est PAS un gate),
    mode `--json` réutilisable. Surcharges : `RELAY_FORECAST_WINDOW`, `RELAY_FORECAST_DRIFT_THRESHOLD`.
  - **0 migration** `rules.conf` : le nouveau script tombe dans le glob `engine/scripts/*.sh` propagé
    par `relay-init`/`relay-update` (aucune section d'instance à seeder). `ci.yml` : 1 assert
    (script propagé + exécutable + exit 0). Smoke-test jetable déterministe **21/21 PASS** (projection
    exacte, insuffisant, vide, dérive↑/↓, exit 0). `shellcheck -S error` CLEAN.
  - **Décisions user (AskUserQuestion)** : (3.2) script séparé `relay-forecast.sh` ; (3.1) points done
    ÷ nb sessions (fenêtre récente) ; (3.3) projection **+ alerte de dérive** ; (3.4) informatif pur.
  - **Priorité 5 (roadmap VISION §12) COMPLÈTE** — dernier item livré.

## [1.14.0] — 2026-06-19

### Added
- **Regression Pattern Memory** — rôle « Auditeur qualité » (`relay-check.sh §12`, `QUAL-1`).
  Le Regression Shield bloquait les patterns **déjà déclarés** interdits mais restait **aveugle aux
  bugs neufs** : quand une session corrigeait un bug (un finding de `KNOWN_ISSUES.md` passe
  `✅ RÉSOLU`), **rien** ne rappelait d'enregistrer le pattern correspondant → le même bug pouvait
  **revenir**. Désormais, dans la **branche non-sécu de §9c** (finding résolu **sans** marqueur
  `[security_surface]` → partition propre, **zéro double-fire** avec la sécu), si **aucun** pattern
  n'a été ajouté au nouveau tier `[regression_warn]` de `rules.conf` dans le même commit stagé →
  **un WARNING signal-only** invite à l'enregistrer. Le **nouveau tier `[regression_warn]`** (§7b) est
  scanné en **WARNING** (≠ `[forbidden_patterns]` ERREUR) : plus sûr à auto-alimenter — un pattern
  imparfait ne bloque **jamais** à tort. Le déclencheur est **déterministe** (grep, 0 token LLM), la
  puce reste **curatée** par l'humain (jamais auto-écrite) ; « pas de pattern applicable » (bug de
  logique/timing) est une réponse **légitime** → le trigger invite, ne harcèle pas.
- **Migration `relay-update §2h`** — seede la section `[regression_warn]` dans les `rules.conf`
  existants (sinon le tier ne toucherait que les nouveaux projets — angle mort SEC-1b). Idempotent.
- **`ci.yml`** — assert que le moteur propagé porte §12 + que `[regression_warn]` est présent.
- **Décisions user** (`AskUserQuestion`) : cible = **nouveau tier `[regression_warn]` (WARNING)** ;
  signal = finding **non-sécu** seulement (partition propre) ; sévérité = **WARNING signal-only**.

## [1.13.0] — 2026-06-19

### Added
- **Decision Trigger** — rôle « Architecte connaissance » (`relay-check.sh §11`, `DECISION-TRIGGER`).
  Une **décision architecturale** (nouvelle dépendance, nouveau projet, nouvelle interface Domain…) est
  souvent prise **implicitement** dans un commit, **sans être tracée** dans `docs/context/DECISIONS.md` →
  la connaissance se perd (pourquoi ce choix ? quelles alternatives rejetées ? sous quelle condition
  réviser ?). `relay-check.sh` lit désormais une section `[decision_surface]` de `rules.conf` (**MARQUEURS
  structurels**, moteur vierge — vocabulaire en instance). Si le **diff stagé** en touche un **ET** qu'aucune
  entrée `## DEC-` n'a été ajoutée à `DECISIONS.md` dans le même commit → **un avertissement signal-only**
  « trace cette décision (choix / alternatives rejetées / condition de révision) ».
- **Signal-only** : n'altère **jamais** l'exit code — l'architecture est un jugement, le LLM est la couche
  faible : le déterministe **rappelle**, l'humain **décide** (pas d'auto-classification bloquante, pas
  d'auto-rédaction de la décision). **Token-négatif** (grep, réutilise `parse_security_section` — miroir exact
  de la famille `§9b`/`§9c`). **Calibration ÉTROITE** (structurels forts seulement, **exclut** migration EF /
  test / refacto local) → 0 faux positif sur un diff réaliste.
- **Migration `relay-update §2g`** (v1.13.0) : seede la section `[decision_surface]` dans les `rules.conf`
  **existants** (sinon le trigger ne toucherait que les nouveaux projets — angle mort SEC-1b). Idempotent.
- `RELAY_PROTOCOL.md` — 1 section formalise le déclencheur (anti-inflation : compensée par la fusion de la
  note « budget session » dans la référence `§10` Scope-Creep).

### Forks tranchés (AskUserQuestion, ouverture de session)
- **Signal** = marqueurs `[decision_surface]` (déterministe, offline, cohérent SEC-2 — pas le message de commit).
- **Trace attendue** = entrée `## DEC-` dans `DECISIONS.md` (miroir « puce de prose » SEC-4).
- **Sévérité** = WARNING signal-only. **Calibration** = étroite (structurels forts seulement).

## [1.12.0] — 2026-06-19

### Added
- **Scope-Creep Alert** — rôle « Chef de projet » (`relay-check.sh §10`, `SCOPE-1`). **Mécanise** la
  règle des 70% qui n'existait jusqu'ici qu'en **prose** (`RELAY_PROTOCOL.md §2 étape 4`) : le LLM est la
  couche faible (il s'auto-déclare « ça tient »). `relay-check.sh` somme désormais l'effort des `TASK[]`
  **retenables** cette session — `status=pending` **+** `owner=session` **+** `depends=[]` (non bloquées) —
  au barème protocole **S=0.5 / M=1 / L=2**. Si la somme dépasse le **budget 70%** (défaut **3.5 pts**,
  surchargeable via `RELAY_SCOPE_BUDGET`) → **un avertissement signal-only** « scope-creep : retiens un
  sous-ensemble, reporte le reste ».
- **Signal-only** : n'altère **jamais** l'exit code (heuristique → guide, cohérent SEC-2/SEC-4 ; l'arbitrage
  de périmètre reste humain). **Token-négatif** (réutilise le format `TASK[]` déjà parsé, 0 nouveau
  vocabulaire d'instance). Ne compte **que** les tâches **non bloquées** (`depends=[]`) → un gros backlog
  majoritairement bloqué **ne déclenche pas** (≠ creep). Aucune migration `relay-update` (`relay-check.sh`
  se propage seul par la boucle de copie).
- `RELAY_PROTOCOL.md §2` — étape 4 formalise le déclencheur mécanisé.

### Notes
- Vérifié : `shellcheck -S error` CLEAN ; **10/10 PASS** (smoke-test jetable — sous-budget ✅, sur-budget ⚠️,
  backlog bloqué ≠ creep, seuil configurable, exclusion bloquées/owner=user/status=done, budget invalide →
  repli 3.5, frontière exacte 3.5 ≤ / 4.0 >). Log : `docs/session_logs/2026-06-19_SCOPE-1-SCOPE-CREEP-ALERT.md`.

## [1.11.0] — 2026-06-19

### Added
- **Security Pattern Memory** — rôle « Spécialiste cybersécurité », **Couche 4** (auto-feed de
  `SECURITY_RULES.md`, `SEC-4`). `relay-check.sh` (§9c) détecte qu'une **correction de sécurité** a
  atterri — un finding de `KNOWN_ISSUES.md` passe `✅ RÉSOLU` dans le diff stagé **et** ce diff porte un
  marqueur `[security_surface]` (réutilise le vocabulaire d'instance → moteur vierge, comme §9b). Si la
  section `Patterns appris` de `SECURITY_RULES.md` n'a **pas** reçu de puce dans le même commit → **un
  avertissement signal-only** invitant à enregistrer le pattern appris, pour que la session suivante ne
  réintroduise pas le bug corrigé (miroir du Regression Shield, transposé à la sécurité).
- Le **déclencheur** est déterministe (grep) ; la **puce** reste **curatée par l'humain** — on n'auto-écrit
  jamais de la sécurité (le LLM est la couche faible). Token-**neutre** (1 puce ciblée, soumise à la jauge
  densité anti-inflation). **Aucune migration `relay-update`** : `relay-check.sh` se propage seul par la
  boucle de copie, et `SECURITY_RULES.md` est déjà seedé (Couche 2, v1.10.0).
- `RELAY_PROTOCOL.md §4b` — étendu : après un fix sécu, enregistrer un pattern appris (Couche 4).

### Notes
- **Lucidité** (inchangée) : gate commit/CI, **pas** un IDS/WAF runtime — ne remplace pas un pentest.
  WARNING signal-only : la détection est heuristique (faux positifs assumés), elle guide sans bloquer.
- **Rôle « Spécialiste cybersécurité » COMPLET** : Couche 1 (gate déterministe, `SEC-1`/`SEC-1b`, v1.8.x)
  + Couche 3 (CI, `SEC-3`, v1.9.0) + Couche 2 (ancrage sélectif, `SEC-2`, v1.10.0) + Couche 4 (auto-feed,
  `SEC-4`, v1.11.0).

## [1.10.0] — 2026-06-19

### Added
- **Security Surface Trigger** — rôle « Spécialiste cybersécurité », **Couche 2** (ancrage sécu sélectif,
  `SEC-2`). `relay-check.sh` (§9b) lit une 3ᵉ section `rules.conf` `[security_surface]` : des **marqueurs**
  de surface sensible (authN, authZ/IDOR, secrets, crypto, + per-stack commentés — **pas** des dangers).
  Touchés dans le diff stagé → **un avertissement signal-only** « ancrer `SECURITY_RULES.md` ». C'est le
  déclencheur **déterministe** qui rend l'ancrage sécu **sélectif** : la checklist n'est chargée **que** si
  une surface est touchée → **token-négatif** (`VISION.md §4`), jamais en permanence. Réutilise le grep de
  la Couche 1 (`parse_security_section`).
- **`templates/docs/rules/SECURITY_RULES.md`** — checklist d'ancrage (5 axes : authN / authZ-IDOR /
  validation / secrets / moindre-privilège + exemples per-stack .NET/Flutter/JS/Python + section
  `Patterns appris` réservée à la Couche 4 `SEC-4`). Fichier d'**instance** (propriété du projet).
- `relay-init.sh` — `render` de `SECURITY_RULES.md` au bootstrap.
- `relay-update.sh` (§2f, migration v1.10.0) — **seede** la section `[security_surface]` **et** dépose
  `SECURITY_RULES.md` dans les projets existants si absents (miroir des migrations §2b→§2e). Idempotent.
- `RELAY_PROTOCOL.md §4b` — formalise l'ancrage sécu sélectif (sélectif = token-négatif ; WARNING, pas
  bloquant car détection heuristique ; le gate dur reste la Couche 1).
- `.github/workflows/ci.yml` (canonique) — le smoke-test vérifie que `relay-init` dépose `SECURITY_RULES.md`
  et seede la section `[security_surface]` dans `rules.conf`.

### Lucidité
- Couche 2 reste un **gate commit/CI**, **pas** un IDS/WAF runtime — ne remplace pas un pentest. WARNING
  signal-only (heuristique → guide, ne gate pas). Le verdict reste humain.

## [1.9.0] — 2026-06-19

### Added
- **Workflow CI RELAY** (`templates/.github/workflows/relay-ci.yml`) — rôle « Spécialiste cybersécurité »,
  **Couche 3** (outillage CI, `SEC-3`). Gate déposé dans chaque projet : `relay-check --strict` (verdict
  **structure/protocole** mécanique) + **gitleaks** (verdict **outil** sur les secrets, scan PR + historique,
  0 token LLM). Division honnête : le Security Shield (§9) scanne le diff **stagé** → il vit au commit (hook
  pre-commit local), pas en CI ; la CI ajoute le scan secrets sur tout le dépôt. **Lucidité** : gate CI, **pas**
  un IDS/WAF runtime — ne remplace pas un pentest.
- `relay-init.sh` — dépose `.github/workflows/relay-ci.yml` au bootstrap (copie-si-absente ; fichier
  d'**instance**, jamais écrasé). Pas via `render()` : le YAML GitHub Actions contient `${{ }}`.
- `relay-update.sh` (§2e, migration v1.9.0) — **seede le workflow dans les projets existants** s'il est
  absent (miroir des migrations §2b/§2c/§2d). Idempotent : un workflow déjà présent reste intact. Sans ce
  seeding, seuls les **nouveaux** projets auraient eu la CI.
- `.github/workflows/ci.yml` (repo canonique) — le smoke-test vérifie désormais que `relay-init` dépose le
  workflow, que c'est un **YAML valide**, et qu'il invoque bien `relay-check --strict` + `gitleaks`.

## [1.8.1] — 2026-06-19

### Added
- `relay-update.sh` (§2d, migration v1.8.0) — **seeding des sections sécu dans les `rules.conf` existants**
  (`SEC-1b`). Un projet initialisé **avant** v1.8.0 n'avait pas `[security_forbidden]`/`[security_warn]` ;
  à la prochaine mise à jour, ces sections sont **ajoutées** (patterns universels actifs + per-stack
  commentés), idempotent au niveau section (si déjà présentes → intactes, données d'instance). Sans ce
  seeding, le Security Shield ne touchait que les **nouveaux** projets. Miroir exact des migrations
  v1.3.0 (`[forbidden_patterns]`) et v1.4.0 (`[design_warn_*]`).

## [1.8.0] — 2026-06-19

### Added
- **Security Shield** (`relay-check.sh` §9, piloté par `rules.conf`) — rôle « Spécialiste cybersécurité »,
  Couche 1 (gate déterministe). Scanne le diff stagé (code **et** config) contre deux sections d'instance :
  `[security_forbidden]` (sévérité **ERREUR** → bloque le commit) et `[security_warn]` (WARNING). Format
  `<regex> | msg=<remédiation> | exclude=<regex contenu> | exclude-path=<fragment>`. **0 token LLM** : pur
  `grep` déterministe — fait le travail que le LLM ferait en lisant (token-négatif, `VISION.md §4`).
- `templates/docs/.relay/rules.conf` — sections `[security_forbidden]`/`[security_warn]` seedées :
  **patterns universels actifs** (clé privée en clair, clé AWS `AKIA…`, hash faible MD5/SHA1, secret en clair,
  identifiant en query string = risque IDOR) + **exemples per-stack commentés** (.NET/Python/Go/Node/React).
  Le moteur ne fournit que le **mécanisme** ; les patterns vivent dans l'instance (« moteur = 0 donnée projet »).
- `docs/SECURITY-ROLE-PLAN.md` — cadrage des 4 couches du rôle (gate déterministe · ancrage sélectif · CI
  outillée · `SECURITY_RULES.md` auto-alimenté) + test tokens par couche + séquencement + découpage `TASK[SEC-*]`.

### Notes
- **Lucidité** : gate commit/CI, **pas** un IDS/WAF runtime — ne remplace pas un pentest.
- Section sécu absente/vide → Shield inactif **annoncé** (jamais muet), miroir des Regression/Design Shields.
- Reste à faire (suite du fil) : `SEC-1b` (seeding des sections sécu dans les `rules.conf` existants via
  `relay-update`), `SEC-3` (CI gitleaks/semgrep), `SEC-2`/`SEC-4` (ancrage sélectif + auto-feed).

## [1.7.0] — 2026-06-19

### Added
- `relay-update.sh` : **prompt accept/décline** (T6-3) en run normal. Quand une mise à jour est
  disponible et que l'on est en terminal (TTY), le script affiche le delta de `CHANGELOG.md`
  (réutilise `print_changelog_delta`) **avant d'appliquer**, puis attend `[o/N]` ; un refus sort
  `0` sans modifier le moindre fichier. Le prompt est placé **avant** le self-update §1c — rien,
  pas même `relay-update.sh` lui-même, n'est touché sans consentement.
- `relay-update.sh` : bypass non-interactif `--yes` / `-y` / `--non-interactive`, **et** auto-détection
  `[ -t 0 ]` → application automatique sans blocage en CI, hooks et pipelines (jamais de prompt
  suspendu). La confirmation obtenue est propagée à travers le re-exec du self-update
  (`RELAY_UPDATE_CONFIRMED=1`) → jamais de double demande.

## [1.6.0] — 2026-06-19

### Fixed
- **Self-update bootstrapping de `relay-update.sh` (angle mort §1b)** : le script de mise à jour
  ne se propageait pas lui-même (la boucle de copie ne traite que `engine/scripts/*.sh`, or
  `relay-update.sh` vit dans `bin/`). Un consommateur lançant son ancien
  `docs/scripts/relay-update.sh` copiait le moteur récent mais rejouait son **ancienne** logique
  de migration (`rules.conf` non seedé, shields inactifs jusqu'à un 2ᵉ run).

### Added
- `relay-update.sh` : étage de **self-update « stage 1 → re-exec stage 2 »**. Stage 1 détecte que
  le script courant diffère du `bin/relay-update.sh` canonique, le copie sur lui-même, puis
  `exec` stage 2 (garde `RELAY_SELFUPDATE_STAGE2`) qui rejoue la migration avec la logique à jour
  — correct en **un seul run**. Idempotent (script déjà à jour → aucun saut, aucune boucle),
  jamais déclenché depuis le canonique (`bin/`, on n'écrase pas la source) ni en `--check`.

## [1.5.0] — 2026-06-19

### Added
- `CHANGELOG.md` (ce fichier) : journal machine-lisible des versions au format Keep a Changelog,
  source unique du delta d'améliorations affiché à l'utilisateur lors d'une mise à jour.
- `relay-update.sh --check` : **Update Advisor** en lecture seule (dry-run, non bloquant).
  Localise le canonique (y compris clone `--depth 1` d'une URL git), compare la version moteur
  installée à la version canonique et, en cas de retard, affiche les entrées de changelog entre
  les deux. N'écrit aucun fichier d'instance, sort `0` — scriptable et offline-safe.
- `RELAY_PROTOCOL.md §6` : étape de clôture □8 — tout bump de `VERSION` (canonique) ajoute une
  entrée `CHANGELOG.md`.

## [1.4.0] — 2026-06-18

### Changed
- **Externalisation du Design System Shield** (§8 du moteur) : les patterns, messages et
  exclusions de design vivent désormais dans `docs/.relay/rules.conf`
  (sections `[design_warn_flutter]` / `[design_warn_css]`) au lieu de tableaux codés en dur.
  Pureté moteur **totale** (aucune donnée de projet en dur ne subsiste).
- Sévérité du Design System Shield conservée à `WARNING` (ne bloque jamais le commit) ;
  section absente → shield inactif annoncé explicitement (pas de silence).

### Added
- `relay-update.sh` : migration v1.4.0 **idempotente au niveau section** — ajoute les sections
  DS à un `rules.conf` existant (projet déjà migré en v1.3.0) sans rien réécrire → zéro perte.

## [1.3.0] — 2026-06-18

### Changed
- **Externalisation des règles du Regression Shield** : les motifs interdits, jusque-là codés
  en dur et spécifiques à AgriConnect, quittent le moteur. Chaque projet déclare désormais ses
  propres motifs dans `docs/.relay/rules.conf` (instance, committé).

### Added
- `relay-update.sh` : migration v1.3.0 qui seede l'ancienne liste de motifs au premier update
  → zéro perte de garde pour les projets existants.

### Fixed
- Un projet sans `rules.conf` voit le Regression Shield **inactif + avertissement explicite**
  (jamais d'assouplissement silencieux).

## [1.2.0] — 2026-06-18

### Added
- `relay-run.sh` : wrapper de preuve transparent qui exécute une commande et émet un reçu
  (`docs/.relay/receipts/<hash>.log`) à citer sous la forme `[verified-run:<hash>]`.
- `relay-check.sh` : porte de reçu — un `[verified-run:<hash>]` sans reçu existant devient une
  **erreur** (preuve falsifiée) ; un `[verified-run]` nu reste un avertissement signal-only.

### Changed
- Rétrocompatibilité prouvée par exécution : une instance existante (runs nus, aucun reçu)
  conserve exactement le même exit code, score et set d'erreurs qu'en v1.1.1.

## [1.1.1] — 2026-06-12

### Added
- GitHub Action (`.github/workflows/ci.yml`) : `shellcheck --severity=error` sur `engine` + `bin`,
  garde de **pureté moteur** (aucune identité de projet en dur) et smoke test (bootstrap
  `relay-init` → `relay-check` produit un Health Score, zéro placeholder résiduel).

### Fixed
- `relay-brief.sh` : SC1087 (`$LAST_DATE[[:space:]]` → `${LAST_DATE}`), bug latent capté par la CI.

## [1.1.0] — 2026-06-12

### Added
- `relay-split.sh` : fractionne automatiquement `NEXT_SESSION.md` au-delà de 150 lignes
  (déjà référencé par l'avertissement de taille de `relay-check.sh`, manquait au canonique).
  Agnostique, propagé à tous les consommateurs.
- `docs/VISION.md` + `docs/FRAMEWORK_SPEC.md` : vision/feuille de route et spécification de
  robustesse (référence du framework, non propagées aux consommateurs).

## [1.0.0] — 2026-06-12

### Added
- Moteur canonique RELAY : séparation **MOTEUR** (propagé) / **INSTANCE** (jamais touché) /
  **TEMPLATE** (seed-once).
- `relay-init.sh` (bootstrap d'un nouveau projet), `relay-update.sh` (propage le moteur seul),
  `docs/.relay-version` + avertissement de skew dans `relay-check.sh`.
- Durcissement de la frontière : seul `RELAY_PROTOCOL.md` se propage ; `RELAY_METRICS.md`
  (compteurs) et `RELAY_RULE_POOL.md` (registre human-gated) reclassés TEMPLATE seed-once
  → un update n'écrase plus aucune donnée de projet.

[Non publié]: https://github.com/GitAmboudilaye/relay/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/GitAmboudilaye/relay/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/GitAmboudilaye/relay/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/GitAmboudilaye/relay/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/GitAmboudilaye/relay/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/GitAmboudilaye/relay/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/GitAmboudilaye/relay/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/GitAmboudilaye/relay/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/GitAmboudilaye/relay/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/GitAmboudilaye/relay/releases/tag/v1.0.0
