# AccessGrant

Dynamic, database-backed, per-tenant role and permission management for
Rails — the "roles and permissions live in the database, admins edit them at
runtime" pattern, without a canonical Rails equivalent until now.

> **Status: design phase.** This repo currently contains project scaffolding
> and design documentation only — no engine code yet. See
> [`docs/proposal.md`](docs/proposal.md) and
> [`docs/architecture.md`](docs/architecture.md) for the full design. The
> installation and usage examples below describe the *planned* v1 API and are
> illustrative, not yet implemented.

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

Full analysis: [`docs/proposal.md`](docs/proposal.md).

## Installation (planned)

```ruby
# Gemfile
gem "access_grant"
```

```
bundle install
rails g access_grant:install --tenant=Organization --identity=Membership
rails db:migrate
bundle exec rake access_grant:sync_permissions
```

## Usage (planned)

```ruby
class Organization < ApplicationRecord
  acts_as_permission_tenant
end

class Membership < ApplicationRecord
  acts_as_permissible
end

membership.permitted?(:manage_billing) # => true / false
```

See [`docs/architecture.md`](docs/architecture.md) for the full data model,
extension points, and design guardrails.

## Development

```
bin/setup
bundle exec rspec
bundle exec rubocop
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for branching, commit, and release
conventions.

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).
