# Gem release automation — design

## Goal

Publish `access_grant` to RubyGems.org with version sync across git tags,
GitHub Releases, and RubyGems, using a manually triggered GitHub Actions
workflow and Trusted Publishing (OIDC). First public version is `1.0.0`.

## Decisions

- First public version: **1.0.0** (bump from unpublished `0.1.0`).
- Release is **fully automated** once started, but triggered **manually** via `workflow_dispatch` (not on push/tag for now).
- RubyGems auth: **Trusted Publishing (OIDC)** — no API key secret.
- Version ownership: **hybrid** — human bumps `version.rb` + `CHANGELOG.md` in a PR on `main`; workflow takes a `version` input and **fails** if `AccessGrant::VERSION` does not match.
- Implementation approach: **official `rubygems/release-gem`** + version guard + GitHub Release + README badges.
- CHANGELOG for the first release must also move to **1.0.0** (same PR as the version bump).

## Release flow

1. Maintainer opens a PR that:
   - Sets `AccessGrant::VERSION` to `X.Y.Z`
   - Moves `[Unreleased]` notes under `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md`
   - Leaves a fresh empty `[Unreleased]` section
   - Commits as `chore: release vX.Y.Z` (or similar Conventional Commit)
2. After merge to `main` (and after CI has passed on that commit), maintainer runs **Actions → Release → Run workflow** with input `version: X.Y.Z`.
3. Workflow (on `main` only):
   - Checks out the repo at the current `main` tip
   - Asserts `AccessGrant::VERSION == inputs.version`
   - Asserts `CHANGELOG.md` contains a `## [X.Y.Z]` heading
   - Does **not** re-run the full CI matrix (relies on CI already green on that commit)
   - Uses `rubygems/release-gem@v1` (OIDC) → builds gem, creates/pushes tag `vX.Y.Z`, pushes gem to RubyGems.org
   - Creates a GitHub Release for `vX.Y.Z` with body extracted from that CHANGELOG section
4. README badges reflect RubyGems version / CI / license automatically after publish.

## Components

### Workflow — `.github/workflows/release.yml`

- Trigger: `workflow_dispatch` with required input `version` (e.g. `1.0.0`)
- Guard: fail unless `github.ref == refs/heads/main`
- Permissions: `id-token: write`, `contents: write`
- GitHub Environment: omit by default; use `release` only if the Trusted Publisher on RubyGems is configured with that same environment name
- Steps:
  1. Checkout + Ruby setup (`bundler-cache`)
  2. Assert `AccessGrant::VERSION == inputs.version`
  3. Assert `CHANGELOG.md` has `## [X.Y.Z]` for that version
  4. `rubygems/release-gem@v1` (build, tag `vX.Y.Z`, push gem via OIDC)
  5. Create GitHub Release for tag `vX.Y.Z` with notes from that CHANGELOG section

### First release content (in-repo)

- Bump `lib/access_grant/version.rb` to `1.0.0`
- Move current `[Unreleased]` CHANGELOG entries under `## [1.0.0] - YYYY-MM-DD`; leave a fresh empty `[Unreleased]`
- Update `CONTRIBUTING.md` release section to the hybrid + Actions flow
- Add README badges (RubyGems version, CI, license); adjust status wording for published gem

### One-time human setup (outside repo)

- RubyGems account with MFA
- Configure Trusted Publisher for gem `access_grant`: owner `SahSantoshh`, repo `access_grant`, workflow `release.yml`, environment matching the workflow (blank or `release`)
- First publish may use RubyGems’ pending/trusted-publisher flow for a gem that does not yet exist on the index

## Badges & docs

- README badges under the title: RubyGems version, CI on `main`, MIT license
- CONTRIBUTING.md documents the hybrid release process (PR bump → manual workflow)
- README remains install-focused; status wording updated for a published gem

## Failure modes

- Wrong branch or missing `version` input → fail before any publish side effects
- `AccessGrant::VERSION` ≠ input, or missing `## [X.Y.Z]` in CHANGELOG → fail before `release-gem`
- Trusted Publisher / OIDC misconfiguration → `release-gem` fails (no silent API-key fallback)
- Existing tag or already-published gem version → fail; no overwrite
- GitHub Release is created only after successful gem publish

## Out of scope

- Auto-publish on tag push (future upgrade)
- Automated version bumping / changelog generation (release-please, etc.)
- Yanking / yank workflows
- Re-running the full CI matrix inside the release workflow
