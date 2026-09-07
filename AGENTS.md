# MakerDock repository workflow

The user requires local Git checkpoints so changes can be rolled back.

- This folder is the canonical app source repository. Preserve its existing history.
- Before changing code, inspect `git status` and record the starting commit. If the working tree contains uncommitted work, preserve it without mixing unrelated changes into a commit.
- Finish each coherent, verified change with a local commit before starting the next change. Do not leave completed implementation work uncommitted.
- Tag significant working releases with an annotated `checkpoint/makerdock-VERSION` tag. Never move or replace an existing checkpoint tag.
- Keep work local. Do not push or publish unless explicitly requested.
- Follow `Docs/rollback.md` when asked to roll back. Prefer a separate worktree or a revert commit that preserves later history. Never discard uncommitted user changes.
- Git checkpoints restore source and tracked configuration. Library models, notes, and print records live outside Git; preserve them during app replacement and inspect compatibility before any requested data rollback.

# Apple account boundary

- Use only the personal Apple Developer / App Store Connect team `CHANWOO KOO (D523TSBMWR)` for MakerDock and the user's personal apps.
- Never create, register, sign, upload, transfer, or publish these resources under `PIEVERY AI Inc. (9VP73Q9QX3)`.
- Before any Apple Developer or App Store Connect mutation, verify the active team/provider and stop if it is not the personal team.

# App identity

- Keep separate production and development variants.
- Production IDs follow `com.ninepiece.app.{platform}.{appname}`, with platform exactly `mac`, `ios`, or `android`, and a lowercase app identifier.
- Development IDs append `.dev`; development display names append the exact suffix `-dev` and icons show a visible `DEV` badge.
- MakerDock production: `MakerDock`, `com.ninepiece.app.mac.makerdock`, `AppIcon`.
- MakerDock development: `MakerDock-dev`, `com.ninepiece.app.mac.makerdock.dev`, `AppIconDev`.
