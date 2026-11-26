class_name EnemyBase
extends CharacterBody3D

@onready var model_mount: Node3D = $model
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var stats: StatComponent = $StatComponent
@onready var health: HealthComponent = $HealthComponent
@onready var ai: AIComponent = $AIComponent
@onready var nav: NavigationAgent3D = $NavigationAgent3D

var modifiers: Array = []
var traits: Array[EnemyTrait] = []

var rarity: String = "normal"
var level := 1
var is_remote := false

@export var hit_delay: float = 0.5

var model: EnemyModel

var display_name: String = ""
var current_health: float = 0.0

func _ready() -> void:
	add_to_group("enemies")

func setup() -> void:
	health.stats = stats              
	health.initialize()
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	stats.stats_changed.connect(health._on_stats_changed)
	
	ai.setup(self, stats, nav)
	ai.attack_requested.connect(_on_attack_requested)

func attach_model(model_scene: PackedScene) -> void:
	model = model_scene.instantiate() as EnemyModel
	model_mount.add_child(model)
	model.bind(ai, health, self)
	EnemySilhouette.cover(model)

func apply_size(radius: float, height: float) -> void:
	var shape := (collision.shape as CylinderShape3D).duplicate() as CylinderShape3D
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5

func _on_attack_requested(target: Node3D) -> void:
	if model == null:
		return
	var cooldown := 1.0 / maxf(stats.get_stat(StatTypes.Stat.ATTACK_SPEED), 0.1)
	var delay := model.play_attack(cooldown)
	SoundManager.play_skill("attack", self, delay)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(self) or health.current_health <= 0.0:
			return
		if not is_instance_valid(target):
			return
	if global_position.distance_to(target.global_position) > ai.attack_range * 1.5:
		return
	var dmg := randf_range(
		stats.get_stat(StatTypes.Stat.MIN_ATTACK_DAMAGE),
		stats.get_stat(StatTypes.Stat.MAX_ATTACK_DAMAGE))
	Coop.hit_source = Coop.Hit.ENEMY
	target.health.take_damage(dmg)
	Coop.hit_source = Coop.Hit.NONE

const CORPSE_MAX_TIME := 3.0


func _on_died() -> void:
	remove_from_group("enemies")
	ai.halt()
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", true)
	if model != null:
		EnemySilhouette.uncover(model)
	get_tree().create_timer(CORPSE_MAX_TIME, false).timeout.connect(queue_free)
	var shape := collision.shape as CylinderShape3D
	await GlitchDeath.play(self, model_mount, shape.radius if shape else 0.5, shape.height if shape else 1.8)
	queue_free()

func _on_health_changed(current: float, max: float) -> void:
	pass

func play_skill_animation(key: String, fit_duration: float) -> float:
	if model == null:
		return 0.0
	var hit_in := model.play_skill(key, fit_duration)
	if hit_in > 0.0:
		SoundManager.play_skill(key, self, hit_in)
	return hit_in
