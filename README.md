[Release](https://github.com/robynclemente0428-debug/Codebreak_Requiem_Project/releases/tag/Final)

# CodeBreak: Requiem

> A top-down action RPG where you don't just equip your skills, you **program** them.

CodeBreak: Requiem is a 3D action RPG built in **Godot 4.7 (GDScript)**. Players write small scripts made of `WHEN` / `DO` rules that change how each skill behaves in a fight. The campaign teaches real programming ideas one act at a time (conditions, loops, sets, functions, sorting), and every boss is a puzzle that a good script can solve.

*Capstone project.*

<!-- Add a screenshot or GIF here, e.g. ![Gameplay](docs/screenshot.png) -->
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/2862a8c9-36d4-40cf-a456-aaef9363a6d3" />


---

## At a glance

| | |
|---|---|
| **Campaign** | 5 acts, levels 1 to 50, three endings |
| **Classes** | 6, each bending the scripting rules |
| **Skills** | 4 skill gems, 16 support gems |
| **Players** | 1 to 4 (solo or LAN co-op) |
| **Content** | 37 quest definitions, 33 enemy definitions, 20+ enemy traits and boss locks |
| **Codebase** | ~430 GDScript files |

---

## The core idea

Each skill (Strike, Shoot, Slam or Blast) can carry a short program: a list of rules. A rule says *when* something is true, *do* something to the skill: hit harder, reach further, repeat the cast, mark an enemy. Scripts are built by drag and drop, so nobody has to type code, but they read exactly like code:

```
always:
  + damage += 20%             # costs 8.0 points
  - attack_speed -= 20%       # pays back 10.0 points

when enemies_nearby(3, 4.0m): # buffs here cost x0.60
  + range_bonus += 1.00m

when every_nth_cast(3):
  + for i in range(2):        # repeat the skill twice
      cast()
      if hit_nothing:
        break
```

Three things stop it from becoming "add every buff":

1. **A point budget.** Every buff costs points and every drawback pays some back. Each extra step on the same stat costs more than the last.
2. **Harder conditions are cheaper.** A buff that only fires when 3 enemies are close costs less than one that is always on.
3. **Short scripts are rewarded.** A script under a block limit earns an efficiency tier (Lean or Elegant) with a free bonus.

Bosses have **locks**: rules that block most damage until the player's script answers them. Scripting is how fights are won.

---

## Story

AXIOM is a vast computational world built by the vanished Architects, where every physical law is an executable rule. It is rotting, and a force called the **Null** is consuming its processes. You play an **Executor**, one of the few beings who can rewrite their own code, and follow the people of Hardfault from evacuation to the Core.

| Act | Levels | Title | Programming idea taught |
|---|---|---|---|
| I | 1–10 | The Spawn Point | Conditions: `when enemies_nearby()` |
| II | 11–20 | The Migration Loop | Loops with exit conditions, nested `if`, `break` |
| III | 21–30 | Root Access | A data structure: the Registry (a set of enemies) |
| IV | 31–40 | Into the Null | Functions: shared routines, `call name()` |
| V | 41–50 | Final Execution | Sorting and indexing: `registry.sort(key=hp)`, `registry[0]` |

After the final boss, the Last Log offers three endings: **Merge**, **Overwrite** or **Terminate**. Your answers to the Null's "pull requests" across Act V shape the epilogue.

---

## Features

- **Skill scripting.** A tiny rule language with a code-editor-style UI (explorer, snippets, output and errors panels), a compiler-like validator, and a point budget.
- **Six classes.** Raider, Enchanter, Gladiator, Assassin, Paladin and Rogue. Each has one class trait that changes the economics of scripting.
- **Boss locks as puzzles.** Echo, Grammar, Fragmented, Recall and more, each testing the programming idea of its act.
- **Procedural dungeons.** Designer-placed markers plus generated rooms, connected with Prim's minimum spanning tree and validated for reachability.
- **Loot and affixes.** Weighted random affixes with level and tag filtering.
- **Quests, ranks and exams.** A single event bus feeds every quest. Ranks are earned by passing scripting exams in Examiner Sudo's sandbox.
- **Safe saving.** Atomic JSON saves with versioned migration.
- **LAN co-op (up to 4 players).** Host-authoritative networking with UDP lobby discovery.

---

## Getting started

### Requirements

- [Godot 4.7](https://godotengine.org/download)

### Run the game

1. Clone the repository.
2. Open `project.godot` in the Godot editor.
3. Press **Run** (F5). The main scene is `scenes/ui/main_menu.tscn`.

### Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| Mouse | Aim |
| Skill keys / mouse buttons | Cast the bound skill |

### LAN co-op

Choose **Lobby** from the main menu. One player hosts; others on the same network see the game in the lobby. Connections use Godot's ENet peer on **UDP port 24547**, so allow it through your firewall. Co-op lives on the `feature/lan-coop` branch.

---

## Project structure

```
autoload/              Global singletons (GameEvents, SaveManager, Coop, ItemGenerator, ...)
systems/               Game rules, mostly reusable components
  skills/ stats/ combat/ enemies/ equipment/ economy/
  quest/ exam/ dialogue/ world/ waypoints/
dungeon_generation/    Procedural level building
  layout/ generators/ validation/ rendering/ population/
scenes/                Things placed in the world, and the UI
  player/ enemy/ map/ loot/ ui/
data/                  Content as Godot Resources (.tres)
  classes/ skill_gems/ support_gems/ skill_programs/ affixes/
  items/ enemies/ quests/ exams/ dialogue/ shops/
tools/                 Test scenes and editors
story_plan/            Design documents (source of truth for story and acts)
core_features/         Key code excerpts
```

Two rules shape the codebase:

- **Content is data, behaviour is code.** A new enemy, item, quest or exam is a `.tres` resource edited in the inspector. Scripts in `systems/` never hard-code a specific boss or sword.
- **Characters are components.** The player and every enemy are a body with child nodes (`StatComponent`, `HealthComponent`, `SkillComponent`, ...) that talk through signals.

---

## Documentation

| Document | What it covers |
|---|---|
| **Overview** (`CodeBreak_Requiem_Overview.html`) | What each system does and why: scripting, combat, enemies, items, dungeons, quests, endings, networking, design patterns, status |
| **Code Guide** (`CodeBreak_Requiem_Code_Guide.html`) | Godot basics, startup path, line-by-line walkthroughs, and recipes for adding conditions, support gems, enemies, locks and quests |

---

## Extending the game

The Code Guide has full recipes. In short:

- **New script condition:** add a class extending `ProgramCondition` in `systems/skills/program/conditions/`, then register it in `ProgramConditions.TYPES`.
- **New support gem:** create a `SupportGemDefinition` in `data/support_gems/`. For new behaviour, also write a script extending `SupportBehavior`.
- **New enemy:** create an `EnemyDefinition` in `data/enemies/`.
- **New boss lock:** write an `EnemyTrait` with a `LOCK_NAME` constant.
- **New quest:** create a `QuestDefinition` in `data/quests/` using events the game already reports.

---

## Testing

Test scenes run on their own: open the `.tscn` and press **Run Current Scene** (F6).

| Tool | Purpose |
|---|---|
| `scripts/new_test/skill_program_test` | Runs skill programs against test actors |
| `tools/act2` … `tools/act5` | Per-act boss, exam and balance checks (Act V has 138 automated checks) |
| `tools/coop_test` | Co-op scenarios and a hand playtest checklist |
| `tools/save_editor` | Inspect and edit save slots |
| `tools/nav_check`, `breach_test`, `glyph_preview` | Navigation, set-piece and UI checks |

---

## Design patterns

Component, data-driven design, strategy, hook chain (decorator-like), observer / event bus, interpreter with validation, dirty-flag cache, host-authoritative networking, plus classic algorithms (Prim's MST, weighted random selection, geometric-series pricing).

---

## Status

| Part | State |
|---|---|
| Acts I–III | Built: towns, dungeons, bosses with locks, exams, side quests |
| Acts IV–V | Playable now. Act V has an automated test scene and has been tested by hand |
| Endings | All three built with epilogues; **credits still missing** |
| LAN co-op | Lobby, shared travel, host-run enemies, boss locks, shared events and trading (`feature/lan-coop`) |
| Theorist rank | After the campaign; final and endgame content |
| Art gaps | Act V's own regular enemies and the two final bosses' models (currently reused) |

---

## Author

**Robyn Paul M. Clemente**, BSIT-A707, STI

**Angela Nicole B. Aporongao**, BSIT-A707, STI

**Earl Justine B. Español**, BSIT-A707, STI

**Dan Julian M. Masong**, BSIT-A707, STI

## Adviser

**Sherwin M. Ostria**

## SY 2026-2027

## Credits

### Third-party assets
 
| Asset | Creator | Source | License |
|---|---|---|---|
| Sci-Fi Essentials Kit | Quaternius | https://quaternius.itch.io/sci-fi-essentials-kit | CC0 |
| Futura Weapon Pack | moisturizedfish | https://moisturizedfish.itch.io/futura-weapon-pack | Free to use, including commercially (per the creator) |
| 3D Monster 05 | Pixelius Vita | https://pixelius-vita.itch.io/3d-monster-05 | See source page |
| KayKit: Fantasy Weapons Bits (free version) | Kay Lousberg (KayKit) | https://kaylousberg.itch.io/fantasy-weapons-bits | CC0 |
| Dire Wolf Lite | Literock Studios | https://literock-studios.itch.io/direwolf-lite | Free for personal and commercial use; credit appreciated; no re-upload or resale |
| Low Poly Sci-Fi Melee Asset Pack | thytardigrade | https://thytardigrade.itch.io/low-poly-sci-fi-melee-asset-pack | No license stated on the source page |
| Retro Screen FX Free (sampler) | heyheythere | https://heyheythere.itch.io/retro-screen-fx-free | See source page <!-- confirm license on the free page --> |
