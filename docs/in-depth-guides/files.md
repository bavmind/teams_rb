# Receiving files

When a user attaches a file to a message, Teams stores it in OneDrive or SharePoint and hands your bot a small metadata attachment describing it. `ctx.files` turns those attachments into lazy `Teams::Files::IncomingFile` handles: listing makes no network requests, and the bytes are fetched only when you ask for them.

## Enable file support in your manifest

Teams only offers the attach button in a 1:1 chat with your bot when the manifest opts in:

```json
"bots": [
  {
    "botId": "${{BOT_ID}}",
    "scopes": ["personal"],
    "supportsFiles": true
  }
]
```

Without it no file reaches your handler and `ctx.files.list` is always empty.

For an [Agent 365](agent-365.md) agentic user, an administrator must consent a Graph file permission (such as `Files.Read.All`) on the agent's blueprint instead — see [inheritable permissions](https://learn.microsoft.com/entra/agent-id/concept-inheritable-permissions).

## Access attached files

```ruby
teams.on_message do |ctx|
  files = ctx.files.list
  next ctx.reply("Send me a file and I will read it.") if files.empty?

  ctx.reply "You sent #{files.length} file(s): #{files.map(&:name).join(", ")}"
end
```

`ctx.files.first` returns the first file or `nil`. Only uploaded files are listed — cards, mentions, and malformed file entries are skipped, never raised. Any file type sent as an upload is included.

### File metadata

| Reader | Description |
|---|---|
| `name` | Display name, including the extension when known |
| `extension` | Extension without the dot (`"pdf"`), from the platform's file type |
| `scope` | Conversation type the file arrived in (`"personal"`, ...) |
| `source` | Where the SDK found the file; `"botActivity"` today |
| `attachment_style` | `"file"` for a file attachment |
| `content_type` | MIME type when the source provides one; `nil` for file attachments (read `DownloadedFile#content_type` instead) |
| `content_url` | Browsable OneDrive/SharePoint link; not a byte URL |
| `unique_id` | OneDrive/SharePoint identifier, for correlation and logging |
| `raw` | The original attachment hash |

## Read a file

```ruby
file = ctx.files.first
downloaded = file.download            # Teams::Files::DownloadedFile
downloaded.bytes                      # binary String
downloaded.content_type               # from the download response
file.text                             # download + UTF-8 decode (lossy)
file.save_as("tmp/report.pdf")        # streams to disk, never buffers the file
file.stream { |chunk| parser << chunk }  # raw chunks; returns an Enumerator without a block
```

The handle memoizes nothing, so every call fetches again. In a personal chat the download link is short-lived, so download once and reuse the `DownloadedFile` (its `text` and `save_as` never re-fetch).

The download is a plain GET with no token attached: the link carries its own credential, and the SDK never sends the bot's token to the storage host. Redirects are followed only over HTTPS.

## Conversation scope support

- **Personal chats.** A traditional bot receives a short-lived, pre-authorized link that the SDK fetches directly. An agentic user receives no link — only `content_url` — so the SDK reads the bytes through Microsoft Graph `/shares` with the agent's own token. Your handler code is the same either way.
- **Group chats and channels.** Teams delivers files there only to agentic users, again carrying just `content_url`, and the SDK reads them through Graph as the agent. A traditional bot receives no files in these scopes.

An agentic user always reads as itself, never as the app: an app-only token sees what the app may read tenant-wide, a different set from what was shared with the agent.

## Handle errors

All file errors inherit from `Teams::FileError`:

| Error | Raised when | Carries |
|---|---|---|
| `Teams::FileUrlExpiredError` | The short-lived download link lapsed. | `reason`: `"first_fetch"` (no bytes were ever fetched; the file has to be sent again) or `"reread"` (an earlier download succeeded; reuse its `DownloadedFile`) |
| `Teams::FileCredentialError` | The Graph read an agentic user's file needs was ruled out before the request: no token could be acquired, or the token carries no `Files.*`/`Sites.*` permission. | `actor`, `cause_detail` (why token acquisition failed, when it raised) |
| `Teams::FileAccessError` | The storage service refused the Graph read. | `status` (`401`: the token was rejected; `403`: the identity lacks the grant — this also covers a file never shared with it and an item that does not exist), `actor`, `details` (the service's own words) |
| `Teams::FileScopeNotSupportedError` | `download` was called on a file from a scope that cannot be downloaded yet. A traditional bot receives files only in personal chats. | `scope` |

`actor` is `"agentic_user"` when the inbound activity carries an agentic identity, `"app"` otherwise.

Failures the SDK cannot attribute (a storage 5xx, a network error) raise a plain `Teams::Error`.
