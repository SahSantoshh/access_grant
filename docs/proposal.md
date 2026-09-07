# AccessGrant: Proposal

> Status: design phase. No engine code exists in this repo yet. This document
> is the "why" and "what"; see [architecture.md](architecture.md) for the
> "how."

## Problem statement

Rails has no canonical gem for the pattern where **roles and permissions live
in the database, and application/tenant admins can create roles and change
what those roles are allowed to do at runtime, without a code deploy**. This
is the pattern popularized in the Laravel ecosystem by
[`spatie/laravel-permission`](https://github.com/spatie/laravel-permission),
and it is a real, common product requirement: an org admin adds a new
"Billing Viewer" role and decides it should see invoices but not edit them —
today, in Rails, that requires a developer to open a pull request.

Every mainstream Rails authorization gem instead pushes permission logic into
Ruby code:

- A **policy class** (Pundit, Action Policy) or an **`Ability` class**
  (CanCanCan) hardcodes which permissions exist and what each role/user can
  do. Changing "who can do what" means editing and redeploying that class.
- These libraries are excellent at *enforcing* authorization decisions
  (`authorize!`, `can?`, `policy.edit?`) but say nothing about *where the
  decision data lives* — that's left entirely to the app.

The one gem that does model roles as data — [Rolify](https://github.com/rolifycommunity/rolify)
— solves the *role assignment* half of the problem (a `roles` table, a join
table, `add_role`/`has_role?`, resource-scoped roles) but, by its own
documentation, is "a simple roles library without any authorization
enforcement." It has no concept of a permission at all: no permission
catalog, no `role_permissions` table, no `permitted?(:key)` method, nothing
that decides what a role can actually *do*. Rolify is typically paired with
CanCanCan or Pundit, at which point the permission logic is right back to
being hardcoded in an `Ability`/policy class — the exact problem this project
exists to solve.

**AccessGrant's contribution is the piece none of these provide**: a
database-backed permission catalog, a `role_permissions` mapping that tenant
admins can edit at runtime, and a `permitted?(key)` check — built as its own
Rails engine rather than as a layer bolted onto Rolify, since building that
mapping is the actual work regardless of what handles role assignment
underneath it.

## Prior art / competitive analysis

| Gem | Roles as data | Permission catalog | Runtime-editable by admins | Per-tenant scoping | Enforcement primitives |
|---|---|---|---|---|---|
| **Pundit** | No (policy classes) | No | No — requires a deploy | App-defined, not built in | Yes (`authorize!`, `policy.action?`) |
| **CanCanCan** | No (`Ability` class) | No | No — requires a deploy | App-defined, not built in | Yes (`can?`, `authorize!`) |
| **Action Policy** | No (policy classes) | No | No — requires a deploy | App-defined, not built in | Yes (`allowed_to?`, `authorize!`) |
| **Rolify** | Yes (`roles` table, join table, resource-scoped roles) | No — no concept of permissions at all | N/A (nothing to edit — no permission model) | Partial (resource-scoped roles), no tenant concept | No — "a simple roles library without any authorization enforcement" (Rolify's own description) |
| **AccessGrant** | Yes (from scratch, not on Rolify) | Yes — code-defined catalog, synced into the DB | Yes — role→permission mapping is fully runtime/admin-controlled | Yes — first-class tenant concept, admin control is per-tenant | Yes — `permitted?(key)` |

### Why not just add a `role_permissions` table on top of Rolify?

This was evaluated and rejected. Rolify's actual surface area — a roles
table, a role-assignment join table, and `add_role`/`has_role?` — is small
and directly reimplementable to fit exactly this gem's tenant/permission
model (see [architecture.md](architecture.md)). Adopting Rolify as a runtime
dependency would still require building 100% of AccessGrant's actual
contribution (the permission catalog, `role_permissions`, `permitted?`) on
top of it, while adding an external dependency whose own scoping model
(global/class-scoped/instance-scoped roles) doesn't line up cleanly with the
tenant-scoped model this gem needs. Building roles and role-assignment
directly keeps the whole data model — tenant, roles, permissions, and their
joins — coherent and fully owned.

## Confirmed product requirements

- **Permission catalog is code-defined, not admin-creatable.** A new
  capability always requires a code change (adding a key to the catalog)
  before it can be granted to anyone. Admins cannot invent permission keys
  from a UI.
- **Roles are fully dynamic and runtime-editable.** Tenant admins can create,
  rename, delete roles, and decide which catalog permissions each role
  grants — at runtime, no deploy. Ordinary seeded roles (e.g.
  Admin/Manager/Worker) are not special-cased; they are editable and
  deletable like any other role. **Owner** is the exception: an optional
  privileged role whose mechanism is host-configured
  (`:protected` / `:bypass` / `:both` / `:none`). See
  [architecture.md](architecture.md#owner-role) and the
  [Owner design spec](superpowers/specs/2026-09-05-owner-role-design.md).
- **Many-to-many roles per person** is a hard requirement, not a single
  role column. The person model is host-named (e.g. `User`); the gem does
  not require a Membership model.
- **Configurable Owner floor; host-owned assignment.** When Owner is
  enabled, it is the in-app floor (explicit permissions and/or a
  `permitted?` short-circuit, per config). The host assigns Owner by
  calling `grant_owner!(person)` after creating a tenant (or in seeds for
  single-tenant) — the gem does not auto-detect creators. When Owner is
  `:none`, recovery is the operational rake task only. There is still no
  ambient bypass outside the configured Owner rules.
- **Per-tenant scoping of admin control.** Who can assign permissions to
  roles, and roles to people, is controllable per tenant — not a single
  global permission matrix shared across every tenant using the host app.
- **Ships as a mountable Rails engine with generators**, following the
  Devise/Pundit convention: `rails g access_grant:install` copies migrations
  into the host app; the gem supplies models, concerns, and (optionally,
  later) controller helpers.
- **License**: MIT. **Ruby**: >= 3.1. **Rails**: >= 7.0.

## Non-goals for v1

- **NoSQL support.** This gem targets ActiveRecord/SQL only for v1. If a
  NoSQL-backed variant is ever warranted, the intent is a separate gem (e.g.
  `access_grant_mongo`) rather than bolting a second persistence layer onto
  this one — see [architecture.md](architecture.md#non-goals--future-considerations)
  for the reasoning.
- **Admin-facing UI, controllers, or serializers.** The gem may optionally
  ship these later; v1 is the data model, extension points, and enforcement
  primitive only.
- **KaamSathi integration.** KaamSathi (the motivating consumer) migrating
  its controllers and `Organization` / person models onto this gem is
  explicit future, separate work — not designed or scheduled here.
- **Auto-granting Owner from request ambient state.** Detecting the org
  creator (`Current.user`, creator associations, etc.) is host-app
  responsibility; the gem only exposes `grant_owner!`.

## Where to go next

See [architecture.md](architecture.md) for the resolved data model,
extension points, proposed DSL, and the design guardrails this gem commits
to.
