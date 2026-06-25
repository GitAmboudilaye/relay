# RELAY — État des capacités v1.x + mise à l'épreuve des rôles

> ## ⏩ MISE À JOUR CLÔTURE 2026-06-25 (canonique v1.22.1) — lire en premier
> Le corps de ce document est l'**instantané de la phase passive** (v1.15.0, daté 2026-06-20) et reste
> exact comme **historique**. Depuis, deux choses ont changé le verdict ci-dessous :
>
> **1. Les rôles sont passés de « prouvés en sandbox » à « vivants en projet réel ».** Le bootstrap §3
> (alors reporté, consommateurs à v1.4.0) **a eu lieu** : AgriConnect et DeepManagment tournent en
> **v1.23.0**. La colonne « éprouvé en conditions réelles » du §2 — partout `❌ PAS encore` à l'époque de
> l'instantané (consommateurs à v1.4.0) — est **fausse aujourd'hui** et corrigée ci-dessous. Deux faits :
>
> > **(a) Les 5 rôles PASSIFS s'exécutent sur de vrais commits.** Le `.git/hooks/pre-commit` d'AgriConnect
> > lance **`relay-check.sh --strict`** (qui porte `§9` SEC-1, `§10` SCOPE-1, `§11` DECISION-TRIGGER,
> > `§12` QUAL-1) sur tout commit touchant du `.cs/.dart`. Depuis la propagation, cela représente
> > **46 commits `.cs`** (sur 102) — épic comptable, PROD-UPGRADE, DS-PAGES… : le gate des 5 rôles a donc
> > tourné **en conditions réelles**, pas en sandbox. **Nuance honnête** : sur du code surtout propre il a
> > surtout tourné **en silence** (sain) — « exécuté sur de vrais diffs » ✅ ≠ « a attrapé une régression
> > réelle à répétition » (cela, mince, et surtout côté actif ci-dessous).
> >
> > **(b) La couche ACTIVE a firé sur du réel** : le hook Claude Code a **deny en live** sur de vrais Edit,
> > le gate no-agent tourne sur le pre-commit AgriConnect, le hook Cline est câblé sur DeepManagment — et
> > c'est le ledger live de l'actif qui a **trouvé 2 faux positifs** corrigés au noyau (v1.19.1, v1.22.1).
>
> **Ce qui reste légitimement `❌` n'est PAS l'exécution terrain, mais la généralisation** : un dev **tiers**
> (pas l'auteur) et/ou un **2ᵉ stack** qui tiennent N sessions conformes. C'est ça le plafond ~5-6/10 (§6),
> distinct de « le gate tourne-t-il sur du vrai code » (oui).
>
> **2. La couche ACTIVE (temps-réel) a été conçue et livrée** — elle n'existait pas à v1.15.0. **3 adaptateurs
> publics** câblent le **même noyau** (`relay-context.sh`) dans 3 canaux, sans coupler le noyau (cadrage →
> [`RELAY-CORE-ACTIF.md`](RELAY-CORE-ACTIF.md)) :
>
> | Adaptateur | Canal | Sémantique d'enforcement | Câblé sur |
> |---|---|---|---|
> | **Claude Code** (v1.18.0) | hook `PreToolUse` | ERROR→`deny`, WARN/INFO→`additionalContext`, rien→silence | AgriConnect ✅ (firing live) |
> | **Cline** (v1.20.0) | hook `PreToolUse` (v3.36+) | ERROR→`{"cancel":true}`, sinon `{"cancel":false}` (ALLOW explicite) | DeepManagment ✅ |
> | **No-agent** (v1.21.0) | git pre-commit / CI | code de sortie : ERROR→exit 1 ; fail-**OPEN** outillage / fail-**CLOSED** finding | AgriConnect ✅ (`--diff-only`) |
>
> **+ métrique token-saved** (`relay-tokens.sh` + ledger d'instance, v1.19.0) — concrétise l'angle produit
> `VISION §4` : token-in (~40/firing) vs token-saved (~2000/deny, contrefactuel modélisé). **+ 2 correctifs
> noyau de faux positifs trouvés par le ledger live** : prose `.md` (v1.19.1), ligne 100 %-commentaire dans
> du code (v1.22.1). **+ mode `--diff-only`** (v1.22.0) qui débloque le brownfield.
>
> **Preuve de généralisation : 4/10 → 5/10.** L'examen cross-LLM DeepSeek
> (examen interne, non publié) prouve la **portabilité** du protocole à un
> LLM non-Claude (format + MRS + archi DDD adoptés sans coaching) mais casse la thèse « le passif compense la
> discipline » (produit hors-git → gate au commit inerte). Le chiffre §6 ci-dessous (« 4/10 ») est donc
> **remplacé par 5/10** ; le besoin neuf **R1** (garde d'état-git en clôture) est inscrit à la feuille de route.
> **Caveat** : l'examen DeepSeek ne portait que sur le **passif** (hook actif câblé après) → l'avant/après
> actif reste à mesurer.
>
> ---
>
> **Référence non propagée** (remplace l'ancienne évaluation v1.7, retirée du dépôt public).
> But : cartographier honnêtement **les 5 rôles que RELAY prétend jouer** au canonique **v1.15.0**,
> et **distinguer ce qui est prouvé mécaniquement de ce qui reste à éprouver en conditions réelles**
> (`docs/VISION.md §346`).
> Sources de vérité : `CHANGELOG.md`, `docs/VISION.md`, logs `docs/session_logs/`. Chaque chiffre
> ci-dessous a été re-vérifié (MRS) sur ces sources — pas recopié d'un brief.
> Produit dans le fil **RELAY-CAPABILITIES** (2026-06-20, lecture seule, 0 code moteur — décision user :
> GEL des nouvelles fonctions, Priorité 5 COMPLÈTE).

---

## 0. Le cadre honnête

> ⚠️ **Instantané v1.15.0 (2026-06-20) — le « Aucun rôle exécuté sur un vrai diff » ci-dessous est PÉRIMÉ.**
> Le bootstrap a eu lieu depuis ; les 5 rôles tournent sur **46 commits `.cs`** AgriConnect réels (voir
> bandeau de tête + §2). Conservé comme historique de la phase passive.

RELAY a livré, en deux jours de sessions (v1.8.0 → v1.15.0), les **4 items de la Priorité 5**
(`VISION §383-387`) **plus** un rôle Spécialiste cybersécurité complet (4 couches) qui n'était même pas
dans la roadmap chiffrée. Chacun est **prouvé mécaniquement** : smoke-test jetable déterministe et/ou
reçu durable `[verified-run:<hash>]`.

**Mais « prouvé mécaniquement » ≠ « éprouvé sur un projet réel ».** Tous les smoke-tests s'exécutent en
**sandbox** (repo jetable, diff fabriqué pour déclencher le gate). **Aucun** de ces rôles ne s'est encore
exécuté sur un **vrai diff d'un vrai projet** : les deux consommateurs (`AgriConnect`, `Tempow/RH`) sont
restés à **v1.4.0** (cf. §3). C'est la limite centrale que ce document refuse de masquer.

---

## 1. Tableau des 5 rôles (mécanisme · preuve · limite · score)

| Rôle | Mécanisme | Version | Preuve (vérifiée) | Limite lucide | Score VISION |
|---|---|---|---|---|---|
| **Spécialiste cybersécurité** (hors roadmap chiffrée) | `relay-check §9` gate `[security_forbidden]`/`[security_warn]` (SEC-1/1b) · CI `relay-ci.yml` + gitleaks (SEC-3) · `§9b` ancrage sélectif `[security_surface]` (SEC-2) · `§9c` auto-feed pattern (SEC-4) | 1.8.0→1.11.0 | `verified-run:628d1c5aa821`, `789f058bba26`, `b8da379f88c7` (13/0), `20a264e2ad2b`, `f8968436e653` (9/0) | **Gate commit + scan CI, pas un IDS/WAF runtime ni un pentest.** Couches 2/4 = WARNING signal-only (heuristique → guide, ne bloque pas). | (pas de score VISION d'origine — rôle émergent) |
| **Chef de projet** | `§10` SCOPE-1 (règle 70% mécanisée) + `relay-forecast.sh` (projection + alerte de dérive) | 1.12.0 + 1.15.0 | SCOPE-1 **10/10 PASS** · FORECAST **21/21 PASS** | Forecast = **informatif pur** (`exit 0`, jamais un gate). Projette le rythme, ne gère pas les risques externes (le bloqueur VISION). Vélocité non calibrée < 2 sessions. | **7 → 9.0** *(preuve mécanique)* |
| **Scrum Master** + **Release Engineer du moteur** | enforcement in-session (MRS, 70%, clôture) · gate `relay-check` au commit · CHANGELOG + Update Advisor `--check` + self-update bootstrapping | (socle) + 1.5.0→1.7.0 | T6 `verified-run:9e52b0e0199f` · T6-3 `cd003604a44c` · T6-4 `5fd4dd5b1d07` | **Enforcement in-session impossible** (`§350`) : MRS/ANCRAGE/70% s'appliquent avant `git add`, reposent sur la discipline du LLM. La dérive FORECAST est **tendancielle**, pas en cours de session. | **8 → 9.0** *(preuve mécanique)* |
| **Auditeur qualité** | `§12` QUAL-1 Regression Pattern Memory + tier `[regression_warn]` scanné `§7b` (WARNING) | 1.14.0 | **12 PASS / 0 FAIL** | **Pas « auto-alimenté » au sens fort** : déclencheur déterministe (grep) qui *invite*, puce **curatée par l'humain** — le LLM ne s'auto-écrit pas un pattern. « Pas de pattern applicable » est une réponse légitime. | **7 → 8.5** *(preuve mécanique)* |
| **Architecte de la connaissance** | `§11` DECISION-TRIGGER (surface structurelle touchée sans `## DEC-` → WARNING) | 1.13.0 | **13 PASS / 0 FAIL** | **1 des 2 items VISION seulement** : « trigger décision implicite » livré ; **« graphe de dépendances des décisions » non livré** (reporté). Calibration étroite (exclut migration/test/refacto). Signal-only. | **6 → 8.0** *(preuve mécanique)* |

> **Justification des deltas** (`VISION §337-340`, cible 9.5 pour les 4) :
> - **Chef de projet 7→9.0** : les **deux** items du chemin VISION (`§115-116`) sont livrés — `relay-forecast.sh`
>   ET l'alerte scope-creep (SCOPE-1 en session + dérive tendancielle dans le forecast). Plafonné sous 9.5
>   car « gestion des risques externes » (le bloqueur, `§338`) reste hors portée d'un gate offline.
> - **Scrum Master 8→9.0** : Release Engineer **plein** (release/distribution v1.5→1.7). Plafonné sous 9.5
>   car l'enforcement **in-session** est une limite architecturale irréductible (`§350`), non franchie.
> - **Auditeur qualité 7→8.5** : Regression Pattern Memory livré, mais en **trigger + curation** et non en
>   auto-génération complète (l'item VISION `§136` disait « sans intervention manuelle » — choix lucide de
>   ne pas laisser le LLM s'auto-écrire de la qualité). Honnête : c'est un demi-pas vers la cible, pas plus.
> - **Architecte connaissance 6→8.0** : seul le **premier** des deux items (`§129` trigger implicite) est
>   livré ; le **graphe de dépendances des décisions** (`§130`) ne l'est pas. Le delta reflète un item sur deux.

---

## 2. Dimension PREUVE — mécanique vs terrain (`VISION §346`)

C'est la réponse directe à « **mettre à l'épreuve les rôles** ». Pour chaque rôle, deux niveaux distincts :

> **⚠️ Table mise à jour 2026-06-25** : la colonne de droite reflétait l'instantané v1.4.0 (rien propagé,
> tout `❌`). Depuis la propagation, le pre-commit AgriConnect lance `relay-check --strict` (les 5 rôles)
> sur **46 commits `.cs`** réels → l'exécution terrain est **acquise** ; ce qui reste `❌` = le **tiers / 2ᵉ stack**.

| Rôle | Prouvé mécaniquement (smoke / sandbox / `[verified-run]`) | Exécuté en conditions réelles (vrai diff d'un vrai projet) | Généralisé (dev tiers / 2ᵉ stack) |
|---|---|---|---|
| Cybersécurité (SEC-1→4) | ✅ FAIT (5 reçus + 13/0 + 9/0) | ✅ **OUI** — SEC-1 gate sur 46 commits `.cs` AgriConnect (surtout silencieux, code propre) | ❌ pas encore |
| Chef de projet (SCOPE-1 + FORECAST) | ✅ FAIT (10/10 + 21/21) | ✅ **OUI** — SCOPE-1 lit le vrai backlog `TASK[]` à chaque `relay-check` | ❌ pas encore |
| Scrum Master / Release Eng. | ✅ FAIT (3 reçus T6) | ✅ **OUI** — gate `relay-check` au commit sur consommateurs à jour + moteur s'auto-release | ❌ pas encore (tiers) |
| Auditeur qualité (QUAL-1) | ✅ FAIT (12/0) | ✅ **OUI** — `§12` exécuté au commit (silencieux : peu de régressions réelles) | ❌ pas encore |
| Architecte connaissance (§11) | ✅ FAIT (13/0) | ✅ **OUI** — `§11` exécuté au commit (silencieux : surfaces structurelles rarement touchées) | ❌ pas encore |

> **Conclusion §346 — mise à jour 2026-06-25 : preuve de généralisation 4/10 → 5/10.** Trois niveaux,
> désormais distincts :
> 1. **Mécanique** (le code fait ce qu'il dit en sandbox) : ✅ fort — smoke déterministes, reçus durables, CI verte.
> 2. **Exécution terrain** (le gate tourne sur de vrais commits) : ✅ **acquise** — le bootstrap (§3) a eu
>    lieu, `relay-check --strict` tourne sur 46 commits `.cs` AgriConnect + la couche active a firé en live.
>    *Nuance* : surtout silencieux (code propre) → exécuté ≠ « a attrapé du réel à répétition ».
> 3. **Généralisation** (un dev **tiers** / un **2ᵉ stack** qui tiennent N sessions sans coaching) : ❌ **toujours
>    pas** — c'est *ça* le plafond. L'examen cross-LLM DeepSeek (portabilité du protocole prouvée, §banner)
>    monte le chiffre à **5/10** ; tant que l'auteur reste le seul opérateur, le plafond structurel est ~5-6.
>
> Les scores per-rôle du §1 restent marqués « (preuve mécanique) » : ils intègrent la mécanique + l'exécution
> terrain, mais **ne franchissent pas** la généralisation tierce — c'est ce dernier niveau qui les ferait monter.

---

## 3. Constat de propagation — moteur complet mais **pas vivant** (pont vers AgriConnect)

**Vérifié 2026-06-20** sur les fichiers `.relay-version` des consommateurs :

| Consommateur | Repo | Version installée | Canonique | Écart |
|---|---|---|---|---|
| AgriConnect | `AgriConnectBackend/docs/.relay-version` (PROJECT=AgriConnect) | **1.4.0** (2026-06-18) | 1.15.0 | **11 versions** |
| Tempow / RH | `DeepManagment/docs/.relay-version` (PROJECT=Tempow) | **1.4.0** (2026-06-18) | 1.15.0 | **11 versions** |

**Conséquences factuelles :**
- `relay-forecast.sh` **absent** des deux (script ajouté en 1.15.0).
- Leur `relay-update.sh` est **antérieur à l'Update Advisor** (`--check`/prompt/self-update ajoutés
  v1.5.0/1.6.0) → la MAJ **ne sera PAS auto-proposée** à leur prochaine session (caveat *forward-only* T6-4).
- Donc **aucun des 5 rôles n'est vivant dans un projet réel.** Tout ce qui précède (§1, §2) vaut en
  sandbox uniquement.

**Action requise = bootstrap manuel unique** (la MAJ ne s'auto-propose pas) :
```bash
RELAY_CANONICAL=/home/ambou/projects/relay \
  bash /home/ambou/projects/relay/engine/bin/relay-update.sh   # ajuster au chemin réel du bin
```
> **Décision user (2026-06-20)** : bootstrap **reporté au retour AgriConnect** (fork 3.1=a), **AgriConnect
> seul** (Tempow reste en pause). Le bootstrap sera la **1ʳᵉ action de reprise AgriConnect** : c'est
> exactement là que les rôles passeront de « prouvé mécaniquement » à « éprouvé terrain » (§2). **Ce
> document est donc le pont** entre la phase Relay (close ici) et la reprise AgriConnect.

---

## 4. Token-discipline (contrainte non négociable `VISION §4`)

Chaque rôle a été conçu **token-négatif ou neutre** — un RELAY qui consomme plus de tokens pour « mieux
se souvenir » a échoué (`§105`) :

| Rôle | Pourquoi token-négatif / neutre |
|---|---|
| Cybersécurité | `grep`/`shellcheck`/`gitleaks` (0 token LLM) ; ancrage sécu **sélectif** (§9b) — checklist chargée *seulement* si surface sensible touchée, jamais en permanence |
| Chef de projet | SCOPE-1 = somme arithmétique au commit ; FORECAST = script on-demand séparé, **jamais** dans le gate |
| Scrum Master / Release Eng. | enforcement par convention au commit ; Update Advisor = diff CHANGELOG lu mécaniquement |
| Auditeur qualité | trigger `grep` déterministe ; 1 puce curatée (jauge de densité) |
| Architecte connaissance | `grep` réutilisant `parse_security_section` (moteur vierge) ; 1 entrée `## DEC-` |

---

## 5. Ce qui reste / hors périmètre (GELÉ — pistes futures, non implémentées)

Décision user (2026-06-20) : **gel des nouvelles fonctions**. Les manques ci-dessous sont **notés, pas
implémentés** :

- **Graphe de dépendances des décisions** (`VISION §130`) — 2ᵉ moitié du rôle Architecte connaissance.
- **Axe 1 CI avancé** — semgrep / audit de dépendances (au-delà de gitleaks ; `§12-Axe1`).
- **Axe 2** — split ADR, graphe de décisions structuré.
- **Validation cross-LLM comportementale** — le caveat d'agnosticité (stack prouvée sandbox, cross-LLM
  non) reste ouvert ; le 2ᵉ pilote Tempow/RH est en pause.
- **Multi-agents** (`§412 Priorité 7`).

> **Le vrai prochain pas n'est pas une nouvelle fonction** : c'est le **bootstrap §3** qui transforme la
> preuve mécanique en preuve terrain. C'est aligné avec le gel — éprouver l'existant avant d'ajouter.

---

## 6. Verdict

- **Moteur** : 5 rôles livrés et **prouvés mécaniquement** à v1.15.0. Priorité 5 VISION **complète**.
- **Preuve** : forte en sandbox, **nulle en terrain** — généralisation toujours à **4/10** (`§344`).
- **Distribution** : moteur complet **mais pas vivant** chez les consommateurs (v1.4.0).
- **Action déterminante** : bootstrap v1.15.0 → AgriConnect, en ouverture de la reprise AgriConnect.

*RELAY-CAPABILITIES clôt la phase Relay. Étape suivante = AgriConnect (bootstrap d'abord, puis backlog —
décision terrain comptable `MODULE_EXPEDITIONS_COMPTA_EVOLUTION.md §2`, ou tâche sûre `EXP-AUDIT-SECU-WEB`).*
