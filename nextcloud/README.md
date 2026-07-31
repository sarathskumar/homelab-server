# Migrating files from Google Drive to Nextcloud (via rclone)

A repeatable workflow for moving specific folders or files from Google Drive
into a self-hosted Nextcloud instance, using [rclone](https://rclone.org/) —
the same underlying approach as `rsync`, but built to speak both cloud
storage APIs and WebDAV natively (rsync alone can't talk to Google Drive or
Nextcloud directly).

Runs entirely from your **local machine** (laptop/desktop) — no need to
install anything inside the Nextcloud server or container.

## Prerequisites

- rclone installed locally
- Your Nextcloud instance reachable from your machine (same network, VPN,
  or tunnel — whatever your setup uses)
- A Nextcloud **app password** (not your real account password)

## 1. Install rclone

**macOS:**
```bash
brew install rclone
```

**Linux:**
```bash
curl https://rclone.org/install.sh | sudo bash
```

**Windows:** download the binary from [rclone.org/downloads](https://rclone.org/downloads/)

Verify:
```bash
rclone version
```

## 2. (Optional but recommended) Create your own Google API client ID

By default, `rclone config` lets you leave `client_id` / `client_secret`
blank and it'll use rclone's shared/default key. This works fine for small
tests, but the shared key's API quota is split across every rclone user
globally — for a larger migration you may hit rate-limit errors partway
through. Creating your own client ID gives you a private quota.

1. Go to [console.cloud.google.com](https://console.cloud.google.com/) → create a new project
2. **APIs & Services → Library** → search "Google Drive API" → **Enable**
3. **APIs & Services → OAuth consent screen** (may appear as "Google Auth Platform")
   → **Get started** → choose **External** audience → fill in app name +
   your email → add your own email as a **test user** → finish (no need to
   publish the app)
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   → Application type: **Desktop app** → Create
5. Copy the generated **Client ID** and **Client Secret** — you'll paste
   these into `rclone config` in the next step

If you skip this, just leave those two fields blank when prompted.

## 3. Configure the Google Drive remote

```bash
rclone config
```

| Prompt | Value |
|---|---|
| `n` | New remote |
| name | `gdrive` |
| Storage type | `drive` (Google Drive) |
| client_id | your own, or blank |
| client_secret | your own, or blank |
| scope | `1` (full access) |
| root_folder_id | blank |
| service_account_file | blank |
| Edit advanced config? | `n` |
| Use auto config? | `y` (opens browser to authorize) |
| Configure as Shared Drive? | `n` |
| Confirm | `y` |

In the browser: log in, click through the "unverified app" warning if you
used your own client ID in Testing mode (**Advanced → Go to `<app>` (unsafe)**
— safe here since it's your own app and your own data), then **Allow**.

## 4. Find your Nextcloud WebDAV URL

In the Nextcloud web UI: **Files** → scroll to the bottom of the left
sidebar → **WebDAV** link shows the full URL. It follows this pattern:

```
https://<your-server-address>/remote.php/dav/files/<your-username>/
```

## 5. Generate a Nextcloud app password

**Settings** (profile icon) → **Security** → under "Devices & sessions" →
**Create new app password** → name it (e.g. `rclone`) → copy the generated
password. Use this instead of your real account password in the next step.

## 6. Configure the Nextcloud remote

```bash
rclone config
```

| Prompt | Value |
|---|---|
| `n` | New remote |
| name | `nextcloud` |
| Storage type | `webdav` |
| url | your WebDAV URL from step 4 |
| vendor | `nextcloud` |
| user | your Nextcloud username |
| password | `y` → paste the **app password** from step 5 |
| bearer_token | blank |
| Edit advanced config? | `n` |
| Confirm | `y` |

## 7. Verify both remotes

```bash
rclone lsd gdrive:
rclone lsd nextcloud:
```

Both should list top-level folders without errors.

### Common issue: self-signed certificate

If your Nextcloud uses HTTPS with a self-signed certificate (common for a
homelab setup without a public CA cert yet), you'll see:

```
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

Quickest fix — disable cert verification for rclone (reasonable if this is
only reachable on your own trusted network):

```bash
export RCLONE_NO_CHECK_CERTIFICATE=true
```

Add that line to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) to make
it permanent. For a more correct fix, import the certificate into your
system's trust store instead of disabling verification globally.

## 8. Find the exact folders/files you want to migrate

```bash
rclone lsd gdrive:                          # top-level folders
rclone lsf gdrive:SomeFolder --dirs-only    # subfolders inside "SomeFolder"
```

## 9. Edit the script

Open `migrate_gdrive_to_nextcloud.sh` and set `SOURCE_PATHS` to the real
paths you want to migrate:

```bash
SOURCE_PATHS=(
  "gdrive:SomeFolder"
  "gdrive:AnotherFolder/Subfolder"
  "gdrive:SomeFolder/single_file.pdf"
)
```

Each entry can be a whole folder (copied recursively, including
subfolders) or a single file.

## 10. Run it

```bash
chmod +x migrate_gdrive_to_nextcloud.sh
./migrate_gdrive_to_nextcloud.sh --dry-run    # preview only, nothing copied
./migrate_gdrive_to_nextcloud.sh --run        # actually copies the data
```

Always review the `--dry-run` output before running `--run` — it lists
every file it would transfer without touching anything, so you can catch
mistakes (wrong folder, unexpected files) before they happen.

The script is resumable: if it's interrupted partway through, just rerun
`--run` and rclone will skip whatever was already copied.

## Notes

- Runs one-way (`rclone copy`, not `sync`) — nothing gets deleted from
  Nextcloud even if it's missing from Drive.
- Logs are written to `~/rclone-migration-logs/` with a timestamp per run.
- Google Docs/Sheets/Slides are exported to `.docx`/`.xlsx`/`.pptx` by
  rclone's defaults, since they aren't real files in Drive.
