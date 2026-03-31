# Contributing

Thanks for helping improve Media Sort Helper.

## Before Opening a Pull Request

- Keep changes focused and reviewable.
- Preserve the app's local-first, safety-first behavior.
- Avoid adding dependencies, permissions, background network behavior, or automation unless the change clearly requires it.
- Update docs when behavior or workflow changes.

## Local Verification

Run these before opening a pull request when they are relevant to your change:

```bash
swift build
./scripts/build_app.sh
```

If you change file-review or commit behavior, also do a quick manual smoke test with a sample root folder that contains `Current Sort`.

## Pull Request Notes

- Describe user-visible behavior changes clearly.
- Call out any new risks, limitations, or deferred follow-ups.
- Include manual test notes for folder selection, scanning, and commit behavior when those areas change.
