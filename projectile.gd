extends Node2D
# Projétil genérico (jogador ou inimigo).

var main
var vel := Vector2.ZERO
var dmg := 10.0
var team := "player"
var pierce := 0
var radius := 0.0
var kb := 60.0
var life := 2.5
var size := Vector2(26, 10)
var col := Color.WHITE
var crit := false
var hit_list: Array = []

func _ready() -> void:
	var v := ColorRect.new()
	v.size = size
	v.position = -size / 2.0
	v.color = col
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	z_index = 20
	rotation = vel.angle()

func _physics_process(delta: float) -> void:
	if main.state != "mission":
		queue_free()
		return
	position += vel * delta
	life -= delta
	if life <= 0.0 or position.x < 0.0 or position.x > main.room_width or position.y < -300.0:
		queue_free()
		return
	if position.y > 612.0:
		if radius > 0.0 and team == "player":
			_explode()
		else:
			queue_free()
		return
	var r := Rect2(position - size / 2.0, size)
	if team == "player":
		for e in get_tree().get_nodes_in_group("enemies"):
			if hit_list.has(e):
				continue
			if r.intersects(e.get_rect()):
				hit_list.append(e)
				e.take_hit(dmg, signf(vel.x), kb, crit, false)
				if radius > 0.0:
					_explode()
					return
				if pierce <= 0:
					queue_free()
					return
				pierce -= 1
	else:
		var p = main.player
		if p != null and not p.dead and r.intersects(p.get_rect()):
			p.take_hit(dmg, position.x - signf(vel.x), kb)
			queue_free()

func _explode() -> void:
	var area := Rect2(position - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
	main.spawn_fx(area, Color(col.r, col.g, col.b, 0.45), 0.2)
	for e in get_tree().get_nodes_in_group("enemies"):
		if hit_list.has(e):
			continue
		if area.intersects(e.get_rect()):
			e.take_hit(dmg * 0.8, signf(e.global_position.x - position.x), kb, false, false)
	main.hitstop(0.05)
	queue_free()
