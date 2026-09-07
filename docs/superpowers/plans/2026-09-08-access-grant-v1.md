# AccessGrant v1 Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working AccessGrant Rails gem: configurable tables, catalog DSL + sync, `access_grant :tenant` / `:user`, `permitted?`, Owner grant/revoke, generators, authorize hook, and recovery rake task.

**Architecture:** Pure ActiveRecord models + Ruby modules (no Pundit/Rolify). Host DB owns tables. Catalog is code (`permissions.rb`) synced by rake. Checks are SQL unions through user↔role↔permission joins. Controller hook maps `controller#action` → `resource.action` using `current_user` / `current_tenant`.

**Tech Stack:** Ruby >= 3.1, Rails/ActiveRecord >= 7.0, RSpec, SQLite for gem tests, Rails generators.

**Spec:** [docs/architecture.md](../architecture.md), [docs/superpowers/specs/2026-09-05-owner-role-design.md](../specs/2026-09-05-owner-role-design.md), [docs/superpowers/specs/2026-09-07-usage-scenarios.md](../specs/2026-09-07-usage-scenarios.md)

## Global Constraints

- Ruby >= 3.1; Rails/ActiveRecord >= 7.0
- No Pundit/Rolify/CanCanCan dependencies
- Permission keys: `\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z` only
- Identity naming: **user** (`access_grant :user`, `user_class`, `current_user`)
- Multi-tenant: `permitted?(key, tenant:)` required; single-tenant: omit tenant
- No gem-level memoization of `permitted?`
- Permission description/category: sync-only; role description: admin-editable
- Production code budget aim: ~1000 lines (generators/templates included as soft budget)
- TDD: failing test before implementation for every behavior task
- Commits: only when the human asks (or at task end if they opted into frequent commits during execution)

## File structure (target)

```
lib/access_grant.rb
lib/access_grant/version.rb
lib/access_grant/engine.rb
lib/access_grant/configuration.rb
lib/access_grant/permission_key.rb
lib/access_grant/catalog.rb
lib/access_grant/catalog/dsl.rb
lib/access_grant/models/permission.rb
lib/access_grant/models/role.rb
lib/access_grant/models/role_permission.rb
lib/access_grant/tenant.rb          # access_grant :tenant
lib/access_grant/user.rb            # access_grant :user + permitted?
lib/access_grant/owner.rb
lib/access_grant/recovery.rb
lib/access_grant/controller_methods.rb
lib/access_grant/railtie.rb
lib/generators/access_grant/install/install_generator.rb
lib/generators/access_grant/setup/setup_generator.rb
lib/generators/access_grant/install/templates/...
lib/generators/access_grant/setup/templates/...
lib/tasks/access_grant_tasks.rake
spec/support/active_record.rb
spec/access_grant/...
```

---

### Task 1: Gem dependencies + ActiveRecord test harness

**Files:**
- Modify: `access_grant.gemspec`
- Modify: `Gemfile`
- Create: `spec/support/active_record.rb`
- Modify: `spec/spec_helper.rb`

**Produces:** SQLite in-memory AR connection usable by later model specs.

- [ ] **Step 1: Add runtime/dev dependencies**

In gemspec:

```ruby
spec.add_dependency "activerecord", ">= 7.0"
spec.add_dependency "railties", ">= 7.0"

spec.add_development_dependency "sqlite3", ">= 1.4"
```

In Gemfile keep `gemspec` and existing test gems.

- [ ] **Step 2: Write failing smoke that AR connects**

```ruby
# spec/support/active_record_spec.rb
RSpec.describe "ActiveRecord test harness" do
  it "connects" do
    expect(ActiveRecord::Base.connection).to be_active
  end
end
```

- [ ] **Step 3: Implement `spec/support/active_record.rb` and require it from spec_helper**

```ruby
require "active_record"
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = Logger.new(IO::NULL)
```

Run: `bundle install && bundle exec rspec spec/support/active_record_spec.rb`

- [ ] **Step 4: Commit if human requested commits**

---

### Task 2: Configuration object

**Files:**
- Create: `lib/access_grant/configuration.rb`
- Modify: `lib/access_grant.rb`
- Test: `spec/access_grant/configuration_spec.rb`

**Produces:** `AccessGrant.configure` / `AccessGrant.config` with defaults from architecture.

- [ ] **Step 1: Failing spec for defaults**

```ruby
RSpec.describe AccessGrant::Configuration do
  it "defaults owner_role to :protected and user_class to User" do
    config = described_class.new
    expect(config.owner_role).to eq(:protected)
    expect(config.owner_role_name).to eq("Owner")
    expect(config.user_class).to eq("User")
    expect(config.tenant_class).to be_nil
    expect(config.default_permission_actions).to eq(%w[index show create update destroy])
    expect(config.tables).to include(
      roles: "roles",
      permissions: "permissions",
      role_permissions: "role_permissions",
      user_roles: "user_roles"
    )
  end
end
```

- [ ] **Step 2: Implement Configuration + AccessGrant.configure**

```ruby
module AccessGrant
  class Configuration
    attr_accessor :tenant_class, :user_class, :owner_role, :owner_role_name,
                  :tables, :default_permission_actions, :current_user_method,
                  :current_tenant_method, :on_tenant_created, :recover_access

    def initialize
      @user_class = "User"
      @owner_role = :protected
      @owner_role_name = "Owner"
      @default_permission_actions = %w[index show create update destroy]
      @current_user_method = :current_user
      @current_tenant_method = :current_tenant
      @tables = {
        roles: "roles",
        permissions: "permissions",
        role_permissions: "role_permissions",
        user_roles: "user_roles"
      }
    end
  end

  def self.config = @config ||= Configuration.new
  def self.configure = yield(config)
  def self.reset_config! = @config = Configuration.new
end
```

Reset config in `RSpec.before` for isolation.

---

### Task 3: PermissionKey validation

**Files:**
- Create: `lib/access_grant/permission_key.rb`
- Test: `spec/access_grant/permission_key_spec.rb`

**Produces:** `AccessGrant::PermissionKey.normalize!` / `valid?`

- [ ] **Step 1: Failing specs**

```ruby
expect(AccessGrant::PermissionKey.normalize!("invoices.index")).to eq("invoices.index")
expect(AccessGrant::PermissionKey.normalize!(:invoices_update)).to raise... # invalid
expect { AccessGrant::PermissionKey.normalize!("Invoices.Index") }.to raise_error(AccessGrant::Error)
expect { AccessGrant::PermissionKey.normalize!("manage_billing") }.to raise_error(AccessGrant::Error)
```

Pattern: `/\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/`

- [ ] **Step 2: Implement and pass**

---

### Task 4: Catalog DSL

**Files:**
- Create: `lib/access_grant/catalog.rb`
- Create: `lib/access_grant/catalog/dsl.rb`
- Test: `spec/access_grant/catalog_spec.rb`

**Produces:** `AccessGrant.permissions { resource :invoices; action :couple, description: "..." }` → enumerable entries `{ key:, description:, category: }`

- [ ] **Step 1: Spec — resource emits default actions with templates**

```ruby
AccessGrant.permissions do
  resource :invoices
end
entries = AccessGrant.catalog.entries
expect(entries.map { |e| e[:key] }).to include("invoices.index", "invoices.destroy")
expect(entries.find { |e| e[:key] == "invoices.index" }[:description]).to match(/list/i)
expect(entries.find { |e| e[:key] == "invoices.index" }[:category]).to eq("invoices")
```

- [ ] **Step 2: Spec — custom action + category block + invalid key raises**

- [ ] **Step 3: Implement DSL**

`resource` name: pluralize for key segment (`:invoice` / `:invoices` → `invoices`). Use ActiveSupport inflector.

Default description templates (architecture table). Clear catalog on each `AccessGrant.permissions` block (replace, don't append) unless documented otherwise — **replace** for predictability.

---

### Task 5: Schema helpers + Permission / Role / RolePermission models

**Files:**
- Create: `lib/access_grant/models/permission.rb`
- Create: `lib/access_grant/models/role.rb`
- Create: `lib/access_grant/models/role_permission.rb`
- Create: `spec/support/schema.rb` (create tables using `AccessGrant.config.tables`)
- Test: `spec/access_grant/models/permission_spec.rb`, `role_spec.rb`

**Produces:** AR models with `self.table_name` from config; Permission validates key; Role `permission_keys=` atomic replace; case-insensitive name uniqueness scoped by tenant_id.

- [ ] **Step 1: Schema support**

```ruby
ActiveRecord::Schema.define do
  create_table AccessGrant.config.tables[:permissions], force: true do |t|
    t.string :key, null: false
    t.text :description
    t.string :category
    t.timestamps
  end
  add_index ..., :key, unique: true
  # roles, role_permissions similarly
end
```

- [ ] **Step 2: Permission model specs (valid key, reject bad key)**

- [ ] **Step 3: Role `#permission_keys=` atomic replace spec**

```ruby
role.permission_keys = %w[invoices.index invoices.update]
expect(role.permission_keys).to match_array(%w[invoices.index invoices.update])
expect {
  role.permission_keys = %w[bad]
}.to raise_error
expect(role.reload.permission_keys).to match_array(%w[invoices.index invoices.update])
```

- [ ] **Step 4: Implement models**

`Role` belongs_to tenant optionally (polymorphic **or** configured class — prefer `belongs_to :tenant, polymorphic: true, optional: true` for test flexibility, matching multi-tenant FK in real migrations as `organization_id` when setup runs — **decision for generators:** concrete FK column named after tenant model; models use `belongs_to :tenant, class_name: config.tenant_class` with foreign_key inferred).

For gem models in tests without a host tenant class, use polymorphic `tenant` (`tenant_type`, `tenant_id`) **or** integer `tenant_id` only. Architecture says concrete FK (`organization_id`). Prefer **concrete foreign key via config** at setup time; for in-gem Role model:

```ruby
# Role uses tenant_id + optional tenant_type if polymorphic;
# v1 generators create organization_id (or configured name) WITHOUT polymorphic.
```

**v1 lock-in:** Role has `tenant_id` bigint nullable (null = single-tenant / global). Host generator adds FK + index. Association:

```ruby
belongs_to :tenant, class_name: AccessGrant.config.tenant_class, optional: true
```

When `tenant_class` nil, skip association definition or use a no-op.

---

### Task 6: Catalog sync

**Files:**
- Create: `lib/access_grant/sync.rb`
- Create: `lib/tasks/access_grant_tasks.rake`
- Test: `spec/access_grant/sync_spec.rb`

**Produces:** `AccessGrant::Sync.call` upserts catalog; never deletes; for `:protected`/`:both` re-attaches all keys to Owner roles.

- [ ] **Step 1: Spec upsert + no delete of orphaned DB keys**

- [ ] **Step 2: Spec Owner reattach when owner_role is :protected**

- [ ] **Step 3: Implement + rake `access_grant:sync_permissions`**

---

### Task 7: `access_grant :user` + `permitted?`

**Files:**
- Create: `lib/access_grant/user.rb`
- Modify: load DSL on ActiveRecord::Base
- Test: `spec/access_grant/user_spec.rb`
- Support: minimal `User` + `Organization` + `user_roles` table in schema

**Produces:**

```ruby
class User < ActiveRecord::Base
  access_grant :user
end
user.permitted?("invoices.index", tenant: org) # true/false
```

- [ ] **Step 1: Specs**

  - missing tenant in multi-tenant (`tenant_class` set) → raise  
  - tenant supplied in single-tenant (`tenant_class` nil) → raise  
  - unknown/malformed key → raise (all owner modes)  
  - grant via role → true; other tenant → false  
  - union of two roles  

- [ ] **Step 2: Implement join association + SQL exists/query**

```ruby
# Pseudo
roles for tenant → role_permissions → permissions.where(key: key).exists?
```

---

### Task 8: `access_grant :tenant` + Owner API

**Files:**
- Create: `lib/access_grant/tenant.rb`
- Create: `lib/access_grant/owner.rb`
- Test: `spec/access_grant/owner_spec.rb`

**Produces:** `org.grant_owner!(user)`, `org.revoke_owner!(user)`, last-Owner protection, reserved name, mechanisms `:protected` / `:bypass` / `:both` / `:none`.

- [ ] **Step 1: Specs per architecture Owner table**

  - `:none` → `grant_owner!` raises  
  - `:protected` → Owner has all catalog keys; strip/delete blocked  
  - `:bypass` → `permitted?` short-circuits true for known valid keys when user has Owner role  
  - multiple owners; revoke last → raise  
  - `on_tenant_created` callback after create  

- [ ] **Step 2: Implement**

Single-tenant: `AccessGrant.grant_owner!(user)` when no tenant_class.

Owner name reserved: Role validation rejects ordinary create/rename to owner name when mode ≠ `:none`.

---

### Task 9: Recovery

**Files:**
- Create: `lib/access_grant/recovery.rb`
- Extend rake task `access_grant:grant_role`
- Test: `spec/access_grant/recovery_spec.rb`

**Produces:** Env-based rake `ROLE=Owner USER_ID=1 TENANT_ID=2 rake access_grant:grant_role` calling `config.recover_access` or default `Recovery.grant_role!`.

---

### Task 10: Controller authorize hook

**Files:**
- Create: `lib/access_grant/controller_methods.rb`
- Test: `spec/access_grant/controller_methods_spec.rb` (lightweight controller class)

**Produces:** `access_grant_authorize!`, `skip_access_grant_authorize!`, maps to catalog key via resource inflection from controller path (`InvoicesController` → `invoices` + `action_name`).

- [ ] **Step 1: Spec index → invoices.index; couple → invoices.couple when declared**

- [ ] **Step 2: Uses `send(config.current_user_method)` and `send(config.current_tenant_method)`**

- [ ] **Step 3: Raise / head 403 on failure — use `AccessGrant::NotAuthorizedError` rescued in Railtie optional; for v1 raise error and document host rescue**

---

### Task 11: Generators (install + setup)

**Files:**
- `lib/generators/access_grant/install/...`
- `lib/generators/access_grant/setup/...`
- Templates for migrations, initializer, `permissions.rb`, `roles.rb`
- Test: generator specs with `rails/generators/test_case` if feasible; else manual checklist in plan execution notes

**Produces:**

- `rails g access_grant:install` — migration for permissions, roles (name + nullable tenant_id), role_permissions  
- `rails g access_grant:setup --multi-tenant --tenant=Organization --user=User --owner-role=protected --tables=auto`  
  - collision-aware table names  
  - write **fully commented** initializer documenting every `config.*` option with defaults and examples (mirror architecture Configuration reference)  
  - write `permissions.rb` / `roles.rb`  
  - patch models  
  - print deploy sync reminder  

Also add YARD (or RDoc) comments on each `Configuration` attribute in
`lib/access_grant/configuration.rb` so IDE hover help matches the docs.

**Template requirement for `config/initializers/access_grant.rb`:** every
option from the architecture Configuration reference appears as an
assignment or a commented example (`tenant_class`, `user_class`,
`owner_role`, `owner_role_name`, `tables`, `default_permission_actions`,
`current_user_method`, `current_tenant_method`, `on_tenant_created`,
`recover_access`).

---

### Task 12: Engine/Railtie load + README smoke path

**Files:**
- Create: `lib/access_grant/engine.rb` or `railtie.rb`
- Modify: `lib/access_grant.rb` requires
- Update: `CHANGELOG.md` Unreleased notes

**Produces:** `require "access_grant"` loads rake tasks and ActiveSupport.on_load hooks for `access_grant` macro.

---

### Task 13: Acceptance scenario smoke (subset)

**Files:**
- Create: `spec/integration/happy_path_spec.rb`

Cover scenario IDs from inventory where feasible in-gem: S023-ish ordinary role, S043/S044 checks, S088–S090 Owner, sync idempotence.

Mark Covered scenarios exercised in a short comment header listing IDs.

---

## Spec coverage checklist (self-review)

| Architecture area | Task |
|---|---|
| Config / tables / user naming | 2, 11 |
| Permission key format | 3, 4, 5 |
| Catalog DSL + templates + no auto-discover | 4 |
| Sync + Owner reattach | 6, 8 |
| permitted? edge cases | 7 |
| Owner mechanisms + last owner | 8 |
| Recovery rake | 9 |
| Controller hook + current_user/tenant | 10 |
| Generators + deploy reminder + commented config reference | 11 |
| Row filters host-owned | docs only (no gem task) |

## Placeholder scan

No TBD steps; generator collision algorithm detail lives in Task 11 implementation (check `connection.table_exists?` + `Object.const_defined?`).

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-08-access-grant-v1.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with checkpoints  

**Which approach?**
