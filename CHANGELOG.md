# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-09-08

### Added

- **Configuration** — table names, tenant/user classes, owner role mode, controller
  hooks (`current_user_method`, `current_tenant_method`), and recovery callback.
- **Permission catalog DSL** — code-defined `AccessGrant.permissions` catalog with
  `resource` / `action` blocks; synced to DB via `rake access_grant:sync_permissions`.
- **Sync** — idempotent upsert of catalog permissions into the database (never deletes).
- **`permitted?(key, tenant:)`** — runtime authorization check on user models.
- **Owner role** — protected/bypass/both modes, last-owner guard, `grant_owner!` /
  `revoke_owner!`.
- **Recovery rake** — `access_grant:grant_role` for ops lockout recovery.
- **Controller authorization** — `access_grant_authorize!` before-action hook
  (raises `AccessGrant::NotAuthorizedError`).
- **Generators** — `access_grant:install` (core tables) and `access_grant:setup`
  (initializer, catalog, user_roles migration, model patches).
- **Railtie** — loads rake tasks and `ActiveSupport.on_load` hooks for
  `ActionController` and `ActiveRecord`.
- Project scaffolding: gemspec, RSpec/RuboCop harness, CI, and design docs
  (docs/proposal.md, docs/architecture.md).

## [0.1.0] - 2026-09-05

- Initial gem skeleton (pre-release, unpublished).
