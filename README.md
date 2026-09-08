# AccessGrant

[![Gem Version](https://img.shields.io/gem/v/access_grant)](https://rubygems.org/gems/access_grant)
[![CI](https://github.com/SahSantoshh/access_grant/actions/workflows/ci.yml/badge.svg)](https://github.com/SahSantoshh/access_grant/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)

Dynamic, database-backed, per-tenant role and permission management for
Rails — the "roles and permissions live in the database, admins edit them at
runtime" pattern, without a canonical Rails equivalent until now.

> **Status:** v1.0 published on [RubyGems](https://rubygems.org/gems/access_grant).
> Design: [`docs/architecture.md`](docs/architecture.md),
> [`docs/proposal.md`](docs/proposal.md).

## The problem

Every mainstream Rails authorization gem hardcodes "who can do what" in Ruby
code — a policy class, an `Ability` class. Changing a permission means a
developer opening a pull request and deploying. AccessGrant instead keeps
the permission *catalog* in code (so a new capability always requires a code
change to exist) but keeps the *role → permission mapping* in the database,
fully editable by tenant admins at runtime.

## How it compares

| Gem | Roles as data | Permission catalog | Runtime-editable | Per-tenant scoping |
|---|---|---|---|---|
| Pundit | No | No | No | App-defined |
| CanCanCan | No | No | No | App-defined |
| Action Policy | No | No | No | App-defined |
| Rolify | Yes | **No** — no permission concept at all | N/A | Partial |
| **AccessGrant** | Yes | **Yes** | **Yes** | **Yes** |

Built **from scratch** (not on Pundit or Rolify). See [`docs/proposal.md`](docs/proposal.md).

## Installation

```ruby
# Gemfile
gem "access_grant"
```

```
bundle install
rails g access_grant:install
rails g access_grant:setup \
  --multi-tenant \
  --tenant=Organization \
  --user=User \
  --owner-role=protected \
  --tables=auto
rails db:migrate
bundle exec rake access_grant:sync_permissions
```

`setup` patches models with `access_grant :tenant` / `access_grant :user`
and writes `config/initializers/access_grant.rb` plus
`config/access_grant/{permissions,roles}.rb`.

**On every deploy:** run `bundle exec rake access_grant:sync_permissions`
after migrate. Catalog sync is **not** a migration.

## Usage

```ruby
class Organization < ApplicationRecord
  access_grant :tenant
end

class User < ApplicationRecord
  access_grant :user
end

# config/access_grant/permissions.rb
AccessGrant.permissions do
  resource :invoices do
    action :couple, description: "Can couple invoices together"
  end
end

org.grant_owner!(current_user)
current_user.permitted?("invoices.index", tenant: org) # => true / false
```

```ruby
# ApplicationController
access_grant_authorize!  # uses current_user + current_tenant
# host defines: def current_tenant; …; end

# Skip public auth endpoints (Devise sessions/registrations/passwords, etc.)
skip_access_grant_authorize! if: :devise_controller?

# Raises AccessGrant::NotAuthorizedError — rescue in the host, e.g.:
# rescue_from AccessGrant::NotAuthorizedError, with: -> { head :forbidden }
```

Keys are strictly `resource.action`. Permission descriptions come from the
catalog (dev/sync only); role descriptions are admin-editable.

See [`docs/architecture.md`](docs/architecture.md) for models, Owner,
[configuration reference](docs/architecture.md#configuration-reference)
(every `config.*` option with examples), overrides, and the full decision
table. Acceptance scenarios:
[`docs/superpowers/specs/2026-09-07-usage-scenarios.md`](docs/superpowers/specs/2026-09-07-usage-scenarios.md).

## Development

```
bin/setup
bundle exec rspec
bundle exec rubocop
```

Public APIs use **YARD** comments (`@param`, `@return`, `@raise`, `@example`) —
the usual Ruby documentation style (YARD extends RDoc). IDEs show them on
hover; optionally generate HTML with `yard doc` if the `yard` gem is installed.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for branching, commit, and release
conventions.

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).
