# RecordVault

An **offline-first** personal records manager built as a vanilla web app
(HTML + CSS + JavaScript, no framework) and packaged for Android with
**Capacitor** — so it runs as an installable APK with no hosting required.

Records live in a **Google Sheets backend** (configurable Apps Script web app).
The app keeps a local cache, so browsing and search keep working without a
network; changes are queued and pushed the next time sync runs. Records can
also be exported to an Excel (`.xlsx`) workbook.

Every record is identified by its **12-digit Aadhaar number**, which doubles as
the sync idempotency key — this is what makes retries safe and prevents
duplicate rows on the server.

---

## Features

- **Mobile login + OTP** — allowlisted mobile numbers sign in with a fixed OTP;
  the session expires after 30 minutes.
- **Offline-first** — records are cached locally; the app is fully usable
  without a network and syncs later.
- **Dashboard** — sync ring, pending/conflict counts, recent records, search,
  and quick actions.
- **Records CRUD** — add, view, edit and delete records with full field
  validation (Aadhaar, IFSC, account number, mobile, etc.).
- **Search** — by name, mobile number, Aadhaar number or application number.
- **Sync** — push-then-pull against the Sheets backend, with statuses
  (`pending` / `synced` / `failed` / `conflict`).
- **Conflict handling** — never auto-overwrites; the user chooses *keep mine* or
  *use server version*.
- **Soft delete** — records are tombstoned locally and only removed after the
  server confirms the deletion.
- **Excel export** — export every record (all fields + created/updated/status)
  as an `.xlsx` workbook; the xlsx library is bundled locally, works offline.
- **Theming** — system / light / dark, persisted locally.
- **Demo mode** — sample data for trying the app without a backend.
- **Fully offline UI** — fonts (Roboto + Material Symbols) and the xlsx library
  are bundled in the app, no CDN needed at runtime.

---

## Screens

```
App (login → session)
└── Bottom navigation
    ├── Dashboard   — sync summary, recent records, quick actions
    ├── Records     — full list + search, tap for details, edit/delete
    └── Settings    — endpoint, connection test, sync, export, theme, privacy

Pushed on top:
├── Record form    — create / edit (validated, sectioned: Identity, Family,
│                    Address, Bank, Contact)
└── Record details — full record view with sync status
```

---

## Record fields

| Field | Notes |
|-------|-------|
| `applicationNo` | Optional application number |
| `name` | Full name |
| `gender` | Male / Female |
| `aadhaarNumber` | 12 digits — primary key + sync idempotency key |
| `guardianName`, `relation` | Father's or husband's name + relation |
| `address`, `addressCorrect` | Current and corrected address |
| `bankName`, `accountNumber`, `ifscCode` | Bank details |
| `mobileNumberCorrect` | 10-digit mobile number |
| `remarks` | Free-form notes |

Sync metadata: `pending` / `synced` / `failed` / `conflict`, created/updated
timestamps, soft-delete tombstone flag.

---

## Project structure

```
RecordVault/
├── index.html          # Web app entry
├── app.js              # All app logic (login, UI, storage, sync, export)
├── styles.css          # App styles + themes
├── www/                # Assets packaged into the Android app
│   ├── index.html      #   (references fonts + xlsx locally, not CDN)
│   ├── app.js
│   ├── styles.css
│   ├── fonts.css       #   local @font-face rules
│   ├── fonts/          #   Roboto + Material Symbols woff2 files
│   └── vendor/         #   xlsx.full.min.js
├── android/            # Capacitor Android project (generated)
├── tool/apps_script/   # Google Apps Script backend (Code.gs)
├── capacitor.config.json
└── package.json
```

---

## Configuration

Everything is configured at the top of `app.js`:

| Constant | Purpose |
|----------|---------|
| `DEFAULT_ENDPOINT` | Default Google Apps Script web-app URL |
| `AUTH.mobiles` | Allowlisted mobile numbers that may sign in |
| `AUTH.otp` | The OTP accepted at login |
| `AUTH.sessionMs` | Session length (30 minutes) |

Users can also point the app at their own backend from **Settings** — the
endpoint is stored in `localStorage` as `rv_endpoint`.

> The default Apps Script endpoint is a **public, unauthenticated** web app.
> Anyone with the URL can read/write what it exposes. Use dummy/demo data until
> an authenticated backend is deployed.

---

## Run the web app

The web app has no build step — serve the folder with any static server:

```bash
npx serve .          # or: python3 -m http.server 8000
```

Then open http://localhost:3000 (or :8000).

---

## Build the Android APK

### Prerequisites

- Node.js + npm
- JDK 17+ (JDK 21 works)
- Android SDK + build-tools (installed via Android Studio or `sdkmanager`)

### One-time setup

```bash
npm install                 # install Capacitor deps
npx cap add android         # already done if android/ exists
echo "sdk.dir=$HOME/Library/Android/sdk" > android/local.properties
```

> **Note (macOS + Java networking):** if Gradle fails with
> `SocketTimeoutException` while `curl` works fine, your network is unreachable
> over IPv6 for Java. Add `-Djava.net.preferIPv4Stack=true` to
> `org.gradle.jvmargs` in `android/gradle.properties` (already done in this
> repo). If the Gradle wrapper distribution itself cannot download (it is
> served from `release-assets.githubusercontent.com`), download the zip listed
> in `android/gradle/wrapper/gradle-wrapper.properties` with `curl` and unpack
> it into `~/.gradle/wrapper/dists/gradle-8.14.3-all/<hash>/` together with a
> `<zipname>.ok` marker file.

### Sync web assets → build debug APK

```bash
cp index.html app.js styles.css www/   # only when web files changed
npx cap sync android
cd android
./gradlew assembleDebug
```

Output:

```
android/app/build/outputs/apk/debug/app-debug.apk
```

Install it on a phone (allow "install unknown apps"). Debug APKs are signed
with a debug key — fine for personal use and testing.

### Build a release APK

**1. Generate a keystore (once, ever):**

```bash
keytool -genkeypair -v \
  -keystore ~/recordvault-release.jks \
  -alias recordvault \
  -keyalg RSA -keysize 2048 -validity 10000
```

Keep the password and the `.jks` file safe — losing them means you can never
publish an update to the same app identity again.

**2. Create `android/key.properties`:**

```properties
storeFile=/Users/YOU/recordvault-release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=recordvault
keyPassword=YOUR_KEY_PASSWORD
```

> Never commit `key.properties` or the keystore — add both to `.gitignore`.

**3. Wire the signing config into `android/app/build.gradle`:**

Load the properties at the top of the file (outside `android { }`):

```gradle
def keyProps = new Properties()
def keyFile = rootProject.file("key.properties")
if (keyFile.exists()) {
    keyProps.load(new FileInputStream(keyFile))
}
```

Then inside `android { ... }`:

```gradle
signingConfigs {
    release {
        storeFile file(keyProps["storeFile"])
        storePassword keyProps["storePassword"]
        keyAlias keyProps["keyAlias"]
        keyPassword keyProps["keyPassword"]
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled false
    }
}
```

**4. Build:**

```bash
npx cap sync android
cd android
./gradlew assembleRelease
```

Output:

```
android/app/build/outputs/apk/release/app-release.apk
```

This APK is signed for release and ready for sideloading or Play Store upload.

> A debug APK and a release APK are signed with different keys. If the debug
> version is already installed on a phone, uninstall it first or installation
> fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

---

## Sync Flow

Sync is a **push-then-pull** cycle. It runs on app load, via the sync button,
and after saving a record; queued changes are kept locally until the server
confirms them.

```
                Manual / save-triggered
                             │
                             ▼
        ┌───────────────────────────────────────┐
        │  1. PUSH  (local → server)             │
        │     pending + failed + tombstones      │
        │     • deleted → POST action=delete     │
        │     • new     → POST action=add        │
        │     • known   → POST action=update     │
        │     confirmed → mark synced, else fail │
        └───────────────────────────────────────┘
                             │ (offline? stop, keep queue)
                             ▼
        ┌───────────────────────────────────────┐
        │  2. PULL   (server → local cache)      │
        │     GET all records, compare by Aadhaar│
        │     • remote-only      → insert        │
        │     • remote newer      → update       │
        │     • both changed      → conflict     │
        │     • missing remotely  → conflict     │
        └───────────────────────────────────────┘
                             │
                             ▼
                        Sync status (UI)
```

### Guarantees

- Local records are **never deleted** until the server confirms the delete.
- Conflicts are **flagged, never auto-overwritten**.
- A failed push leaves the local record intact for a later retry.

### Sync statuses

| Status | Meaning |
|--------|---------|
| `pending` | Created/edited locally, not yet confirmed by the server |
| `synced` | Server explicitly confirmed the last change |
| `failed` | Last attempt errored; record is kept locally for retry |
| `conflict` | Remote and local both changed; user review required |

---

## Local storage

All state lives in `localStorage`:

| Key | Contents |
|-----|----------|
| `rv_cache` | Cached record list (offline copy) |
| `rv_endpoint` | Custom backend Apps Script URL (if set) |
| `rv_session` | Login session (expires after 30 minutes) |
| `rv_theme` | `system` / `light` / `dark` |

> Uninstalling the Android app wipes this data. Use sync/export as backup.

---

## Backend (Google Apps Script)

Reference server: `tool/apps_script/Code.gs` (deployed as a Web App).

```
GET  → { "success": true, "data": [ ... ] }
POST → { "action": "add" | "update" | "delete", "record": { ... } }
       → { "success": true, "action": "...", "aadhaarNumber": "..." }
       → { "success": false, "message": "..." }
```

- Records are matched on the 12-digit Aadhaar number, so `add` is an **upsert**.
- The endpoint is followed manually with retries/backoff for idempotent
  reads/writes.

---

## Privacy & security notes

- The login allowlist and OTP live in client-side code (`app.js`) — this is a
  convenience gate, **not** real security. Deploy an authenticated backend for
  anything sensitive.
- Exported files contain personal information — share only with trusted
  recipients.
- The app collects only the fields you enter; nothing is sent anywhere except
  the configured backend.
