# AccessGrant: Architecture & Design

> Status: design phase. Nothing described here as "proposed" is implemented
> yet — this document specifies the target design for the next spec → plan →
> build cycle. See [proposal.md](proposal.md) for the problem this solves and
> why it's shaped this way. Owner role details:
> [superpowers/specs/2026-09-05-owner-role-design.md](superpowers/specs/2026-09-05-owner-role-design.md).

## Data model

All tables are ActiveRecord/SQL, owned by the host app's database (this gem
ships migrations via a generator; it does not run its own separate
database).

```
tenant (host app model, e.g. Organization) — multi-tenant only
  └─┬─ roles                      (belongs_to tenant when multi-tenant;
    │                              global when single-tenant)
    └─┬─ role_permissions         (join: role_id, permission_id)
      └── permissions             (catalog: key, description, category)

person (host app model, e.g. User)
  └── <person>_roles              (join: person foreign key, role_id — host-named)
```

- **`permissions`** — `key` (unique string), `description`, `category`. Rows
  are upserted from a code constant (`Permission::CATALOG` — exact
  constant/module name TBD at implementation time) via a rake task. Rows in
  this table are never created or edited through a UI; the table is a
  database mirror of a code-defined catalog.
- **`roles`** — In multi-tenant mode, `belongs_to` the host app's tenant
  model (foreign-keyed to whatever `access_grant:setup` recorded as the
  tenant class), `name`, unique per `(tenant_id, name)`. In single-tenant
  mode, roles have no tenant column and are app-global. Fully dynamic:
  create/rename/delete via the host app's own admin UI, calling into models
  this gem provides. Ordinary seeded roles (e.g. Admin/Manager) are normal
  rows. **Owner** is the one configurable privileged role — see
  [Owner role](#owner-role) below.
- **`role_permissions`** — plain join table, `role_id` + `permission_id`,
  unique on the pair.
- **`<person>_roles`** — join table between the host app's person model
  (e.g. `User`, `Account`) and `roles`, named after that class so installs
  do not collide. Enables many-to-many: one person can hold multiple roles.
  The gem does not use a Membership model; if the host has Membership, that
  stays a host concern.
- **`permitted?(key, tenant: nil)`** — instance method mixed into the host
  app's person model. Computes the union of permission keys across the
  person's roles as a single SQL query (join through `<person>_roles` →
  `role_permissions` → `permissions`, filtering on `key`), memoized per
  instance. Multi-tenant: pass `tenant:` so the check is scoped to that
  house. Single-tenant: omit `tenant:`.

## Extension points (proposed DSL)

> Everything in this section is **proposed, not yet implemented.**

"Tenant" and "person" are host app concepts. The gem needs a declaration
mechanism rather than hardcoding class names.

```ruby
class Organization < ApplicationRecord
  access_grant :tenant
end

class User < ApplicationRecord
  access_grant :person
end
```

- **`access_grant :tenant`** — declared on the host app's tenant model
  (multi-tenant). Sets up `has_many :roles`, inverse wiring, and
  `grant_owner!` / `revoke_owner!`.
- **`access_grant :person`** — declared on the host app's person model.
  Sets up the roles association (through the host-named join table) and
  mixes in `permitted?`.

Naming rationale: one method, two hats — simpler than
`acts_as_permission_tenant` / `acts_as_permissible`, and still obvious from
reading the model which classes participate.

### Generators (two-phase)

```
rails g access_grant:install
rails g access_grant:setup
```

**`install`** writes migrations for `permissions`, `roles` (name only), and
`role_permissions` — no tenant or person assumptions yet.

**`setup`** accepts flags or asks interactively when omitted:

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

Then writes:

- Migrations for the tenant FK on `roles` (multi-tenant only) and the
  host-named person↔role join table (e.g. `user_roles`).
- `config/initializers/access_grant.rb`:

  ```ruby
  AccessGrant.configure do |config|
    config.tenant_class = "Organization"   # multi-tenant only
    config.person_class = "User"
    config.owner_role = :protected         # :protected | :bypass | :both | :none
    config.owner_role_name = "Owner"
  end
  ```

- Patches the tenant and person model files with `access_grant :tenant`
  / `access_grant :person` (skips if already present; fails clearly if
  a model file cannot be found).

## Owner role

Owner is the configurable privileged floor. Full design:
[2026-09-05-owner-role-design.md](superpowers/specs/2026-09-05-owner-role-design.md).

**Gem vs host**

- Gem: Owner mechanisms, `grant_owner!` / `revoke_owner!`, at-least-one-Owner
  on revoke, catalog re-attach for `:protected` / `:both`.
- Host: who is the creator and when to call `grant_owner!`. The gem does
  not auto-detect creators (`Current.user`, creator columns, etc.).

```ruby
# Host responsibility after creating an org
org = Organization.create!(name: "Acme")
org.grant_owner!(current_user)

# Single-tenant (e.g. seeds)
AccessGrant.grant_owner!(maya)
```

Multiple Owners per scope are allowed. Revoking the last Owner fails when
Owner is enabled. Creating a tenant with zero Owners is allowed until the
host grants one.

| `owner_role` | Meaning |
|---|---|
| `:protected` (default) | Owner row has every catalog key; sync keeps it complete; cannot strip/delete the role; `permitted?` stays a normal join |
| `:bypass` | Having Owner short-circuits `permitted?` to true |
| `:both` | Protected rows plus short-circuit |
| `:none` | No special Owner; `grant_owner!` raises |

## Catalog sync mechanism

New permission keys always require a code change (adding to the catalog
constant), but rolling that out to a running app is a **data sync, not a
schema migration**:

```
bundle exec rake access_grant:sync_permissions
```

Upserts the catalog constant into the `permissions` table (insert new keys,
update description/category on existing keys, never delete — removing a key
from the catalog is a separate, deliberate decision left to a future admin
tool, not an automatic side effect of a sync). For `:protected` / `:both`,
also re-attaches every catalog permission to Owner roles. Catalog entry
needs one deploy + one rake run; *assigning* permissions to ordinary roles
remains fully runtime/admin-controlled.

## Lockout escape hatch

When `owner_role` is `:none`, or a host never called `grant_owner!`, or data
needs repair, an operational rake task recovers access. It must work for
**both** modes:

```
# Multi-tenant — grant Owner (or any role) to a person in one org
bundle exec rake access_grant:grant_role[Owner,person_id,tenant_id]

# Single-tenant — no tenant argument; roles are app-global
bundle exec rake access_grant:grant_role[Owner,person_id]
```

Exact Rake argument plumbing can use env vars if bracket args are awkward
(`ROLE=Owner PERSON_ID=1 TENANT_ID=42 rake access_grant:grant_role`); the
requirement is that ops can name the role, the person, and (when
multi-tenant) the tenant.

This is explicitly an **operational** tool (server/console access), never an
ambient bypass outside the configured Owner mechanism. With Owner enabled
(`:protected` / `:bypass` / `:both`), the in-app floor is Owner itself;
the rake task remains for ops edge cases (including a forgotten first grant).

## Design principles / guardrails

These are commitments this gem's implementation must honor, not aspirational
guidance — they come directly from failure modes identified while auditing
the motivating host app's current ad hoc authorization code.

### 1. Self-service is not the complement of "lacks permission"

"Lacks permission X" and "is a restricted self-service identity" are
different facts and must be checked independently. A design where "no
`manage_x` permission" implicitly means "fall back to acting only on your own
record" breaks the moment roles are fully dynamic and deletable — there is no
guarantee a "no manage_x" identity is the self-service case at all. The
self-service/ownership check (e.g. "do you own this record?") must be its
own explicit, independent gate. Any broader permission is *additive* — it
grants more access — and must never be treated as the sole complement of "not
a manager."

**Example.** Maya is a worker with no `manage_timesheets` permission. The
app must not infer “so she may only edit her own timesheets.” That
self-service rule is a separate check (`timesheet.user_id == maya.id`).
Jordan has `manage_timesheets` — that *adds* the ability to edit anyone’s
sheet; it is not the sole definition of “not a worker.” If an admin deletes
every manage-role tomorrow, workers without an explicit ownership check
would otherwise fall into a broken “no permission ⇒ do nothing / do
everything” gap.

### 2. No permission check rides on ambient/global mutable state

A permission check must not silently depend on ambient/global state (e.g. a
`CurrentAttributes`-style singleton) that some other code path on the same
request can mutate. Anywhere a call site's context is something other than
"the current request's own person" (for example, a check performed on
behalf of a record fetched by ID rather than the requester themselves), the
person must be passed explicitly as an argument rather than read off a
global. This closes a real hazard class: a controller that repoints a
`Current`-style singleton mid-request (e.g. based on a note's own
organization rather than the request's own header) can silently change what
a later ambient permission check evaluates against.

Creator detection for Owner assignment likewise stays **out** of the gem —
the host passes the person into `grant_owner!` explicitly.

**Example.** A Notes controller loads a note, then does
`Current.organization = note.organization` so a partial can render the
note’s org name. Later in the same action,
`Current.user.permitted?(:delete_notes)` would silently evaluate against
the *note’s* org if `permitted?` read ambient Current — wrong if the
requester is acting as a member of a different org. Correct pattern:
`current_user.permitted?(:delete_notes, tenant: current_organization)`
with both values taken from the request’s own auth context, not from the
loaded record.

### 3. Migration sequencing for adopting the gem in an existing app

When a host app migrates from a legacy single-role column onto this gem's
tables, that migration path must be split into (at minimum) three separate
migrations, not one:

1. **Create** the new tables (`roles`, `role_permissions`, the
   person↔role join table).
2. **Backfill** data from the legacy column into the new tables.
3. **Drop** the legacy column.

Mixing "create tables" + "backfill via ActiveRecord models on those same
tables" + "drop a column" into a single migration risks schema-cache
staleness within that migration and complicates rollback. Steps 1 and 2 can
ship ahead of the code cutover safely (old code simply ignores the new,
unknown tables); step 3 must ship in the same deploy as the application code
that stops reading the dropped column. This applies both as guidance this
gem's docs give to host apps, and to how this gem's own future migrations
(e.g. adding a column to `roles`) should be structured.

**Example.** Host has `memberships.role` as a string. Ship migration A
(create AccessGrant tables) in deploy 1 with no app code change. Ship
migration B (backfill `roles` / joins from the string column) in deploy 2,
still reading the old column at runtime. Ship migration C (drop
`memberships.role`) in the same deploy that switches controllers to
`permitted?`. One big migration that creates, backfills via models, and
drops in a single transaction is harder to roll back and can see a stale
schema cache mid-run.

## Role name uniqueness

Within a scope (one tenant when multi-tenant; the whole app when
single-tenant), `roles.name` is **case-insensitive**. `"Owner"` and
`"owner"` collide. Store a canonical form (implementation detail: e.g.
preserve display casing the host passed on create, but uniqueness and
lookups use a case-insensitive comparison / unique index).

## Permission catalog convention

The catalog is **code-defined** by the host, synced into `permissions` by
rake. The gem ships a default empty catalog file and a documented
convention; it does not invent product permission keys for the host.

**Install generates** `config/access_grant/permissions.rb`:

```ruby
# config/access_grant/permissions.rb
AccessGrant.permissions do
  # category "billing" do
  #   permission :manage_billing, "Create and edit invoices"
  #   permission :view_billing,   "View invoices"
  # end
end
```

**Host convention**

1. Add keys only in that file (or files it `require`s).
2. Deploy.
3. Run `bundle exec rake access_grant:sync_permissions`.

Constant/module name at runtime is an implementation detail of that DSL
(e.g. the block registers into `AccessGrant.permission_catalog`). Admins
never create keys in the UI; they only attach existing keys to roles.

The gem may ship a tiny commented example set in the generated file so the
shape is obvious; production keys always come from the host.

## Default roles at tenant creation (not resource-scoped roles)

Two different ideas:

| Idea | Meaning | v1 |
|---|---|---|
| **Default tenant roles** | When an org is created, seed named roles (Owner, Admin, Member, …) with default permission sets | Yes — via host-configured callback |
| **Resource-scoped roles** | Role on one record (“moderator of Forum #5”), Rolify-style | Deferred — not v1 |

**Recommended v1 approach for defaults:** the gem exposes a hook the host
wires; the gem does not hardcode Admin/Member product roles.

```ruby
AccessGrant.configure do |config|
  config.on_tenant_created = ->(tenant) do
    # Host defines which roles exist for a new org.
    # Owner row may already be ensured by grant_owner!; host can add more:
    AccessGrant::Role.ensure_defaults_for!(
      tenant,
      "Admin"  => %i[manage_members view_billing],
      "Member" => %i[view_billing]
    )
  end
end
```

Exact helper names are implementation details; the contract is:

1. Host registers what “default roles” means for their product.
2. Gem invokes that callback when a tenant record is created (`access_grant
   :tenant` after_create), or the host calls the ensure helper themselves.
3. Assigning a person to Owner remains **`grant_owner!(person)`** — still
   host-owned. Seeding role *definitions* is separate from assigning the
   creator.

Admins can later rename, delete, or re-permission those roles at runtime
(except Owner rules when Owner is privileged). Single-tenant apps run the
same ensure helper once from seeds instead of on tenant create.

Resource-scoped roles stay a future consideration until a real host needs
per-record roles; tenant-wide defaults cover the “starting point roles”
need without that schema.

## Compatibility

- **Ruby**: >= 3.1
- **Rails**: >= 7.0
- **Database**: ActiveRecord/SQL only for v1 (see Non-goals below)

## Non-goals / future considerations

- **NoSQL.** Out of scope for v1. The data model above (foreign keys, join
  tables, unique compound indexes) is relational by nature; if NoSQL support
  is ever pursued, the intent is a separate gem (e.g. `access_grant_mongo`)
  rather than retrofitting this one, since the join-heavy `permitted?` query
  and per-tenant uniqueness constraints don't translate directly to a
  document model. This is a deliberate deferral, not a rejection — revisit
  if/when a concrete NoSQL host app needs this gem.
- **Admin-facing controllers/serializers.** May be added later as an
  optional add-on (e.g. `access_grant-admin_ui` or controllers ships behind
  a config flag); v1 ships the data model, extension points, and
  `permitted?` only.
- **Resource-scoped roles** (Rolify-style "moderator of this specific
  Forum") — deferred; use tenant-wide default-role hooks for starting
  roles instead.
- **Auto-grant Owner from ambient request state.** Out of scope; host
  calls `grant_owner!`.

## Open questions

- Exact rake task argument syntax for `access_grant:grant_role` (bracket
  args vs `ROLE=` / `PERSON_ID=` / `TENANT_ID=` env style).
- Shape of the default-roles helper API
  (`ensure_defaults_for!` vs a richer DSL) — finalize at implementation
  plan time from the contract above.
