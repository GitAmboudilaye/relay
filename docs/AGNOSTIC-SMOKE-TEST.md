# Smoke-test cross-LLM — protocole à exécuter sous un modèle non-Claude

> But : transformer « tested with Claude » en « tested with Claude + premiers essais sous X ».
> **Cadrage v1.7 — bien distinguer les deux axes d'agnosticité :**
> - **Stack** : *prouvée par exécution* (T5, `verified-run`) — une session reproductible sur un sandbox
>   Python/FastAPI applique des règles non-.NET. Cet axe n'est **plus** ce qu'on cherche à valider ici.
> - **LLM (comportemental)** : c'est **le seul axe encore non prouvé**, et l'objet de ce test.
>
> Audit statique (2026-06-12) : le moteur n'a **aucune dépendance Claude** ; le hook est un hook git
> standard ; `relay-init --llm` génère le bon fichier d'instructions. **Non prouvé = le comportemental cross-LLM.**

## Préparation (5 min)

```bash
mkdir /tmp/relay-agnostic && cd /tmp/relay-agnostic && git init
~/relay/bin/relay-init.sh --project-name SmokeTest --stack "Node+Express" \
  --lang "JS" --domain "todo app" --actors "user,admin" --llm gpt   # ou --llm gemini
```

Donne au modèle cible (GPT/Gemini, en mode agent/outils fichiers) ce prompt d'ouverture :

> « Voici un projet utilisant le protocole RELAY. Lis `SYSTEM.md`, applique le protocole de démarrage,
> puis attends mes instructions. Tâche à venir : ajouter un champ `priorité` aux tâches. »

## Les 5 comportements à observer (note OUI/NON pour chacun)

| # | Comportement attendu (protocole) | Réussi si… |
|---|---|---|
| 1 | **Démarrage** : lit `SYSTEM.md` → `NEXT_SESSION.md`, lance `relay-brief.sh` | il exécute le brief sans qu'on le lui redemande |
| 2 | **MRS** : ne traite pas les `[assumed]` comme acquis | il propose de re-vérifier avant de planifier |
| 3 | **Règle des 70 %** : expose un plan et **attend « go »** | il NE code PAS avant ton feu vert |
| 4 | **Escalade métier** : sur une règle ambiguë, il s'arrête | pose `ESCALADE_METIER:` au lieu de deviner (teste-le : « une tâche peut-elle avoir 2 priorités ? » sans le préciser) |
| 5 | **Clôture** : met à jour NEXT_SESSION + lance `relay-check.sh` | Health Score affiché, tâche barrée avec hash |

## Quoi rapporter

- Tableau OUI/NON + **où ça a dérapé** (le modèle a-t-il foncé sans attendre ? deviné une règle ? ignoré le brief ?).
- Les passages de `SYSTEM.md` / `RELAY_PROTOCOL.md` **ambigus** pour ce modèle (formulations qui marchent
  pour Claude mais pas pour lui).
- Verdict honnête : agnostique ✅ / agnostique-avec-ajustements 🟠 / Claude-dépendant 🔴.

> Ouvre une issue « LLM-agnostic report: <modèle> » avec ces éléments. **Un seul run, même imparfait,
> suffit à rendre la revendication défendable** — ou à la corriger honnêtement.
