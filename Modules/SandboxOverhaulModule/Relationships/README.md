# Directed relationships

Per-character feelings stored in `SandboxState.directed_relationships[observerID][targetID]`.
`DirectedRelationships` is the only intended way to read or write them. Get it with `SandboxOverhaulModule.getRelationships()`
(call it each time, do not cache it across games).

| Axis | Key | Range | Meaning |
|---|---|---|---|
| affection | `a` | -100..100 | Negative: resentment or hatred. Positive: fondness and care. |
| trust | `t` | -100..100 | Negative: expects betrayal or harm. Positive: reliable and safe. |
| respect | `r` | -100..100 | Negative: contempt. Positive: admires ability, courage or principles. |
| fear | `f` | 0..100 | How able and willing they think the target is to cause harm. |
| desire | `d` | -100..100 | Negative: sexual aversion. Positive: sexual attraction. |

Defaults are 0. The axes are independent, and A to B is stored separately from B to A.
Pairs whose recognised axes are all at default are not stored. Unknown per-pair keys are preserved.
Characters that no longer exist (`GM.main.getCharacter(id)` is null; `"pc"` is always kept) are pruned just before saving.

No gameplay event reads or writes these values yet. BDCC's own `RelationshipSystem` (shared affection and lust) is untouched and unrelated.
