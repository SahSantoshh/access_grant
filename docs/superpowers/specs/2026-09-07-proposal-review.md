# AccessGrant — Proposal Review

> Adopted into this repo from an external design review (2026-09-07).
> Author responses / resolutions live in
> [architecture.md](../../architecture.md) under **Resolved public-contract
> decisions**. Scenario IDs: [2026-09-07-usage-scenarios.md](2026-09-07-usage-scenarios.md).

The core design makes sense: a code-defined catalog, database-backed roles and permission mappings, additive permissions, and explicit tenant context. The separation between capability checks and host-owned record/ownership rules is also well explained.

I’d keep that shape. My main focus before implementation would be making the public API complete and predictable. This is already a good entry point:

```ruby
maya.permitted?(:manage_billing, tenant: acme)
```

A few targeted things would help:

## 1. Show the ordinary role-management flow end to end

Owner has a clear assignment API, but the everyday workflow is less concrete. Could we show creating a Billing role, selecting permissions, assigning it to Maya, checking access, editing its permissions, and removing the assignment?

Use the actual intended model associations and methods—no additional wrappers needed where ActiveRecord is already clear. Include how an admin form reads the available catalog and selected permissions.

That example would let us judge the API as a whole: can someone understand and use this without reading the implementation?

## 2. Resolve two edge cases in `permitted?`

```ruby
maya.permitted?(:manage_billing)               # Multi-tenant install
maya.permitted?(:misspelled_key, tenant: acme)
```

The tenant argument is described as optional, but the text also says it must be passed. I’d recommend raising clearly when it is missing in multi-tenant mode.

For unknown keys, the normal database query appears to return false, while Owner bypass appears to return true. Please make the intended behavior explicit. I lean toward surfacing an unknown-key error consistently, since otherwise typos can be hidden while developing as Owner.

## 3. Define when permission edits take effect

The proposal specifies per-instance memoization. What happens here?

```ruby
maya.permitted?(:manage_billing, tenant: acme) # => true

# An admin removes that grant through a separately loaded role instance.
# The change commits.

maya.permitted?(:manage_billing, tenant: acme) # => ?
```

Runtime editing is the central feature, so freshness should be part of the public contract. Specify the cache lifetime/invalidation behavior, or start without gem-level memoization.

For mutations, also document that repeated assignment does not create duplicates and replacing a permission set cannot leave a partially applied change if validation fails.

## 4. Tighten the enforcement boundary around Owner

The modes and their rationale are already documented. The remaining questions concern how their guarantees hold:

- Since bypass uses the configured Owner name, can creating or renaming an ordinary role accidentally make it privileged? Reserve/protect that identity explicitly.
- Last-Owner revocation is prohibited, but what happens with concurrent revocations, direct assignment deletion, or deletion of the person?

These don’t require more public configuration. They need a precise statement of which paths uphold the invariant and tests for those paths.

## 5. Confirm catalog retirement behavior

Sync deliberately retains permission rows, and checks query those rows. My reading is that removing a key from the code catalog does **not** revoke existing grants. Is that intended?

If so, document it directly, along with the supported way to retire a permission. That makes the existing non-destructive sync decision understandable operationally.

Two smaller integration points: update the README to the approved person-model DSL/setup, and consider namespaced tables and associations so installation does not collide with an existing `roles` structure.

The quality bar I’m aiming for is a small Rails gem whose normal usage is obvious and whose edge cases are unsurprising. I’d prioritize that complete example and these guarantees before expanding the API. A sub-1,000-line production implementation is a useful constraint—including generators and migration templates—but clarity and correctness should determine whether the shape is right.
