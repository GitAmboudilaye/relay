# Adaptateur Cline — hook `PreToolUse` (RELAY-CLINE)

**2ᵉ adaptateur** du RELAY Core « actif » (cf. `docs/RELAY-CORE-ACTIF.md §1.2/§3`), après Claude Code.
Il câble le **noyau agnostique** `relay-context.sh` dans [Cline](https://cline.bot) via son système de
**hooks** (`PreToolUse`, Cline v3.36+) — pour que la règle pertinente d'un fichier soit injectée **avant**
l'écriture (shift-left), au lieu d'être sanctionnée à la clôture par `relay-check.sh` (a posteriori =
réécriture = tokens).

> **Le noyau ne connaît pas Cline.** Tout le spécifique-harnais vit ici. Cet adaptateur appelle le **même**
> `relay-context.sh` que l'adaptateur Claude Code — il peut disparaître sans toucher au noyau (§1.2).

## 🔁 Mise à jour de cap — Cline a des hooks BLOQUANTS

La note historique « Cline = MCP » (`RELAY-CORE-ACTIF.md`, README claude-code) supposait que Cline ne
pourrait offrir que de l'**advisory** via un outil MCP que l'agent appelle. **Cette hypothèse est
périmée** : depuis **Cline v3.36**, Cline expose un vrai hook `PreToolUse` capable de **bloquer** un outil
(`{"cancel": true}`) **et** d'injecter du contexte (`contextModification`). On atteint donc la **parité
d'enforcement** avec l'adaptateur Claude Code — un `deny` réel, pas un simple conseil. Le canal MCP reste
une option pour un harnais qui n'aurait que ça ; ici, le hook est strictement supérieur (et plus simple :
aucun serveur MCP, juste un script qui lit stdin / écrit stdout).

## Mécanique

`relay-precheck.sh` reçoit le JSON `PreToolUse` de Cline sur stdin (`toolName` + `parameters`), appelle
`relay-context.sh --path=<édité> --stdin` sur le **contenu proposé**, puis traduit la sortie en décision
de hook Cline :

| Sortie noyau | Décision hook Cline | Effet |
|---|---|---|
| ≥1 pattern **ERROR** (proscrit) | `{"cancel": true, "errorMessage": …}` | **Bloque** l'écriture ; l'agent voit la raison et corrige **avant** d'écrire → réécriture aval évitée = tokens économisés. |
| Seulement **WARN/INFO** | `{"cancel": false, "contextModification": …}` | **Non-bloquant** ; l'agent est informé (terse, §1.3). |
| Rien / défaillance | `{"cancel": false}` | **ALLOW explicite** → l'outil suit son flux normal. |

### Différences avec l'adaptateur Claude Code (`relay-hook.sh`)

Le **noyau** est rigoureusement le même ; seule la **frontière harnais** change :

- **Schéma JSON d'entrée** : Cline = `toolName` + `parameters.{path, content|diff}` ; Claude Code =
  `tool_name` + `tool_input.{file_path, content|new_string|edits[]}`.
- **Schéma JSON de sortie** : Cline = `{cancel, errorMessage, contextModification}` ; Claude Code =
  `{hookSpecificOutput:{permissionDecision, permissionDecisionReason, additionalContext}}`.
- **Le « silence »** : Claude Code = *aucune sortie* (exit 0) ; Cline = **ALLOW explicite**
  `{"cancel": false}` (le hook Cline renvoie toujours un JSON).
- **Outils ciblés** : `write_to_file`, `replace_in_file` (+ `new_file`/`edit_file` défensivement). Tout
  autre outil (`execute_command`, lecture…) → ALLOW immédiat, rien à analyser.

**FAIL-OPEN absolu** : python3 absent, JSON illisible, noyau introuvable, contenu vide, outil
non-écriture → `{"cancel": false}` / exit 0. L'édition n'est **jamais** bloquée par un bug d'outillage.

## Ledger token-saved (RELAY-TOKENS)

À chaque firing non-trivial, le hook appende **1 ligne** dans `docs/.relay/token-ledger.log`, au **même
format** que l'adaptateur Claude Code :

```
<ISO8601> <deny|context> err=<n> total=<n> <fichier>
```

→ `relay-tokens.sh` agrège **les deux harnais** sans modification (`token-in` amont vs `token-saved` aval
évité ; `--json` dispo). L'écriture est en sous-shell (fail-open), le ledger est **gitignoré** (donnée
d'instance, même convention que `relay-run.sh`).

## Câblage

Cline exécute un fichier nommé **exactement `PreToolUse`** (sans extension, exécutable), placé dans
`.clinerules/hooks/` (projet) ou `~/Documents/Cline/Rules/Hooks/` (global). Comme `relay-init` n'écrase
jamais la config d'un projet, **vous créez ce fichier vous-même** en le pointant vers l'adaptateur :

**Consommateur** (après `relay-init` / `relay-update`, l'adaptateur est en
`docs/adapters/cline/relay-precheck.sh`) — un **symlink** suffit :

```bash
mkdir -p .clinerules/hooks
ln -s ../../docs/adapters/cline/relay-precheck.sh .clinerules/hooks/PreToolUse
```

Ou, si les symlinks ne sont pas souhaitables (FS/Windows), un **wrapper** `.clinerules/hooks/PreToolUse` :

```bash
#!/usr/bin/env bash
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../docs/adapters/cline/relay-precheck.sh"
```

**Dépôt canonique RELAY** (dogfood) : la cible est `engine/adapters/cline/relay-precheck.sh`.

> L'adaptateur résout son propre emplacement de façon **symlink-safe** (`readlink -f` + repli racine git),
> donc le symlink fonctionne même appelé sous le nom `PreToolUse`. Tant que le projet n'a pas de
> `docs/.relay/rules.conf` (état des lieux non seedé), le noyau reste silencieux → le hook est inoffensif.

## Prérequis

- **Cline v3.36+** (système de hooks `PreToolUse`).
- `python3` (frontières JSON). Absent → l'adaptateur fail-open (ALLOW). Le **noyau** reste en Bash pur.
- `RELAY_CONTEXT_BIN` (optionnel) force le chemin du noyau — utilisé par le smoke test.
