# Owner role for tenant creator

> Status: approved design (docs only; not yet implemented)
> Date: 2026-09-05

Privileged Owner role with explicit host-side assignment. The gem
provides the Owner API and rules; the host app decides who becomes
Owner and when (for example after creating an organization).

## Responsibility split

**Gem owns**

- Privileged Owner behavior via `config.owner_role`
  (`:protected` | `:bypass` | `:both` | `:none`)
- `grant_owner!(person)` / `revoke_owner!(person)` on the tenant
  (multi-tenant) or `AccessGrant.grant_owner!` /
  `AccessGrant.revoke_owner!` (single-tenant)
- Enforce “at least one Owner” when revoking, once an Owner exists
- Seed/protect Owner rows and re-attach catalog keys on sync for
  `:protected` / `:both`
- Generators, DSL, and `permitted?`

**Host app owns**

- Who the org creator is
- When to call `grant_owner!` (controller, service, callback, seeds)
- Single-tenant first Owner (seeds or console)

The gem does **not** auto-detect a creator, read `Current.user`, or
inspect a `creator` / `created_by` column. No `auto_grant_owner`,
`current_person`, or `creator_column` config.

```ruby
# Host app — project responsibility
org = Organization.create!(name: "Acme")
org.grant_owner!(current_user)
```

## Data model

**Phase 1 — `rails g access_grant:install`**

Creates core tables only (no tenant or person assumptions):

- `permissions` — catalog keys
- `roles` — `name` only (no tenant column yet)
- `role_permissions` — role ↔ permission

**Phase 2 — `rails g access_grant:setup`**

Accepts flags (non-interactive) or asks interactively when omitted:

```
rails g access_grant:setup \
  --multi-tenant \
  --tenant=Organization \
  --person=User \
  --owner-role=protected
```

| Flag | Meaning | Default |
|---|---|---|
| `--multi-tenant` / `--single-tenant` | Scope mode | asked if omitted |
| `--tenant=Organization` | Tenant class (multi-tenant only) | `Organization` |
| `--person=User` | Person class | `User` |
| `--owner-role=protected` | Owner mechanism | `protected` |

Writes:

- Migrations for the tenant FK on `roles` (multi-tenant only) and the
  person↔role join (`user_roles`, `account_roles`, …)
- `config/initializers/access_grant.rb` with the chosen classes and
  Owner settings
- **Patches host models:** inserts `access_grant :tenant` into the
  tenant model file and `access_grant :person` into the person model
  file (skips if already present; fails clearly if the model file
  cannot be found)

```
Organization ──< Role >── role_permissions ── Permission
                 │
                 └──< user_roles >── User
```

No Membership model. Membership remains a host concern if the app
needs it; AccessGrant attaches roles to the configured person.

## DSL

```ruby
class Organization < ApplicationRecord
  access_grant :tenant
end

class User < ApplicationRecord
  access_grant :person
end
```

Replaces the earlier proposed `acts_as_permission_tenant` /
`acts_as_permissible`. One method, two hats. The `setup` generator
inserts these lines into the named model files; the host can still
add or edit them by hand if needed.

## Owner behavior

### Config

```ruby
AccessGrant.configure do |config|
  config.owner_role = :protected  # :protected | :bypass | :both | :none
  config.owner_role_name = "Owner"
end
```

Default mechanism is `:protected` when the host skips the setup
question.

### Assignment API

```ruby
# Multi-tenant
org.grant_owner!(maya)
org.revoke_owner!(maya)
org.grant_owner!(jordan)  # multiple Owners allowed

# Single-tenant
AccessGrant.grant_owner!(maya)
AccessGrant.revoke_owner!(maya)
```

`grant_owner!`:

1. Finds or creates the Owner role for that scope
2. Applies the configured mechanism (attach all catalog keys when
   `:protected` or `:both`)
3. Inserts the person↔role row

Creating a tenant without calling `grant_owner!` is allowed. The gem
does not enforce a first Owner on create. The “at least one Owner”
rule applies only when **revoking**: you cannot go from one Owner to
zero. Ops can still recover via `access_grant:grant_role`.

If `owner_role` is `:none`, `grant_owner!` raises so the host notices
Owner is turned off.

### Mechanisms

| `owner_role` | Role row | Permission rows | `permitted?` | Strip / delete Owner | Remove last Owner |
|---|---|---|---|---|---|
| `:none` | not seeded | — | normal join | n/a | n/a |
| `:protected` | seeded | every catalog key; sync re-attaches | normal join | no | no |
| `:bypass` | seeded | optional | short-circuit true if person has Owner | role assignable | no (still block last) |
| `:both` | seeded | every catalog key + sync | short-circuit true | no | no |

Plain-language examples:

- **`:protected`** — Owner is a full keyring in the database. Maya
  cannot uncheck permissions on Owner or delete the role. She can
  make Jordan an Owner, then give up her own key.
- **`:bypass`** — Having the Owner role name is enough for
  `permitted?` to return true, even with empty permission rows.
- **`:both`** — Full keyring and short-circuit.
- **`:none`** — No special Owner; host builds roles only; lockout
  rake task is the floor.

### Catalog sync

`access_grant:sync_permissions` upserts catalog keys. For
`:protected` and `:both`, it also re-attaches every catalog
permission to every Owner role in scope.

## Permission checks

```ruby
# Multi-tenant — “Can Maya manage billing in Acme?”
maya.permitted?(:manage_billing, tenant: acme)

# Single-tenant
maya.permitted?(:manage_billing)
```

Checks are scoped per tenant when multi-tenant. Owner of Acme does
not imply access in Beta.

## Error cases

- **Forgot first Owner** — Acme exists with zero Owners until the
  host calls `grant_owner!` or ops runs the rake task. Allowed.
- **Revoke last Owner** — fails with a clear error that the scope
  must keep at least one Owner (`:protected`, `:bypass`, `:both`).
- **Wrong tenant** — `maya.permitted?(:key, tenant: beta)` is false
  if Maya only has roles on Acme.
- **Owner off** — `grant_owner!` raises when `owner_role` is `:none`.

## Lockout escape hatch

Operational rake task remains for recovery (including zero-Owner
scopes after a forgotten grant, or data repair):

```
bundle exec rake access_grant:grant_role[role_name,person_id]
```

Out of band only — not an ambient bypass in `permitted?` beyond the
configured Owner mechanism.

## Out of scope

- Auto-granting Owner from `Current.user` or a creator association
- Membership as the gem’s identity model
- Fully tenant-less installs beyond single-tenant mode (roles with
  no tenant column)
- Engine implementation (this document is design only)

## Decisions

- **Owner is privileged (configurable floor).** Revises the earlier
  “no unrevokable super-admin” product requirement. Rationale: orgs
  need a floor so the creator cannot lock themselves out by editing
  Owner’s permissions.
- **Privilege mechanism is a host choice** — `:protected` (default),
  `:bypass`, `:both`, or `:none`. Rationale: different hosts want
  different floors; the gem should not hardcode one mechanism.
- **Assignment is always explicit via `grant_owner!`.** The host
  decides who the creator is and when to grant. Rationale: detecting
  “who created the org” is project responsibility, not the gem’s.
- **Creating a tenant without an Owner is allowed.** The gem does
  not enforce first Owner on create. Rationale: follows from
  host-owned assignment.
- **Multiple Owners per scope are allowed.** Rationale: orgs have
  more than one person who needs the floor.
- **At least one Owner when revoking.** You cannot remove the last
  Owner in a scope (when Owner is enabled). Rationale: the house
  must keep a key-holder; the rake task is for ops, not accidental
  zero Owners.
- **No Membership in the gem.** Person model is named at setup; join
  is `#{person}_roles`. Rationale: Membership is a host concern;
  roles already belong to the tenant.
- **`permitted?` takes an optional tenant** in multi-tenant mode.
  Rationale: without Membership, tenant must be passed when a person
  can belong to many orgs.
- **Two-phase generator** — `access_grant:install` then
  `access_grant:setup`. Setup accepts `--tenant`, `--person`,
  `--multi-tenant` / `--single-tenant`, and `--owner-role` (or asks
  interactively). Rationale: tenant wiring may not exist on day one;
  flags keep CI/scripts non-interactive.
- **Setup patches model files** with `access_grant :tenant` and
  `access_grant :person`. Rationale: install should leave the host
  wired without a manual model edit; skip if already present.
- **DSL: `access_grant :tenant` / `access_grant :person`.** Replaces
  `acts_as_permission_tenant` / `acts_as_permissible`. Rationale:
  one method, two hats, simpler naming.
- **Default `owner_role` is `:protected`.** Rationale: explicit
  permission rows for everything, no `permitted?` short-circuit
  unless the host opts in.
- **No gem auto-detect of creator** (`Current.user`, creator
  columns, etc.). Rationale: that responsibility stays on the
  project side; the gem only exposes the API to configure and call.
