# Contribuer à RELAY

> RELAY gagne en crédibilité par ce qu'il **refuse de laisser passer**, pas par le nombre de règles.
> La règle d'or des contributions : **on durcit, on n'enfle pas.**

## La contribution la plus utile : tester sous un autre LLM

La revendication « LLM-agnostique » n'est **pas prouvée** — RELAY n'a tourné qu'avec Claude. Faire
tourner une vraie session RELAY sous **GPT, Gemini, Llama, Mistral…** et rapporter ce qui casse vaut
plus que n'importe quel ajout de règle. Ce qui nous intéresse :
- Le LLM suit-il le protocole d'ouverture (brief → MRS → plan → « go ») sans être sur-guidé ?
- Respecte-t-il les gates (ancrage, escalade, `[verified-*]`) ou les contourne-t-il ?
- Quels passages de `RELAY_PROTOCOL.md` sont ambigus pour un moteur non-Claude ?

Ouvre une issue « LLM-agnostic report: <modèle> » avec le transcript ou les écarts observés.

## Le modèle anti-inflation (à respecter pour toute nouvelle règle)

Une idée d'amélioration du protocole **n'entre pas directement** dans `RELAY_PROTOCOL.md`. Cycle de vie :

1. **Candidate** — la §Suggestion est consignée dans `RELAY_RULE_POOL.md` (`trigger-count=1`). Elle
   reste un *acquis de session*, pas une règle du protocole.
2. **Promotion** — elle ne rejoint le protocole qu'à **deux conditions réunies** :
   - **2ᵉ déclencheur indépendant** : un second cas vécu, dans **un autre contexte/projet** (pas une
     re-citation du même incident) confirme le besoin.
   - **+ validation humaine explicite** : aucun script ne promeut. Jamais d'auto-promotion.
3. **Retrait/fusion** — `relay-check.sh --density` signale les règles « dormantes » (jamais déclenchées) :
   soit un garde-fou silencieux à garder, soit une règle situationnelle à retirer. **Décision humaine.**

`relay-check.sh --density` **avertit** (sans bloquer) si une règle `vN.N` est citée dans le protocole
**sans** entrée `promue` dans le pool. Une §Suggestion = **au plus une** règle ajoutée, ou une retirée/fusionnée.

**Une bonne règle est une *forcing function* qui se déclenche réellement** (elle a déjà bloqué/attrapé
quelque chose), pas un conseil décoratif. Si elle ne peut pas faire échouer un `relay-check`, c'est de
la doc, pas une règle.

## Discipline MOTEUR / INSTANCE (ne pas la casser)

- Un fichier **moteur** (`engine/`) ne doit contenir **aucune donnée de projet** (nom, compteurs,
  KI, registre de règles, exemples projet). Sinon une propagation écrase les données d'un consommateur.
- Les données spécifiques d'un projet vont en **instance** (`docs/context/RELAY_PROJECT_DNA.md`,
  `NEXT_SESSION.md`, `KNOWN_ISSUES.md`…) — jamais propagées.
- Les compteurs (`RELAY_METRICS.md`) et le registre (`RELAY_RULE_POOL.md`) sont des **templates
  seed-once** : posés au bootstrap, ensuite propriété du projet.
- Un script moteur doit être **project-agnostic** : dériver le nom de projet de `docs/.relay-version`
  / d'un fichier d'instance, **zéro identité en dur**.

## Tester une modification (obligatoire)

Toute modif du moteur se prouve **par exécution**, pas par lecture :

1. **`relay-check.sh` passe** sur un projet réel (Health Score ≥ 80, 0 erreur).
2. **Non-régression des gates** — la modif ne doit pas désarmer un garde-fou. Exemple : si tu touches
   le Regression Shield, prouve qu'un vrai antipattern est **toujours** attrapé ET que l'idiome légitime
   ne l'est plus (deux cas testés).
3. **Propagation sûre** — `relay-update.sh` vers un projet test : le fix arrive **et** un fichier
   d'instance modifié à la main **survit** (sentinelle).
4. Sois honnête sur ton propre niveau : `[verified-run]` (tu l'as exécuté) vs `[verified-build]`
   (tu l'as lu/compilé). C'est précisément la distinction que RELAY encode.

## Flux de PR

1. Branche depuis `main`. Modifie `engine/` et/ou `bin/`. **Bump `VERSION`** (sémantique :
   patch = fix, minor = règle/feature, en restant frugal sur les ajouts).
2. Décris dans la PR : le **déclencheur réel** (quel incident motive la modif), le test d'exécution,
   et le niveau `[verified-*]`.
3. Pour une **règle de protocole** : ajoute-la d'abord comme **candidate** dans `RELAY_RULE_POOL.md`.
   Ne la formalise dans `RELAY_PROTOCOL.md` que si un 2ᵉ déclencheur indépendant existe (sinon la PR
   reste « candidate »).
4. Une fois mergé + `VERSION` bumpé, les consommateurs récupèrent la correction via `relay-update.sh`.

## Style

Bash portable (éviter les lookahead `-P` si un post-filtre suffit), Markdown ; cohérence avec le ton
existant. Les commits du framework : `relay(framework): …` ou `feat(relay): …`.
