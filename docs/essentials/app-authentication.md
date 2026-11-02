# App authentication

How the app proves itself to Teams, and how Teams proves itself to the app.

## Inbound validation

Every `POST /api/messages` request must carry a Bot Framework JWT. Token decoding, JWK import, RS256 signature verification, and standard claims use the established [`jwt` gem](https://github.com/jwt/ruby-jwt); Teams-specific endpoint selection, signing-key caching, and service URL checks remain in this SDK.

The app validates:

- **Signature** against Microsoft's published signing keys (RS256, JWKS fetched and cached)
- **Issuer** — the Bot Framework issuer, or your tenant's Entra issuers (v1 and v2 forms) when `TENANT_ID` is configured
- **Audience** — your app id, in any of the three accepted forms: the bare id, `api://{id}`, `api://botid-{id}`
- **Expiry / not-before** with five minutes of clock tolerance, matching the JavaScript Teams SDK
- **`serviceurl` claim** — must match the activity's service URL, preventing spoofed routing

Rejected requests get a 401 with a warn log line. Requests are rejected wholesale when no credentials are configured (with a loud startup warning) unless `dangerously_allow_unauthenticated_requests: true` is set explicitly — which is for local development only. The option can also come from the `DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS` environment variable (`true`/`false`, `1`/`0`, `yes`/`no`, or `on`/`off`); the older `skip_auth:` name still works as a deprecated alias.

### Signing-key caching and rotation

The signing-key cache follows the defaults used by the [JavaScript Teams SDK](https://github.com/microsoft/teams.js/blob/3420e8899e71ed7cc74711d62f07c25e73d45b42/packages/apps/src/middleware/auth/jwt-validator.ts) and its [`jwks-rsa` 4.1.0 dependency](https://github.com/auth0/node-jwks-rsa/blob/v4.1.0/src/wrappers/cache.js): each JWKS endpoint has a least-recently-used cache of at most five public keys, indexed by JWT `kid`. Only the requested key is cached, even when a downloaded key document contains several keys.

Keys expire ten minutes after retrieval. Cache hits update recency but do not extend expiry. An uncached or expired key triggers a fresh JWKS fetch immediately, including when another key was fetched moments earlier. Misses are coordinated per JWKS endpoint, and waiting requests recheck the cache to share successful lookups. Cache reads and updates take only a brief shared mutex; HTTP requests run outside it, and Bot Framework discovery has separate synchronization. A slow key fetch or discovery request therefore does not block verification with another unexpired cached key. There is no background refresh, negative caching, retry cooldown, or fetch rate limit, matching the JavaScript SDK's current configuration. Arbitrary unknown key IDs can therefore cause repeated outbound requests; account for this when protecting your bot endpoint.

Key-fetch, discovery, and malformed key-response failures reject authentication with HTTP 401 and a warn log line through the Rack adapter. Failed lookups are not cached and may be retried immediately. Other unexpired cached keys remain usable, but expired keys are never used as a fallback during an outage. Bot Framework discovery still resolves `jwks_uri` once per validator; tenant keys still use the configured tenant endpoint. Existing issuer, audience, service URL, and RS256 checks remain in place; this matches JavaScript's cache defaults, not every feature of its authentication stack.

## Outbound bot tokens

Replies and proactive sends authenticate with an app-only token from the Entra client-credentials flow, acquired and cached automatically (single-flight refresh with expiry skew — the other SDKs get the equivalent from MSAL). Nothing to configure beyond the three credentials.

## The trust model in one paragraph

Teams never talks to your bot directly — the Bot Framework service does, signing every request with Microsoft-issued tokens audienced to *your* app id. Your bot talks back through the service URL from the validated activity, authenticating with *your* app's token. User identity inside activities (`ctx.activity.from`) is asserted by Teams and safe to trust once the JWT validates; user identity for *external* calls (Graph, your own API) comes from [user authentication](../in-depth-guides/user-authentication.md) instead.

## Sovereign clouds

Pass a `cloud:` environment to route logins, token services, and Graph to sovereign endpoints. The public cloud is the default.
