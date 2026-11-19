# TODO

Planned work for Burner, roughly in priority order. When an item ships, remove
it from here and add it to [CHANGELOG.md](CHANGELOG.md).

---

## 1. Android: "Share to Burner" from the system share sheet

**Goal:** from any Android app (Gallery, Files, Chrome, WhatsApp…), tap
**Share → Burner** and the shared files or text open straight in Burner's Send
screen, ready to become a drop. Today you have to open Burner and pick the
files again.

### User flow
1. In another app, select one or more files (or some text/a URL) and tap
   **Share**.
2. Pick **Burner** in the share sheet.
3. Burner opens on **Send** with the files and text already added. Expiry,
   public link and burn options work as usual.
4. *(Optional "quick send")* With a setting on, Burner creates the drop right
   away with the default options and shows the code, link and QR, so sharing
   takes one tap.

### Implementation notes
- **Manifest:** add `intent-filter`s to `MainActivity` for
  `android.intent.action.SEND` and `android.intent.action.SEND_MULTIPLE`
  with `mimeType="*/*"`, plus `text/plain` for shared text and links.
- **Receiving the intent:** use a plugin such as `receive_sharing_intent` or
  `share_handler`, or a small platform channel in `MainActivity.kt`. Handle
  both cases:
  - **Cold start:** the app was closed; read the initial intent at startup.
  - **Warm start:** the app is already running (`singleTop`); listen for
    `onNewIntent`.
- **Content URIs:** shared files arrive as `content://` URIs, not paths.
  Stream them into the upload, or copy to the cache dir, and wrap them as
  `XFile`, so `DropService.create` works unchanged. Read the display name and
  size from `OpenableColumns`.
- **Not signed in:** keep the pending share in memory and show it on Send right
  after sign-in instead of dropping it.
- **Routing:** add a way for the app root to open `HomeScreen` on Send with
  initial files/text (like `initialCode` does for Receive).
- **Limits:** apply `DropLimits` when the share arrives (too many files, too
  large) and explain what was skipped.
- **Bonus:** the other direction too. Add a "Share" button on received files
  and on the drop link, using `share_plus`, to hand them to other apps.

### Done when
- Sharing 1 file, many files, a photo from Gallery and a URL from Chrome all
  land on Send with the right names and sizes.
- Works from a cold start, from the background, and when signed out.
- Tested on Android 10 and 14+, with a file near the 100 MB limit.

---

## 2. Ubuntu: feel like a native desktop tool

**Goal:** Burner lives in the top bar and the file manager like a built-in
utility, instead of a window you have to open first.

### 2a. Status bar (tray) icon
- Show a Burner flame in the Ubuntu top bar. Ubuntu ships the AppIndicator
  extension enabled; vanilla GNOME needs it installed.
- **Menu:**
  - **Open Burner**
  - **Send files…** (opens the file chooser and creates a drop)
  - **Send clipboard** (makes a text drop from the clipboard and copies the
    code back)
  - **Receive code…** (opens Receive with the input focused)
  - **Recent drops** (the last few codes; clicking one copies it)
  - **Quit**
- **Close to tray:** closing the window hides it; Burner keeps running in the
  tray. Add a setting to turn this off.
- **Autostart (optional):** a setting that writes
  `~/.config/autostart/com.example.burner.desktop` with a "start minimized"
  flag.
- **Notifications:** a desktop notification when a drop is ready ("Code
  ABC-234 copied"), and when a download is saved.
- **Packages to evaluate:** `tray_manager` or `system_tray` (they need
  `libayatana-appindicator3-dev`), `window_manager` (close-to-tray and
  show/hide), `local_notifier` (notifications). Add the new apt packages to
  the README prerequisites.

### 2b. "Open with Burner" and file manager integration
- **Open With:** add `MimeType=application/octet-stream;...` and
  `Exec=<install>/burner %F` to the desktop entry that
  `linux/install-desktop-entry.sh` writes, so Burner appears in Nautilus →
  **Open With…** for any file.
- **Right-click "Send with Burner":** install a Nautilus script
  (`~/.local/share/nautilus/scripts/Send with Burner`) that runs
  `burner <files>`, or a Nautilus Python extension for a top-level menu item.
- **Command-line files:** `main(List<String> args)` should read file paths
  passed by the runner (`dart_entrypoint_arguments`) and open Send with them
  pre-added, the same path as the Android share.
- **Single instance:** if Burner is already running, `burner file.pdf` should
  hand the files to the existing window instead of opening a second one. Make
  the `GtkApplication` in `linux/runner/my_application.cc` unique and handle
  `open`/`command-line`, then forward the paths to Dart over a method channel.
- **Packaging (later):** a `.deb`, Snap or Flatpak that installs the desktop
  entry, icon, MIME associations and Nautilus script, so the install script
  isn't needed.

### Done when
- Burner starts in the tray, stays running after the window is closed, and
  the tray menu works on Ubuntu 24.04 (X11 and Wayland).
- Right-clicking a file in Nautilus → **Send with Burner** produces a drop in
  the running instance, with no second window.

---

## Backlog

- Google sign-in (needs a desktop OAuth flow on Linux)
- Folder drops (zip on the fly)
- Rules unit tests with the Firebase emulator (needs Java)
- Optional end-to-end encryption, with the key carried in the link fragment
- Re-enable sign-up (`BURNER_SIGNUP_ENABLED`) once there's a plan for abuse
  (invite codes or an allowlist in the rules)
