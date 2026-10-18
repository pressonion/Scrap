extends Node2D

# ============================================================
# SCRAPJACK - GODOT 4
# Wave combat, robot parts, weapon pickups, sword and guns.
# ============================================================

const SCREEN_WIDTH := 960.0
const SCREEN_HEIGHT := 600.0
const FLOOR_Y := 510.0
const PLAYER_WIDTH := 30.0
const PLAYER_HEIGHT := 52.0
const GRAVITY := 1250.0

const FLOATING_SCALE := Vector2(3.5, 3.5)
const FLOATING_HEALTH := 44.0
const FLOATING_SPEED := 85.0
const FLOATING_ATTACK_COOLDOWN := 0.9
const FLOATING_BOB_HEIGHT := 3.0
const FLOATING_HITBOX_SHRINK := 0.62
const JUMP_BUFFER_DURATION := 0.15

const WEAPON_PICKUP_SIZE := Vector2(36.0, 36.0)
const HAND_GUN_SIZE := Vector2(72.0, 38.0)
const LONG_GUN_SIZE := Vector2(88.0, 38.0)
const HAND_SWORD_SIZE := Vector2(38.0, 38.0)

const SWORD_ATTACK_COOLDOWN := 0.38
const SWORD_SWING_DURATION := 0.20

# The sword PNG points diagonally toward the upper-right.
# Its handle is approximately near the bottom-left.
const SWORD_HANDLE_IN_IMAGE := Vector2(8.0, 30.0)
const SWORD_RAISED_ANGLE := 0.0
const SWORD_LOWERED_ANGLE := 1.15
const SWORD_KNOCKBACK := 360.0

# Murky Slaad: reduced health, slow movement, no health bar.
const MURKY_SLAAD_HEALTH := 720.0
const MURKY_SLAAD_SPEED := 18.0
# These are the actual on-screen dimensions used by both the sprite and hitbox.
const MURKY_SLAAD_WIDTH := 150.0
const MURKY_SLAAD_HEIGHT := 166.0
const MURKY_SLAAD_SPAWN_WAVE := 3

var rng := RandomNumberGenerator.new()

var background_texture: Texture2D
var sword_texture: Texture2D
var gun_textures: Dictionary = {}

var robot_sprite: AnimatedSprite2D
var floating_sprite: AnimatedSprite2D
var murky_slaad_sprite: AnimatedSprite2D

var current_robot_animation := ""
var visual_time := 0.0

var floating_alive := true
var floating_health := FLOATING_HEALTH
var floating_x := 760.0
var floating_float_time := 0.0
var floating_attack_timer := 0.5
var floating_facing := -1.0
var floating_spawned_left := false
var floating_flash_timer := 0.0

var player_pos := Vector2(130, FLOOR_Y - PLAYER_HEIGHT)
var player_velocity := Vector2.ZERO
var facing := 1.0
var grounded := true
var player_is_moving := false

var player_health := 100.0
var player_max_health := 100.0
var invincible_timer := 0.0
var attack_timer := 0.0
var shoot_timer := 0.0
var jump_buffer_timer := 0.0

var jump_requested := false
var pickup_requested := false
var restart_requested := false

var parts: Dictionary = {}

# Slot 1 is always the sword.
# Slot 2 is the currently collected gun.
var current_slot := 1
var weapon_name := "None"
var weapon_asset := ""
var weapon_damage := 22.0
var weapon_range := 76.0
var weapon_rate := 0.38

# Sword swing animation.
var sword_is_down := false
var sword_flash_timer := 0.0

var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var particles: Array[Dictionary] = []

var wave := 0
var enemies_to_spawn := 0
var spawn_timer := 0.0
var intermission := 1.5
var total_kills := 0
var scrap := 0

var game_over := false
var message := "SCRAPJACK"
var message_timer := 3.0


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	rng.randomize()

	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	get_window().title = "SCRAPJACK"

	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	background_texture = load("res://pixelart.png") as Texture2D
	sword_texture = load("res://Icon28_02.png") as Texture2D

	gun_textures = {
		"Revolver": load("res://Revolver.png") as Texture2D,
		"Bolt Rifle": load("res://Winchester.png") as Texture2D,
		"Scrap Shotgun": load("res://1878 Hartford.png") as Texture2D,
		"Plasma Blaster": load("res://Laser Rifle.png") as Texture2D,
		"MP-43": load("res://MP - 43.png") as Texture2D
	}

	if background_texture == null:
		push_warning("Could not load res://pixelart.png")

	if sword_texture == null:
		push_warning("Could not load res://Icon28_02.png")

	for gun_name in gun_textures:
		if gun_textures[gun_name] == null:
			push_warning("Could not load weapon image: " + str(gun_name))

	robot_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	floating_sprite = get_node_or_null("AnimatedSprite2D2") as AnimatedSprite2D
	murky_slaad_sprite = get_node_or_null("AnimatedSprite2D3") as AnimatedSprite2D

	if robot_sprite == null:
		push_error("AnimatedSprite2D must be a direct child of Game.")
	else:
		setup_robot_animation()

	if floating_sprite == null:
		push_error("AnimatedSprite2D2 must be a direct child of Game.")
	else:
		setup_floating_enemy()

	if murky_slaad_sprite == null:
		push_error("AnimatedSprite2D3 must be a direct child of Game.")
	else:
		setup_murky_slaad_animation()

	start_game()


# ============================================================
# PLAYER ANIMATION
# ============================================================

func setup_robot_animation() -> void:
	if robot_sprite.sprite_frames == null:
		push_error("Assign SpriteFrames to AnimatedSprite2D.")
		return

	var frames: SpriteFrames = robot_sprite.sprite_frames

	for animation_name in ["default", "run", "death"]:
		if not frames.has_animation(animation_name):
			push_error("Missing player animation: " + animation_name)

	if frames.has_animation("default"):
		frames.set_animation_loop("default", true)

	if frames.has_animation("run"):
		frames.set_animation_loop("run", true)

	if frames.has_animation("death"):
		frames.set_animation_loop("death", false)

	robot_sprite.speed_scale = 1.0
	robot_sprite.scale = Vector2(2.5, 2.5)
	robot_sprite.centered = true
	robot_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	robot_sprite.flip_h = false
	robot_sprite.visible = true

	current_robot_animation = ""
	play_robot_animation("default")


func play_robot_animation(animation_name: String) -> void:
	if robot_sprite == null or robot_sprite.sprite_frames == null:
		return

	if not robot_sprite.sprite_frames.has_animation(animation_name):
		return

	if current_robot_animation == animation_name:
		return

	current_robot_animation = animation_name
	robot_sprite.play(animation_name)


func sync_robot_sprite() -> void:
	if robot_sprite == null:
		return

	robot_sprite.position = player_pos + Vector2(
		PLAYER_WIDTH / 2.0,
		PLAYER_HEIGHT / 2.0
	)

	robot_sprite.flip_h = facing < 0.0

	if game_over:
		robot_sprite.visible = true
		return

	if invincible_timer > 0.0:
		robot_sprite.visible = int(Time.get_ticks_msec() / 80) % 2 != 0
	else:
		robot_sprite.visible = true

	if player_is_moving:
		play_robot_animation("run")
	else:
		play_robot_animation("default")


func play_death_animation() -> void:
	if robot_sprite == null or robot_sprite.sprite_frames == null:
		return

	robot_sprite.visible = true

	if robot_sprite.sprite_frames.has_animation("death"):
		robot_sprite.sprite_frames.set_animation_loop("death", false)
		current_robot_animation = "death"
		robot_sprite.play("death")


# ============================================================
# FLOATING EYE ENEMY
# ============================================================

func setup_floating_enemy() -> void:
	if floating_sprite.sprite_frames == null:
		push_error("Assign SpriteFrames to AnimatedSprite2D2.")
		return

	if not floating_sprite.sprite_frames.has_animation("default"):
		push_error("AnimatedSprite2D2 needs an animation named default.")
		return

	floating_sprite.sprite_frames.set_animation_loop("default", true)
	floating_sprite.animation = "default"
	floating_sprite.speed_scale = 1.0
	floating_sprite.centered = true
	floating_sprite.scale = FLOATING_SCALE
	floating_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floating_sprite.visible = true
	floating_sprite.z_index = 1
	floating_sprite.play("default")


func reset_floating_enemy() -> void:
	floating_alive = true
	floating_health = FLOATING_HEALTH
	floating_spawned_left = rng.randf() < 0.5
	floating_x = 150.0 if floating_spawned_left else SCREEN_WIDTH - 160.0
	floating_float_time = 0.0
	floating_attack_timer = 0.5
	floating_facing = 1.0 if floating_spawned_left else -1.0
	floating_flash_timer = 0.0

	if floating_sprite != null:
		floating_sprite.scale = FLOATING_SCALE
		floating_sprite.modulate = Color.WHITE
		floating_sprite.visible = true
		floating_sprite.play("default")


func get_floating_enemy_hitbox() -> Rect2:
	if floating_sprite == null or floating_sprite.sprite_frames == null:
		return Rect2()

	var frames: SpriteFrames = floating_sprite.sprite_frames

	if not frames.has_animation("default"):
		return Rect2()

	var frame_count := frames.get_frame_count("default")

	if frame_count <= 0:
		return Rect2()

	var frame_index := clampi(floating_sprite.frame, 0, frame_count - 1)
	var texture := frames.get_frame_texture("default", frame_index)

	if texture == null:
		return Rect2()

	var visible_size := texture.get_size() * Vector2(
		absf(floating_sprite.scale.x),
		absf(floating_sprite.scale.y)
	)

	visible_size *= FLOATING_HITBOX_SHRINK

	return Rect2(
		floating_sprite.position - visible_size / 2.0,
		visible_size
	)


func get_player_hitbox() -> Rect2:
	return Rect2(
		player_pos + Vector2(5.0, 4.0),
		Vector2(PLAYER_WIDTH - 10.0, PLAYER_HEIGHT - 6.0)
	)


func update_floating_enemy(delta: float) -> void:
	if not floating_alive or floating_sprite == null or game_over:
		return

	floating_float_time += delta
	floating_attack_timer = maxf(0.0, floating_attack_timer - delta)
	floating_flash_timer = maxf(0.0, floating_flash_timer - delta)

	if floating_flash_timer > 0.0:
		floating_sprite.modulate = Color(4.0, 4.0, 4.0, 1.0)
	else:
		floating_sprite.modulate = Color.WHITE

	var player_center := player_pos + Vector2(
		PLAYER_WIDTH / 2.0,
		PLAYER_HEIGHT / 2.0
	)

	var direction := signf(player_center.x - floating_x)

	if direction == 0.0:
		direction = floating_facing

	floating_facing = direction
	floating_x += direction * FLOATING_SPEED * delta
	floating_x = clampf(floating_x, 18.0, SCREEN_WIDTH - 18.0)

	var bob := sin(floating_float_time * 3.0) * FLOATING_BOB_HEIGHT

	floating_sprite.position = Vector2(
		floating_x,
		FLOOR_Y - 48.0 + bob
	)

	floating_sprite.flip_h = floating_spawned_left

	if get_floating_enemy_hitbox().intersects(get_player_hitbox()) \
	and grounded \
	and floating_attack_timer <= 0.0:

		floating_attack_timer = FLOATING_ATTACK_COOLDOWN

		if invincible_timer <= 0.0:
			var armor_power: int = parts["armor"]["power"]
			var damage := maxf(5.0, 14.0 - float(armor_power * 3))

			player_health -= damage
			invincible_timer = 0.65
			player_velocity.x = direction * 110.0

			spawn_particles(
				player_center,
				Color("#FF8ACB"),
				7
			)

			if player_health <= 0.0:
				player_health = 0.0
				trigger_game_over()


func damage_floating_enemy(damage: float, hit_position: Vector2) -> void:
	if not floating_alive:
		return

	floating_health -= damage
	floating_flash_timer = 0.12

	if floating_sprite != null:
		floating_sprite.modulate = Color(4.0, 4.0, 4.0, 1.0)

	spawn_particles(hit_position, Color("#FFB0E0"), 6)

	if floating_health <= 0.0:
		floating_health = 0.0
		floating_alive = false

		if floating_sprite != null:
			floating_sprite.visible = false

		spawn_particles(hit_position, Color("#E8A8D1"), 14)

		total_kills += 1
		scrap += rng.randi_range(2, 5)


# ============================================================
# MURKY SLAAD ANIMATION
# Uses the actual AnimatedSprite2D3 node and its SpriteFrames.
# Does not draw MurkySlaad.png as a static sprite sheet.
# ============================================================

func setup_murky_slaad_animation() -> void:
	if murky_slaad_sprite.sprite_frames == null:
		push_error(
			"Assign the Murky Slaad SpriteFrames to AnimatedSprite2D3."
		)
		murky_slaad_sprite.visible = false
		return

	if not murky_slaad_sprite.sprite_frames.has_animation("default"):
		push_error(
			"AnimatedSprite2D3 needs an animation named default."
		)
		murky_slaad_sprite.visible = false
		return

	murky_slaad_sprite.sprite_frames.set_animation_loop("default", true)
	murky_slaad_sprite.animation = "default"
	murky_slaad_sprite.speed_scale = 1.0
	murky_slaad_sprite.centered = true

	# Scale the actual AnimatedSprite2D frame to the target display size.
	# Changing only the enemy width/height constants would resize the hitbox,
	# but would not resize the visible sprite.
	var first_frame_texture: Texture2D = murky_slaad_sprite.sprite_frames.get_frame_texture("default", 0)
	if first_frame_texture != null:
		var frame_size := first_frame_texture.get_size()
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			murky_slaad_sprite.scale = Vector2(
				MURKY_SLAAD_WIDTH / frame_size.x,
				MURKY_SLAAD_HEIGHT / frame_size.y
			)
		else:
			murky_slaad_sprite.scale = Vector2(3.0, 3.0)
	else:
		murky_slaad_sprite.scale = Vector2(3.0, 3.0)

	murky_slaad_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	murky_slaad_sprite.modulate = Color.WHITE
	murky_slaad_sprite.z_index = 1
	murky_slaad_sprite.visible = false
	murky_slaad_sprite.play("default")


func sync_murky_slaad_sprite() -> void:
	if murky_slaad_sprite == null:
		return

	if game_over:
		murky_slaad_sprite.visible = false
		return

	# This scene has one AnimatedSprite2D3, so only one Murky Slaad
	# is allowed to be alive at a time.
	for enemy in enemies:
		if str(enemy["type"]) != "MurkySlaad":
			continue

		var pos: Vector2 = enemy["pos"]

		murky_slaad_sprite.position = pos + Vector2(
			MURKY_SLAAD_WIDTH / 2.0,
			MURKY_SLAAD_HEIGHT / 2.0
		)

		murky_slaad_sprite.flip_h = str(enemy.get("spawn_side", "right")) == "left"

		if float(enemy["flash_timer"]) > 0.0:
			murky_slaad_sprite.modulate = Color(
				4.0, 4.0, 4.0, 1.0
			)
		else:
			murky_slaad_sprite.modulate = Color.WHITE

		murky_slaad_sprite.visible = true

		if murky_slaad_sprite.animation != "default":
			murky_slaad_sprite.play("default")
		elif not murky_slaad_sprite.is_playing():
			murky_slaad_sprite.play("default")

		return

	murky_slaad_sprite.visible = false
	murky_slaad_sprite.modulate = Color.WHITE


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey

	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_SPACE \
	or key_event.keycode == KEY_W \
	or key_event.keycode == KEY_UP:
		jump_requested = true

	if key_event.keycode == KEY_E:
		pickup_requested = true

	if key_event.keycode == KEY_R:
		restart_requested = true

	if key_event.keycode == KEY_1:
		current_slot = 1
		message = "SWORD EQUIPPED"
		message_timer = 1.0

	if key_event.keycode == KEY_2:
		current_slot = 2

		if weapon_name == "None":
			message = "NO GUN - FIND A WEAPON"
		else:
			message = "GUN EQUIPPED: " + weapon_name

		message_timer = 1.4


# ============================================================
# START / RESTART
# ============================================================

func start_game() -> void:
	player_pos = Vector2(130, FLOOR_Y - PLAYER_HEIGHT)
	player_velocity = Vector2.ZERO
	player_health = 100.0
	player_max_health = 100.0
	facing = 1.0
	grounded = true
	player_is_moving = false
	invincible_timer = 0.0
	attack_timer = 0.0
	shoot_timer = 0.0
	jump_buffer_timer = 0.0

	sword_is_down = false
	sword_flash_timer = 0.0

	jump_requested = false
	pickup_requested = false
	restart_requested = false

	parts = {
		"head": {"name": "Scrap Head", "power": 0},
		"arm": {"name": "Basic Arm", "power": 0},
		"legs": {"name": "Standard Legs", "power": 0},
		"armor": {"name": "Tin Armor", "power": 0}
	}

	current_slot = 1
	weapon_name = "None"
	weapon_asset = ""
	weapon_damage = 22.0
	weapon_range = 76.0
	weapon_rate = 0.38

	enemies.clear()
	projectiles.clear()
	pickups.clear()
	particles.clear()

	reset_floating_enemy()

	if murky_slaad_sprite != null:
		murky_slaad_sprite.visible = false
		murky_slaad_sprite.modulate = Color.WHITE
		murky_slaad_sprite.play("default")

	wave = 0
	enemies_to_spawn = 0
	spawn_timer = 0.0
	intermission = 1.5
	total_kills = 0
	scrap = 0
	game_over = false
	message = "SCRAPJACK"
	message_timer = 3.0

	current_robot_animation = ""
	sync_robot_sprite()
	sync_murky_slaad_sprite()


func trigger_game_over() -> void:
	if game_over:
		return

	game_over = true
	message = "SCRAP DESTROYED"
	message_timer = 999.0
	player_is_moving = false
	sword_flash_timer = 0.0
	sword_is_down = false

	if floating_sprite != null:
		floating_sprite.visible = false

	if murky_slaad_sprite != null:
		murky_slaad_sprite.visible = false

	enemies.clear()
	projectiles.clear()
	pickups.clear()
	particles.clear()

	play_death_animation()


# ============================================================
# MAIN LOOP
# ============================================================

func _process(delta: float) -> void:
	visual_time += delta
	if game_over:
		if restart_requested:
			start_game()

		restart_requested = false
		sync_robot_sprite()
		sync_murky_slaad_sprite()
		queue_redraw()
		return

	attack_timer = maxf(0.0, attack_timer - delta)
	shoot_timer = maxf(0.0, shoot_timer - delta)
	invincible_timer = maxf(0.0, invincible_timer - delta)
	message_timer = maxf(0.0, message_timer - delta)

	# Animate the sword down and smoothly return it to its raised pose.
	if sword_flash_timer > 0.0:
		sword_flash_timer = maxf(
			0.0,
			sword_flash_timer - delta
		)

		if sword_flash_timer <= 0.0:
			sword_is_down = false

	update_player(delta)

	if game_over:
		queue_redraw()
		return

	update_enemies(delta)

	if game_over:
		queue_redraw()
		return

	update_floating_enemy(delta)
	update_projectiles(delta)
	update_pickups(delta)
	update_particles(delta)
	update_waves(delta)

	sync_robot_sprite()
	sync_murky_slaad_sprite()
	queue_redraw()


# ============================================================
# PLAYER MOVEMENT
# ============================================================

func update_player(delta: float) -> void:
	var move_direction := 0.0

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_direction -= 1.0

	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_direction += 1.0

	player_is_moving = not is_zero_approx(move_direction)

	var move_speed := 265.0
	var leg_name: String = parts["legs"]["name"]

	if leg_name == "Runner Legs":
		move_speed = 365.0
	elif leg_name == "Tank Legs":
		move_speed = 185.0

	player_velocity.x = move_direction * move_speed

	if move_direction != 0.0:
		facing = signf(move_direction)

	if jump_requested:
		jump_buffer_timer = JUMP_BUFFER_DURATION
	else:
		jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)

	jump_requested = false

	if jump_buffer_timer > 0.0 and grounded:
		player_velocity.y = -455.0
		grounded = false
		jump_buffer_timer = 0.0

	player_velocity.y += GRAVITY * delta
	player_pos += player_velocity * delta

	if player_pos.y + PLAYER_HEIGHT >= FLOOR_Y:
		player_pos.y = FLOOR_Y - PLAYER_HEIGHT
		player_velocity.y = 0.0
		grounded = true
	else:
		grounded = false

	player_pos.x = clampf(
		player_pos.x,
		12.0,
		SCREEN_WIDTH - PLAYER_WIDTH - 12.0
	)

	# Hold J to repeatedly attack or fire.
	if Input.is_key_pressed(KEY_J) and attack_timer <= 0.0:
		if current_slot == 1:
			melee_attack()
		elif weapon_name != "None":
			shoot_weapon()
		else:
			message = "NO GUN - FIND A WEAPON"
			message_timer = 0.8
			attack_timer = 0.25

	if pickup_requested:
		collect_nearest_pickup()

	pickup_requested = false


# ============================================================
# SWORD ATTACK AND KNOCKBACK
# ============================================================

func melee_attack() -> void:
	attack_timer = SWORD_ATTACK_COOLDOWN

	# Start a new slash. The swing animation returns automatically.
	sword_is_down = true
	sword_flash_timer = SWORD_SWING_DURATION

	var arm_power: int = parts["arm"]["power"]
	var damage := weapon_damage + float(arm_power * 5)

	var player_center := player_pos + Vector2(
		PLAYER_WIDTH / 2.0,
		26.0
	)

	var slash_rect: Rect2

	if facing > 0.0:
		slash_rect = Rect2(
			player_center.x - 5.0,
			player_center.y - 38.0,
			weapon_range + 5.0,
			76.0
		)
	else:
		slash_rect = Rect2(
			player_center.x - weapon_range,
			player_center.y - 38.0,
			weapon_range + 5.0,
			76.0
		)

	spawn_particles(
		player_center + Vector2(facing * 35.0, 0.0),
		Color("#FFD477"),
		5
	)

	if floating_alive:
		var floating_hitbox := get_floating_enemy_hitbox()

		if slash_rect.intersects(floating_hitbox):
			damage_floating_enemy(
				damage,
				floating_hitbox.get_center()
			)

	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		var enemy_width := 32.0
		var enemy_height := 48.0

		if enemy["type"] == "Heavy":
			enemy_width = 42.0
			enemy_height = 56.0
		elif enemy["type"] == "MurkySlaad":
			enemy_width = MURKY_SLAAD_WIDTH
			enemy_height = MURKY_SLAAD_HEIGHT

		var enemy_rect := Rect2(
			Vector2(enemy["pos"]),
			Vector2(enemy_width, enemy_height)
		)

		if slash_rect.intersects(enemy_rect):
			enemy["health"] = float(enemy["health"]) - damage

			# Push enemies away from the sword.
			enemy["knockback"] = facing * SWORD_KNOCKBACK

			if enemy["type"] != "MurkySlaad":
				enemy["vy"] = -100.0

			if enemy["type"] == "MurkySlaad":
				enemy["flash_timer"] = 0.12

			spawn_particles(
				enemy_rect.get_center(),
				Color("#FFE1A0"),
				6
			)

			if float(enemy["health"]) <= 0.0:
				enemies[i] = enemy
				defeat_enemy(i)
			else:
				enemies[i] = enemy


# ============================================================
# GUN ATTACK
# ============================================================

func shoot_weapon() -> void:
	if shoot_timer > 0.0 or weapon_name == "None":
		return

	shoot_timer = weapon_rate
	attack_timer = 0.12

	var arm_power: int = parts["arm"]["power"]
	var damage := weapon_damage + float(arm_power * 4)

	var muzzle := player_pos + Vector2(
		PLAYER_WIDTH / 2.0 + facing * 34.0,
		22.0
	)

	if weapon_name == "Scrap Shotgun":
		for spread_y in [-65.0, 0.0, 65.0]:
			projectiles.append({
				"pos": muzzle,
				"vel": Vector2(facing * 650.0, spread_y),
				"damage": damage * 0.65,
				"life": 1.2,
				"color": Color("#FFD477")
			})
	else:
		var projectile_speed := 650.0
		var projectile_color := Color("#FFD477")

		match weapon_name:
			"Revolver":
				projectile_speed = 800.0
				projectile_color = Color("#FFE4A0")
			"Bolt Rifle":
				projectile_speed = 1050.0
				projectile_color = Color("#F5F0CF")
			"Plasma Blaster":
				projectile_speed = 720.0
				projectile_color = Color("#73E8FF")
			"MP-43":
				projectile_speed = 750.0
				projectile_color = Color("#E8D6A5")

		projectiles.append({
			"pos": muzzle,
			"vel": Vector2(facing * projectile_speed, 0.0),
			"damage": damage,
			"life": 1.5,
			"color": projectile_color
		})

	spawn_particles(muzzle, Color("#FFF0B0"), 4)


# ============================================================
# ENEMY AI
# ============================================================

func update_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if game_over or i >= enemies.size():
			return

		var enemy: Dictionary = enemies[i]
		var pos: Vector2 = enemy["pos"]
		var enemy_type: String = enemy["type"]

		var enemy_width := 32.0
		var enemy_height := 48.0

		if enemy_type == "Heavy":
			enemy_width = 42.0
			enemy_height = 56.0
		elif enemy_type == "MurkySlaad":
			enemy_width = MURKY_SLAAD_WIDTH
			enemy_height = MURKY_SLAAD_HEIGHT

		var enemy_center := pos + Vector2(
			enemy_width / 2.0,
			enemy_height / 2.0
		)

		var player_center := player_pos + Vector2(
			PLAYER_WIDTH / 2.0,
			PLAYER_HEIGHT / 2.0
		)

		var direction := signf(player_center.x - enemy_center.x)

		if direction == 0.0:
			direction = 1.0
		enemy["facing"] = direction

		var knockback: float = enemy["knockback"]
		var enemy_speed: float = float(enemy["speed"])

		# Murky Slaad is exceptionally slow.
		if enemy_type == "MurkySlaad":
			enemy_speed = MURKY_SLAAD_SPEED
			enemy["facing"] = direction

			enemy["flash_timer"] = maxf(
				0.0,
				float(enemy["flash_timer"]) - delta
			)

			if absf(knockback) > 5.0:
				pos.x += knockback * delta
				enemy["knockback"] = move_toward(
					knockback,
					0.0,
					500.0 * delta
				)
			else:
				pos.x += direction * enemy_speed * delta

			pos.x = clampf(pos.x, 0.0, SCREEN_WIDTH - enemy_width)
			pos.y = FLOOR_Y - enemy_height

			enemy["pos"] = pos

			var slaad_rect := Rect2(
				pos,
				Vector2(enemy_width, enemy_height)
			)

			enemy["attack_timer"] = maxf(
				0.0,
				float(enemy["attack_timer"]) - delta
			)

			if slaad_rect.intersects(get_player_hitbox()) \
			and float(enemy["attack_timer"]) <= 0.0:

				enemy["attack_timer"] = 1.1

				if invincible_timer <= 0.0:
					var armor_power: int = parts["armor"]["power"]
					var contact_damage := maxf(
						5.0,
						24.0 - float(armor_power * 3)
					)

					player_health -= contact_damage
					invincible_timer = 0.75
					player_velocity.x = direction * 250.0

					if grounded:
						player_velocity.y = -170.0
						grounded = false

					spawn_particles(
						player_center,
						Color("#C7A7E8"),
						9
					)

					if player_health <= 0.0:
						player_health = 0.0
						trigger_game_over()
						return

			enemies[i] = enemy
			continue

		# Regular enemies.
		if enemy_type == "Heavy":
			enemy_speed *= 0.75
		elif enemy_type == "Runner":
			enemy_speed *= 1.5

		if absf(knockback) > 5.0:
			pos.x += knockback * delta
			enemy["knockback"] = move_toward(
				knockback,
				0.0,
				900.0 * delta
			)
		elif absf(player_center.x - enemy_center.x) > 32.0:
			pos.x += direction * enemy_speed * delta

		enemy["attack_timer"] = maxf(
			0.0,
			float(enemy["attack_timer"]) - delta
		)

		enemy["vy"] = float(enemy["vy"]) + GRAVITY * delta
		pos.y += float(enemy["vy"]) * delta

		if pos.y + enemy_height >= FLOOR_Y:
			pos.y = FLOOR_Y - enemy_height
			enemy["vy"] = 0.0

		pos.x = clampf(pos.x, 0.0, SCREEN_WIDTH - enemy_width)
		enemy["pos"] = pos

		var enemy_rect := Rect2(pos, Vector2(enemy_width, enemy_height))

		if enemy_rect.intersects(get_player_hitbox()) \
		and float(enemy["attack_timer"]) <= 0.0:

			enemy["attack_timer"] = 1.0

			if invincible_timer <= 0.0:
				var armor_power: int = parts["armor"]["power"]
				var damage := maxf(
					4.0,
					float(enemy["damage"]) - armor_power * 3.0
				)

				player_health -= damage
				invincible_timer = 0.65
				player_velocity.x = direction * 190.0

				if grounded:
					player_velocity.y = -140.0
					grounded = false

				spawn_particles(
					player_center,
					Color("#FF6B68"),
					8
				)

				if player_health <= 0.0:
					player_health = 0.0
					trigger_game_over()
					return

		enemies[i] = enemy


# ============================================================
# PROJECTILES
# ============================================================

func update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var bullet: Dictionary = projectiles[i]

		bullet["pos"] = (
			Vector2(bullet["pos"]) +
			Vector2(bullet["vel"]) * delta
		)
		bullet["life"] = float(bullet["life"]) - delta

		var bullet_pos: Vector2 = bullet["pos"]
		var hit := false

		if floating_alive:
			var floating_hitbox := get_floating_enemy_hitbox()

			if floating_hitbox.has_point(bullet_pos):
				damage_floating_enemy(
					float(bullet["damage"]),
					bullet_pos
				)
				hit = true

		if not hit:
			for j in range(enemies.size() - 1, -1, -1):
				var enemy: Dictionary = enemies[j]
				var enemy_width := 32.0
				var enemy_height := 48.0

				if enemy["type"] == "Heavy":
					enemy_width = 42.0
					enemy_height = 56.0
				elif enemy["type"] == "MurkySlaad":
					enemy_width = MURKY_SLAAD_WIDTH
					enemy_height = MURKY_SLAAD_HEIGHT

				var enemy_rect := Rect2(
					Vector2(enemy["pos"]),
					Vector2(enemy_width, enemy_height)
				)

				if enemy_rect.has_point(bullet_pos):
					enemy["health"] = (
						float(enemy["health"]) -
						float(bullet["damage"])
					)

					enemy["knockback"] = (
						signf(float(bullet["vel"].x)) * 180.0
					)

					if enemy["type"] != "MurkySlaad":
						enemy["vy"] = -65.0
					else:
						enemy["flash_timer"] = 0.12

					spawn_particles(
						bullet_pos,
						Color("#FFD477"),
						4
					)

					hit = true

					if float(enemy["health"]) <= 0.0:
						enemies[j] = enemy
						defeat_enemy(j)
					else:
						enemies[j] = enemy

					break

		if hit or float(bullet["life"]) <= 0.0:
			projectiles.remove_at(i)
		else:
			projectiles[i] = bullet


# ============================================================
# PICKUPS AND PARTICLES
# ============================================================

func update_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var item: Dictionary = pickups[i]
		item["life"] = float(item["life"]) - delta

		if float(item["life"]) <= 0.0:
			pickups.remove_at(i)
		else:
			pickups[i] = item


func update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[i]

		particle["life"] = float(particle["life"]) - delta
		particle["pos"] = (
			Vector2(particle["pos"]) +
			Vector2(particle["vel"]) * delta
		)
		particle["vel"] = Vector2(particle["vel"]) * 0.94

		if float(particle["life"]) <= 0.0:
			particles.remove_at(i)
		else:
			particles[i] = particle


# ============================================================
# WAVES
# ============================================================

func update_waves(delta: float) -> void:
	if enemies_to_spawn > 0:
		spawn_timer -= delta

		if spawn_timer <= 0.0:
			spawn_enemy()
			enemies_to_spawn -= 1
			spawn_timer = maxf(0.3, 1.0 - float(wave) * 0.035)

	elif enemies.is_empty():
		intermission -= delta

		if intermission <= 0.0:
			wave += 1

			enemies_to_spawn = mini(3 + wave * 2, 35)
			intermission = 3.0

			message = "WAVE " + str(wave)
			message_timer = 2.0

			# Bring the eye back at the start of every wave, with full health.
			# Its spawn side is randomized so it does not always enter from the right.
			reset_floating_enemy()

			if wave % 5 == 0:
				message = "WARNING: HEAVY BOTS INCOMING"


func spawn_enemy() -> void:
	# Every regular enemy chooses one of the two screen edges at random.
	var spawn_x := SCREEN_WIDTH - 55.0

	if rng.randf() < 0.5:
		spawn_x = 30.0

	# Only spawn a Murky Slaad if one is not already alive.
	# AnimatedSprite2D3 is used to animate that enemy.
	var slaad_already_alive := false

	for existing_enemy in enemies:
		if str(existing_enemy["type"]) == "MurkySlaad":
			slaad_already_alive = true
			break

	if wave >= MURKY_SLAAD_SPAWN_WAVE \
	and not slaad_already_alive \
	and rng.randf() < minf(0.18 + float(wave - MURKY_SLAAD_SPAWN_WAVE) * 0.045, 0.52):

		var slaad_x := SCREEN_WIDTH - MURKY_SLAAD_WIDTH - 10.0

		if rng.randf() < 0.5:
			slaad_x = 10.0

		enemies.append({
			"pos": Vector2(
				slaad_x,
				FLOOR_Y - MURKY_SLAAD_HEIGHT
			),
			"health": MURKY_SLAAD_HEALTH,
			"max_health": MURKY_SLAAD_HEALTH,
			"speed": MURKY_SLAAD_SPEED,
			"damage": 24.0,
			"type": "MurkySlaad",
			"variant": rng.randi_range(0, 5),
			"spawn_side": "left" if slaad_x < SCREEN_WIDTH / 2.0 else "right",
			"facing": -1.0 if slaad_x > SCREEN_WIDTH / 2.0 else 1.0,
			"attack_timer": 0.7,
			"knockback": 0.0,
			"vy": 0.0,
			"flash_timer": 0.0
		})
		return

	var enemy_type := "Basic"
	var roll := rng.randf()

	if wave >= 2 and roll < 0.28:
		enemy_type = "Runner"

	if wave >= 3 and roll > 0.68:
		enemy_type = "Heavy"

	var max_hp := 45.0 + float(wave) * 8.0
	var enemy_speed := 85.0 + float(wave) * 2.5
	var damage := 12.0 + float(wave)

	if enemy_type == "Runner":
		max_hp *= 0.7
		enemy_speed *= 1.35
		damage *= 0.8

	if enemy_type == "Heavy":
		max_hp *= 2.3
		enemy_speed *= 0.65
		damage *= 1.8

	enemies.append({
		"pos": Vector2(spawn_x, FLOOR_Y - 48.0),
		"health": max_hp,
		"max_health": max_hp,
		"speed": enemy_speed,
		"damage": damage,
		"type": enemy_type,
		"variant": rng.randi_range(0, 5),
		"spawn_side": "left" if spawn_x < SCREEN_WIDTH / 2.0 else "right",
		"facing": -1.0 if spawn_x > SCREEN_WIDTH / 2.0 else 1.0,
		"attack_timer": 0.5,
		"knockback": 0.0,
		"vy": 0.0
	})


func defeat_enemy(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return

	var enemy: Dictionary = enemies[index]
	var death_pos: Vector2 = enemy["pos"] + Vector2(16, 24)

	if enemy["type"] == "MurkySlaad":
		death_pos = enemy["pos"] + Vector2(
			MURKY_SLAAD_WIDTH / 2.0,
			MURKY_SLAAD_HEIGHT / 2.0
		)

	enemies.remove_at(index)

	if enemy["type"] == "MurkySlaad":
		if murky_slaad_sprite != null:
			murky_slaad_sprite.visible = false
			murky_slaad_sprite.modulate = Color.WHITE

	total_kills += 1
	scrap += rng.randi_range(2, 5)

	# Use the same death particle effect as the other enemies.
	var death_color := Color("#91D7B1")

	if enemy["type"] == "MurkySlaad":
		death_color = Color("#C7A7E8")

	spawn_particles(death_pos, death_color, 16)

	if rng.randf() < 0.50:
		var slots := ["head", "arm", "legs", "armor"]
		var slot: String = slots[rng.randi_range(0, slots.size() - 1)]
		var component := make_part(slot)

		pickups.append({
			"pos": death_pos,
			"kind": slot,
			"name": component["name"],
			"power": component["power"],
			"life": 22.0
		})

	if rng.randf() < 0.40:
		var weapon := make_weapon()

		pickups.append({
			"pos": death_pos + Vector2(15, 0),
			"kind": "weapon",
			"name": weapon["name"],
			"power": weapon["power"],
			"asset": weapon["asset"],
			"life": 22.0
		})


# ============================================================
# PART GENERATION
# ============================================================

func make_part(slot: String) -> Dictionary:
	match slot:
		"head":
			var options := [
				{"name": "Scout Visor", "power": 1},
				{"name": "Targeting Head", "power": 2},
				{"name": "Heavy Helmet", "power": 3}
			]
			return options[rng.randi_range(0, options.size() - 1)]

		"arm":
			var options := [
				{"name": "Crusher Arm", "power": 2},
				{"name": "Power Arm", "power": 3},
				{"name": "Hydraulic Arm", "power": 4}
			]
			return options[rng.randi_range(0, options.size() - 1)]

		"legs":
			var options := [
				{"name": "Runner Legs", "power": 1},
				{"name": "Tank Legs", "power": 2},
				{"name": "Spring Legs", "power": 3}
			]
			return options[rng.randi_range(0, options.size() - 1)]

		_:
			var options := [
				{"name": "Reinforced Armor", "power": 1},
				{"name": "Heavy Armor", "power": 2},
				{"name": "Titanium Armor", "power": 3}
			]
			return options[rng.randi_range(0, options.size() - 1)]


# ============================================================
# WEAPON GENERATION
# ============================================================

func make_weapon() -> Dictionary:
	var options := [
		{
			"name": "Revolver",
			"power": 24,
			"asset": "res://Revolver.png"
		},
		{
			"name": "Bolt Rifle",
			"power": 32,
			"asset": "res://Winchester.png"
		},
		{
			"name": "Scrap Shotgun",
			"power": 28,
			"asset": "res://1878 Hartford.png"
		},
		{
			"name": "Plasma Blaster",
			"power": 35,
			"asset": "res://Laser Rifle.png"
		},
		{
			"name": "MP-43",
			"power": 17,
			"asset": "res://MP - 43.png"
		}
	]

	return options[rng.randi_range(0, options.size() - 1)]


# ============================================================
# COLLECTING PICKUPS
# ============================================================

func collect_nearest_pickup() -> void:
	var best_index := -1
	var best_distance := 72.0

	var player_center := player_pos + Vector2(
		PLAYER_WIDTH / 2.0,
		PLAYER_HEIGHT / 2.0
	)

	for i in range(pickups.size()):
		var item: Dictionary = pickups[i]
		var distance := player_center.distance_to(Vector2(item["pos"]))

		if distance < best_distance:
			best_distance = distance
			best_index = i

	if best_index == -1:
		message = "NO PARTS IN REACH"
		message_timer = 1.0
		return

	var item: Dictionary = pickups[best_index]

	if item["kind"] == "weapon":
		equip_weapon(item)
	else:
		equip_part(item)

	pickups.remove_at(best_index)


func equip_part(item: Dictionary) -> void:
	var slot: String = item["kind"]
	var old_part: Dictionary = parts[slot]

	pickups.append({
		"pos": player_pos + Vector2(PLAYER_WIDTH / 2.0, 20),
		"kind": slot,
		"name": old_part["name"],
		"power": old_part["power"],
		"life": 22.0
	})

	parts[slot] = {
		"name": item["name"],
		"power": item["power"]
	}

	var old_max := player_max_health
	var head_power: int = parts["head"]["power"]

	player_max_health = 100.0 + float(head_power * 10)

	if player_max_health > old_max:
		player_health += player_max_health - old_max

	player_health = minf(player_health, player_max_health)

	message = "EQUIPPED: " + str(item["name"])
	message_timer = 1.8

	spawn_particles(
		player_pos + Vector2(PLAYER_WIDTH / 2.0, 20),
		Color("#7DE7D1"),
		10
	)


func equip_weapon(item: Dictionary) -> void:
	weapon_name = str(item["name"])
	weapon_asset = str(item["asset"])
	current_slot = 2

	match weapon_name:
		"Revolver":
			weapon_damage = 24.0
			# Slightly faster firing without turning it into a rapid-fire gun.
			weapon_rate = 0.33
		"Bolt Rifle":
			weapon_damage = 32.0
			weapon_rate = 0.55
		"Scrap Shotgun":
			weapon_damage = 28.0
			weapon_rate = 0.65
		"Plasma Blaster":
			weapon_damage = 35.0
			weapon_rate = 0.48
		"MP-43":
			weapon_damage = 17.0

			# The MP-43 now fires less frequently.
			# Each shot has a 0.42-second cooldown.
			weapon_rate = 0.42
		_:
			weapon_damage = float(item.get("power", 22))
			weapon_rate = 0.4

	message = "GUN EQUIPPED: " + weapon_name
	message_timer = 2.0


# ============================================================
# PARTICLES
# ============================================================

func spawn_particles(pos: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(45.0, 190.0)

		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": color,
			"life": rng.randf_range(0.15, 0.45)
		})


# ============================================================
# DRAWING
# ============================================================

func _draw() -> void:
	draw_background()

	if game_over:
		draw_rect(
			Rect2(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT),
			Color(0, 0, 0, 0.76)
		)

		draw_centered_text(
			"SCRAP DESTROYED",
			245,
			42,
			Color("#FF7777")
		)

		draw_centered_text(
			"You survived until wave " + str(wave),
			300,
			22,
			Color.WHITE
		)

		draw_centered_text(
			"Kills: " + str(total_kills) + "    Scrap: " + str(scrap),
			340,
			18,
			Color("#E5C98B")
		)

		draw_centered_text(
			"PRESS R TO RESTART",
			405,
			22,
			Color.WHITE
		)
		return

	draw_pickups()
	draw_projectiles()
	draw_enemies()
	draw_player()
	draw_particles()
	draw_hud()


func draw_background() -> void:
	if background_texture != null:
		draw_texture_rect(
			background_texture,
			Rect2(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT),
			false
		)
	else:
		draw_rect(
			Rect2(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT),
			Color("#171D28")
		)


func draw_player() -> void:
	var player_center := player_pos + Vector2(
		PLAYER_WIDTH / 2.0,
		PLAYER_HEIGHT / 2.0
	)

	if current_slot == 1:
		draw_sword(player_center)
	elif current_slot == 2 and weapon_name != "None":
		draw_gun(player_center)
	# Equipment changes gameplay stats, but dropped parts are the visual focus.
	# The player sprite is intentionally left unchanged when parts are equipped.


# ============================================================
# SWORD DRAWING
# ============================================================

func draw_sword(player_center: Vector2) -> void:
	if sword_texture == null:
		return

	var sword_pivot := player_center + Vector2(
		facing * 19.0,
		5.0
	)

	var image_size := HAND_SWORD_SIZE

	var handle_position := Vector2(
		image_size.x * (SWORD_HANDLE_IN_IMAGE.x / 38.0),
		image_size.y * (SWORD_HANDLE_IN_IMAGE.y / 38.0)
	)

	var image_offset := -handle_position

	# Smooth swing down and back up within the same attack.
	var sword_angle := SWORD_RAISED_ANGLE

	if sword_flash_timer > 0.0:
		var progress := 1.0 - (
			sword_flash_timer / SWORD_SWING_DURATION
		)

		progress = clampf(progress, 0.0, 1.0)

		# Starts raised, swings down, then returns to raised.
		sword_angle = sin(progress * PI) * SWORD_LOWERED_ANGLE

	# Reverse the rotation direction when facing left.
	sword_angle *= facing

	var sword_scale := Vector2.ONE

	if facing < 0.0:
		sword_scale.x = -1.0
		image_offset.x = -image_offset.x - image_size.x

	draw_set_transform(
		sword_pivot,
		sword_angle,
		sword_scale
	)

	draw_texture_rect(
		sword_texture,
		Rect2(image_offset, image_size),
		false
	)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ============================================================
# GUN DRAWING
# ============================================================

func draw_gun(player_center: Vector2) -> void:
	var texture: Texture2D = gun_textures.get(weapon_name)

	if texture == null:
		return

	var gun_position := player_center + Vector2(
		facing * 30.0,
		0.0
	)

	var gun_size := HAND_GUN_SIZE

	if weapon_name == "Bolt Rifle" \
	or weapon_name == "Scrap Shotgun" \
	or weapon_name == "Plasma Blaster" \
	or weapon_name == "MP-43":
		gun_size = LONG_GUN_SIZE

	var gun_scale := Vector2(-1.0, 1.0)

	if facing < 0.0:
		gun_scale.x = 1.0

	draw_set_transform(gun_position, 0.0, gun_scale)

	draw_texture_rect(
		texture,
		Rect2(-gun_size / 2.0, gun_size),
		false
	)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ============================================================
# ENEMY DRAWING
# ============================================================

func draw_enemies() -> void:
	for enemy in enemies:
		var enemy_type: String = str(enemy["type"])
		# Murky Slaad is drawn by AnimatedSprite2D3 using its real SpriteFrames.
		if enemy_type == "MurkySlaad":
			continue
		draw_pixel_enemy(enemy)


# Pixel-art monster rendering. Each spawn gets its own palette/gear variant,
# and the legs animate while it moves. All shapes snap to a chunky pixel grid.
func draw_pixel_enemy(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy["pos"]
	var enemy_type: String = str(enemy["type"])
	var width := 32.0
	var height := 48.0
	if enemy_type == "Heavy":
		width = 42.0
		height = 56.0
	var variant: int = int(enemy.get("variant", 0))
	var facing_dir: float = float(enemy.get("facing", -1.0))
	var spawn_side: String = str(enemy.get("spawn_side", "right"))
	# Mirror the complete custom pixel-art monster around its own center when it
	# spawned on the left, so asymmetrical gear and face details are reversed too.
	if spawn_side == "left":
		draw_set_transform(Vector2(pos.x * 2.0 + width, 0.0), 0.0, Vector2(-1.0, 1.0))
	var moving := absf(player_pos.x + PLAYER_WIDTH / 2.0 - (pos.x + width / 2.0)) > 34.0 and not game_over
	var step := 0.0
	if moving:
		step = sin(visual_time * (11.0 if enemy_type == "Runner" else 7.0) + float(pos.x) * 0.07) * 3.0
	var shadow_y := FLOOR_Y - 3.0
	draw_rect(Rect2(pos.x + 2.0, shadow_y, width - 4.0, 4.0), Color("#20232B"))

	var body_palette := [Color("#6F9A69"), Color("#8D665A"), Color("#687EA0"), Color("#9B7651"), Color("#786A9F"), Color("#688F8C")]
	var head_palette := [Color("#A7C47A"), Color("#C58A70"), Color("#91A9C8"), Color("#D1A56B"), Color("#B2A0D7"), Color("#8AC0B2")]
	var dark_palette := [Color("#344B39"), Color("#50362F"), Color("#34445E"), Color("#59432E"), Color("#453A5C"), Color("#2F514D")]
	var body: Color = body_palette[variant]
	var head: Color = head_palette[variant]
	var dark: Color = dark_palette[variant]
	var metal := Color("#C5C9C9") if variant % 2 == 0 else Color("#B48B55")
	var eye := Color("#F9D96C") if variant % 3 != 1 else Color("#F27868")

	# Two separated, articulated legs with alternating stride.
	var leg_y := pos.y + height - 14.0
	var left_leg_x := pos.x + (7.0 if width < 40.0 else 9.0)
	var right_leg_x := pos.x + width - (14.0 if width < 40.0 else 18.0)
	draw_rect(Rect2(left_leg_x + step, leg_y, 7.0, 10.0), dark)
	draw_rect(Rect2(left_leg_x + step - 1.0, leg_y + 8.0, 9.0, 4.0), metal)
	draw_rect(Rect2(right_leg_x - step, leg_y, 7.0, 10.0), dark)
	draw_rect(Rect2(right_leg_x - step - 1.0, leg_y + 8.0, 9.0, 4.0), metal)
	draw_rect(Rect2(left_leg_x + step + 1.0, leg_y + 2.0, 2.0, 4.0), body)
	draw_rect(Rect2(right_leg_x - step + 1.0, leg_y + 2.0, 2.0, 4.0), body)

	# Chunky torso, shadow side, rivets and shoulder plates.
	var torso_y := pos.y + 17.0
	var torso_h := height - 31.0
	draw_rect(Rect2(pos.x + 4.0, torso_y, width - 8.0, torso_h), dark)
	draw_rect(Rect2(pos.x + 6.0, torso_y + 2.0, width - 14.0, torso_h - 4.0), body)
	draw_rect(Rect2(pos.x + 8.0, torso_y + 4.0, width - 18.0, 4.0), head)
	draw_rect(Rect2(pos.x + 8.0, torso_y + 12.0, width - 18.0, 3.0), metal)
	draw_rect(Rect2(pos.x + 6.0, torso_y + 5.0, 3.0, 3.0), metal)
	draw_rect(Rect2(pos.x + width - 10.0, torso_y + 5.0, 3.0, 3.0), metal)
	draw_rect(Rect2(pos.x + width / 2.0 - 2.0, torso_y + 7.0, 4.0, 5.0), eye)
	draw_rect(Rect2(pos.x + 1.0, torso_y + 1.0, 6.0, 9.0), body)
	draw_rect(Rect2(pos.x + width - 7.0, torso_y + 1.0, 6.0, 9.0), dark)

	# Head shape varies: horns, ears, goggles, jaw plates, or a crown ridge.
	var head_y := pos.y + 3.0
	var head_x := pos.x + (5.0 if width < 40.0 else 8.0)
	var head_w := width - (10.0 if width < 40.0 else 16.0)
	draw_rect(Rect2(head_x, head_y + 3.0, head_w, 12.0), dark)
	draw_rect(Rect2(head_x + 2.0, head_y + 1.0, head_w - 4.0, 12.0), head)
	draw_rect(Rect2(head_x + 4.0, head_y + 5.0, head_w - 8.0, 4.0), dark)
	var eye_y := head_y + 6.0
	draw_rect(Rect2(head_x + 5.0, eye_y, 4.0, 3.0), eye)
	draw_rect(Rect2(head_x + head_w - 9.0, eye_y, 4.0, 3.0), eye)
	draw_rect(Rect2(head_x + 7.0, head_y + 11.0, head_w - 14.0, 2.0), Color("#241F28"))
	match variant:
		0:
			draw_rect(Rect2(head_x + 1.0, head_y - 2.0, 5.0, 5.0), metal)
			draw_rect(Rect2(head_x + head_w - 6.0, head_y - 2.0, 5.0, 5.0), metal)
		1:
			draw_rect(Rect2(head_x + 2.0, head_y + 1.0, head_w - 4.0, 3.0), metal)
			draw_rect(Rect2(head_x + head_w / 2.0 - 2.0, head_y - 3.0, 5.0, 5.0), eye)
		2:
			draw_rect(Rect2(head_x - 2.0, head_y + 4.0, 4.0, 5.0), head)
			draw_rect(Rect2(head_x + head_w - 2.0, head_y + 4.0, 4.0, 5.0), head)
		3:
			draw_rect(Rect2(head_x + 1.0, head_y - 3.0, 4.0, 6.0), metal)
			draw_rect(Rect2(head_x + head_w - 5.0, head_y - 3.0, 4.0, 6.0), metal)
		4:
			draw_rect(Rect2(head_x + 2.0, head_y - 2.0, head_w - 4.0, 4.0), dark)
			draw_rect(Rect2(head_x + 4.0, head_y - 1.0, head_w - 8.0, 2.0), eye)
		_:
			draw_rect(Rect2(head_x + 1.0, head_y + 1.0, 4.0, 4.0), metal)
			draw_rect(Rect2(head_x + head_w - 5.0, head_y + 1.0, 4.0, 4.0), metal)

	# Enemy class-specific silhouettes and recognizable equipment.
	if enemy_type == "Runner":
		# Lightweight scarf, forward spikes and glowing runner core.
		draw_rect(Rect2(pos.x + 4.0, torso_y + 3.0, 5.0, 4.0), Color("#E86F55"))
		draw_rect(Rect2(pos.x + 1.0, torso_y + 7.0, 7.0, 3.0), Color("#E86F55"))
		draw_rect(Rect2(pos.x + width - 8.0, torso_y + 5.0, 5.0, 3.0), eye)
	else:
		# Scrap gauntlets and asymmetrical shoulder armor.
		draw_rect(Rect2(pos.x + 1.0, torso_y + 9.0, 6.0, 8.0), metal)
		draw_rect(Rect2(pos.x + width - 7.0, torso_y + 9.0, 6.0, 8.0), body)
		draw_rect(Rect2(pos.x + width - 6.0, torso_y + 12.0, 4.0, 2.0), metal)
	if enemy_type == "Heavy":
		# Broad armored plating, rivets, and a large chest emblem.
		draw_rect(Rect2(pos.x + 4.0, torso_y - 2.0, width - 8.0, 5.0), metal)
		draw_rect(Rect2(pos.x + 9.0, torso_y + 6.0, width - 18.0, 10.0), dark)
		draw_rect(Rect2(pos.x + width / 2.0 - 4.0, torso_y + 8.0, 8.0, 6.0), eye)
		draw_rect(Rect2(pos.x + 3.0, pos.y + 18.0, 4.0, 8.0), metal)
		draw_rect(Rect2(pos.x + width - 7.0, pos.y + 18.0, 4.0, 8.0), metal)

	# Health strip remains above each regular enemy.
	var health_ratio := clampf(float(enemy["health"]) / maxf(1.0, float(enemy["max_health"])), 0.0, 1.0)
	draw_rect(Rect2(pos.x, pos.y - 9.0, width, 4.0), Color("#392D36"))
	draw_rect(Rect2(pos.x, pos.y - 9.0, width * health_ratio, 4.0), Color("#EF7773"))
	if spawn_side == "left":
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ============================================================
# PICKUP DRAWING
# ============================================================

func draw_pickups() -> void:
	for item in pickups:
		var pos: Vector2 = item["pos"]

		# Tiny dark shadow helps each loose part read clearly against the floor.
		draw_rect(Rect2(pos.x - 15.0, pos.y + 11.0, 30.0, 4.0), Color("#171B24"))

		if item["kind"] == "weapon":
			var item_name: String = str(item["name"])
			var texture: Texture2D = gun_textures.get(item_name)

			if texture != null:
				draw_texture_rect(
					texture,
					Rect2(pos - WEAPON_PICKUP_SIZE / 2.0, WEAPON_PICKUP_SIZE),
					false
				)
				draw_rect(
					Rect2(pos - WEAPON_PICKUP_SIZE / 2.0 - Vector2(2, 2), WEAPON_PICKUP_SIZE + Vector2(4, 4)),
					Color("#F6E7A0"), false, 2.0
				)
			else:
				draw_rect(Rect2(pos - Vector2(12, 12), Vector2(24, 24)), Color("#F6E7A0"))
			continue

		draw_part_pickup(item, pos)


func draw_part_pickup(item: Dictionary, pos: Vector2) -> void:
	# Each dropped part is drawn as a small, readable pixel-art object rather
	# than a colored square. The silhouette and details depend on its exact name.
	var item_name := str(item.get("name", ""))
	var kind := str(item.get("kind", "armor"))
	var outline := Color("#252A35")
	var metal := Color("#AAB6BB")
	var light := Color("#E0E6DF")
	var shade := Color("#65717D")
	var accent := Color("#F1CE75")

	match item_name:
		"Scout Visor":
			metal = Color("#6B9CB7")
			light = Color("#B9E5EA")
			shade = Color("#34566F")
			accent = Color("#73F0E2")
		"Targeting Head":
			metal = Color("#4B9D98")
			light = Color("#A7E6D7")
			shade = Color("#285D66")
			accent = Color("#FF5F67")
		"Heavy Helmet":
			metal = Color("#B38B4D")
			light = Color("#E4C985")
			shade = Color("#665039")
			accent = Color("#F8E5A2")
		"Crusher Arm":
			metal = Color("#B56E51")
			light = Color("#E5A17A")
			shade = Color("#663F3B")
			accent = Color("#F2D184")
		"Power Arm":
			metal = Color("#758BC0")
			light = Color("#B5C8E9")
			shade = Color("#414D78")
			accent = Color("#82F0D0")
		"Hydraulic Arm":
			metal = Color("#A7B9BA")
			light = Color("#E1E9DD")
			shade = Color("#566C77")
			accent = Color("#E7B75F")
		"Runner Legs":
			metal = Color("#5C9DB7")
			light = Color("#A8DDE8")
			shade = Color("#31566D")
			accent = Color("#F3D77A")
		"Tank Legs":
			metal = Color("#828A98")
			light = Color("#C8D0D0")
			shade = Color("#444D5D")
			accent = Color("#DDAA61")
		"Spring Legs":
			metal = Color("#B28A4C")
			light = Color("#E7CA83")
			shade = Color("#695238")
			accent = Color("#8CE0CE")
		"Reinforced Armor":
			metal = Color("#748C9B")
			light = Color("#C4D4D7")
			shade = Color("#3F5565")
			accent = Color("#E6C878")
		"Heavy Armor":
			metal = Color("#626F89")
			light = Color("#A6B3C6")
			shade = Color("#343E55")
			accent = Color("#E09A64")
		"Titanium Armor":
			metal = Color("#9AAEB0")
			light = Color("#E4E9DF")
			shade = Color("#53666F")
			accent = Color("#79E7D5")
		"Tin Armor":
			metal = Color("#8A979D")
			light = Color("#CBD2CC")
			shade = Color("#4B5962")
			accent = Color("#E6C878")

	match kind:
		"head":
			# Helmet shell, brow, face opening and glowing eyes.
			draw_rect(Rect2(pos.x - 11, pos.y - 8, 22, 17), outline)
			draw_rect(Rect2(pos.x - 8, pos.y - 11, 16, 5), outline)
			draw_rect(Rect2(pos.x - 8, pos.y - 8, 16, 12), metal)
			draw_rect(Rect2(pos.x - 5, pos.y - 4, 10, 6), shade)
			draw_rect(Rect2(pos.x - 4, pos.y - 3, 3, 3), accent)
			draw_rect(Rect2(pos.x + 1, pos.y - 3, 3, 3), accent)
			draw_rect(Rect2(pos.x - 7, pos.y + 5, 14, 3), outline)
			draw_rect(Rect2(pos.x - 6, pos.y - 7, 12, 2), light)
			if item_name == "Targeting Head":
				draw_rect(Rect2(pos.x + 7, pos.y - 13, 3, 7), outline)
				draw_rect(Rect2(pos.x + 8, pos.y - 14, 4, 3), accent)
				draw_rect(Rect2(pos.x - 13, pos.y - 2, 3, 7), shade)
			elif item_name == "Heavy Helmet":
				draw_rect(Rect2(pos.x - 13, pos.y - 5, 4, 10), metal)
				draw_rect(Rect2(pos.x + 9, pos.y - 5, 4, 10), metal)
				draw_rect(Rect2(pos.x - 3, pos.y + 3, 6, 2), light)
			else:
				draw_rect(Rect2(pos.x - 12, pos.y - 1, 3, 3), accent)

		"arm":
			# Shoulder, elbow joint, segmented forearm and a different hand shape.
			draw_rect(Rect2(pos.x - 13, pos.y - 7, 9, 11), outline)
			draw_rect(Rect2(pos.x - 11, pos.y - 5, 6, 7), metal)
			draw_rect(Rect2(pos.x - 5, pos.y - 3, 7, 7), shade)
			draw_rect(Rect2(pos.x - 4, pos.y - 2, 5, 5), accent)
			draw_rect(Rect2(pos.x + 1, pos.y - 5, 10, 11), outline)
			draw_rect(Rect2(pos.x + 3, pos.y - 3, 6, 7), metal)
			draw_rect(Rect2(pos.x + 5, pos.y - 1, 4, 3), light)
			if item_name == "Crusher Arm":
				draw_rect(Rect2(pos.x + 8, pos.y - 9, 9, 17), outline)
				draw_rect(Rect2(pos.x + 10, pos.y - 7, 6, 13), metal)
				draw_rect(Rect2(pos.x + 10, pos.y - 9, 3, 4), light)
				draw_rect(Rect2(pos.x + 13, pos.y + 5, 4, 4), light)
			elif item_name == "Power Arm":
				draw_rect(Rect2(pos.x + 7, pos.y - 8, 12, 15), outline)
				draw_rect(Rect2(pos.x + 9, pos.y - 6, 8, 11), metal)
				draw_rect(Rect2(pos.x + 10, pos.y - 4, 6, 3), accent)
			else:
				draw_rect(Rect2(pos.x + 8, pos.y - 8, 9, 3), light)
				draw_rect(Rect2(pos.x + 9, pos.y + 5, 3, 5), shade)
				draw_rect(Rect2(pos.x + 14, pos.y + 5, 3, 5), shade)
			draw_rect(Rect2(pos.x - 7, pos.y - 1, 3, 3), light)

		"legs":
			# Two separate mechanical legs with hips, knees, shins and feet.
			if item_name == "Tank Legs":
				draw_rect(Rect2(pos.x - 13, pos.y - 5, 12, 15), outline)
				draw_rect(Rect2(pos.x + 1, pos.y - 5, 12, 15), outline)
				draw_rect(Rect2(pos.x - 11, pos.y - 3, 8, 11), metal)
				draw_rect(Rect2(pos.x + 3, pos.y - 3, 8, 11), metal)
				draw_rect(Rect2(pos.x - 12, pos.y + 6, 11, 5), shade)
				draw_rect(Rect2(pos.x + 1, pos.y + 6, 11, 5), shade)
				draw_rect(Rect2(pos.x - 12, pos.y + 8, 11, 2), accent)
				draw_rect(Rect2(pos.x + 1, pos.y + 8, 11, 2), accent)
			else:
				draw_rect(Rect2(pos.x - 10, pos.y - 10, 8, 9), outline)
				draw_rect(Rect2(pos.x + 2, pos.y - 10, 8, 9), outline)
				draw_rect(Rect2(pos.x - 8, pos.y - 8, 4, 6), metal)
				draw_rect(Rect2(pos.x + 4, pos.y - 8, 4, 6), metal)
				draw_rect(Rect2(pos.x - 9, pos.y - 2, 6, 9), outline)
				draw_rect(Rect2(pos.x + 3, pos.y - 2, 6, 9), outline)
				draw_rect(Rect2(pos.x - 7, pos.y, 2, 4), accent)
				draw_rect(Rect2(pos.x + 5, pos.y, 2, 4), accent)
				draw_rect(Rect2(pos.x - 11, pos.y + 5, 10, 5), outline)
				draw_rect(Rect2(pos.x + 1, pos.y + 5, 10, 5), outline)
				draw_rect(Rect2(pos.x - 9, pos.y + 6, 6, 2), light)
				draw_rect(Rect2(pos.x + 3, pos.y + 6, 6, 2), light)
				if item_name == "Spring Legs":
					# Exposed spring coils distinguish the jumping legs.
					draw_rect(Rect2(pos.x - 8, pos.y - 1, 5, 2), accent)
					draw_rect(Rect2(pos.x - 6, pos.y + 2, 5, 2), accent)
					draw_rect(Rect2(pos.x + 3, pos.y - 1, 5, 2), accent)
					draw_rect(Rect2(pos.x + 5, pos.y + 2, 5, 2), accent)
				elif item_name == "Runner Legs":
					draw_rect(Rect2(pos.x - 9, pos.y - 7, 6, 2), light)
					draw_rect(Rect2(pos.x + 3, pos.y - 7, 6, 2), light)

		"armor":
			# Chest plate with shoulder guards, segmented plates and a power core.
			draw_rect(Rect2(pos.x - 13, pos.y - 7, 26, 16), outline)
			draw_rect(Rect2(pos.x - 10, pos.y - 10, 7, 5), outline)
			draw_rect(Rect2(pos.x + 3, pos.y - 10, 7, 5), outline)
			draw_rect(Rect2(pos.x - 10, pos.y - 6, 20, 12), metal)
			draw_rect(Rect2(pos.x - 8, pos.y - 8, 5, 4), light)
			draw_rect(Rect2(pos.x + 3, pos.y - 8, 5, 4), light)
			draw_rect(Rect2(pos.x - 4, pos.y - 3, 8, 7), shade)
			draw_rect(Rect2(pos.x - 2, pos.y - 1, 4, 3), accent)
			draw_rect(Rect2(pos.x - 8, pos.y + 6, 5, 3), shade)
			draw_rect(Rect2(pos.x + 3, pos.y + 6, 5, 3), shade)
			if item_name == "Heavy Armor":
				draw_rect(Rect2(pos.x - 15, pos.y - 4, 4, 11), metal)
				draw_rect(Rect2(pos.x + 11, pos.y - 4, 4, 11), metal)
				draw_rect(Rect2(pos.x - 5, pos.y + 4, 10, 2), accent)
			elif item_name == "Titanium Armor":
				draw_rect(Rect2(pos.x - 2, pos.y - 7, 4, 2), accent)
				draw_rect(Rect2(pos.x - 11, pos.y + 1, 3, 3), light)
				draw_rect(Rect2(pos.x + 8, pos.y + 1, 3, 3), light)
			else:
				draw_rect(Rect2(pos.x - 9, pos.y + 2, 3, 3), shade)
				draw_rect(Rect2(pos.x + 6, pos.y + 2, 3, 3), shade)

	# Thin highlight glints and a few bolts make each icon read as pixel art.
	if kind != "head":
		draw_rect(Rect2(pos.x - 12, pos.y - 12, 3, 2), light)
		draw_rect(Rect2(pos.x + 9, pos.y + 10, 3, 2), shade)


# ============================================================
# PROJECTILE DRAWING
# ============================================================

func draw_projectiles() -> void:
	for bullet in projectiles:
		var pos: Vector2 = bullet["pos"]
		var color: Color = bullet["color"]
		var direction: float = signf(float(bullet["vel"].x))

		var bullet_x := pos.x - 8.0

		if direction < 0.0:
			bullet_x = pos.x - 2.0

		draw_rect(
			Rect2(bullet_x, pos.y - 3.0, 10.0, 6.0),
			color
		)


func draw_particles() -> void:
	for particle in particles:
		var pos: Vector2 = particle["pos"]
		var color: Color = particle["color"]

		draw_rect(
			Rect2(pos.x - 2, pos.y - 2, 4, 4),
			color
		)


# ============================================================
# HUD
# ============================================================

func draw_hud() -> void:
	draw_rect(Rect2(0, 0, SCREEN_WIDTH, 78), Color("#101722"))

	draw_string(
		ThemeDB.fallback_font,
		Vector2(20, 29),
		"SCRAPJACK",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		22,
		Color("#E8F0F2")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(20, 52),
		"WAVE " + str(wave) + "   KILLS " + str(total_kills),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color("#9DAFB8")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(245, 25),
		"HULL",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("#CFDCE1")
	)

	draw_rect(
		Rect2(245, 33, 180, 14),
		Color("#3A2831")
	)

	draw_rect(
		Rect2(
			245,
			33,
			180.0 * (player_health / player_max_health),
			14
		),
		Color("#E96F70")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(438, 45),
		str(int(player_health)) + " / " + str(int(player_max_health)),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("#E6ECEF")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(560, 27),
		"SCRAP: " + str(scrap),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color("#E9C77E")
	)

	var selected_weapon_text := "SWORD (1)"

	if current_slot == 2:
		if weapon_name == "None":
			selected_weapon_text = "EMPTY SLOT (2)"
		else:
			selected_weapon_text = weapon_name + " (2)"

	draw_string(
		ThemeDB.fallback_font,
		Vector2(560, 51),
		"WEAPON: " + selected_weapon_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("#A9D6CD")
	)

	draw_rect(
		Rect2(690, 88, 255, 122),
		Color("#101722")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(704, 110),
		"EQUIPPED PARTS",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		Color("#F0D28C")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(704, 133),
		"HEAD: " + str(parts["head"]["name"]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color("#DCE4E9")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(704, 153),
		"ARM: " + str(parts["arm"]["name"]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color("#DCE4E9")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(704, 173),
		"LEGS: " + str(parts["legs"]["name"]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color("#DCE4E9")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(704, 193),
		"ARMOR: " + str(parts["armor"]["name"]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color("#DCE4E9")
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(20, 580),
		"A/D MOVE   SPACE JUMP   1 SWORD   2 GUN   J ATTACK/FIRE   E EQUIP   R RESTART",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("#D1DCE0")
	)

	if message_timer > 0.0:
		draw_centered_text(message, 112, 20, Color("#F4D58B"))

	if not pickups.is_empty():
		draw_centered_text(
			"PRESS E NEAR A PART OR GUN TO PICK IT UP",
			145,
			14,
			Color("#A7DCCF")
		)


func draw_centered_text(
	text: String,
	y: float,
	size: int,
	color: Color
) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(0, y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		SCREEN_WIDTH,
		size,
		color
	)
