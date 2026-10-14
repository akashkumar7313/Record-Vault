# RecordVault

An **offline-first** personal records manager built with Flutter. Records are
stored locally in SQLite, so the app works fully without a network. When online,
an optional background sync mirrors records to a Google Sheets + Google Drive
backend and pushes queued changes back. Records can also be exported to Excel.

Every record is identified by its **12-digit Aadhaar number**, which doubles as
the sync idempotency key — this is what makes retries safe and prevents duplicate
rows on the server.

---

## Features

- **Offline-first CRUD** — create, edit, view and delete records with no network.
- **Profile photos** — picked from the gallery, stored in private app storage,
  uploaded to Google Drive on sync, and backfilled on a fresh install.
- **Search** — by name, mobile number or Aadhaar number.
- **Dashboard** — sync summary ring, pending/conflict counts, recent records,
  and quick actions.
- **Background sync** — manual (pull-to-refresh / sync button) and automatic on
  connectivity returning.
- **Conflict handling** — never auto-overwrites; the user chooses `keep mine` or
  `use server version`.
- **Soft delete** — records are tombstoned locally and only removed after the
  server confirms the deletion.
- **Excel export** — share or save an `.xlsx` workbook of all records.
- **Theming** — system / light / dark, persisted locally.
- **Privacy-first logging** — a `SafeLogger` that never logs personal values.

---

## Getting Started

```bash
flutter pub get
flutter run
```

Point the app at your own backend without editing source:

```bash
flutter run --dart-define=RECORD_VAULT_SHEETS_URL=https://script.google.com/macros/s/XXXX/exec
```

> The default Apps Script endpoint is a **public, unauthenticated** web app.
> Anyone with the URL can read/write what it exposes. Use dummy data until an
> authenticated backend is deployed.

### Tests & analysis

```bash
flutter analyze
flutter test
```

Unit tests run against an in-memory SQLite database via `sqflite_common_ffi`,
so no device is required.

---

## Architecture

The project follows a **layered, feature-first** structure. Dependencies point
inward: UI → providers → repository → database, and UI → providers → services.

```
lib/
├── main.dart                     # App entry: installs error handler, runApp
├── app/                          # App shell, routing, theme
│   ├── app.dart                  # Root MaterialApp (theme + routes)
│   ├── router.dart               # Named routes + onGenerateRoute
│   ├── shell/home_shell.dart     # Bottom-nav scaffold (3 tabs)
│   └── theme/                    # AppTheme, spacing, themeMode provider
├── core/                         # Cross-cutting, dependency-free helpers
│   ├── constants/                # AppConstants (timeouts, keys, limits)
│   ├── errors/                   # AppException + AppErrorHandler
│   ├── utils/                    # formatters, validators, SafeLogger
│   └── widgets/                  # Reusable UI (buttons, fields, dialogs...)
├── data/                         # Domain + infrastructure
│   ├── database/app_database.dart        # Low-level SQLite (sqflite)
│   ├── models/                           # PersonalRecord, Gender, SyncStatus
│   ├── repositories/record_repository.dart # Domain-facing persistence API
│   ├── services/                         # Sheets, sync, photos, export, ...
│   └── providers/data_providers.dart     # Riverpod wiring of the data layer
└── features/                     # One folder per feature (UI + providers)
    ├── dashboard/                # Overview screen
    ├── records/                  # List, form, details
    ├── settings/                 # Sync, export, theme, privacy
    └── export/                   # Excel export controller
```

### Layers

| Layer | Responsibility | Key files |
|-------|----------------|-----------|
| **UI** | Screens and widgets, no business logic | `features/**/screens`, `core/widgets` |
| **State** | Riverpod providers/controllers | `features/**/providers`, `data/providers` |
| **Domain/Repo** | Persistence API, sync rules | `record_repository.dart`, `sync_service.dart` |
| **Data** | SQLite + remote services | `app_database.dart`, `services/*` |

---

## App Flow

### Navigation

`HomeShell` hosts three tabs in an `IndexedStack` (state is preserved across
tabs). The selected tab lives in `navigationTabProvider`.

```
HomeShell
├── Dashboard   → greeting, sync summary, search, recent records, quick actions
├── Records     → full list + search, tap for details, edit/delete
└── Settings    → sync status, connection test, Excel export, theme, privacy
```

Two routes are pushed on top of the shell (`app/router.dart`):

- `/record/form` — create (no args) or edit (pass `RecordFormArgs(record:)`).
- `/record/details` — pass the Aadhaar number as the argument.

### Add / Edit a record

1. `RecordFormScreen` validates input (`core/utils/validators.dart`).
2. On new records it blocks a duplicate Aadhaar before saving.
3. `RecordsController.save()` writes to SQLite and marks the record `pending`.
4. A best-effort `syncNow()` is triggered; the UI never blocks on the network.
5. On success the screen pops back to the list.

### Delete a record

1. Confirm dialog → `RecordsController.softDelete()` writes a tombstone
   (`isDeleted = true`, `syncStatus = pending`).
2. The row stays locally until the sync push confirms it, then it is
   hard-deleted.

### Search

`searchQueryProvider` holds the query and is shared between Dashboard and
Records. `RecordsController` re-reads from SQLite filtered by that query.

---

## Sync Flow

Sync is a **push-then-pull** cycle coordinated by `SyncService.syncAll()`,
driven by `SyncController` (`settings_providers.dart`). It runs manually and
automatically when connectivity returns.

```
                Manual / connectivity-triggered
                             │
                             ▼
        ┌───────────────────────────────────────┐
        │  1. PUSH  (local → server)             │
        │     getPending() = pending + failed    │
        │     + tombstones (never conflicts)     │
        │     • deleted → POST action=delete     │
        │     • new     → POST action=add        │
        │     • known   → POST action=update     │
        │     photo → base64 → Drive fileId      │
        │     confirmed → markSynced(), else fail│
        └───────────────────────────────────────┘
                             │ (offline? stop, keep queue)
                             ▼
        ┌───────────────────────────────────────┐
        │  2. PULL   (server → local)            │
        │     GET all records, compare by Aadhaar│
        │     • remote-only      → insert        │
        │     • remote newer      → update       │
        │     • photo backfill    → download     │
        │     • both changed      → conflict     │
        │     • missing remotely  → conflict     │
        └───────────────────────────────────────┘
                             │
                             ▼
                    SyncReport → SyncState (UI)
```

### Guarantees

- Local records are **never deleted** until the server confirms the delete.
- A record is marked `synced` **only** after explicit server confirmation
  (an ambiguous `200` is treated as unconfirmed).
- Conflicts are **flagged, never auto-overwritten**.
- A failed push leaves the local record intact for a later retry.
- `markSynced` only applies if the local copy still matches the version that was
  sent — so an edit made mid-flight is not clobbered.

### Sync statuses (`SyncStatus`)

| Status | Meaning |
|--------|---------|
| `pending` | Created/edited locally, not yet confirmed by the server |
| `synced` | Server explicitly confirmed the last change |
| `failed` | Last attempt errored; record is kept locally for retry |
| `conflict` | Remote and local both changed; user review required |

---

## Data Model

### `PersonalRecord`

Immutable, null-safe domain entity. Local fields (`syncStatus`, `photoPath`,
tombstone flags) are excluded from the remote payload.

| Field | Notes |
|-------|-------|
| `aadhaarNumber` | Primary key + sync idempotency key |
| `fullName`, `fatherName`, `motherName` | Identity |
| `mobileNumber`, `email`, `address` | Contact |
| `dateOfBirth`, `gender` | Stored as stable strings |
| `photoPath` | Local private-storage path |
| `photoFileId` | Google Drive file id (after sync) |
| `createdAt`, `updatedAt` | UTC timestamps |
| `syncStatus`, `lastSyncedAt`, `remoteUpdatedAt` | Sync metadata |
| `isDeleted`, `deletedAt` | Soft-delete tombstone |

### Local storage (SQLite)

- `records` — all fields above, keyed by `aadhaar_number`, indexed on
  `full_name`, `mobile_number`, `updated_at`, `sync_status`.
- `app_meta` — key/value store (`last_sync_at`, `theme_mode`).

`AppDatabase` accepts an injectable `DatabaseFactory`/path so tests use an
in-memory database.

---

## Backend (Google Apps Script)

Reference server: `tool/apps_script/Code.gs` (deployed as a Web App).

```
GET  → { "success": true, "data": [ ... ] }
POST → { "action": "add" | "update" | "delete", "record": { ... } }
       → { "success": true, "action": "...", "aadhaarNumber": "...",
           "photoFileId": "<driveFileId|''>" }
       → { "success": false, "message": "..." }
```

- Records are matched on the 12-digit Aadhaar number, so `add` is an **upsert**.
- `photoBase64` is uploaded to Google Drive and its file id stored.
- `GoogleSheetsService` follows the Apps Script `302` redirect manually and
  retries idempotent reads/writes with backoff.

---

## Testing

```
test/
├── core/validators_test.dart
├── data/personal_record_test.dart
├── data/record_repository_test.dart
├── data/sync_service_test.dart
├── data/google_sheets_service_test.dart
├── data/excel_export_service_test.dart
├── data/photo_storage_service_test.dart
├── helpers/test_database.dart          # In-memory sqflite fixture
└── widget_test.dart
```
