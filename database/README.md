# Database schema

[schema.sql](schema.sql) is a relational model of the game's data (SQLite 3, ~70 tables). It mirrors what the game already stores, so each table maps back to a script:

| Part | Today lives in | Tables |
|---|---|---|
| Lookups | GDScript enums (`StatTypes.Stat`, `TagTypes`, `EquipmentSlots.Slot`, `Ranks.LADDER`) | `stat`, `mod_op`, `tag`, `equipment_slot`, `rarity`, `rank` |
| Game content | `res://data/**/*.tres` | classes, items, affixes, gems, stims, enemies, waypoints, quests, exams, shops, dialogue |
| Player data | `user://saves/slot_N.json` (`SaveManager`, `player.write_save()`) | `player_character` and everything keyed by `character_id` |

Skill-script programs (`SkillProgram.to_dict()`, routine bodies) are kept as JSON columns. They are nested trees (rules, then conditions, effects, loops and branches) that the game always loads and saves whole, so splitting them into rows would add a dozen tables without making any query easier.

## Full ERD

- [erd.png](erd.png) is the whole diagram as one image (all tables, crow's-foot lines).
- [erd.html](erd.html) is the same diagram, interactive: open it in a browser, drag to pan, scroll to zoom, and click a table to highlight its links.
- The sheet is split into 13 area panels. Inside a panel, parent tables are on the left and the tables that reference them on the right. A table that belongs to another area shows up as a dashed stub (just its key), and references to the lookup tables are written as `→ stat`, `→ tag` and so on instead of lines.
- After changing `schema.sql`, rebuild `erd.html` with `python database/build_erd.py` (which tables go in which area is set at the top of that script).

## Content ERD

```mermaid
erDiagram
    character_class }o--|| class_trait : has
    character_class }o--o| item : "starting weapon / gem"
    item }o--o| weapon_type : "weapon"
    item }o--o| equipment_type : "equipment"
    item }o--o| skill_gem : "skill gem"
    item }o--o| support_gem : "support gem"
    item }o--o| stim : "stim"
    equipment_type }o--|| equipment_slot : "goes in"
    item ||--o{ item_base_stat : ""
    affix ||--o{ affix_tag : "rolls on"
    item ||--o{ item_allowed_affix_tag : ""
    skill_gem ||--o{ skill_gem_modifier : ""
    skill_gem ||--o{ skill_gem_required_weapon : ""
    support_gem ||--o{ support_gem_modifier : ""
    enemy ||--o{ enemy_skill : casts
    enemy_skill }o--|| skill_gem : ""
    enemy_skill ||--o{ enemy_skill_support : ""
    enemy_modifier ||--o{ enemy_modifier_stat : ""
    enemy ||--o{ enemy_allowed_modifier_tag : ""
    act ||--o{ waypoint : contains
    waypoint ||--o{ waypoint_link : "links to"
    waypoint ||--o{ waypoint_required_quest : "unlocked by"
    quest ||--o{ quest_objective : has
    quest ||--o{ quest_prerequisite : requires
    quest ||--o{ quest_reward_item : rewards
    quest }o--o| quest : "next quest"
    quest }o--o| rank : grants
    rank ||--o| exam : "tested by"
    exam ||--o{ exam_wave : has
    exam_wave }o--|| enemy : spawns
    shop ||--o{ shop_item : stocks
    shop_item }o--|| item : ""
```

## Player ERD

```mermaid
erDiagram
    player_character }o--|| character_class : plays
    player_character }o--o| waypoint : "last town"
    player_character ||--o{ item_instance : owns
    item_instance }o--|| item : "copy of"
    item_instance ||--o{ item_instance_affix : rolled
    item_instance_affix }o--|| affix : ""
    player_character ||--o{ inventory_entry : backpack
    player_character ||--o{ equipped_item : wears
    inventory_entry |o--|| item_instance : ""
    equipped_item |o--|| item_instance : ""
    player_character ||--o{ skill_socket : has
    skill_socket |o--o| item_instance : "skill gem"
    skill_socket ||--o{ skill_socket_support : ""
    skill_socket ||--o{ skill_program : "one per script set"
    player_character ||--o{ script_set_name : ""
    player_character ||--o{ script_library_entry : ""
    player_character ||--o{ script_routine : ""
    player_character ||--o{ character_quest : ""
    character_quest ||--o{ character_objective_progress : ""
    character_quest }o--|| quest : ""
    player_character ||--o{ exam_grade : ""
    player_character ||--o{ recovered_item : ""
    player_character ||--o{ deed : ""
    player_character ||--o{ pending_support_choice : ""
```

## Design notes

- **One item table, one instance table.** `item` is the `ItemDefinition`; `item_kind` plus a CHECK makes sure exactly the matching type column (weapon type, equipment type, gem, stim) is filled. `item_instance` is the `ItemInstance` a character actually holds, with its rarity, level and rolled affixes.
- **Where an instance sits** is a separate row in `inventory_entry`, `equipped_item`, `skill_socket` or `skill_socket_support`. Each of those has a UNIQUE `instance_id`, so the same copy can't be equipped and in the backpack at once. (Moving an item is a delete-and-insert between those tables.)
- **Socketed gems are instances.** The JSON save currently keeps only the gem's definition id for sockets; the schema stores the instance so gems could carry their own level or quality later.
- **Enemy traits** (`data/enemy_traits/*.tres`) are `EnemyModifierDefinition` resources with an on-spawn script, so they share `enemy_modifier` with `is_trait = 1`.
- **Rank** is derived, not stored: `v_character_rank` picks the highest rank whose quest the character has completed (fill `quest.grants_rank_id` from `Ranks.LADDER`).
- **Tags** from four GDScript enums share one `tag` table, split by `tag_family`.

## SQL Server

[schema_sqlserver.sql](schema_sqlserver.sql) is the same schema in T-SQL, generated from `schema.sql` by [export_sqlserver.py](export_sqlserver.py). It creates (or refreshes) a `CodeBreakRequiem` database:

```bash
python database/export_sqlserver.py
sqlcmd -S localhost -E -b -i database/schema_sqlserver.sql
```

Rerunning the load drops and recreates the tables, so any rows typed into them are lost. Differences from the SQLite version: text columns are `NVARCHAR(100)` (or `NVARCHAR(MAX)` for long text and JSON), and five cascading deletes are plain references, because SQL Server allows only one delete path to a table. The generated file lists those five at the top.

To view it in SQL Server Management Studio, connect to `localhost` with Windows Authentication and open Databases > CodeBreakRequiem > Tables. To get SSMS's own diagram, right-click **Database Diagrams** > New Database Diagram and add the tables you want.

## Trying it

```bash
python -c "import sqlite3; c=sqlite3.connect('database/game.db'); c.executescript(open('database/schema.sql').read())"
```

The `stat` and `tag` lookup tables are created empty; fill them from `systems/stats/stat_type.gd` and `systems/Tags/tag_types.gd` (enum order = `enum_value`).
