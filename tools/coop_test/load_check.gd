extends Node
## Loads every script the co-op work touches and says which ones don't compile. Touches no save.
## Run: godot --headless --path . res://tools/coop_test/load_check.tscn

const SCRIPTS: Array[String] = [
	"res://autoload/coop.gd",
	"res://autoload/sound_manager.gd",
	"res://autoload/npc_nameplates.gd",
	"res://dungeon_generation/population/dungeon_populator.gd",
	"res://scenes/loot/loot_pickup.gd",
	"res://scenes/loot/pickup_controller.gd",
	"res://systems/props/loot_prop.gd",
	"res://systems/props/loot_chest.gd",
	"res://systems/skills/core/skill_behavior.gd",
	"res://systems/skills/supports/explode_on_kill_support.gd",
	"res://systems/skills/supports/tremor_chain_support.gd",
	"res://systems/enemies/enemy_spawner.gd",
	"res://systems/world/ward_beacon.gd",
	"res://scenes/map/town/dock_defense.gd",
	"res://scenes/map/town/convoy/hull_breach.gd",
	"res://scenes/map/town/convoy/deck_system.gd",
	"res://scenes/map/town/convoy/guns_breach.gd",
	"res://scenes/map/town/yard_sweep.gd",
	"res://systems/waypoints/waypoints.gd",
	"res://scenes/map/town/town_area.gd",
	"res://scenes/map/map_management/portal.gd",
	"res://scenes/map/map_management/area_manager.gd",
	"res://scenes/ui/player_ui/mini_map/mini_map.gd",
	"res://scenes/player/player.gd",
	"res://tools/coop_test/coop_test.gd",
]


func _ready() -> void:
	var bad := 0
	for path in SCRIPTS:
		var s := load(path) as GDScript
		var ok := s != null and s.can_instantiate()
		if not ok:
			bad += 1
		print("[LOAD] %s %s" % ["ok  " if ok else "FAIL", path])
	print("[LOAD] %s" % ("ALL OK" if bad == 0 else "%d FAILED" % bad))
	get_tree().quit(1 if bad > 0 else 0)
