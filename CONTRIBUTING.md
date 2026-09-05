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

This project follows [Semantic Versioning](https://semver.org/). To cut a
release:

1. Bump the version in `lib/access_grant/version.rb`.
2. Move the relevant `[Unreleased]` entries in `CHANGELOG.md` under a new
   `[X.Y.Z] - YYYY-MM-DD` heading.
3. Commit as `chore: release vX.Y.Z`.
4. Run `bundle exec rake release`, which tags `vX.Y.Z`, pushes the tag, and
   pushes the built gem to RubyGems.

## Code style

RuboCop must pass with no offenses (`bundle exec rubocop`). Match the
conventions already established in the codebase rather than introducing new
ones ad hoc; propose `.rubocop.yml` changes separately if a rule genuinely
doesn't fit.
