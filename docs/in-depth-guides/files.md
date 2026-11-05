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

## Handle errors

All file errors inherit from `Teams::FileError`:

| Error | Raised when | Carries |
|---|---|---|
| `Teams::FileUrlExpiredError` | The short-lived download link lapsed. | `reason`: `"first_fetch"` (no bytes were ever fetched; the file has to be sent again) or `"reread"` (an earlier download succeeded; reuse its `DownloadedFile`) |
| `Teams::FileScopeNotSupportedError` | `download` was called on a file from a scope that cannot be downloaded yet. A traditional bot receives files only in personal chats. | `scope` |

Failures the SDK cannot attribute (a storage 5xx, a network error) raise a plain `Teams::Error`.
