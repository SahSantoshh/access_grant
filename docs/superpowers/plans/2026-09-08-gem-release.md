# Gem Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a manually triggered GitHub Actions release that publishes `access_grant` 1.0.0 to RubyGems via Trusted Publishing, creates a GitHub Release, and shows version/CI/license badges on the README.

**Architecture:** Hybrid release — humans bump `version.rb` + `CHANGELOG.md` on `main`; `workflow_dispatch` with a `version` input guards those values, then `rubygems/release-gem` (OIDC) tags and pushes the gem; a follow-up step opens the GitHub Release from the matching CHANGELOG section.

**Tech Stack:** GitHub Actions, `rubygems/release-gem@v1`, Bundler gem tasks, Keep a Changelog, shields.io / badge.fury badges.

**Spec:** `docs/superpowers/specs/2026-09-08-gem-release-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `.github/workflows/release.yml` | Manual release: version guards, gem publish, GitHub Release |
| `lib/access_grant/version.rb` | Canonical gem version (`1.0.0`) |
| `CHANGELOG.md` | Keep a Changelog notes for `1.0.0` |
| `README.md` | Badges + published-gem status wording |
| `CONTRIBUTING.md` | Human release steps + Trusted Publisher setup |
| `access_grant.gemspec` | Align `homepage` / metadata URIs with GitHub owner `SahSantoshh` if needed |

---

### Task 1: Bump version and CHANGELOG to 1.0.0

**Files:**
- Modify: `lib/access_grant/version.rb`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Set version constant to 1.0.0**

Replace contents of `lib/access_grant/version.rb` with:

```ruby
# frozen_string_literal: true

module AccessGrant
  VERSION = "1.0.0"
end
```

- [ ] **Step 2: Move Unreleased notes under `[1.0.0]`**

Update `CHANGELOG.md` so that:

1. `## [Unreleased]` remains, with no entries yet (empty section or just the heading).
2. Current bullet list under `[Unreleased]` moves under `## [1.0.0] - 2026-09-08`.
3. Keep the existing `## [0.1.0] - 2026-09-05` skeleton entry below.

Expected shape:

```markdown
## [Unreleased]

## [1.0.0] - 2026-09-08

### Added

- **Configuration** — …
(…all former Unreleased Added bullets…)

## [0.1.0] - 2026-09-05

- Initial gem skeleton (pre-release, unpublished).
```

- [ ] **Step 3: Commit**

```bash
git add lib/access_grant/version.rb CHANGELOG.md
git commit -m "$(cat <<'EOF'
chore: bump version to 1.0.0

Prepare the first public release notes and version constant for
RubyGems / GitHub Release publishing.
EOF
)"
```

---

### Task 2: Add release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/release.yml` with exactly this content (no GitHub Environment block — Trusted Publisher environment must stay blank to match):

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Gem version to release (must match AccessGrant::VERSION)"
        required: true
        type: string

permissions:
  contents: read

jobs:
  release:
    name: Publish gem ${{ inputs.version }}
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    permissions:
      contents: write
      id-token: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.1"
          bundler-cache: true

      - name: Assert version matches
        env:
          EXPECTED_VERSION: ${{ inputs.version }}
        run: |
          set -euo pipefail
          ACTUAL="$(ruby -r./lib/access_grant/version -e 'print AccessGrant::VERSION')"
          if [ "$ACTUAL" != "$EXPECTED_VERSION" ]; then
            echo "::error::AccessGrant::VERSION ($ACTUAL) != workflow input ($EXPECTED_VERSION)"
            exit 1
          fi
          if ! grep -qE "^## \[${EXPECTED_VERSION}\]" CHANGELOG.md; then
            echo "::error::CHANGELOG.md missing heading ## [${EXPECTED_VERSION}]"
            exit 1
          fi
          echo "Releasing access_grant ${EXPECTED_VERSION}"

      - name: Publish to RubyGems
        uses: rubygems/release-gem@v1

      - name: Extract changelog notes
        id: notes
        env:
          VERSION: ${{ inputs.version }}
        run: |
          set -euo pipefail
          NOTES_FILE="${RUNNER_TEMP}/release_notes.md"
          awk -v ver="$VERSION" '
            $0 ~ "^## \\[" ver "\\]" {capture=1; next}
            /^## \[/ {if (capture) exit}
            capture {print}
          ' CHANGELOG.md > "$NOTES_FILE"
          if [ ! -s "$NOTES_FILE" ]; then
            echo "::error::No CHANGELOG body found for ${VERSION}"
            exit 1
          fi
          {
            echo "path=${NOTES_FILE}"
          } >> "$GITHUB_OUTPUT"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ inputs.version }}
          name: v${{ inputs.version }}
          body_path: ${{ steps.notes.outputs.path }}
          fail_on_unmatched_files: true
```

Notes for implementers:

- `rubygems/release-gem` runs Bundler’s `rake release` (build, tag `vX.Y.Z`, push tag, `gem push` via OIDC).
- Do **not** add `environment: release` unless RubyGems Trusted Publisher is also configured with that environment name.
- Trusted Publisher on RubyGems must use workflow filename `release.yml` and repository `SahSantoshh/access_grant`.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "$(cat <<'EOF'
ci: add manual RubyGems release workflow

Add workflow_dispatch release with version guards, Trusted Publishing
via rubygems/release-gem, and GitHub Release notes from CHANGELOG.
EOF
)"
```

---

### Task 3: README badges and status wording

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add badges and update status blurb**

At the top of `README.md`, immediately after `# AccessGrant`, insert:

```markdown
[![Gem Version](https://badge.fury.io/rb/access_grant.svg)](https://rubygems.org/gems/access_grant)
[![CI](https://github.com/SahSantoshh/access_grant/actions/workflows/ci.yml/badge.svg)](https://github.com/SahSantoshh/access_grant/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)
```

Replace the status blockquote:

```markdown
> **Status: v1 implementation.** Full design:
> [`docs/architecture.md`](docs/architecture.md),
> [`docs/proposal.md`](docs/proposal.md).
```

with:

```markdown
> **Status:** v1.0 published on [RubyGems](https://rubygems.org/gems/access_grant).
> Design: [`docs/architecture.md`](docs/architecture.md),
> [`docs/proposal.md`](docs/proposal.md).
```

Preserve the rest of the README unchanged unless badges were already partially added — do not duplicate badge lines.

- [ ] **Step 2: Align gemspec homepage with GitHub owner (if mismatched)**

If `access_grant.gemspec` still points at `https://github.com/santoshsah/access_grant`, update `spec.homepage` (and derived metadata URIs) to `https://github.com/SahSantoshh/access_grant` so RubyGems links match the real repo.

- [ ] **Step 3: Commit**

```bash
git add README.md access_grant.gemspec
git commit -m "$(cat <<'EOF'
docs: add release badges and published status

Surface RubyGems/CI/license badges and point homepage metadata at the
canonical GitHub repository.
EOF
)"
```

---

### Task 4: Update CONTRIBUTING release docs

**Files:**
- Modify: `CONTRIBUTING.md` (section `## Versioning & releases`)

- [ ] **Step 1: Replace the release section**

Replace the entire `## Versioning & releases` section with:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "$(cat <<'EOF'
docs: document hybrid Actions release process

Replace local rake release instructions with the manual workflow_dispatch
flow and Trusted Publisher setup notes.
EOF
)"
```

---

### Task 5: Verify locally (no publish)

**Files:** none (verification only)

- [ ] **Step 1: Confirm version loads**

Run:

```bash
ruby -r./lib/access_grant/version -e 'puts AccessGrant::VERSION'
```

Expected: `1.0.0`

- [ ] **Step 2: Confirm CHANGELOG heading exists**

Run:

```bash
grep -E '^## \[1\.0\.0\]' CHANGELOG.md
```

Expected: a line starting with `## [1.0.0]`

- [ ] **Step 3: Confirm workflow file is valid YAML-ish**

Run:

```bash
ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "ok"'
```

Expected: `ok`

- [ ] **Step 4: Do not publish from the agent**

Publishing requires the maintainer to configure Trusted Publishing and click **Run workflow**. After merge to `main`, the human runs Release with `version: 1.0.0`.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Manual `workflow_dispatch` + version input | Task 2 |
| Hybrid version bump + CHANGELOG 1.0.0 | Task 1 |
| Trusted Publishing / `rubygems/release-gem` | Task 2 |
| GitHub Release from CHANGELOG | Task 2 |
| README badges | Task 3 |
| CONTRIBUTING update | Task 4 |
| No CI matrix in release job | Task 2 (omitted by design) |
| No yank / no changelog automation | Out of scope (omitted) |

## Handoff note for humans

After this lands on `main`: configure Trusted Publisher on RubyGems, then run **Actions → Release → Run workflow** with `version: 1.0.0`.
