# Adaptateur Claude Code — hook `PreToolUse` (RELAY-3)

Couche **adaptateur** du RELAY Core « actif » (cf. `docs/RELAY-CORE-ACTIF.md §1.2/§3`). Elle câble le
**noyau agnostique** `relay-context.sh` dans Claude Code via un hook `PreToolUse` — pour que la règle
pertinente d'un fichier soit injectée **avant** l'écriture (shift-left), au lieu d'être sanctionnée à la
clôture par `relay-check.sh` (a posteriori = réécriture = tokens).

> **Le noyau ne connaît pas Claude Code.** Tout le spécifique-harnais vit ici. Un autre harnais (Cline =
> MCP, sans agent = git hook, CI = étape pipeline) recevra son propre adaptateur appelant le **même**
> `relay-context.sh`. Cet adaptateur peut disparaître sans toucher au noyau.

## Mécanique

`relay-hook.sh` reçoit le JSON `PreToolUse` sur stdin (`tool_input.file_path` + contenu proposé), appelle
`relay-context.sh --path=<édité> --stdin` sur ce contenu, puis traduit la sortie en décision de hook :

| Sortie noyau | Décision hook Claude Code | Effet |
|---|---|---|
| ≥1 pattern **ERROR** (proscrit) | `permissionDecision: "deny"` + `permissionDecisionReason` | **Bloque** l'écriture ; l'agent voit la raison et corrige **avant** d'écrire → réécriture aval évitée = tokens économisés. |
| Seulement **WARN/INFO** | `additionalContext` | **Non-bloquant** ; l'agent est informé (terse, §1.3). |
| Rien | *(aucune sortie)* | Silence → flux de permission normal. |

**FAIL-OPEN absolu** : python3 absent, JSON illisible, noyau introuvable, contenu vide → aucune sortie /
exit 0. L'édition n'est **jamais** bloquée par un bug d'outillage.

## Ledger token-saved (RELAY-TOKENS, v1.19.0)

À chaque firing non-silencieux, le hook appende **1 ligne** dans `docs/.relay/token-ledger.log` :

```
<ISO8601> <deny|context> err=<n> total=<n> <fichier>
```

C'est la source runtime de la métrique `token-saved` que ni git ni `NEXT_SESSION.md` ne portent. La lire
avec **`relay-tokens.sh`** (`token-in` amont vs `token-saved` aval évité ; `--json` dispo). L'écriture est
en sous-shell : un échec n'enfreint **jamais** le fail-open. Le ledger est **gitignoré** (donnée
d'instance, self-deposit `docs/.relay/.gitignore` — même convention que `relay-run.sh`).

## Câblage

Dans le projet, ajouter à `.claude/settings.json` (le `settings.json` repo est versionné ; les choix
perso vont dans `settings.local.json`) :

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/docs/adapters/claude-code/relay-hook.sh" }
        ]
      }
    ]
  }
}
```

- **Consommateur** (après `relay-init`/`relay-update`) : le hook est propagé en
  `docs/adapters/claude-code/relay-hook.sh` (chemin du `command` ci-dessus). Le snippet est fourni dans
  `templates/.claude/settings.json` — **à recopier soi-même** : `relay-init` n'écrase jamais le
  `settings.json` d'un projet.
- **Dépôt canonique RELAY** (dogfood) : `command` pointe vers
  `$CLAUDE_PROJECT_DIR/engine/adapters/claude-code/relay-hook.sh`.

Le hook ne s'active **qu'au démarrage d'une session Claude Code** (rechargement des settings). Tant que le
projet n'a pas de `docs/.relay/rules.conf` (état des lieux non seedé), le noyau reste silencieux → le hook
est inoffensif.

## Prérequis

- `python3` (frontières JSON). Absent → l'adaptateur fail-open (silencieux). Le **noyau** reste, lui, en
  Bash pur (`relay-context.sh`).
- `RELAY_CONTEXT_BIN` (optionnel) force le chemin du noyau — utilisé par le smoke test.
