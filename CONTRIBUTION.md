# Contributing to BetterTot

BetterTot welcomes focused bug fixes, tests, documentation improvements, and
small features that preserve its local-first design.

## Before You Start

- Read [SPEC.md](SPEC.md) for current behavior and architecture.
- Check [PLAN.md](PLAN.md) before expanding scope.
- Open an issue before starting a large feature or architectural change.
- Do not include user notes, local paths, credentials, signing assets, or other
  private data in issues, tests, logs, or commits.

## Development Setup

BetterTot requires macOS 13 or later and a compatible Xcode toolchain.

```sh
git clone https://github.com/saaivignesh20/BetterTot.git
cd BetterTot
swift run
```

Build the application bundle with:

```sh
scripts/bundle.sh
open dist/BetterTot.app
```

## Making Changes

1. Create a branch from `main`.
2. Add or update tests before changing behavior.
3. Keep changes focused and follow the existing AppKit and Swift patterns.
4. Update `SPEC.md` when user-visible behavior or architecture changes.
5. Run the automated and relevant manual checks.

Do not add telemetry, background networking, cloud storage, or a new
dependency without prior architectural discussion.

## Testing

Run the complete verification suite:

```sh
scripts/test.sh
```

The suite enforces at least 80% aggregate line coverage and a per-source-file
minimum. For UI or interaction changes, also complete the relevant items in
[docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md).

## Pull Requests

Pull requests should include:

- A concise description of the problem and solution
- User-visible or compatibility effects
- Automated tests added or changed
- Manual verification performed
- Screenshots for visual changes

Use conventional commit subjects such as `feat:`, `fix:`, `docs:`, `test:`,
or `chore:`. Keep unrelated changes in separate pull requests.

## Reporting Security Issues

Follow the private reporting process in [SECURITY.md](SECURITY.md). Do not open
a public issue or include real note contents, credentials, signing identities,
or other private user data.
