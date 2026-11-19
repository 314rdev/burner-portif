# CLAUDE.md

Context for AI assistants working on **burner**.

## What it is

burner is an AirDrop-style tool for Ubuntu, web and Android. A user drags files
(or pastes text) into the window, burner uploads them and returns a short code
(`ABC-234`), a link and a QR code. Another device signed in to burner enters
the code and downloads the contents. Drops expire (10 min to 7 days) and can be
"burn after first open".

## Hard constraints

- **No server/backend.** No Cloud Functions, no custom API. Clients talk to
  Firebase directly; all authorisation is in `firestore.rules` and
  `storage.rules`. Don't propose a backend to solve a problem; find a
  rules-based or client-side approach (or a Firebase/GCS-native feature like
  TTL policies and bucket lifecycle rules).
- **Only authenticated users** (Firebase Auth, email + password) can read or
  write anything in Firestore or Storage.
- **Platforms:** Linux (Ubuntu) desktop, web, Android. The UI must be
  responsive across all three. iOS/macOS/Windows folders exist from
  `flutter create` but are not targets.

## Architecture

Flutter app, no FlutterFire. FlutterFire has no Linux support, so every
Firebase call goes through small pure-Dart REST clients built on
`package:http`. One code path for all platforms.

```
lib/
  main.dart                    wires services, reads ?code= from the web URL
  app.dart                     MaterialApp, auth gate, SetupRequiredApp
  config/firebase_config.dart  values from --dart-define-from-file
  models/drop.dart             Drop, DropFile, UsageStats (+ Firestore mapping)
  services/
    auth_service.dart          Identity Toolkit REST: sign in/up, reset,
                               token refresh; session in shared_preferences
    firestore_client.dart      Firestore v1 REST: get/commit/delete/runQuery,
                               FirestoreCodec for typed Value JSON
    storage_client.dart        Storage v0 REST: streamed upload, download, delete
    drop_service.dart          domain logic + DropLimits (shared with the rules)
    file_saver*.dart           conditional import: io (Downloads dir / Android
                               save dialog) vs web (blob download)
    firebase_exception.dart    REST error parsing + user-facing messages
  ui/
    services_scope.dart        InheritedWidget giving pages the services
    theme.dart                 theme, Breakpoints, ContentWidth, showMessage
    home_screen.dart           NavigationRail (>=840px) / NavigationBar
    send_page.dart             DropTarget (desktop_drop) + file_picker + text
    receive_page.dart          code entry, text/file display, downloads
    history_page.dart          the user's drops + usage counters
    widgets/share_card.dart    code, copy buttons, QR
```

State management is plain `ChangeNotifier` / `setState`; no provider/bloc.
Keep it that way unless the app clearly outgrows it.

## Data model

- `drops/{code}`: `ownerUid`, `text`, `files[] {name,size,contentType,path}`,
  `createdAt` (server time), `expiresAt`, `burnAfterRead`, `burned`,
  `downloads`. The 6-char code is the doc id, drawn from
  `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`.
- `users/{uid}`: usage counters `dropsCreated`, `bytesUploaded`,
  `dropsReceived`, `bytesDownloaded`, `lastActiveAt`. Written with Firestore
  `increment` transforms in the same commit as the drop.
- Storage: `drops/{ownerUid}/{20-char random folder}/{index}_{safeName}`.

Flow: upload files → one Firestore `commit` creates the drop
(`currentDocument.exists=false`) and bumps usage. On a code collision the
commit fails (ALREADY_EXISTS or PERMISSION_DENIED) and `create` retries with a
new code. If the commit fails, uploaded files are deleted.

Receiving: `find` (GET) → `markReceived` (download +1, set `burned` when
burn-after-read) → per-file download.

Cleanup without a backend: on app start, `DropService.cleanup()` deletes the
current user's expired/burned drops and their files. The backstop for users
who never return is a Firestore TTL policy on `drops.expiresAt` and a bucket
lifecycle rule (`storage-lifecycle.json`); see README.

## Keep these in sync

Limits are duplicated by necessity (rules can't import Dart):

| Limit | Dart (`DropLimits`) | Rules |
| --- | --- | --- |
| 100 MB per file | `maxFileBytes` | `storage.rules` |
| 20 files per drop | `maxFiles` | `firestore.rules` |
| 100 000 text chars | `maxTextChars` | `firestore.rules` |
| 7-day max expiry | `maxTtl` | `firestore.rules` (+5 min skew) |
| Code alphabet/length | `DropCodes` | `firestore.rules` regex |
| Drop document fields | `Drop.toCreateMap` | `dropFields()` |
| Usage fields | `UsageStats` / `DropService` | `counters()` |

If you change the drop document shape, update `firestore.rules` too or
creates will be denied.

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux   --dart-define-from-file=config/firebase.env.json
flutter run -d chrome  --dart-define-from-file=config/firebase.env.json
flutter run -d <android-device> --dart-define-from-file=config/firebase.env.json
flutter build web --dart-define-from-file=config/firebase.env.json && firebase deploy --only hosting
firebase deploy --only firestore:rules,storage
```

`config/firebase.env.json` is gitignored; `config/firebase.env.example.json`
is the template. Without it the app shows `SetupRequiredApp`.

## Conventions and gotchas

- Firebase REST auth headers: Firestore uses `Authorization: Bearer <idToken>`,
  Storage uses `Authorization: Firebase <idToken>`.
- Firestore REST integers are strings (`integerValue: "42"`); use
  `FirestoreCodec`, don't hand-build Value JSON.
- A GET on a missing or hidden drop returns 403 (rules can't evaluate
  `resource.data` on a null doc), so `find` treats PERMISSION_DENIED as "not
  found".
- `DropTarget` must be disabled when its page is hidden (`SendPage.dropEnabled`)
  or it keeps catching drops.
- On web, upload progress jumps to 100% before the network send finishes
  (BrowserClient buffers the body). Downloads on web need bucket CORS
  (`storage-cors.json`).
- `file_picker` on Linux needs `zenity` (or `kdialog`) installed.
- Tests use `MockClient` from `package:http/testing.dart`; services take an
  optional `http.Client` for that reason. Rules are not covered by tests yet
  (needs the Firebase emulator + Java).
- Commit messages and code comments in English. Run `flutter analyze` and
  `flutter test` before committing.
