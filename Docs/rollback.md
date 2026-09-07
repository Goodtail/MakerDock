# Local rollback checkpoints

MakerDock 1.5.0 (9) implementation is preserved in commit `60caff4`.
The annotated tag `checkpoint/makerdock-1.5.0` marks the same implementation plus these workflow instructions.

The repository is `outputs/plateshelf/plateshelf-desktop` relative to the workspace. Run the commands below from this repository. Git was already initialized before this checkpoint, and its earlier commits have been retained.

## Inspect or rebuild a checkpoint without changing current work

```sh
git status --short
git show --stat checkpoint/makerdock-1.5.0
git worktree add --detach /private/tmp/MakerDock-rollback-1.5.0 checkpoint/makerdock-1.5.0
```

Build from the separate worktree using the README and the production/development identity rules in `AGENTS.md`. If the temporary path already exists, choose a different unused path.

For a requested rollback on the current branch, review the later commits and create revert commits rather than rewriting history. Preserve uncommitted changes first; a request to inspect an older version does not authorize discarding current work.

## Local release and history copies

The checkpoint folder under `.git/checkpoints/makerdock-1.5.0/` contains:

- `MakerDock-1.5.0-universal.dmg`: the signed universal production installer.
- `history.bundle`: a standalone copy of all repository refs at this checkpoint.
- `CHECKPOINT.json`: the full checkpoint commit and installer SHA-256.

Verify the history copy with:

```sh
git bundle verify .git/checkpoints/makerdock-1.5.0/history.bundle
```

A Git bundle can also be cloned into a new, unused directory if a separate source checkout is needed. These are local copies, not an off-device backup. No remote repository or publication is configured.

## Scope

Source, resources, project settings, tests, scripts, and this workflow are tracked here. Adjacent delivery documentation and the Chrome extension are outside this app repository. User library data in Application Support is also outside Git. Replacing an app must preserve its current library; source rollback alone does not roll back models or print history.
