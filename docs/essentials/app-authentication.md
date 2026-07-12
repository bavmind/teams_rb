# App authentication

How the app proves itself to Teams, and how Teams proves itself to the app. All of it matches the TypeScript, Python, and .NET SDKs.

## Inbound validation

Every `POST /api/messages` request must carry a Bot Framework JWT. The app validates:

- **Signature** against Microsoft's published signing keys (RS256, JWKS fetched and cached)
- **Issuer** — the Bot Framework issuer, or your tenant's Entra issuers (v1 and v2 forms) when `TENANT_ID` is configured
- **Audience** — your app id, in any of the three accepted forms: the bare id, `api://{id}`, `api://botid-{id}`
- **Expiry / not-before**
- **`serviceurl` claim** — must match the activity's service URL, preventing spoofed routing

Rejected requests get a 401 with a warn log line. Requests are rejected wholesale when no credentials are configured (with a loud startup warning) unless `skip_auth: true` is set explicitly — which is for local development only.

## Outbound bot tokens

Replies and proactive sends authenticate with an app-only token from the Entra client-credentials flow, acquired and cached automatically (single-flight refresh with expiry skew — the other SDKs get the equivalent from MSAL). Nothing to configure beyond the three credentials.

## The trust model in one paragraph

Teams never talks to your bot directly — the Bot Framework service does, signing every request with Microsoft-issued tokens audienced to *your* app id. Your bot talks back through the service URL from the validated activity, authenticating with *your* app's token. User identity inside activities (`ctx.activity.from`) is asserted by Teams and safe to trust once the JWT validates; user identity for *external* calls (Graph, your own API) comes from [user authentication](../in-depth-guides/user-authentication.md) instead.

## Sovereign clouds

Pass a `cloud:` environment to route logins, token services, and Graph to sovereign endpoints. The public cloud is the default.
