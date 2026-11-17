# Using your own Google client_id

[Português](client-id.md) · **English**

The plugin works without any Google Cloud setup. This guide explains when it's worth creating your own OAuth client, and how to do it.

## Background

To access Google Drive, rclone needs an **OAuth client**: an "app" registered with Google, identified by a `client_id` and a `client_secret`. There are two options:

| | rclone's default client | Your own client |
|---|---|---|
| Setup | none: it's what `gdrive setup` uses by default | ~10 min in the Google Cloud Console |
| API quota | shared with **every rclone user in the world** | yours alone |
| Rate-limit errors (`403 rateLimitExceeded`) | frequent at peak times | practically never |
| Future | rclone warns it is being retired and will stop working during 2026 | doesn't depend on rclone |
| Cost | free | free: the Drive API isn't billed, and no card or billing account is needed |
| Consent screen | verified "rclone" | "Google hasn't verified this app" warning (expected: the app is yours) |

When the default client hits its limit, the mount gets slow or fails, and the file manager reports folders as unreadable. The panel may also stop refreshing storage usage and starred folders until the quota recovers.

**Recommendation:** use the default client to try the plugin out. For daily use, create your own.

### Why doesn't the plugin ship with a client?

Embedding a client in the plugin is technically possible, but:

- Google classifies the `drive` scope as **restricted**, and an unverified app is limited to **100 users over the whole lifetime of the project**;
- verifying an app with a restricted scope requires a paid security assessment (CASA);
- the quota would be shared by everyone using the plugin, bringing back the shared-client problem on a smaller scale.

So each person creates their own. The client is personal and only stored on your machine, in `~/.config/rclone/rclone.conf`.

## Step by step

### 1. Create the project and enable the API

1. Create a project at https://console.cloud.google.com/projectcreate (e.g. `rclone-gdrive`).
2. With the project selected at the top of the page, enable the **Google Drive API**: https://console.cloud.google.com/apis/library/drive.googleapis.com → **Enable**.

The console may offer a "free trial" or ask you to enable billing. Ignore it: nothing here needs it.

### 2. Configure the app (Google Auth Platform)

1. Open https://console.cloud.google.com/auth/overview → **Get started**:
   - **App name:** `rclone`
   - **User support email:** yours
   - **Audience:** External
   - **Contact information:** your email
2. In **Branding**, also fill in:
   - **Application home page:** any page of yours, e.g. `https://github.com/LoganMerazzi/omarchy-gdrive`
   - **Application privacy policy link:** e.g. `https://github.com/LoganMerazzi/omarchy-gdrive/blob/main/PRIVACY.md`

   Both links are **required to publish** the app. Without them, the **Publish app** button stays grayed out. Since the app is never submitted for verification, Google doesn't review these pages. Don't upload a logo: with a logo, Google requires verification.
3. Click **Save**.

### 3. Publish the app

In **Audience**, click **Publish app** → **Confirm**. The status should change to **In production**.

> **Don't leave the app in "Testing" mode.** In testing, only the emails listed under *Test users* can authorize, and **the token expires every 7 days**: the Drive unmounts itself every week.

### 4. Create the client

In **Clients** → **Create client**:

- **Type:** Desktop app
- **Name:** `rclone`

Copy the **Client ID** and **Client secret**. If you see *"OAuth access is restricted to the test users"*, the app isn't published yet: go back to step 3.

### 5. Use the client in the plugin

- **New install:** run `gdrive setup` (or `extras/install.sh`) and paste the ID and secret when asked.
- **Existing remote:** run `gdrive client`. It saves the ID and secret, re-authorizes in the browser and restarts the mount.

During authorization, Google shows **"Google hasn't verified this app"**. Click **Advanced** → **Go to rclone (unsafe)**, allow Drive access and click **Continue**.

To check: `rclone about gdrive:` should no longer print the *shared client_id* notice.

## Multiple machines

Use the **same** client on all of them: run `gdrive client` on each one with the same ID and secret. Each machine gets its own token.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Error 403: access_denied` / "app has not completed the Google verification process" | app in Testing mode | publish the app (step 3) |
| **Publish app** grayed out | home page or privacy policy missing in Branding | fill in both links (step 2) |
| Drive stops mounting after a week | app in Testing: the token expires in 7 days | publish the app and run `gdrive client` again |
| `403 rateLimitExceeded` | still on the default client | check `client_id` with `rclone config show gdrive` |

## Going back to the default client

```bash
rclone config update gdrive client_id= client_secret=
rclone config reconnect gdrive:
systemctl --user restart rclone-gdrive
```

To revoke access for any client: https://myaccount.google.com/permissions.
