# App authentication

How the app proves itself to Teams, and how Teams proves itself to the app.

## Inbound validation

Every `POST /api/messages` request must carry a trusted JWT: a Bot Framework service token or an Entra-issued Agent 365 token. Token decoding, JWK import, RS256 signature verification, and standard claims use the established [`jwt` gem](https://github.com/jwt/ruby-jwt). This experimental branch delegates JWKS retrieval and caching to [`jwk-loader`](https://github.com/anakinj/jwk-loader), while retaining Teams-specific endpoint selection and service URL checks.

The app validates:

- **Signature** against Microsoft's published signing keys (RS256, JWKS fetched and cached)
- **Issuer** — the Bot Framework issuer, or your tenant's Entra issuers (v1 and v2 forms) when `TENANT_ID` is configured
- **Audience** — your app id, in any of the three accepted forms: the bare id, `api://{id}`, `api://botid-{id}`
- **Expiry / not-before** with five minutes of clock tolerance, matching the JavaScript Teams SDK
- **`serviceurl` claim** — must match the activity's service URL, preventing spoofed routing

Rejected requests get a 401 with a warn log line. Requests are rejected wholesale when no credentials are configured (with a loud startup warning) unless `dangerously_allow_unauthenticated_requests: true` is set explicitly — which is for local development only. The option can also come from the `DANGEROUSLY_ALLOW_UNAUTHENTICATED_REQUESTS` environment variable (`true`/`false`, `1`/`0`, `yes`/`no`, or `on`/`off`); the older `skip_auth:` name still works as a deprecated alias.

### Signing-key caching and rotation

**Experimental alternative to the cache merged in [PR #12](https://github.com/bavmind/teams_rb/pull/12).** This branch uses `jwk-loader` 1.3 or newer with a ten-minute maximum cache age rather than a JavaScript-style per-key cache. The feature discussion is tracked in [jwk-loader issue #15](https://github.com/anakinj/jwk-loader/issues/15).

Each trusted JWKS URI has a provider with an isolated memory cache storing the whole key set. Sets expire ten minutes after a successful fetch; hits do not extend expiry. The next lookup refreshes an expired set, even for a known key and before the loader's default fifteen-minute invalidation grace period. Unknown keys within the ten-minute lifetime are rejected without refreshing. This differs from main's immediate unknown-key fetch and five-key LRU limit. There is no background refresh or per-set key-capacity limit, and refresh timing uses the loader's wall clock. The validator retains at most 100 endpoint providers, preserving main's bounded tenant caching. The existing validator mutex coordinates concurrent lookups, including network fetches; a slow key fetch can block other validations. Discovery has separate synchronization.

The loader fetches JWKS through `Net::HTTP`; the validator's injected `http:` client handles only Bot Framework discovery. JWT, JSON, HTTP status, transport, and key-import failures become authentication errors, yielding logged HTTP 401 responses through the Rack adapter. Non-2xx responses are rejected before parsing and are not cached. Failed refreshes preserve the previous set and its timestamp, but expired keys are never returned as fallback. A later request can retry immediately; there is no separate failed-fetch cooldown.

Bot Framework discovery still resolves `jwks_uri` once per validator. Agent 365 inbound tokens use their validated tenant endpoint; other tenant-token validation uses the configured tenant. RS256, issuer, audience, five-minute clock tolerance, service URL checks for service tokens, and rejection of ambiguous missing-`kid` tokens remain in place.

## Outbound bot tokens

Replies and proactive sends authenticate with an app-only token from the Entra client-credentials flow, acquired and cached automatically (single-flight refresh with expiry skew — the other SDKs get the equivalent from MSAL). Nothing to configure beyond the three credentials.

## The trust model in one paragraph

Teams never talks to your bot directly — the Bot Framework service does, signing every request with Microsoft-issued tokens audienced to *your* app id. Your bot talks back through the service URL from the validated activity, authenticating with *your* app's token. User identity inside activities (`ctx.activity.from`) is asserted by Teams and safe to trust once the JWT validates; user identity for *external* calls (Graph, your own API) comes from [user authentication](../in-depth-guides/user-authentication.md) instead.

## Sovereign clouds

Pass a `cloud:` environment to route logins, token services, and Graph to sovereign endpoints. The public cloud is the default.
