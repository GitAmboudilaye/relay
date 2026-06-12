# RELAY_PROJECT_DNA.md — {{PROJECT_NAME}}
# RELAY Framework — Pilier 6
#
# But : donner à chaque session le sentiment d'être dans la même équipe.
# Pas "où en est le projet" (→ NEXT_SESSION.md) mais "pourquoi ça existe et ce qu'on ne doit jamais casser."
#
# Mis à jour : {{TODAY}} (initialisation)

---

## § Identité du projet

**{{PROJECT_NAME}}** — Stack : {{STACK}} | Domaine : {{DOMAIN}}

**Utilisateurs réels (terrain) :**
{{ACTORS_DNA_LIST}}

**Problème résolu :**
[Décrire en 2-3 phrases le problème métier résolu par ce projet.]

---

## § Connaissance terrain implicite

> Ce qu'un expert du domaine "{{DOMAIN}}" sait instinctivement mais qu'un LLM doit lire explicitement.

| Contexte terrain | Implication technique |
|---|---|
| [exemple de contrainte terrain] | [exemple d'implication sur le code] |

---

## § Décisions invariantes

> Ces règles ne changent jamais sans autorisation explicite.

| Invariant | Raison | Conséquence si violé |
|---|---|---|
| [ex: Domain/ = zéro dépendance externe] | [Architecture clean] | [Couplage] |

---

## § Briefing équipe

> Paragraphes chronologiques — lire le dernier en premier.

**Session INITIALISATION ({{TODAY}}) :**
Structure RELAY initialisée. Remplir ce fichier avec l'identité projet, les contraintes terrain et les décisions invariantes avant la première session de développement.

---

## § Prochain cap

**[Décrire la prochaine étape majeure du projet]**

---

## § Spécificités RELAY (config locale — ex-§8 du protocole, jamais propagé)

> Ces réglages sont propres à ce projet : `relay-update.sh` ne les touche pas.

- **Repos** : mono-repo → `relay-check.sh --strict` sans `--companion-repo` ; multi-repo →
  `--companion-repo=<path>` pour vérifier les hash commits du 2ᵉ repo.
- **Stack / build** : {{STACK}} — [contraintes de build, commandes].
- **Priorités absolues** : [findings sécurité/dette qui priment sur toute feature, réf. `KNOWN_ISSUES.md`].
