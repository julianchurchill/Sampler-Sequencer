# Sampler-Sequencer Development Guidelines

## Branching Policy

**Never commit directly to `main`.** All changes must go through feature branches and be merged via pull request.

### Workflow

1. Create a feature branch from `main`:
   ```
   git checkout main
   git pull origin main
   git checkout -b feature/your-feature-name
   ```
2. Make your changes and commit to the feature branch.
3. Push the branch and open a pull request targeting `main`.
4. Merge only after the CI build passes (GitHub Actions runs `flutter build apk --release`).

### Branch naming

Use descriptive prefixes:
- `feature/` — new functionality
- `fix/` — bug fixes
- `chore/` — tooling, dependencies, config changes

## Versioning and Changelog

Every pull request that changes user-facing behaviour **must**:

1. **Update `CHANGELOG.md`** — add an entry under a new version heading (or an `[Unreleased]` section if the version hasn't been decided yet). Follow the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format: `### Added`, `### Changed`, `### Fixed`, `### Removed`.

2. **Bump the version in `pubspec.yaml`** (`version: MAJOR.MINOR.PATCH+BUILD`) following [Semantic Versioning](https://semver.org/):
   - `PATCH` — bug fixes, no new features
   - `MINOR` — new backwards-compatible features
   - `MAJOR` — breaking changes
   - `BUILD` — increment by 1 on every release (Android `versionCode`)

Pure housekeeping changes (CI config, docs, tooling) do not require a version bump, but should still note the change in `CHANGELOG.md` if it affects developers.
