# AmySortHelper (macOS)

A safety-first macOS app for reviewing files on disk and sorting reviewed items into `Keep` or `Delete`.

## Folder Layout

The app expects a root folder (default):

`/Users/jkfisher/Resilio Sync/Quickswap/Amy Photos/`

Inside that root, it reads files from:

- `Current Sort` (required source folder)

And commits reviewed files to:

- `Keep` (created on commit if missing)
- `Delete` (created on commit if missing)

## What It Does

- Scans top-level files in `Current Sort` (no recursion).
- Includes image and video files.
- Shows capture date when available (EXIF/video metadata), with file date fallback.
- Uses singleton review only (oldest first).
- Defaults every loaded item to `Delete` until changed.
- Moves only **reviewed** items on commit.
- Uses a commit preview with counts/samples and safety confirmation.
- Does not persist in-progress review sessions across launches.

## Safety Behavior

- No background network calls.
- No automatic file moves.
- Commit is user-initiated.
- Commit requires arming confirmation.
- Commits over 200 files require a second confirmation.
- Name conflicts auto-rename (`name (2).ext`) instead of overwrite.

## Run In Xcode

1. Open this folder in Xcode:

```bash
open Package.swift
```

2. Build and run.
3. Confirm root folder path on the left.
4. Add files to `Current Sort`.
5. Click **Scan Current Sort**.
6. Review items and assign Keep/Delete.
7. Arm commit and click **Commit Move to Keep/Delete**.

## Build Standalone .app

```bash
cd /path/to/AmySortHelper
./scripts/build_app.sh
```

Then copy `dist/Amy Sort Helper.app` to `/Applications`.
