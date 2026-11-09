extends CharacterBody2D
# Jogador: movimento, combo, habilidades, esquiva e dano recebido.

const GRAVITY := 1600.0
const JUMP_V := 720.0
const SIZE := Vector2(36, 64)

var main
var cls: Dictionary = {}
var level := 1
var st: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var energy := 1.0
var facing := 1
var combo_idx := 0
var combo_timer := 0.0
var lock := 0.0
var buffer_atk := 0.0
var buffer_jump := 0.0
var coyote := 0.0
var invuln := 0.0
var dodge_cd := 0.0
var shield_t := 0.0
var dash_t := 0.0
var dash_v := 0.0
var dash_hit: Dictionary = {}
var dash_list: Array = []
var cds: Array = [0.0, 0.0, 0.0]
var pending: Array = []
var dead := false
var body: ColorRect
var weapon: ColorRect
var aura: ColorRect
var cam: Camera2D

func setup(main_ref, class_id: String, profile: Dictionary) -> void:
	main = main_ref
	cls = Data.classes[class_id]
	level = int(profile.level)
	st = Data.calc_stats(class_id)
	max_hp = float(st.hp)
	hp = max_hp
	energy = float(st.energy)
	collision_layer = 2
	collision_mask = 1
	z_index = 10
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = SIZE
	cs.shape = sh
	add_child(cs)
	body = ColorRect.new()
	body.size = SIZE
	body.position = -SIZE / 2.0
	body.color = Color.html(cls.color)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	weapon = ColorRect.new()
	weapon.size = Vector2(28, 8)
	weapon.color = Color(0.9, 0.9, 0.9)
	weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weapon)
	aura = ColorRect.new()
	aura.size = SIZE + Vector2(20, 20)
	aura.position = -aura.size / 2.0
	aura.color = Color(0.4, 0.9, 1.0, 0.35)
	aura.visible = false
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(aura)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_bottom = 720
	add_child(cam)
	cam.make_current()

func get_rect() -> Rect2:
	return Rect2(global_position - SIZE / 2.0, SIZE)

func reset_to(pos: Vector2) -> void:
	position = pos
	velocity = Vector2.ZERO
	pending.clear()
	lock = 0.0
	dash_t = 0.0
	cam.reset_smoothing()

func respawn(pos: Vector2) -> void:
	dead = false
	visible = true
	hp = max_hp * 0.6
	energy = float(st.energy)
	invuln = 2.0
	reset_to(pos)

func _physics_process(delta: float) -> void:
	if dead or main.state != "mission":
		return
	_timers(delta)
	var on_floor := is_on_floor()
	coyote = 0.1 if on_floor else coyote - delta
	if not on_floor:
		velocity.y += GRAVITY * delta
	var dir := Input.get_axis("move_left", "move_right")
	if dash_t > 0.0:
		velocity.x = dash_v
		velocity.y = 0.0
		_dash_hits()
	elif lock > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	else:
		velocity.x = dir * float(st.speed)
		if dir != 0.0:
			facing = int(signf(dir))
	if Input.is_action_just_pressed("jump"):
		buffer_jump = 0.12
	if buffer_jump > 0.0 and coyote > 0.0 and dash_t <= 0.0:
		velocity.y = -JUMP_V
		coyote = 0.0
		buffer_jump = 0.0
	if Input.is_action_just_released("jump") and velocity.y < -200.0:
		velocity.y *= 0.5
	if Input.is_action_just_pressed("attack"):
		buffer_atk = 0.2
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0.0 and dash_t <= 0.0:
		_dodge()
	for i in 3:
		if Input.is_action_just_pressed("skill%d" % (i + 1)):
			_skill(i)
	if buffer_atk > 0.0 and lock <= 0.0 and dash_t <= 0.0:
		buffer_atk = 0.0
		_basic()
	energy = minf(float(st.energy), energy + float(st.regen) * delta)
	move_and_slide()
	_update_visual()

func _timers(delta: float) -> void:
	for i in 3:
		cds[i] = maxf(0.0, cds[i] - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	lock = maxf(0.0, lock - delta)
	buffer_atk -= delta
	buffer_jump -= delta
	invuln -= delta
	shield_t -= delta
	dash_t -= delta
	combo_timer -= delta
	if combo_timer <= 0.0:
		combo_idx = 0
	var due: Array = []
	for p in pending:
		p.t -= delta
		if p.t <= 0.0:
			due.append(p)
	if not due.is_empty():
		pending = pending.filter(func(x): return x.t > 0.0)
		for p in due:
			p.fn.call()

# ---------- Ataques ----------
func _face_input() -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = int(signf(dir))

func _basic() -> void:
	var steps: Array = cls.combo
	var step: Dictionary = steps[combo_idx]
	_face_input()
	lock = float(step.dur)
	combo_timer = float(step.dur) + float(cls.reset)
	combo_idx = (combo_idx + 1) % steps.size()
	velocity.x = facing * float(step.get("adv", 0))
	pending.append({"t": float(step.startup), "fn": func(): _do_hit(step)})

func _do_hit(s: Dictionary) -> void:
	if dead:
		return
	match s.type:
		"melee":
			_melee(s)
		"projectile":
			_shoot(s)
		"aoe":
			_aoe(s)

func _roll(mult: float) -> Array:
	var d: float = float(st.atk) * mult * randf_range(0.92, 1.08)
	var crit := randf() * 100.0 < minf(float(st.crit), 60.0)
	if crit:
		d *= 1.6
	return [d, crit]

func _damage_rect(rect: Rect2, s: Dictionary) -> void:
	var hit := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if rect.intersects(e.get_rect()):
			var r := _roll(float(s.dmg))
			e.take_hit(r[0], signf(e.global_position.x - global_position.x), float(s.get("kb", 100)), r[1], s.get("launch", false))
			hit = true
	if hit:
		main.hitstop(0.08 if float(s.dmg) > 1.5 else 0.04)

func _melee(s: Dictionary) -> void:
	var rng: float = float(s.range)
	var rect: Rect2
	if s.get("both", false):
		rect = Rect2(global_position + Vector2(-rng, -45), Vector2(rng * 2.0, 90))
	elif facing > 0:
		rect = Rect2(global_position + Vector2(0, -45), Vector2(rng, 90))
	else:
		rect = Rect2(global_position + Vector2(-rng, -45), Vector2(rng, 90))
	main.spawn_fx(rect, Color(1, 1, 1, 0.35), 0.12)
	_damage_rect(rect, s)

func _aoe(s: Dictionary) -> void:
	var c := global_position + Vector2(facing * float(s.ox), 0)
	var rect := Rect2(c - Vector2(float(s.w), float(s.h)) / 2.0, Vector2(float(s.w), float(s.h)))
	main.spawn_fx(rect, Color.html(cls.color).lightened(0.3) * Color(1, 1, 1, 0.5), 0.25)
	_damage_rect(rect, s)

func _shoot(s: Dictionary) -> void:
	var cnt := int(s.get("count", 1))
	var spread := float(s.get("spread", 0.0))
	for i in cnt:
		var ang := (i - (cnt - 1) / 2.0) * spread
		var p := preload("res://projectile.gd").new()
		p.main = main
		p.team = "player"
		p.vel = Vector2(facing * float(s.speed), 0.0).rotated(ang * facing)
		var r := _roll(float(s.dmg))
		p.dmg = r[0]
		p.crit = r[1]
		p.pierce = int(s.get("pierce", 0))
		p.radius = float(s.get("radius", 0.0))
		p.kb = float(s.get("kb", 60))
		p.col = Color.html(cls.color).lightened(0.35)
		p.size = Vector2(float(s.get("pw", 26)), float(s.get("ph", 10)))
		p.position = global_position + Vector2(facing * 24.0, -8.0)
		main.room_node.add_child(p)

# ---------- Habilidades e esquiva ----------
func _skill(i: int) -> void:
	if i >= cls.skills.size() or dash_t > 0.0:
		return
	var s: Dictionary = cls.skills[i]
	if level < int(s.unlock):
		main.toast("%s libera no nível %d" % [s.name, int(s.unlock)])
		return
	if cds[i] > 0.0 or energy < float(s.cost):
		return
	energy -= float(s.cost)
	cds[i] = float(s.cd)
	_face_input()
	pending.clear()
	match s.type:
		"melee", "projectile", "aoe":
			lock = float(s.get("dur", 0.4))
			pending.append({"t": float(s.get("startup", 0.1)), "fn": func(): _do_hit(s)})
		"dash":
			dash_t = float(s.dur)
			dash_v = facing * float(s.dist) / float(s.dur)
			dash_hit = s
			dash_list = []
			invuln = maxf(invuln, float(s.dur) * 0.6)
			lock = float(s.dur)
		"backstep":
			dash_t = 0.2
			dash_v = -facing * float(s.dist) / 0.2
			dash_hit = {}
			invuln = maxf(invuln, 0.35)
			lock = 0.2
		"shield":
			shield_t = float(s.duration)
			main.spawn_text(global_position + Vector2(0, -50), "Escudo!", Color(0.5, 0.95, 1.0), 24)

func _dodge() -> void:
	_face_input()
	dash_t = 0.22
	dash_v = facing * 590.0
	dash_hit = {}
	invuln = maxf(invuln, 0.3)
	dodge_cd = 0.9
	lock = 0.22
	pending.clear()

func _dash_hits() -> void:
	if dash_hit.is_empty():
		return
	var r := get_rect().grow(10.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if dash_list.has(e):
			continue
		if r.intersects(e.get_rect()):
			dash_list.append(e)
			var rr := _roll(float(dash_hit.dmg))
			e.take_hit(rr[0], float(facing), float(dash_hit.get("kb", 200)), rr[1], false)
			main.hitstop(0.06)

# ---------- Dano ----------
func take_hit(raw: float, from_x: float, kb: float = 150.0) -> void:
	if dead or invuln > 0.0 or main.state != "mission":
		return
	var d: float = raw * (1.0 - float(st.def) / (float(st.def) + 60.0))
	if shield_t > 0.0:
		d *= 0.25
	hp -= d
	invuln = 0.7 if shield_t <= 0.0 else 0.35
	main.hits_taken += 1
	main.combo = 0
	main.spawn_text(global_position + Vector2(0, -50), str(int(d)), Color(1, 0.3, 0.3), 26)
	var dirn := signf(global_position.x - from_x)
	if dirn == 0.0:
		dirn = 1.0
	velocity.x = dirn * kb
	lock = 0.2
	pending.clear()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		visible = false
		main.on_player_died()

func _update_visual() -> void:
	weapon.position = Vector2(14.0 if facing > 0 else -42.0, -4.0)
	weapon.color = Color(1, 0.95, 0.5) if lock > 0.0 else Color(0.9, 0.9, 0.9)
	aura.visible = shield_t > 0.0
	var blink := invuln > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0
	body.modulate.a = 0.45 if blink else 1.0
