# AccessGrant: Architecture & Design

> Status: design phase. Nothing described here as "proposed" is implemented
> yet — this document specifies the target design for the next spec → plan →
> build cycle. See [proposal.md](proposal.md) for the problem this solves and
> why it's shaped this way.

## Data model

All tables are ActiveRecord/SQL, owned by the host app's database (this gem
ships migrations via a generator; it does not run its own separate
database).

```
tenant (host app model, e.g. Organization)
  └─┬─ roles                      (belongs_to tenant; unique per tenant+name)
    └─┬─ role_permissions         (join: role_id, permission_id)
      └── permissions             (catalog: key, description, category)

identity (host app model, e.g. Membership)
  └── <identity>_roles            (join: identity foreign key, role_id — host-named)
```

- **`permissions`** — `key` (unique string), `description`, `category`. Rows
  are upserted from a code constant (`Permission::CATALOG` — exact
  constant/module name TBD at implementation time) via a rake task. Rows in
  this table are never created or edited through a UI; the table is a
  database mirror of a code-defined catalog.
- **`roles`** — `belongs_to :tenant` (polymorphic or foreign-keyed to
  whatever the host app names as `tenant_class`, see below), `name`, unique
  per `(tenant_id, name)`. Fully dynamic: create/rename/delete via the host
  app's own admin UI, calling into models this gem provides. No role is
  special-cased in code — a seeded "Admin" role is just a normal row.
- **`role_permissions`** — plain join table, `role_id` + `permission_id`,
  unique on the pair.
- **`<identity>_roles`** — join table between the host app's assignable
  identity model (e.g. `Membership`) and `roles`, named after the host app's
  identity class so multiple host apps can install this gem without a name
  collision. Enables many-to-many: one identity can hold multiple roles.
- **`permitted?(key)`** — instance method mixed into the host app's identity
  model. Computes the union of permission keys across all of the identity's
  roles as a single SQL query (join through `<identity>_roles` →
  `role_permissions` → `permissions`, filtering on `key`), memoized per
  instance so repeated calls within one request/object lifetime don't
  re-query.

## Extension points (proposed DSL)

> Everything in this section is **proposed, not yet implemented.**

The central reusability problem: "tenant" and "assignable identity" are host
app concepts (KaamSathi: `Organization` / `Membership`; another app might use
`Account` / `User` directly). The gem needs a declaration mechanism rather
than hardcoding class names.

```ruby
class Organization < ApplicationRecord
  acts_as_permission_tenant
end

class Membership < ApplicationRecord
  acts_as_permissible
end
```

- **`acts_as_permission_tenant`** — declared on the host app's tenant model.
  Sets up the `has_many :roles` association and whatever inverse wiring
  `roles` needs to belong to this model.
- **`acts_as_permissible`** — declared on the host app's assignable-identity
  model. Sets up the roles association (through the host-named join table)
  and mixes in `permitted?(key)`.

Naming rationale: `acts_as_*` mirrors the established Rails plugin
convention (`acts_as_list`, `acts_as_paranoid`, and adjacent to Rolify's own
`resourcify`), so it reads immediately as familiar to Rails developers, and
gives the two declarations symmetric, guessable naming.

### Generator

```
rails g access_grant:install --tenant=Organization --identity=Membership
```

Writes:

- Migrations for `permissions`, `roles`, `role_permissions`, and the
  host-named identity↔role join table (e.g. `membership_roles`).
- `config/initializers/access_grant.rb`:

  ```ruby
  AccessGrant.configure do |config|
    config.tenant_class = "Organization"
    config.identity_class = "Membership"
  end
  ```

The generator does not itself add `acts_as_permission_tenant` /
`acts_as_permissible` to the host app's models — the host app adds those
explicitly, so it's always obvious from reading the model which classes
participate.

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
tool, not an automatic side effect of a sync). This is the actual mechanism
that satisfies "an admin doesn't need a deploy to reassign access": the
catalog entry needs one deploy + one rake run; *assigning* that permission to
roles is then fully runtime/admin-controlled.

## Lockout escape hatch

Because there is deliberately no hardcoded, unrevokable super-admin (see
[proposal.md](proposal.md#confirmed-product-requirements)), an operational
rake task must exist from day one as the only sanctioned way to recover from
a tenant admin accidentally revoking their own ability to manage roles:

```
bundle exec rake access_grant:grant_role[role_name,identity_id]
```

This is explicitly an **operational** tool (run by whoever has server/console
access — an ops person or the host app's own superuser tooling), never an
app-level bypass baked into the permission-check code path itself. Keeping it
out-of-band is what makes "no hardcoded floor" an acceptable trade rather
than a genuine lockout risk.

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

### 2. No permission check rides on ambient/global mutable state

A permission check must not silently depend on ambient/global state (e.g. a
`CurrentAttributes`-style singleton) that some other code path on the same
request can mutate. Anywhere a call site's context is something other than
"the current request's own identity" (for example, a check performed on
behalf of a record fetched by ID rather than the requester themselves), the
identity must be passed explicitly as an argument rather than read off a
global. This closes a real hazard class: a controller that repoints a
`Current`-style singleton mid-request (e.g. based on a note's own
organization rather than the request's own header) can silently change what
a later ambient permission check evaluates against.

### 3. Migration sequencing for adopting the gem in an existing app

When a host app migrates from a legacy single-role column onto this gem's
tables, that migration path must be split into (at minimum) three separate
migrations, not one:

1. **Create** the new tables (`roles`, `role_permissions`, the
   identity↔role join table).
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
  Forum," i.e. roles scoped to an individual record rather than the whole
  tenant) — not committed to v1. Left as an open question below.

## Open questions

- Should v1 support resource-scoped roles (role scoped to one specific
  record, not just tenant-wide), or is tenant-wide scoping sufficient until
  a real consumer needs finer granularity?
- Exact naming for the permission catalog constant/module (`Permission::CATALOG`
  used as a placeholder throughout this doc).
- Exact rake task argument syntax for `access_grant:grant_role` (illustrated
  above with Rake's `[arg1,arg2]` syntax as a placeholder).
- Whether `roles.name` collisions should be case-sensitive or
  case-insensitive per tenant.
