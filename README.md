# Media Sort Helper (macOS)

Media Sort Helper is a safety-first macOS app for reviewing image and video files from any selected folder, then moving reviewed items into opinionated destination folders.

## What This Is

This is a largely vibe-coded personal hobby app built for my own use. It does what I wanted it to do. If it also happens to be useful to you, great, but no warranties, support promises, stability guarantees, or long-term commitments are implied.

## Folder Workflow

Choose any source folder to review. The app scans only that folder's top-level files.

When you commit reviewed items, the app moves them into these sibling folders beside the selected source folder:

- `Keep`
- `Delete`
- `Send and Delete`

Destination folders are created automatically if they do not already exist.

Example:

- If you choose `/Photos/Batch 07`, the app scans files in `/Photos/Batch 07`
- Committed files move into `/Photos/Keep`, `/Photos/Delete`, or `/Photos/Send and Delete`

## What It Does

- Scans only the top-level files in the selected folder and does not recurse into subfolders.
- Includes supported image and video files.
- Shows capture date when available from EXIF or video metadata, with file date fallback.
- Orders review items oldest first.
- Defaults loaded items to `Delete` until you change the decision.
- Moves only reviewed items when you explicitly commit.
- Shows a commit preview with counts, samples, and confirmation gates.
- Does not persist in-progress review sessions across launches.

## Safety Behavior

- No background network calls.
- No automatic file moves.
- Commit is always user-initiated.
- Commit requires arming confirmation.
- Commits over 200 files require a second confirmation.
- Name conflicts auto-rename using `name (2).ext` instead of overwriting.

## Run In Xcode

1. Open the package in Xcode:

```bash
open Package.swift
```

2. Build and run.
3. Click **Choose Folder...** and select any source folder you want to review.
4. Add files to that folder if needed.
5. Click **Scan Folder**.
6. Review items and assign `Keep`, `Delete`, or `Send and Delete`.
7. Arm commit and click **Commit Move**.

## Build Standalone .app

```bash
cd /path/to/MediaSortHelper
./scripts/build_app.sh
```

The script creates `dist/Media Sort Helper.app` as a universal macOS app bundle with both `arm64` and `x86_64` slices, so it can run on Apple Silicon and Intel Macs that meet the app's minimum macOS version.

If you need a custom build matrix, set `MEDIA_SORT_HELPER_TARGET_TRIPLES` to a space-separated list of Swift target triples before running the script.

## Notarization And Gatekeeper

This app is not notarized. macOS may warn or block it when you try to open it, especially if you downloaded a built `.app` from someone else.

If Gatekeeper blocks it, use the normal macOS override flow:

1. In Finder, Control-click the app and choose **Open**.
2. Click **Open** in the confirmation dialog if macOS offers it.
3. If macOS still blocks it, go to **System Settings > Privacy & Security** and use **Open Anyway** for the blocked app, then try again.

The app is intended for people who are comfortable running an unnotarized personal project build.
