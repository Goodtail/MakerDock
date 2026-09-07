# Contributing

Thanks for helping make downloaded models easier to find and finished prints easier to remember.

Start with [development](Docs/development.md) and [integration status](Docs/integration-status.md). Bug reports should include the macOS version, MakerDock version, the action taken, and the expected result. Include only files you have permission to share, and remove personal paths and credentials.

For changes:

1. Keep the production/development identity and library-storage separation intact.
2. Keep public-release web automation disabled unless the project has established the required service authorization.
3. Preserve original files and compatibility with saved libraries and print records.
4. Update English, Korean, Japanese, and Simplified Chinese resources together when changing interface text.
5. Run the checks relevant to the change and explain the user-visible behavior in your pull request.

Use synthetic fixtures where possible. `AppTests/Fixtures/Fixture.3mf` is a tiny test archive created for this project, not a downloaded creator model. The screenshot examples are generated from original geometry by `scripts/create-demo-library.py`.

By submitting a contribution, you agree to license your contribution under the project's MIT license. Keep third-party notices with any permitted dependencies you introduce. Do not include Bambu Studio's closed network plugin, account credentials, creator downloads, private service captures, or unrelated company resources.
