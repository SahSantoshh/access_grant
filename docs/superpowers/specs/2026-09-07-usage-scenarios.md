# AccessGrant — Usage Scenarios and Proposal Coverage

> Adopted into this repo from an external design review (2026-09-07).
> Companion to [architecture.md](../../architecture.md),
> [2026-09-05-owner-role-design.md](2026-09-05-owner-role-design.md), and
> [2026-09-07-proposal-review.md](2026-09-07-proposal-review.md).
>
> This is a scenario inventory for acceptance checks — **not** a v1 feature
> shopping list. Status meanings and priorities below still apply. Where
> architecture later **resolves** an Open/Partial item, treat architecture
> as authoritative and update the row when implementing tests.

> Terminology note (2026-09-07): the assignable identity is **user**
> (`access_grant :user`, `user_class`, `current_user`), not “person.”
> Older rows in this inventory may still say “person”; treat that as **user**.

Companion to the proposal review; this is a scenario inventory, not a replacement RFC.

**Reviewed baseline:** commit `66c7fcc20e167c45160ea285cc1766dbab2d6e4d` (and later design brainstorm). Database-backed catalog and grants, configured person model, explicit tenant checks, and all four Owner modes are preserved. The repository contains design documentation and scaffolding only. **Covered means specified, not implemented or tested.**

This is a broad inventory of realistic happy paths, edge cases, and integration boundaries—not a claim to enumerate every possible application. Missing optional features are not automatically v1 requirements. Use the IDs to record decisions and later link executable tests.

## How to read this

| Status | Meaning |
|---|---|
| Covered | Explicitly specified, or a direct consequence of an explicit rule. Preserve and test. |
| Partial | Intent exists, but the public contract is incomplete or ambiguous. |
| Inferred | Likely behavior from the described schema/query, not an explicit promise. Confirm. |
| Open | No clear contract found. Decide, document a limitation, or defer. |
| Host | Host owns this application behavior; document integration rather than expanding the gem. |
| Deferred | Latest proposal explicitly excludes it. Not a design defect. |
| Conflict | Documents disagree, or the prescribed sequence needs correction for the stated scenario. |

“Desired behavior / interpretation” is review guidance unless marked Covered. It must not be confused with a promise already made by the author. Public APIs not present in the proposal are intentionally not invented here.

## Source map

- **A — [Architecture](../../architecture.md):** model, DSL, sync, defaults, guardrails, installation, resolved public-contract decisions.
- **O — [Owner specification](2026-09-05-owner-role-design.md):** approved Owner and person-model decisions.
- **P — [Proposal](../../proposal.md):** purpose, product scope, non-goals.
- **R — [README](../../../README.md):** planned install/usage (kept aligned with architecture).
- **Review — [Proposal review](2026-09-07-proposal-review.md):** external review that drove several resolutions.

## The usage we should be able to demonstrate

These calls are actually proposed:

```ruby
class Organization < ApplicationRecord
  access_grant :tenant
end

class User < ApplicationRecord
  access_grant :person
end

AccessGrant.permissions do
  category "billing" do
    permission :view_billing, "View invoices"
    permission :manage_billing, "Create and edit invoices"
  end
end

# After deployment and access_grant:sync_permissions:
acme.grant_owner!(maya)
maya.permitted?(:manage_billing, tenant: acme)
```

The missing ordinary-role walkthrough should use the author's intended ActiveRecord associations/methods to: create Billing Viewer → select view_billing → assign Maya → check Acme and Beta → edit grants → check again → revoke assignment. Show catalog enumeration and current selections for an admin form. The model supports this intent; the exact public workflow is not fully documented.

**Important:** Maya can legitimately hold roles in both Acme and Beta. Assigning a Beta role to a global person is not inherently a tenant mismatch. The host authorizes the acting administrator; any mutation that separately accepts tenant context must validate consistency.


**Inventory:** 116 scenarios. Covered: 31, Partial: 11, Open: 43, Conflict: 2, Inferred: 5, Host: 21, Deferred: 3.


## Setup and adoption

Evidence: A: Extension points, Generators, Compatibility; O: Decisions; R. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S001 | Install with Organization and User | Covered | Use install then setup with explicit flags; generate tenant/person wiring. | Exercise the documented generated installation. |
| S002 | Install a single-tenant application | Covered | Roles are global; checks omit tenant. | Exercise setup, role creation, checks, and recovery in this mode. |
| S003 | Use a differently named person/tenant model | Covered | Configured classes replace hardcoded User/Organization. | Test custom names and associations. |
| S004 | Run setup when a model file is missing | Covered | Setup fails clearly rather than silently skipping wiring. | Keep as acceptance test. |
| S005 | Run setup on already-wired models | Partial | Existing DSL declarations are skipped. | Specify migration/config file conflict behavior; do not overwrite host edits. |
| S006 | Install into an app already using roles/permissions tables | Open | Installation should avoid collisions or stop clearly. | Choose namespacing/configuration; generic names currently collide. |
| S007 | Install with UUID or namespaced host models | Open | Generated foreign keys and model lookup should match supported host types. | Declare and test support; avoid implying every Rails model layout works. |
| S008 | Follow README versus latest design | Conflict | One canonical install and identity example. | README uses old Membership DSL; align with approved User/person setup. |
| S009 | Adopt during a rolling deployment | Conflict | Old processes must retain columns they still use. | Architecture drops legacy column in cutover deploy; defer drop until old readers/writers are gone. |
| S010 | Backfill while legacy roles continue changing | Open | Changes during migration must not disappear. | Document coordinated writes or a controlled maintenance cutover. |

## Permission catalog and deployment

Evidence: A: Data model, Catalog sync mechanism, Permission catalog convention. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S011 | Declare a new capability | Covered | Add code key and metadata, deploy, run sync. | Keep documented path. |
| S012 | Admin invents a permission in the UI | Covered | Not supported; admins select existing catalog entries. | Verify host UI does not expose arbitrary catalog creation. |
| S013 | Update description or category | Covered | Sync updates metadata on existing keys. | Test that role mappings remain intact. |
| S014 | Repeat an unchanged sync | Covered | Upsert catalog rows without duplicating keys. | Verify idempotence including protected Owner attachment. |
| S015 | Deploy a key but forget sync | Open | No accidental allow; clear operational diagnosis. | Define check/assignment behavior for code-known but absent database keys. |
| S016 | Remove a declaration but retain database grants | Inferred | Non-deleting sync plus database joins suggests existing grants remain effective. | Confirm this explicitly; removal from code is not established revocation. |
| S017 | Rename a capability | Open | Explicitly migrate grants or intentionally reset them. | Document supported sequence; do not infer rename from key removal/addition. |
| S018 | Reintroduce a removed key | Open | No surprising reuse of old authority. | Explain retained grants and prohibit semantic key reuse without deliberate cleanup. |
| S019 | Run sync concurrently or interrupt it halfway | Open | Retry should converge; partial completion must be understandable. | Specify transaction/retry behavior for catalog and Owner reattachment. |
| S020 | Old/new application versions run simultaneously | Open | Catalog/check behavior during overlap is documented. | Test additive rollout and retirement; define authoritative key validation source. |
| S021 | Declare duplicate, blank, or malformed keys | Open | Fail clearly before ambiguous catalog data is accepted. | Specify validation and duplicate declaration rules. |
| S022 | Boot/reload Rails or run generators before migrations | Open | Catalog loading is repeatable and does not require unavailable tables. | Test development reload and fresh installation boot. |

## Ordinary roles and admin forms

Evidence: A: Data model, Extension points, Role name uniqueness; P: Confirmed product requirements. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S023 | Create Billing Viewer at runtime | Covered | Create tenant role and attach existing view permission without deployment. | Show canonical model-based Ruby example. |
| S024 | Rename or delete an ordinary role | Covered | Ordinary roles are editable/deletable. | Document supported CRUD and deletion effects on joins. |
| S025 | Create Admin in Acme and Admin in Beta | Covered | Names are unique within scope, not across tenants. | Keep as tenant separation test. |
| S026 | Create Admin and admin within one scope | Covered | Case-insensitive uniqueness rejects collision. | Test database enforcement on supported adapters. |
| S027 | List catalog options for a role editor | Partial | Permission table supplies keys/descriptions/categories. | Show supported query, ordering, and selected-key lookup; no wrapper required. |
| S028 | List a person’s roles in Acme only | Partial | Person roles association exists and roles carry tenant. | Show canonical scoped query; avoid listing every tenant in an Acme form. |
| S029 | Replace a role’s selected permission set | Partial | Runtime editing is intended. | Choose supported operation; validate and commit entire replacement atomically. |
| S030 | Save an empty permission selection | Inferred | Ordinary role with no grants should confer no capabilities. | Specify empty-set semantics and test. |
| S031 | Add the same permission twice | Partial | Role-permission pair is unique. | Define API outcome: harmless repeat or clear validation error. |
| S032 | Move an existing role from Acme to Beta | Open | Existing assignments must not silently acquire authority in another scope. | Recommend immutable tenant or an explicitly defined migration operation. |

## Role assignment and removal

Evidence: A: Data model, Extension points, Lockout escape hatch. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S033 | Assign several roles to Maya | Covered | Many-to-many roles are a hard requirement. | Show ordinary assignment and removal API. |
| S034 | Assign Acme and Beta roles to the same Maya | Covered | Valid: person is global and checks select tenant. | Do not incorrectly prohibit cross-tenant roles on one person. |
| S035 | Assign the same role repeatedly | Open | Prefer one effective assignment without duplicate rows. | Specify join uniqueness and idempotent public behavior. |
| S036 | Revoke an assignment that does not exist | Open | Prefer harmless repeat for retryable administration. | Define outcome; do not let retries create surprising errors. |
| S037 | Remove one of two roles granting the same permission | Covered | Union means the other role continues granting it. | Test with cache freshness accounted for. |
| S038 | Remove the final role granting a permission | Inferred | Fresh normal evaluation should deny. | Specify when memoized checks observe removal. |
| S039 | Assign an unsaved, wrong-class, or deleted role/person | Open | Reject invalid inputs without partial data. | Define supported persisted inputs and public errors. |
| S040 | Replace all roles on a person | Open | Useful admin workflow; must preserve selected tenant boundaries. | Document scoped replacement or explicit add/remove sequence; no new helper required. |
| S041 | Submit a Beta role ID through an Acme admin page | Host | Host must validate the acting admin’s authority and target scope. | If gem API also accepts tenant, enforce consistency; role-only assignment is not intrinsically invalid. |
| S042 | Two requests concurrently assign the same role | Open | One assignment; predictable retry behavior. | Test uniqueness plus mutation handling, not only validations. |

## Permission-check API

Evidence: A: Data model, Guardrail 2; O: Permission checks, Error cases, Decisions. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S043 | Check a granted key in Acme | Covered | permitted?(:key, tenant: acme) returns true. | Keep existing predicate shape. |
| S044 | Check Acme role against Beta | Covered | False when person has only Acme grants, including Acme Owner. | Keep as acceptance test. |
| S045 | Check a known key with no matching roles | Inferred | Normal join yields false. | State deny-by-default explicitly. |
| S046 | Omit tenant in multi-tenant mode | Partial | Signature allows nil; prose says pass tenant. | Resolve ambiguity; recommend clear missing-context error. |
| S047 | Supply tenant in single-tenant mode | Open | Do not silently imply tenant isolation in a global install. | Define rejection or explicitly documented handling. |
| S048 | Check unknown/misspelled permission as ordinary person | Inferred | Database join suggests false; validation is not specified. | Choose and document false versus error; error is a review preference. |
| S049 | Check unknown/misspelled permission as Owner | Partial | Bypass says short-circuit true; key validation order is unstated. | Make behavior explicit across all modes. |
| S050 | Pass symbol versus string key | Partial | Symbol examples and string storage imply normal usage. | Specify normalization and case sensitivity. |
| S051 | Pass nil, unsaved, deleted, or wrong-class tenant | Open | No global fallback or accidental allow. | Define invalid-context behavior. |
| S052 | Change Current.organization after loading a record | Covered | Explicit input prevents ambient state from altering checks. | Retain existing guardrail example. |
| S053 | Ask why a check passed or list effective permissions | Open | Admin troubleshooting should be possible through documented queries. | Show role/grant inspection; a new explanation API is optional. |

## Freshness, transactions, and failures

Evidence: A: Data model (per-instance memoization); P: Runtime-editable permissions. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S054 | Edit a role after an earlier successful check on same instance | Open | Define whether next check sees committed change. | Specify memoization invalidation or lifetime. |
| S055 | Edit through a second process or loaded instance | Open | Freshness promise must cover ordinary admin edits elsewhere. | Test existing instance against separately committed mutation. |
| S056 | Check Acme then Beta on the same person instance | Partial | Explicit scope must remain effective under memoization. | Cache key must distinguish tenant and permission. |
| S057 | Check false, then grant permission | Open | Cached denial must have a defined refresh path too. | Test grants as well as revocations. |
| S058 | Check while a permission replacement is uncommitted | Open | No partially applied set should be visible. | Define transaction boundary and supported isolation assumptions. |
| S059 | Two admins replace a role’s permissions concurrently | Open | Each edit is atomic; final result is a coherent set. | Choose serialized replacement or conflict detection, not accidental merging. |
| S060 | Host transaction rolls back an assignment | Open | Database and cached decisions must not retain rolled-back access. | Test check-after-rollback behavior. |
| S061 | Read permission from a lagging replica | Open | Document that freshness depends on connection routing. | State writer requirement if post-commit revocation freshness is promised. |
| S062 | Database times out during permission check | Open | Failure must never become an allow. | Document error propagation; do not disguise outage as successful authorization. |
| S063 | Render many buttons or check many people | Open | Performance should remain bounded and understandable. | Measure actual query count; specify any preload/cache contract before optimizing. |

## Membership and person lifecycle

Evidence: A: Data model; O: Out of scope, Decisions. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S064 | Require Membership as a gem-owned model | Deferred | Latest design intentionally does not use Membership as identity. | Do not treat README’s stale example as intended support. |
| S065 | Remove Acme membership while User role joins remain | Host | Membership is host-owned; joins are independent in proposed model. | Document active-membership gate or cleanup so removed members cannot use retained grants. |
| S066 | Suspend membership or disable a user | Host | Host eligibility must deny even when capabilities remain assigned. | Include one integration example; gem cannot infer custom status fields. |
| S067 | Delete a person with role assignments | Open | No dangling assignments; last-Owner policy must be considered. | Specify foreign-key/dependent cleanup and privileged deletion behavior. |
| S068 | Delete a tenant with roles and Owners | Open | Define intended cleanup; tenant deletion differs from locking out an existing tenant. | Specify cascade/restriction behavior. |
| S069 | Soft-delete then restore a user or membership | Host | Restoration policy decides whether access returns. | Document retained grants and explicit host cleanup/restore policy. |
| S070 | Invite someone before a persisted person exists | Host | Host invitation flow decides when to create person and assignments. | Document persistence requirement; pending invitations need not be gem models. |
| S071 | Anonymous visitor or unauthenticated request | Host | Host decides public access before person checks. | Do not assume nil recipient support or public-access grants. |

## Record reads and application integration

Evidence: A: Guardrails 1–2, Non-goals; P: Non-goals. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S072 | View an invoice in the selected tenant | Host | Capability check plus tenant-scoped record lookup. | Use acme.invoices.find(id), not unrestricted Invoice.find(id). |
| S073 | List/search/paginate/export authorized records | Host | Apply host policy relation before counts, pagination, and export. | Add an end-to-end collection example; gem does not infer row scopes. |
| S074 | Allow own timesheets plus broader manager access | Covered | Independent ownership condition plus additive capability. | Keep existing explicit self-service guardrail. |
| S075 | Hide a button when access is denied | Host | Predicate is suitable for UI, but server must still enforce. | Document controller/service enforcement alongside view example. |
| S076 | Restrict fields or filter writable parameters | Host | Host policy/serializer decides field-level behavior. | Do not interpret a tenant capability as every field being accessible. |
| S077 | Enforce invoice state, plan limits, or separation of duties | Host | Business predicates compose with capability check. | Owner bypass should not silently become a host-wide policy bypass. |
| S078 | Authorize a background export after permission was revoked | Host | Host decides execution-time recheck and uses explicit person/tenant. | Show reauthorization for delayed sensitive work, with freshness caveats. |
| S079 | Check once then perform a concurrent sensitive mutation | Host | A predicate alone cannot eliminate check/use races. | Document host transaction/locking needs when atomic authorization is required. |
| S080 | Cache a response containing permission-controlled data | Host | Host response cache must account for access changes. | Gem memoization policy does not invalidate application/CDN caches. |

## Who may administer access

Evidence: P: Per-tenant scoping of admin control; A: Data model, Non-goals. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S081 | Tenant admin creates or edits a role | Partial | Host admin UI invokes supplied models; per-tenant admin control is intended. | State that mutation methods do not automatically authenticate/authorize caller. |
| S082 | Billing admin attempts to grant payroll access | Host | Host decides grantable subset; editing some roles does not imply granting everything. | Provide policy example if delegated administration is a supported host use case. |
| S083 | Admin edits or grants a role to themselves | Host | Host decides self-escalation rules. | Make caller authorization boundary clear. |
| S084 | Admin submits arbitrary permission IDs | Host | Host validates allowed grants, gem preserves relationship integrity. | Document catalog selection and rejection of invalid foreign keys. |
| S085 | Support staff administer another tenant | Host | Host explicitly authorizes target tenant and person. | No ambient bypass is introduced. |
| S086 | Record who changed grants and why | Host | Audit storage and acting-user capture are host concerns unless an extension is promised. | Show model/service integration; do not demand an audit subsystem in v1. |

## Owner role and recovery

Evidence: O: Assignment API, Mechanisms, Error cases, Decisions; A: Lockout escape hatch. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S087 | Create tenant without first Owner | Covered | Allowed until host calls grant_owner! or ops recovers. | Keep explicit first-owner responsibility. |
| S088 | Grant Owner explicitly after tenant creation | Covered | Find/create scope Owner, apply configured mechanism, assign person. | Keep documented API. |
| S089 | Add a second Owner and revoke first | Covered | Multiple Owners allowed; revoke succeeds while another remains. | Test both scope modes. |
| S090 | Revoke the final Owner | Covered | Fails in protected, bypass, and both modes. | Test stated invariant. |
| S091 | Use protected Owner | Covered | All catalog keys through normal join; strip/delete role prohibited. | Test sync reattachment and protection. |
| S092 | Use bypass or both Owner | Covered | Bypass short-circuits; both also maintains protected grant rows. | Keep distinct documented behavior; test known keys and scope. |
| S093 | Use owner_role none | Covered | No special Owner; grant_owner! raises; ops can grant ordinary roles. | Test recovery without special privilege. |
| S094 | Sync new permission with protected/both Owners | Covered | Attach new catalog permissions to those Owner roles. | Test across existing tenants. |
| S095 | Create/rename ordinary role to privileged Owner name | Open | Name changes must not accidentally establish privilege. | Define reserved-name or stable-identity enforcement. |
| S096 | Repeat grant_owner! or run it concurrently | Open | No duplicate Owner role/assignment or partial setup. | Specify idempotence and database constraints. |
| S097 | Two final Owners concurrently revoke themselves | Open | Stated at-least-one rule must survive concurrency. | Specify transaction/locking strategy and test. |
| S098 | Delete last Owner assignment/person outside revoke_owner! | Open | Clarify whether invariant covers every supported mutation path. | Protect or document restricted APIs; do not imply callbacks cover raw SQL. |
| S099 | Suspend the only Owner | Host | A retained Owner row does not guarantee an eligible human can log in. | Document recovery and host suspension policy. |
| S100 | Change Owner mode or configured name after adoption | Open | Privilege changes must be deliberate and reproducible. | Specify supported transition/migration or declare configuration immutable. |
| S101 | Recover using operational role-grant task | Covered | Name role/person/tenant in multi-tenant; omit tenant in single-tenant. | Finalize syntax; explain unknown role/person and duplicate grant behavior. |

## Default roles and extensibility

Evidence: A: Default roles at tenant creation, Non-goals. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S102 | Seed host-defined roles when a tenant is created | Covered | Configured callback invokes default-role helper; no fixed product roles. | Keep separation of definitions and creator assignment. |
| S103 | Admin edits a previously seeded role | Covered | Ordinary defaults remain editable and deletable. | Test that runtime edits are allowed. |
| S104 | Re-run default helper after admin customizes roles | Open | Do not unexpectedly overwrite customer choices. | Define ensure semantics: create-only, merge, or replacement. |
| S105 | Default-role callback fails during tenant creation | Open | No unexplained partial tenant/role state. | Define rollback and retry behavior; test unsynced catalog keys. |
| S106 | Use resource-scoped roles on one invoice/forum | Deferred | Explicitly outside v1. | Preserve boundary; host policy may cover simpler ownership needs. |
| S107 | Use NoSQL or gem-provided admin controllers | Deferred | Explicitly outside core v1. | Do not count intentional non-goals as defects. |
| S108 | Need direct user grants, deny rules, or role inheritance | Open | No such semantics are proposed; current model is additive role union. | State unsupported unless a concrete v1 requirement warrants expansion. |
| S109 | Need global superadmin across all tenants | Open | Tenant Owner explicitly is not global superadmin. | Keep host policy responsibility or explicitly defer; do not infer global bypass. |

## Additional boundary and interaction cases

Evidence: A: Data model, Catalog sync mechanism, Default roles; O: Assignment API, Mechanisms. “Open” denotes a missing contract in the reviewed documents, not an observed bug.

| ID | Scenario | Status | Desired behavior / interpretation | Follow-up or acceptance check |
|---|---|---|---|---|
| S110 | Assign Owner through an ordinary role association | Open | Owner setup/protection should not be silently bypassed. | Specify whether helper is required, and how supported association writes preserve invariants. |
| S111 | Create tenant/Owner concurrently with catalog sync | Open | New protected Owner should have a coherent catalog set after operations complete. | Test interleaving; define completeness and retry expectations. |
| S112 | Create tenant succeeds but initial Owner grant fails | Covered | Zero-Owner tenant is explicitly allowed. | Host wraps create-and-grant in a transaction if atomic onboarding is required. |
| S113 | Run recovery for a role named Owner when mode is none | Partial | No implicit bypass should arise from the name. | Clarify ordinary role creation/lookup and missing-role behavior. |
| S114 | Give temporary access that expires tomorrow | Open | Time-limited grants are not proposed. | Explicitly defer or use host scheduling/revocation with documented delay; avoid implying native expiry. |
| S115 | Authorize multiple person classes simultaneously | Open | One configured person class is described. | Declare support boundary; do not assume polymorphic User/Bot/ServiceAccount support. |
| S116 | Use API token narrower than its owner’s roles | Host | Token scopes must further constrain person capabilities. | Host combines token and role checks; gem must not imply token restrictions are automatic. |

## Priorities for the author

**Before implementing the public contract:** finish the ordinary-role walkthrough; resolve missing tenant and unknown/unsynced key behavior; define freshness, duplicate assignment, and atomic replacement; specify Owner name protection and last-Owner enforcement paths.

**Before claiming drop-in readiness:** align README, define cleanup and supported schema/key types, check naming collisions, document catalog retirement, and correct rolling migration guidance. Exercise a generated host installation rather than relying only on isolated models.

**Keep host responsibilities visible:** membership eligibility, record scopes, delegated administration, business rules, and response caching remain application responsibilities. A complete integration example is more valuable than adding abstractions for every row above.

**Keep the gem small:** these scenarios are a test and documentation inventory, not a feature shopping list. A sub-1,000-line production budget should include generators/templates; tests can be longer. Use explicit non-support where it is honest and compatible with the intended v1.

## Suggested first integration exercise

1. Install using the current person/tenant DSL and sync billing keys.
2. Create Acme and Beta; give Maya an ordinary Acme billing role using the intended public operations.
3. Confirm Acme allow, Beta deny, and the chosen missing/unknown-input behavior.
4. Give a second Acme role the same permission; revoke the first and confirm the union remains.
5. Edit the last grant through another instance/connection and check the documented freshness boundary.
6. Prove a failed permission-set edit leaves the prior set intact; retry assignment without duplicates.
7. Protect invoice detail and collection with host membership and tenant scoping.
8. Exercise each configured Owner mode, concurrent last-owner revocation, and allowed cleanup paths.
9. Repeat relevant checks in single-tenant mode and verify recovery.

Record expected results before coding; then attach test names and observed results to the relevant scenario IDs. No execution results are claimed by this file.

