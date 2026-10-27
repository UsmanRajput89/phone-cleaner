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

## Design: Soft UI (neumorphism), dark. User-chosen. Mockup: Claude design artifact "Phone Cleaner"
- One surface colour everywhere: bg `#23262E`. USER HATES BLUR, GLOW AND FADE EFFECTS. Depth comes only from
  crisp, tiny shadows: raised = `0 0 0 1px #2C3039, 0 2px 3px rgba(0,0,0,0.3)` (1px ring + 3px blur max),
  pressed/selected/slots = `inset 0 2px 3px rgba(0,0,0,0.35)`. NO light counter-shadow, NO gradients, NO
  translucent overlays, NO BackdropFilter/blur anywhere. Swipe card "to delete" state = solid 3px coral ring +
  chip; the info strip under the photo is a solid panel, not a fade. Photo placeholders are flat colours.
- Light theme (also required, follows system, Settings can force one): bg `#E6EAF0`, ring `#D3D8E0`,
  shadow `rgba(70,80,100,0.22)`, text `#2B3040`, muted `#5E6577`, accent `#3B4FC4`, keep `#17714A`,
  to-delete `#B02A3E`. Same crisp shadow rules.
- Colours: text `#E6E8EE`, muted `#A3A9B8` (keep contrast, never go dimmer), accent `#8FA2FF`,
  keep `#7DE3B1`, to-delete `#FF9AA5`.
- Shapes: very round (cards 20-32px radius, buttons and nav fully round). Font: system Roboto,
  large light-weight numbers, small muted labels.
- Screens: Home (raised ring disc with inset centre, raised stat cards, inset progress slots, raised nav bar with
  inset selected item), Swipe (raised photo card in a frame, 3 raised round buttons: To delete / Undo / Keep),
  List (selected rows inset, unselected raised, raised CTA "Move N to ToDelete"), ToDelete (raised thumbnails,
  inset info note, inset file tiles). See the design artifact for exact layout.
- PERFORMANCE RULE (old phone): blurred shadows are expensive. Build the shadow as a reusable `BoxDecoration`
  constant, wrap every list row and grid tile in `RepaintBoundary`, use the TINY shadow for repeated items
  (list rows, grid tiles), never animate shadows, and cap blur at 16. If scrolling stutters on the phone,
  drop shadows on repeated items first and keep them on nav, buttons and the home ring.
- Empty and finished states get a short calm message, no illustrations.
- The UI is implemented only after the user approves the mockup.

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
