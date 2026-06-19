# SECURITY_RULES.md — checklist d'ancrage sécurité (RELAY Couche 2)

> **Fichier d'INSTANCE** : seedé par relay-init/relay-update, **propriété du projet**, jamais écrasé.
> Adaptez/élaguez les exemples per-stack à VOTRE stack.
>
> **Chargement SÉLECTIF (principe token-négatif, `VISION.md §4`)** : ce fichier n'est **pas** chargé en
> permanence. Le grep déterministe `[security_surface]` de `rules.conf` détecte qu'une **surface sensible**
> est touchée dans le diff ; `relay-check.sh` (§9b « Security Surface Trigger ») le signale alors, et
> **c'est seulement à ce moment** que vous chargez cette checklist + ajoutez `SECURITY_ANCHOR:` à la tâche.
>
> **LUCIDITÉ (à répéter)** : RELAY est un **gate commit + CI**, *pas* un IDS/WAF runtime. Cette checklist
> ne remplace **pas** un pentest. On ne demande pas au LLM de juger sa propre sécurité ; on délègue au
> déterministe (grep, outils CI) chaque fois que possible — cette checklist est l'aide au jugement humain
> pour le reste.

---

## Quand ancrer (déclencheurs)

Une de ces surfaces touchée dans le diff → parcourir la checklist + écrire `SECURITY_ANCHOR:` dans le `TASK[]` :
authentification · autorisation · mot de passe / secret / token / clé d'API · chiffrement / hash · accès
à un objet identifié par un id (IDOR) · requête SQL · upload de fichier · désérialisation · `exec`/`eval`.

---

## 1. authN — authentification

- [ ] Le mot de passe est-il **haché** (bcrypt/argon2/PBKDF2), jamais en clair ni MD5/SHA1 ?
- [ ] Échec de login : message **générique** (pas « user inconnu » vs « mauvais mdp ») + anti-bruteforce ?
- [ ] Session/JWT : expiration courte, **signature vérifiée**, secret hors du code ?
- [ ] Déconnexion = invalidation effective (pas un simple GET côté client) ?

> Exemples per-stack (adapter) :
> - **.NET** : `PasswordHasher<T>` ; `[Authorize]` sur l'endpoint ; `ClockSkew` réduit ; secret JWT en config protégée.
> - **Flutter** : aucun secret/clé dans le bundle ; token en `flutter_secure_storage`, pas en `SharedPreferences`.
> - **JS/Node** : `bcrypt.hash` ; `jsonwebtoken` avec `expiresIn` ; secret en `process.env`.
> - **Python** : `passlib`/`argon2` ; pas de `SECRET_KEY` codé en dur (Django/Flask).

## 2. authZ / IDOR — autorisation

- [ ] Chaque accès à un objet vérifie que l'appelant en est **propriétaire / dans le bon tenant** ?
- [ ] L'id de l'objet vient du **claim/session**, jamais d'un `?id=` ou body non vérifié ?
- [ ] Rôle/permission contrôlé **côté serveur** sur chaque action (pas seulement masqué dans l'UI) ?
- [ ] Un POST/PUT direct (sans passer par l'UI) ne contourne pas le gating ?

> Exemples per-stack (adapter) :
> - **.NET** : `[Authorize(Roles="...")]` + filtre `WHERE ClientId == claim.ClientId` sur **chaque** requête/POST.
> - **Flutter** : ne jamais faire confiance au mobile comme vérité d'autorisation — re-vérifier au backend.
> - **JS/Node** : `if (resource.ownerId !== req.user.id) return res.sendStatus(403)`.
> - **Python** : `get_object_or_404(Model, id=id, owner=request.user)` (Django) — filtrer par owner dans la requête.

## 3. validation des entrées

- [ ] Toute entrée externe est **validée/typée** (longueur, format, plage) avant usage ?
- [ ] Requêtes SQL **paramétrées** (jamais de concaténation de chaîne) ?
- [ ] Sortie HTML **échappée** (anti-XSS) ; pas de `dangerouslySetInnerHTML`/`innerHTML` brut ?
- [ ] Upload : type/taille bornés, nom assaini, hors webroot exécutable ?

> Exemples per-stack (adapter) :
> - **.NET** : DataAnnotations + `ModelState.IsValid` ; EF/Dapper paramétré ; Razor échappe par défaut.
> - **Flutter** : valider côté backend même si le formulaire valide côté client.
> - **JS/Node** : `zod`/`joi` ; requêtes paramétrées (`?`/`$1`) ; échapper la sortie (pas de `innerHTML=`).
> - **Python** : pas de `% `/f-string dans le SQL (ORM ou `cursor.execute(sql, params)`) ; pas de `eval`.

## 4. secrets

- [ ] Aucun secret/clé/mot de passe **en clair dans le code ou la config committée** ?
- [ ] Secrets via variable d'environnement / secret store / `appsettings.*.json` **non committé** ?
- [ ] Pas de secret loggé / renvoyé dans une réponse d'erreur ?

> Exemples per-stack (adapter) :
> - **.NET** : `appsettings.Development.json` dans `.gitignore` ; `Environment.GetEnvironmentVariable`.
> - **Flutter** : `--dart-define` / variables de build, jamais en dur dans le source.
> - **JS/Node** : `.env` gitignoré + `dotenv` ; pas de clé dans le bundle front.
> - **Python** : `os.environ` / `python-decouple` ; `.env` gitignoré.
> *(Le gate déterministe Couche 1 `[security_forbidden]` bloque déjà les secrets évidents — clé privée, AKIA…)*

## 5. moindre privilège

- [ ] Le compte/service utilisé a-t-il **le minimum** de droits (DB, FS, cloud, API tierces) ?
- [ ] TLS **activé** bout en bout (pas de `verify=False` / `InsecureSkipVerify` / bypass cert) ?
- [ ] CORS restreint à des origines connues (pas `*` sur un endpoint authentifié) ?
- [ ] Endpoints d'admin/debug désactivés ou protégés en production ?

---

## Patterns appris (auto-feed — Couche 4, SEC-4)

> Chaque correction de sécurité (fix d'un finding KI sécu) ajoute ici **un pattern concret** appris, de
> sorte que la session suivante ne le réintroduise pas. Soumis à la jauge densité (anti-inflation).
> *(Section alimentée par SEC-4 ; vide tant que SEC-4 n'est pas livré.)*
