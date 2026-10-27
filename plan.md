# phone-cleaner: build plan

Personal Android app (Flutter) for one user to triage ~13k+ files on an old, slow phone into a
`ToDelete` folder. The user deletes from there himself. **The app never permanently deletes anything.**

## Target device
- POCO phone, Android 11 (RKQ1.200826.002), MIUI Global 12.5.8. Old and laggy: keep everything light.
- Install is by sideloaded release APK downloaded from GitHub Releases on the phone.

## Hard rules
1. No delete code in the app. Only move (rename) into `/storage/emulated/0/ToDelete/` and restore back.
2. Never scan or touch: `Android/data`, `Android/obb`, dot-folders, `cache`/`.thumbnails` folders,
   and WhatsApp `Databases` and `Backups`.
3. Tests run only against a generated fake tree in a temp dir. Never touch real user files from CI or the agent.
4. Stay inside this repo only. No secrets, settings or other repos.
5. No background services, no duplicate/blur detection, no preloading of everything.

## Features
**Home:** progress ring (reviewed / total), per-bucket counts (Camera, Screenshots, WhatsApp, Downloads,
Documents, Other), size freed estimate (size of ToDelete), buttons: Swipe, List, ToDelete.

**Swipe mode (photos, videos):** one card at a time. Swipe left = move to ToDelete immediately.
Swipe right = keep. Undo (last 20 actions). Batch counter "n/100" with a gentle "batch done" screen.
Sort: oldest / largest / newest. Filter by bucket. Videos show a thumbnail and play only on tap.
Haptic tick on action. WhatsApp bucket is off by default.

**List mode (docs, PDFs, APKs, zips, everything else):** list sorted by size (toggle by date/name),
checkbox multi-select, "Move N to ToDelete" button, extension filter chips, tap to open the file.

**ToDelete screen:** grid/list of moved files, tap to restore to original path, count and total size.
Hint text: "Delete from Gallery or the Files app". No delete button.

## Design (minimal, clean, dark-first)
- Dark by default (OLED black), light theme optional. No blur, no shadows, no heavy animation (old GPU).
- Palette: bg `#0B0B0D`, surface `#151518`, border `#232328`, text `#F2F2F3`, muted `#8A8A90`,
  keep `#3DDC97`, remove `#FF5C6C`, accent `#7C8CFF`.
- Typography: system font, large light-weight numbers, small muted labels, generous spacing, 16px radius.
- Swipe card: image fills the card, slight tilt while dragging, edge tint green (right) or coral (left),
  bottom bar with file name, size, date and folder. Two round buttons (remove / keep) for one-hand use.
- Empty and finished states get a short calm message, no illustrations.
- A Design mockup is approved by the user BEFORE the UI is implemented.

## Architecture
- Flutter, plain `ChangeNotifier`/`ValueNotifier` state, no heavy state libraries.
- Packages: sqflite, path, path_provider, permission_handler, video_player, video_thumbnail, open_filex.
- Scanner: `Isolate.run`, streams `Directory.list(recursive: true, followLinks: false)`, batch inserts into SQLite
  in transactions. Roots: `/storage/emulated/0` minus exclusions, plus
  `Android/media/com.whatsapp/WhatsApp/Media` and `Android/media/com.whatsapp.w4b` (reachable with All files access).
- SQLite table `files(path PK, size, mtime, bucket, kind, status, orig_path)`;
  status = pending | kept | todelete. Paged queries (50 rows), indexed on status, bucket, size, mtime.
- Move: `File.rename` into ToDelete (create dir, no `.nomedia`, so it shows as a gallery album).
  Name collision: append ` (n)`. On rename failure across volumes: copy, verify size, then remove source. Update DB.
- Media rescan: small Kotlin MethodChannel calling `MediaScannerConnection.scanFile` for old and new
  paths, debounced and batched every ~5 moves and on exit.
- Thumbnails: `ResizeImage`/`cacheWidth` ~400; video thumbs generated on demand and cached on disk; docs use icons.
- Permission: `MANAGE_EXTERNAL_STORAGE`; first launch explains and opens the All files access settings.

## Repo / build
- Repo has `lib/`, `test/`, `pubspec.yaml`, `android_overlay/` (AndroidManifest.xml, MainActivity.kt, keystore),
  `.github/workflows/build.yml`.
- CI generates the Android scaffold (`flutter create --platforms=android .`), copies `android_overlay/` over it,
  then runs `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --release`.
- Release build (debug builds are laggy). Sign with a committed personal keystore so updates install over older
  versions and keep the saved progress.
- On success: publish APK to GitHub Releases (`gh release create` with GITHUB_TOKEN).
- On failure: commit the last ~200 lines of the build log to a `build-logs` branch so the agent can read and fix it.
- Workflow `permissions: contents: write`.

## Tests (pure Dart, fake tree)
Scanner exclusions, bucket/kind classification, DB paging and status changes, move + restore, collision naming,
undo, batch counter.

## Phases
1. Push access check (done) and design mockup approved.
2. Core logic + tests.
3. Swipe mode, list mode, ToDelete screen, home.
4. Workflow, first build, fix loop until the release APK exists.
5. User installs, tests ~20 real files, reports bugs, final fixes.

## Done when
- Release APK is on the Releases page and installs on Android 11 / MIUI 12.5.
- Scan of ~13k files finishes and the app scrolls smoothly.
- Swipe left moves a file into the ToDelete album; restore returns it; undo works.
- No code path permanently deletes a file.
