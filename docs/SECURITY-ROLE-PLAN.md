# Cadrage — Rôle « Spécialiste cybersécurité » de RELAY

> Fil 2 (direction user 2026-06-19) : enrichir les compétences de RELAY. Cette piste est **en tête de
> Priorité 5** (`VISION.md §12`). C'est une **promotion** d'un rôle déjà partiel (ancrage IDOR, gating
> P0/P1, Regression Shield), pas un rôle neuf.
>
> **Principe directeur non négociable (`VISION.md §4`)** : chaque couche doit **réduire** la consommation
> de tokens, pas l'augmenter. Une couche qui échoue à ce test n'entre pas.
>
> **Lucidité (à répéter dans chaque livrable)** : RELAY reste un **gate commit + CI**, *pas* un IDS/WAF
> runtime. Il ne remplace pas un pentest. Conçu en **couches où le LLM est la couche faible** — on ne
> demande **pas** au LLM de juger sa propre sécurité (l'excès de confiance à éviter) ; on délègue le
> verdict à du déterministe (grep, outils) chaque fois que possible.

## Les 4 couches + test tokens

| # | Couche | Quoi | Test tokens | Mécanisme |
|---|---|---|---|---|
| **1** | **Gate déterministe** | regex sécu dangereuses dans `rules.conf` (clé privée/secret en clair, SQL concaténé, crypto faible, IDOR `?id=`, TLS désactivé) | ✅ **négatif** — pur `grep` dans relay-check/CI, **0 token LLM** ; fait le travail que le LLM ferait en lisant | étend `[forbidden_patterns]` (mécanisme prouvé) → nouvelles sections `[security_forbidden]`/`[security_warn]` |
| **2** | **Ancrage sécu sélectif** | checklist authN / authZ-IDOR / validation / secrets / moindre-privilège, chargée **seulement si surface sensible touchée** | 🟡 **négatif SI sélectif** — déclenchée par un grep (surface détectée), **jamais** chargée en permanence (sinon inflationniste) | `SECURITY_RULES.md` chargé conditionnellement + trigger protocole |
| **3** | **Outillage CI** | semgrep / gitleaks / audit deps ; relay-check honore le verdict | ✅ **négatif** — délègue à des outils déterministes (rejoint Axe 1 CI/CD `§12`) | GitHub Actions + relay-check |
| **4** | **`SECURITY_RULES.md` auto-alimenté** | chaque correction sécu → pattern ajouté (miroir Regression Shield) | 🟡 **neutre** (écriture ciblée) — soumis à la jauge densité pour éviter l'inflation | auto-feed depuis les commits de fix |

## Séquencement

1. **Couche 1 — Gate déterministe** ← *cette session*. La plus token-négative, autonome, étend un
   mécanisme déjà prouvé. Socle des autres couches.
2. **Couche 3 — CI** (rejoint Axe 1 CI/CD) : `relay-check --strict` + gitleaks/semgrep en GitHub Actions.
   Donne la « réactivité » réelle (verdict outil, pas avis LLM).
3. **Couche 2 — Ancrage sélectif** : nécessite le trigger de détection de surface sensible (réutilise
   le grep de la Couche 1) → chargement conditionnel de la checklist.
4. **Couche 4 — Auto-feed** : dernier, car dépend d'un `SECURITY_RULES.md` mûr (Couche 2) + de la
   discipline densité (anti-inflation).

## Décisions d'archi (tranchées avec l'user, AskUserQuestion 2026-06-19)

- **D-SEC-1** : périmètre S1 = **cadrage doc + Couche 1** (gate déterministe), pas cadrage-seul ni Couche 1+CI.
- **D-SEC-2** : **patterns universels actifs + per-stack seedés (commentés)**. Le **moteur ne fournit que
  le mécanisme** ; les patterns vivent dans `rules.conf` d'instance (respecte « moteur = 0 donnée projet »).
  Seuls les patterns **quasi-zéro faux positif** bloquent (`[security_forbidden]`) ; les heuristiques utiles
  mais bruitées avertissent (`[security_warn]`).

## Découpage des tâches

- `TASK[SEC-1]` ✅ *(cette session)* — Couche 1 : sections `[security_forbidden]`/`[security_warn]` dans
  le template `rules.conf` (universels actifs + per-stack commentés) + Security Shield dans `relay-check.sh`
  (parse + scan diff stagé code **et** config, sévérité error/warn, fallback « inactif » jamais muet) +
  bump `VERSION` 1.8.0 + `CHANGELOG` + reçu `[verified-run]`.
- `TASK[SEC-1b]` — `relay-update.sh` **seede** les sections sécu dans les `rules.conf` existants (zéro perte
  de garde pour les projets déjà initialisés ; miroir du seeding `[forbidden_patterns]`). effort=S.
- `TASK[SEC-3]` — Couche 3 : workflow GitHub Actions (`relay-check --strict` + gitleaks). effort=M, depends=[Axe 1 CI].
- `TASK[SEC-2]` — Couche 2 : `SECURITY_RULES.md` + trigger ancrage sélectif (grep surface sensible). effort=L.
- `TASK[SEC-4]` — Couche 4 : auto-feed de `SECURITY_RULES.md` depuis les commits de fix sécu. effort=M, depends=[SEC-2].
