# Character Format

This document details the per-character bundle format for the Shadow Fighter (LOTA) project.

## Directory Structure

Every character owns a self-contained bundle under `/characters/<character_name>/`. Cross-character and systemic logic lives in `/scripts/`.

Example layout for a character named `jerb`:
```text
/characters/jerb/
  jerb_data.tres          # CharacterData resource: stats and move references
  moves/                  # MoveData resources
    jab.tres
    heavy.tres
    fireball.tres
```

## CharacterData Resource

The `CharacterData` resource (`res://scripts/character/character_data.gd`) acts as the root of the character's definition. It contains:
- **Core stats:** `character_name`, `max_health`, `walk_speed`, `jump_velocity`
- **Move references:** Links to specific `MoveData` resources (`move_fast`, `move_heavy`, `move_skill`, `move_ultimate`) that are triggered from the FSM attack states.

## MoveData References

Moves are defined as `.tres` files (instances of the `MoveData` class) located in the character's `moves/` subdirectory. They act as the authoritative frame data source (startup, active, recovery frames, damage, hitstun, etc.).

By linking these `.tres` files directly in the `CharacterData` inspector, we decouple the FSM structure from the individual character's move specifications.
