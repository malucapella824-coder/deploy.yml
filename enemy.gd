extends CharacterBody2D
# Inimigo/chefe guiado por dados: lista de ataques, fases, telegrafia e janela de punição.

var main
var id := ""
var d: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var size := Vector2(44, 32)
var is_boss := false
var armor := false
var flying := false
var dead := false
var state := "move"   # move, windup, active, recover, stunned
var state_t := 0.0
var cur: Dictionary = {}
var cds: Dictionary = {}
var last_atk := ""
var repeat_count := 0
var spawn_invuln := 0.5
var phase := 1
var facing := -1
var flash_t := 0.0
var hit_done := false
var charge_dir := Vector2.ZERO
var speed_mult := 1.0
var xp := 0
var gold := 0
var atk := 10.0
var move_speed := 60.0
var base_color := Color.WHITE
var body: ColorRect
var warn: ColorRect
var eye: ColorRect
var bar_bg: ColorRect
var bar: ColorRect

func setup(main_ref, monster_id: String, data: Dictionary, pos: Vector2) -> void:
	main = main_ref
	id = monster_id
	d = data
	hp = float(d.hp)
	max_hp = hp
	size = Vector2(float(d.size[0]), float(d.size[1]))
	flying = d.get("flying", false)
	armor = d.get("armor", false)
	is_boss = d.get("boss", false)
	atk = float(d.atk)
	xp = int(d.xp)
	gold = int(d.gold)
	move_speed = float(d.speed)
	base_color = Color.html(d.color)
	position = pos
	collision_layer = 4
	collision_mask = 1
	z_index = 5
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	cs.shape = sh
	add_child(cs)
	warn = ColorRect.new()
	warn.color = Color(1, 0.15, 0.1, 0.3)
	warn.visible = false
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warn)
	body = ColorRect.new()
	body.size = size
	body.position = -size / 2.0
	body.color = base_color
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	eye = ColorRect.new()
	eye.size = Vector2(maxf(8.0, size.x * 0.18), maxf(6.0, size.y * 0.14))
	eye.color = Color(1, 1, 1)
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(eye)
	bar_bg = ColorRect.new()
	bar_bg.size = Vector2(size.x, 5)
	bar_bg.position = Vector2(-size.x / 2.0, -size.y / 2.0 - 12.0)
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.visible = false
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	bar = ColorRect.new()
	bar.size = bar_bg.size
	bar.position = bar_bg.position
	bar.color = Color(0.9, 0.2, 0.2)
	bar.visible = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	add_to_group("enemies")

func get_rect() -> Rect2:
	return Rect2(global_position - size / 2.0, size)

func _physics_process(delta: float) -> void:
	if dead or main.state != "mission":
		return
	var p = main.player
	flash_t -= delta
	spawn_invuln -= delta
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta)
	if not flying:
		velocity.y += 1600.0 * delta
	if p == null or p.dead:
		_stop(delta)
		move_and_slide()
		_update_visual()
		return
	var to_p: Vector2 = p.global_position - global_position
	match state:
		"move":
			_move(to_p)
			_choose_attack(to_p.length() if flying else absf(to_p.x))
		"windup":
			state_t -= delta
			_stop(delta)
			if state_t <= 0.0:
				_execute()
		"active":
			state_t -= delta
			_active()
		"recover", "stunned":
			state_t -= delta
			_stop(delta)
			if state_t <= 0.0:
				state = "move"
	move_and_slide()
	_update_visual()

func _stop(delta: float) -> void:
	if flying:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)

func _move(to_p: Vector2) -> void:
	var dist := absf(to_p.x)
	facing = 1 if to_p.x > 0.0 else -1
	var spd := move_speed * speed_mult
	match d.move:
		"walk":
			velocity.x = facing * spd if dist > float(d.get("stop", 40)) else 0.0
		"kite":
			if dist < float(d.get("kite_min", 300)):
				velocity.x = -facing * spd
			elif dist > float(d.get("kite_max", 450)):
				velocity.x = facing * spd
			else:
				velocity.x = 0.0
		"hover":
			var p = main.player
			var tgt: Vector2 = p.global_position + Vector2(sin(Time.get_ticks_msec() / 600.0) * 160.0, -150.0)
			var dv := tgt - global_position
			velocity = dv.normalized() * spd if dv.length() > 10.0 else Vector2.ZERO

func _choose_attack(dist: float) -> void:
	if spawn_invuln > 0.0:
		return
	var opts: Array = []
	var total := 0.0
	for a in d.attacks:
		if int(a.get("phase", 1)) > phase:
			continue
		if float(cds.get(a.id, 0.0)) > 0.0:
			continue
		if dist < float(a.get("min", 0)) or dist > float(a.get("max", 60)):
			continue
		if a.id == last_atk and repeat_count >= 2:
			continue
		opts.append(a)
		total += float(a.get("w", 1.0))
	if opts.is_empty():
		return
	var roll := randf() * total
	var pick: Dictionary = opts[0]
	for a in opts:
		roll -= float(a.get("w", 1.0))
		if roll <= 0.0:
			pick = a
			break
	repeat_count = repeat_count + 1 if pick.id == last_atk else 1
	last_atk = pick.id
	cur = pick
	cds[pick.id] = float(pick.get("cd", 2.0))
	state = "windup"
	state_t = float(pick.windup)
	velocity.x = 0.0
	_show_warning(pick)

func _melee_rect(r: float) -> Rect2:
	var x: float = size.x / 2.0 if facing > 0 else -size.x / 2.0 - r
	return Rect2(global_position + Vector2(x, -size.y / 2.0), Vector2(r, size.y))

func _slam_rect(radius: float) -> Rect2:
	return Rect2(global_position + Vector2(-radius, size.y / 2.0 - 110.0), Vector2(radius * 2.0, 120.0))

func _show_warning(a: Dictionary) -> void:
	var r := Rect2()
	match a.type:
		"melee":
			r = _melee_rect(float(a.range))
		"slam":
			r = _slam_rect(float(a.radius))
		"charge":
			var ln: float = float(a.speed) * float(a.dur)
			var x: float = size.x / 2.0 if facing > 0 else -size.x / 2.0 - ln
			r = Rect2(global_position + Vector2(x, -size.y / 2.0), Vector2(ln, size.y))
		_:
			warn.visible = false
			return
	warn.position = r.position - global_position
	warn.size = r.size
	warn.visible = true

func _execute() -> void:
	warn.visible = false
	var p = main.player
	match cur.type:
		"melee":
			var r := _melee_rect(float(cur.range))
			main.spawn_fx(r, Color(1, 0.3, 0.2, 0.5), 0.15)
			if r.intersects(p.get_rect()):
				p.take_hit(atk * float(cur.dmg), global_position.x, 220.0)
			_enter_recover()
		"slam":
			var r2 := _slam_rect(float(cur.radius))
			main.spawn_fx(r2, Color(1, 0.5, 0.1, 0.5), 0.25)
			if r2.intersects(p.get_rect()):
				p.take_hit(atk * float(cur.dmg), global_position.x, 280.0)
			_enter_recover()
		"projectile":
			var cnt := int(cur.get("count", 1))
			var spread := float(cur.get("spread", 0.0))
			var aim: Vector2 = (p.global_position - global_position).normalized()
			for i in cnt:
				var ang := (i - (cnt - 1) / 2.0) * spread
				var pr := preload("res://projectile.gd").new()
				pr.main = main
				pr.team = "enemy"
				pr.vel = aim.rotated(ang) * float(cur.speed)
				pr.dmg = atk * float(cur.dmg)
				pr.kb = 160.0
				pr.col = Color(1, 0.45, 0.15)
				pr.size = Vector2(22, 14)
				pr.position = global_position
				main.room_node.add_child(pr)
			_enter_recover()
		"charge":
			state = "active"
			state_t = float(cur.dur)
			charge_dir = Vector2(facing, 0)
			hit_done = false
		"dive":
			state = "active"
			state_t = float(cur.dur)
			charge_dir = (p.global_position - global_position).normalized()
			hit_done = false
		"summon":
			for i in int(cur.count):
				main.spawn_monster(cur.monster, global_position + Vector2(randf_range(-150.0, 150.0), -80.0))
			main.spawn_text(global_position + Vector2(0, -size.y), "Invocação!", Color(1, 0.6, 0.3), 28)
			_enter_recover()

func _active() -> void:
	var p = main.player
	if cur.type == "charge":
		velocity.x = charge_dir.x * float(cur.speed)
	else:
		velocity = charge_dir * float(cur.speed)
	if not hit_done and get_rect().intersects(p.get_rect()):
		hit_done = true
		p.take_hit(atk * float(cur.dmg), global_position.x, 300.0)
	if state_t <= 0.0:
		velocity = Vector2.ZERO
		_enter_recover()

func _enter_recover() -> void:
	state = "recover"
	state_t = float(cur.get("recover", 0.6)) / speed_mult

func _check_phase() -> void:
	var phases: Array = d.get("phases", [])
	if phases.is_empty():
		return
	var ratio := hp / max_hp
	var ph := 1
	for t in phases:
		if ratio < float(t):
			ph += 1
	if ph > phase:
		phase = ph
		var sm: Array = d.get("phase_speed", [])
		if sm.size() >= phase:
			speed_mult = float(sm[phase - 1])
		state = "recover"
		state_t = 1.2
		spawn_invuln = 1.2
		warn.visible = false
		main.spawn_text(global_position + Vector2(0, -size.y), "FASE %d!" % phase, Color(1, 0.4, 0.2), 38)

func take_hit(dmg: float, dir: float, kb: float, crit: bool, launch) -> void:
	if dead or spawn_invuln > 0.0:
		return
	if state == "recover" or state == "stunned":
		dmg *= 1.2   # janela de punição
	hp -= dmg
	flash_t = 0.08
	main.register_hit()
	main.spawn_text(global_position + Vector2(0, -size.y / 2.0 - 10.0), str(int(dmg)), Color(1, 0.85, 0.2) if crit else Color.WHITE, 30 if crit else 22)
	if not armor and not is_boss:
		velocity.x = dir * kb
		if state == "windup" or state == "move":
			state = "stunned"
			state_t = 0.45 if launch else 0.25
			warn.visible = false
		if launch and not flying:
			velocity.y = -300.0
	_check_phase()
	if hp <= 0.0:
		_die()

func _die() -> void:
	dead = true
	remove_from_group("enemies")
	warn.visible = false
	bar.visible = false
	bar_bg.visible = false
	main.on_enemy_died(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)

func _update_visual() -> void:
	if flash_t > 0.0:
		body.color = Color(1, 1, 1)
	elif state == "windup":
		body.color = base_color.lerp(Color(1, 0.8, 0.1), 0.6)
	elif state == "recover" or state == "stunned":
		body.color = base_color.darkened(0.35)
	else:
		body.color = base_color
	eye.position = Vector2(size.x * 0.15 if facing > 0 else -size.x * 0.15 - eye.size.x, -size.y * 0.25)
	var blink := spawn_invuln > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0
	body.modulate.a = 0.4 if blink else 1.0
	if not is_boss and hp < max_hp:
		bar_bg.visible = true
		bar.visible = true
		bar.size = Vector2(bar_bg.size.x * clampf(hp / max_hp, 0.0, 1.0), bar_bg.size.y)
