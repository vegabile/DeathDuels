# Weapon Animation Patterns

Weapon Tool names are the item identity. Animation profile keys use the same name normalized to lowercase alphanumeric text:

- `Small Pistol`, `small pistol`, and `SmallPistol` resolve to `smallpistol`
- `revolver scoped` resolves to `revolverscoped`
- `gun gun` resolves to `gungun`

## Current Gun Keys

Gun profiles live in `src/Shared/Gun/Configs.lua`.

- `smallpistol`
- `sniper`
- `scarl`
- `colt`
- `small`
- `revolverscoped`
- `ak12`
- `ar15`
- `shotgun`
- `gungun`
- `smally`

Each gun profile can define:

- `Idle`
- `ShootLeadIn`
- `Shoot`
- `Reload`

`Shoot` keeps the existing gameplay behavior. `Reload` is visual only, uses the gun shoot cooldown, and does not count as using a gun for quest tracking.

## Current Knife Keys

Knife profiles live in `src/Shared/Knife/Configs.lua`.

- `knife`
- `knife1`

Each knife profile can define:

- `Throw`
- `AirSpin`
- `Stab`
- `Idle`

`AirSpin` is stored for future throw visuals and is not played yet.

## Adding Animations

Add the profile under the normalized item key in the weapon config. The Tool can keep a display-friendly name as long as the normalized key matches.

Use search by item and function:

```sh
rg "shotgun"
rg "Reload"
rg "knife1"
```

Do not create item-specific action modules just to change visuals. Add behavior code only when the item actually needs different gameplay.
