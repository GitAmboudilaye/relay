# RELAY_RULE_POOL.md — registre des règles candidates (Pilier 11, anti-inflation)
# [LLM-AGNOSTIC] · [MÉTA] Voir `RELAY_PROTOCOL.md §7.1` pour le cycle de vie.

> **Rôle** : toute §Suggestion versionnée `vN.N` entre ici comme **candidate** (`trigger-count=1`).
> Elle ne rejoint le **ruleset actif** (formalisée dans `RELAY_PROTOCOL.md §1-§8) qu'au **2ᵉ
> déclencheur indépendant** (autre session/contexte) **+ confirmation humaine** (jamais d'auto-promotion).
> `relay-check.sh --density` warn (exit 0, non bloquant) si une `vN.N` du ruleset actif n'a pas
> d'entrée `statut=promue` ici.

| Règle | trigger-count | sessions | statut | résumé |
|---|---|---|---|---|
| [vN.N] | [1] | [S?] | candidate | [résumé d'une règle proposée par une §Suggestion — entre toujours ici en premier] |

> **Registre vierge à l'initialisation.** Chaque §Suggestion versionnée d'une session ajoute UNE ligne
> `candidate`. La promotion `candidate → promue` (= règle formalisée dans `RELAY_PROTOCOL.md §1-§7`)
> exige un **2ᵉ déclencheur indépendant** + **validation humaine** (jamais d'auto-promotion).
> Tant qu'une `vN.N` n'est citée dans aucune section §1-§7 du protocole, `--density` n'émet aucun warning.
