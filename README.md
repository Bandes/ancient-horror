# Elder Cave

A top-down survival horror game built with [DragonRuby GTK](https://dragonruby.org). Originally a submission for the Ancient and Nameless KIFASS game jam.

**Version:** 0.3.3

## Premise

You are an acolyte performing a forbidden ritual deep underground. Collect idols scattered through a procedurally generated cave, place them at the altar, and hold the ritual long enough to summon the Great Ones — while surviving the things that hunt you.

## Gameplay

- Explore a cave to collect **idols** (start with 2, 6 total hidden in the map)
- Bring idols to the **altar** and hold position to fill the ritual meter
- Win by completing the ritual with 3+ large shoggoths at the altar
- Lose if your **HP reaches 0** or your **sanity hits 0**

### Threats

- **Shoggoths** — flocking creatures that swarm and merge into larger forms; spawn every 6 seconds, escalating over time
- **Inquisitors** — fast hunters that chase you directly; up to 3 active, more unlock as time passes
- **Watchers** — slow hunters that drain your sanity (unlocked by modifier)

### Player Abilities

| Action | Keyboard | Mobile |
|--------|----------|--------|
| Move | WASD / Arrow keys | On-screen joystick |
| Pick up / Place idol | Space | Interact button |
| Repel shoggoths | E | Repel button |
| Pause | Escape | Pause button |

**Repel** pushes nearby shoggoths away — 2.5 second cooldown.

**Sanity** drains near shoggoths and in darkness; recovers in lit areas. Low sanity causes visual distortion effects.

## Modifiers

Each run offers 3 random modifiers that shake up the rules:

| Modifier | Effect |
|----------|--------|
| Swift Acolyte | +30% move speed |
| Fervor | Repel cooldown halved |
| Fragile Psyche | +50 max sanity, drains 2× |
| Ironflesh | +2 max HP, −20% speed |
| Hunted | Hunter cap +2 |
| Dim Altar | Need 4 great ones at altar to win |
| Thin Veil | Ritual fills 50% faster |
| Eager Shoggoths | Boids 25% faster |
| Keeper of Torches | Sanity recovers 3×, −1 max HP |
| Dread Pace | Shoggoths spawn twice as fast |
| Watcher Kin | Some hunters become Watchers |
| Miasma | Sanity drains constantly — nowhere is safe |
| Fecund Depths | Shoggoths merge at half the normal threshold |
| Cursed Relics | Each held idol slowly drains sanity |
| Scattered Minds | Start empty-handed — all idols hidden in the cave |

## Escalation

Every 60 seconds the shoggoth spawn rate increases and one more hunter slot opens, up to 6 hunters and a spawn interval of 2 seconds.

## Built With

- [DragonRuby GTK](https://dragonruby.org) — Ruby game engine
- Flow-field pathfinding for hunters
- Flocking simulation (boids) for shoggoths
