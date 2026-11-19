# burner 🔥

AirDrop-style sharing for Ubuntu, the web and Android. Drag files (or paste
text) into burner, get a short code like `ABC-234`, a link and a QR code, then
open that code on another device to download everything. Drops expire on their
own and can burn after the first open.

There's no server. The app talks to Firebase directly (Auth, Cloud Firestore,
Cloud Storage), and the security rules in this repo decide who can do what.

## Features

- **Drag and drop** files onto the window (Linux desktop and web), or pick
  them with the file chooser (all platforms).
- **Text drops**: send a note, link or snippet, with or without files.
- **Code, link and QR**: the link opens the web app with the code already
  filled in.
- **Expiry**: 10 minutes, 1 hour, 24 hours or 7 days.
- **Burn after first open**: only the first device that opens the code gets it.
- **My drops**: your drops, their status and open count, plus usage totals
  (drops sent/received, bytes uploaded/downloaded).
- **Signed-in users only**: nothing in Firestore or Storage is readable or
  writable without Firebase Auth.
- **Responsive**: a side rail on wide windows, a bottom bar on phones.

## How it works

```
 Device A (sender)                          Device B (receiver)
 ─────────────────                          ───────────────────
 1. upload files ─────► Cloud Storage
    drops/{uid}/{random}/…
 2. commit ───────────► Firestore            4. GET drops/{code} ◄── enters code
    drops/{code}  + users/{uid} usage        5. downloads +1 (burn if needed)
 3. show code / link / QR  ─ ─ ─ ─ ─ ─ ─ ►   6. download files ◄── Cloud Storage
```

Every request carries the user's Firebase ID token, so the rules in
[`firestore.rules`](firestore.rules) and [`storage.rules`](storage.rules) are
enforced on every call.

## Firebase setup

You need a Firebase project on the **Blaze** plan. Cloud Storage for Firebase
requires it for new buckets, and the free usage quotas still apply.

1. **Authentication** → Sign-in method → enable **Email/Password**.
2. **Firestore Database** → create a database (Native mode).
3. **Storage** → get started (this creates the default bucket).
4. **Project settings** → General → *Your apps* → add a **Web app**. Copy
   `apiKey`, `projectId` and `storageBucket`.
5. Create the app config:

   ```bash
   cp config/firebase.env.example.json config/firebase.env.json
   ```

   Fill in the values. `BURNER_WEB_URL` is where you host the web build
   (for example `https://<project-id>.web.app`). It's used for share links;
   leave it empty if you don't host the web app. This file is gitignored.

6. Deploy the rules (needs the [Firebase CLI](https://firebase.google.com/docs/cli)):

   ```bash
   firebase login
   firebase use --add            # pick your project
   firebase deploy --only firestore:rules,storage
   ```

7. **Auto-delete expired data.** The app cleans up a user's expired drops when
   they open it. These two settings handle drops whose owner never comes back:

   ```bash
   # Firestore: delete drop documents once expiresAt has passed
   gcloud firestore fields ttls update expiresAt \
     --collection-group=drops --enable-ttl --project=<project-id>

   # Storage: delete uploaded files older than 8 days (max expiry is 7)
   gcloud storage buckets update gs://<bucket> --lifecycle-file=storage-lifecycle.json
   ```

8. **Web downloads need CORS** on the bucket:

   ```bash
   gcloud storage buckets update gs://<bucket> --cors-file=storage-cors.json
   ```

   You can replace `"*"` in `storage-cors.json` with your hosting origin(s).

> **API key restrictions:** if you restrict the Web API key in Google Cloud
> Console, the Linux and Android builds call the same REST APIs without a
> browser referrer. Either leave application restrictions off (API
> restrictions to Identity Toolkit, Token Service, Firestore and Firebase
> Storage are fine) or use a separate key for the native builds.

## Running

### Prerequisites

- Flutter 3.44+ (Dart 3.12+)
- **Ubuntu desktop builds:**

  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev zenity
  ```

  The file chooser uses `zenity`.
- **Android:** Android SDK / Android Studio.

### Commands

```bash
flutter pub get
```

```bash
flutter run -d linux --dart-define-from-file=config/firebase.env.json
```

```bash
flutter run -d chrome --dart-define-from-file=config/firebase.env.json
```

```bash
flutter run -d <android-device-id> --dart-define-from-file=config/firebase.env.json
```

### Building and deploying

```bash
flutter build linux --release --dart-define-from-file=config/firebase.env.json
```

```bash
flutter build apk --release --dart-define-from-file=config/firebase.env.json
```

```bash
flutter build web --release --dart-define-from-file=config/firebase.env.json && firebase deploy --only hosting
```

The Linux bundle is written to `build/linux/x64/release/bundle/`.

### Tests

```bash
flutter analyze && flutter test
```

## Security model

- Every Firestore and Storage operation requires a signed-in user.
- Anyone signed in who knows a code can open a **live** drop (not expired, not
  burned). Codes are 6 characters from a 32-symbol alphabet (~1 billion
  combinations), and users can't list other people's drops.
- Only the owner can create, list or delete their drops and files. Recipients
  can only increment the open counter and set `burned`.
- Files sit under a random 20-character folder that's only revealed through a
  live drop document. Storage itself only checks that the user is signed in.
- Usage counters are written by the client, so they're self-reported. The
  rules only stop them from going down.
- **Open sign-up:** by default anyone can create an account in your project.
  For a personal tool, create your accounts and then turn off sign-ups under
  Authentication → Settings → User actions.
- **Burn after first open is best-effort.** Two devices opening the same code
  at the same moment can both get it, and a modified client could skip the
  burn step.

## Limits

| | |
|---|---|
| File size | 100 MB per file |
| Files per drop | 20 |
| Text | 100,000 characters |
| Expiry | up to 7 days |

These are enforced in both the app (`DropLimits` in
`lib/services/drop_service.dart`) and the rules. Change them in both places.

## Project layout

See [CLAUDE.md](CLAUDE.md) for the architecture, data model and conventions.

## Roadmap ideas

- Google sign-in (needs a desktop OAuth flow on Linux)
- Folder drops (zip on the fly)
- Android share-sheet target ("Share to burner")
- Rules unit tests with the Firebase emulator
- Optional end-to-end encryption, with the key carried in the link fragment
