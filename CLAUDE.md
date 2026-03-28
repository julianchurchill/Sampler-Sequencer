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
