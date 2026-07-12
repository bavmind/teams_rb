# Sovereign clouds

Government and sovereign cloud tenants use different login, Bot Framework, and Graph endpoints. The app routes everything from a single `cloud:` configuration:

```ruby
gcch = Teams::CloudEnvironment.new(
  login_endpoint: "https://login.microsoftonline.us",
  login_tenant: "botframework.com",
  bot_scope: "https://api.botframework.us/.default",
  token_service_url: "https://tokengcch.botframework.azure.us",
  open_id_metadata_url: "https://login.botframework.azure.us/v1/.well-known/openidconfiguration",
  token_issuer: "https://api.botframework.us",
  graph_scope: "https://graph.microsoft.us/.default"
)

teams = Teams::App.new(cloud: gcch)
```

Everything derives from the cloud environment automatically:

- **Bot tokens** — requested from the cloud's login endpoint with its bot scope
- **Inbound validation** — issuer and signing keys from the cloud's metadata
- **User tokens / sign-in** — the cloud's token service
- **Graph** — the host is derived from the cloud's graph scope (`https://graph.microsoft.us` above)

The public cloud is the default; nothing to configure outside sovereign deployments. Endpoint values for the specific sovereign clouds are in [Microsoft's sovereign cloud documentation](https://learn.microsoft.com/azure/bot-service/how-to-deploy-gov-cloud-high).
