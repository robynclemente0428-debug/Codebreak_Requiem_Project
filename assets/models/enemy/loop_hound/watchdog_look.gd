extends Node
## The Watchdog's look (watchdog_model.tscn): the Loop Hound's mesh, restyled so it reads as a
## different machine, not a bigger hound. On every mesh of the model:
##   material_override  gunmetal: dark blued steel, very metallic, the hound's normal map kept
##                      for its shape, and a faint cyan glow from inside the plates (no fire)
##   material_overlay   watchdog_scan_overlay.gdshader: a cyan rim, a scan band sweeping up the
##                      body, register lines; WatchdogLock drives its `beat` and `alarm`
## The overlay is set before the enemy is built, so EnemySilhouette chains its silhouette after
## it (it keeps a model's own overlay). It's this Watchdog's own copy, kept on the model's meta
## "watchdog_overlay" for WatchdogLock.

const OVERLAY_SHADER := preload("res://assets/shaders/materials/shader/watchdog_scan_overlay.gdshader")
const NORMAL_MAP := preload("res://assets/models/enemy/loop_hound/Dire_Wolf_Lite_DireWolf_Normal.png")
const OVERLAY_META := &"watchdog_overlay"


func _ready() -> void:
	var model := get_parent()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.11, 0.13, 0.17)
	body.metallic = 0.9
	body.metallic_specular = 0.7
	body.roughness = 0.28
	body.normal_enabled = true
	body.normal_texture = NORMAL_MAP
	body.normal_scale = 1.2
	body.emission_enabled = true
	body.emission = Color(0.25, 0.75, 1.0)
	body.emission_energy_multiplier = 0.18
	body.rim_enabled = true
	body.rim = 0.4
	body.rim_tint = 0.6
	var overlay := ShaderMaterial.new()
	overlay.shader = OVERLAY_SHADER
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		if g is GPUParticles3D or g is CPUParticles3D:
			continue
		(g as GeometryInstance3D).material_override = body
		(g as GeometryInstance3D).material_overlay = overlay
	model.set_meta(OVERLAY_META, overlay)
