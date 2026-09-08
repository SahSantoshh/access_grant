# Contributing

## Getting started

```
bin/setup
bundle exec rspec
bundle exec rubocop
```

`bin/console` starts an IRB session with the gem loaded, for quick manual
experiments.

## Branching

`main` is always releasable. Work happens on short-lived branches named by
type:

- `feature/<slug>` — new functionality
- `fix/<slug>` — bug fixes
- `docs/<slug>` — documentation-only changes
- `chore/<slug>` — tooling, dependencies, CI, maintenance

## Commit messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`.

Examples:

```
feat: add permitted? memoization per instance
fix: prevent duplicate role names within a tenant
docs: document the migration sequencing guardrail
```

A breaking change is marked either with `!` after the type/scope
(`feat!: rename acts_as_permissible to acts_as_grantable`) or a
`BREAKING CHANGE:` footer explaining the impact.

## Pull requests

Every PR should:

- Pass `bundle exec rspec` and `bundle exec rubocop` (enforced by CI).
- Update `CHANGELOG.md` under `[Unreleased]` for any user-facing change.
- Update `README.md` / `docs/` if behavior or the public API changed.

The PR template checklist covers this — fill it in rather than deleting it.

## Versioning & releases

This project follows [Semantic Versioning](https://semver.org/).

### Cut a release

1. Open a PR on `main` that:
   - Bumps `AccessGrant::VERSION` in `lib/access_grant/version.rb`
   - Moves `[Unreleased]` entries in `CHANGELOG.md` under
     `## [X.Y.Z] - YYYY-MM-DD` and leaves a fresh empty `[Unreleased]`
   - Uses commit message `chore: release vX.Y.Z`
2. Merge the PR and wait for CI on `main` to pass.
3. In GitHub Actions, run the **Release** workflow on `main` with input
   `version` set to `X.Y.Z` (must match `AccessGrant::VERSION`).
4. The workflow:
   - Fails fast if the version or CHANGELOG heading does not match
   - Publishes the gem to RubyGems.org via Trusted Publishing (OIDC)
   - Creates git tag `vX.Y.Z` and a GitHub Release from the CHANGELOG section

Do **not** run `bundle exec rake release` locally for production publishes;
Actions owns tagging and `gem push`.

### One-time RubyGems setup

1. Create a RubyGems.org account and enable MFA.
2. Configure a [Trusted Publisher](https://guides.rubygems.org/trusted-publishing/)
   for gem `access_grant`:
   - Repository owner: `SahSantoshh`
   - Repository name: `access_grant`
   - Workflow filename: `release.yml`
   - Environment: leave blank (must match the workflow — no `environment:` key)
3. For the first publish, use RubyGems’ pending trusted-publisher flow if the
   gem name is not on the index yet.

## Code style

RuboCop must pass with no offenses (`bundle exec rubocop`). Match the
conventions already established in the codebase rather than introducing new
ones ad hoc; propose `.rubocop.yml` changes separately if a rule genuinely
doesn't fit.
