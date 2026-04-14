# Knife Model Requirements

What a knife template in `ReplicatedStorage.KnifeModels` must look like to work correctly in-game.

## Location

- Every knife template lives under `ReplicatedStorage.KnifeModels`.
- Each template is a `Tool` whose name is used as its `knifeName` for loadout selection.
- `KnifeModels` must contain at least one `Tool`; anything that isn't a `Tool` causes `WeaponDistributor` to refuse to boot.

## Tool

| Property | Required value | Why |
| --- | --- | --- |
| `ClassName` | `Tool` | `WeaponModelValidator.validateKnife` rejects anything else |
| `Name` | unique within `KnifeModels` | used as the `knifeName` key in loadouts |
| `RequiresHandle` | `true` (default) | the auto-grip Motor6D depends on a child named `Handle` |

The `IsKnife` attribute is **not** set on the template — it's applied to each clone at distribution time. Leaving it unset on templates is how `WeaponDistributor` distinguishes "source model" from "in-player copy."

## Handle

A direct child of the `Tool`, named exactly `Handle`.

| Property | Required value | Why |
| --- | --- | --- |
| `ClassName` | `BasePart` (any subclass: `Part`, `MeshPart`, `UnionOperation`) | `validateKnife` requires a `BasePart` Handle |
| `Name` | `Handle` | Roblox's auto-grip only looks at a child named `Handle` |
| `Transparency` | `0` | anything >0 makes the knife invisible to everyone |
| `LocalTransparencyModifier` | `0` | per-client visibility multiplier; leave at default |

The following properties are **normalized at server boot** by `WeaponDistributor.normalizeKnifeHandle` — so the template can be in any reasonable state, but the runtime values will always be:

| Property | Runtime value | Reason |
| --- | --- | --- |
| `Massless` | `true` | prevents the Handle's mass from affecting the wielder's physics |
| `CanCollide` | `false` | prevents the Handle from colliding with the wielder or world |
| `Anchored` | `false` | the auto-grip Motor6D must be able to move it |
| `RenderFidelity` (MeshPart only) | `Precise` | **required** when `Workspace.StreamingEnabled = true` — `Automatic` causes the MeshPart to fail to render on third-party clients even though the wielder sees it and damage still lands |

## Extra children

The template should contain **only** the `Handle`. `WeaponDistributor.ensureKnifeHitbox` will add its own `Hitbox` part at boot:

- A `Part` named `Hitbox`, sized to the tool's bounding box at template time.
- Transparent, non-colliding, massless, no shadow.
- Welded to the `Handle` via a `WeldConstraint` so it rides the hand grip.
- This is what server-side stab detection uses — **do not** add your own `Hitbox`, the init step detects and skips if one already exists.

If a template ships with a pre-built `Hitbox`, the auto-generation is skipped; the manually-placed one is trusted as-is.

## Things that will break the knife

- Handle is not a `BasePart` (e.g. a `Model` or `Folder`).
- Handle is named anything other than `Handle`.
- Handle has extra unwelded child parts — only the `Handle` itself is gripped by the hand; unwelded siblings stay at the template's world position.
- `MeshPart` Handle with `RenderFidelity = Automatic` under `StreamingEnabled` — this is the bug that prompted `normalizeKnifeHandle` to exist. Kills still land because the server hitbox is a regular `Part`, but observers never see the knife.
- Private or unmoderated `MeshId` / `TextureID` assets owned by an account that doesn't have publish rights to the game.
- Handle `Anchored = true` persisted at runtime — the grip Motor6D cannot move an anchored part.

## Related code

- `src/Server/WeaponDistributor/init.lua` — `normalizeKnifeHandle`, `ensureKnifeHitbox`, template registration.
- `src/Shared/WeaponModelValidator.lua` — `validateKnife` boot-time checks.
- `src/Shared/Knife/KnifeUtility.lua` — `findKnifeTool` (by `IsKnife` attribute on live clones).
- `src/Server/KnifeService/Actions/StabAction.lua` — uses `tool:FindFirstChild("Hitbox")` for damage overlap.
