# Contributing to LetsFLUTssh

Thanks for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork and create a feature branch
3. Install Flutter SDK (see [flutter.dev](https://flutter.dev/docs/get-started/install))
4. Run `make deps` to install dependencies
5. Run `make check` to verify everything works (analyzer + tests)

## Development

- **Build:** always use Makefile — `make run`, `make build-linux`, `make test`, `make analyze`
- **Tests:** all new code must have tests. Target 100% coverage on new code; 80% is the hard minimum (SonarCloud Quality Gate)
- **Linting:** `make analyze` must pass with no issues before submitting

## Commit Messages

Format: `type: short description`

| Prefix | Use for |
|--------|---------|
| `feat:` | New features |
| `fix:` | Bug fixes |
| `refactor:` | Code improvements |
| `test:` | Test changes only |
| `docs:` | Documentation only |
| `chore:` | Dependencies, config |
| `ci:` | CI/CD changes |

Commit messages appear in auto-generated release notes — keep them clear and user-readable.

## Pull Requests

- One logical change per PR
- Include tests for new functionality
- `make analyze` and `make test` must pass
- Describe what and why in the PR description

## Reporting Bugs

Open an [issue](https://github.com/Llloooggg/LetsFLUTssh/issues) with:
- Steps to reproduce
- Expected vs actual behavior
- Platform and version

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
