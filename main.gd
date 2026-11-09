extends Node2D
# Gerenciador do jogo: menus, missão, salas, HUD, controles de toque e resultados.

const FLOOR_Y := 620.0
const MAX_INV := 30

var state := "menu"
var room_node: Node2D
var ui: CanvasLayer
var hud: CanvasLayer
var touch: CanvasLayer
var player: CharacterBody2D
var cur_class := ""
var room_idx := 0
var room_width := 2200.0
var waves_left: Array = []
var wave_timer := 0.8
var room_cleared := false
var is_boss_room := false
var portal_open := false
var portal_rect := Rect2()
var portal_node: ColorRect
var changing_room := false
var mission_time := 0.0
var hits_taken := 0
var deaths := 0
var lives := 3
var gained_xp := 0
var gained_gold := 0
var kills := 0
var max_combo := 0
var combo := 0
var combo_timer := 0.0
var boss_ref = null
var refs: Dictionary = {}
var toast_t := 0.0
var inv_sel := -1

func _ready() -> void:
	randomize()
	_setup_input()
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	touch = CanvasLayer.new()
	touch.layer = 6
	add_child(touch)
	show_menu()

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP], "attack": [KEY_J], "dodge": [KEY_SHIFT],
		"skill1": [KEY_K], "skill2": [KEY_L], "skill3": [KEY_SEMICOLON]
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)

# ================= Helpers de UI =================
func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

func _bg(col: Color) -> void:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(r)

func _center_box() -> VBoxContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	c.add_child(v)
	return v

func _label(text: String, size: int = 24, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, cb: Callable, min_size: Vector2 = Vector2(360, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 26)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func profile() -> Dictionary:
	return Data.save.profiles[cur_class]

# ================= Menus =================
func show_menu() -> void:
	state = "menu"
	_clear_mission()
	_clear(ui)
	_bg(Color(0.07, 0.08, 0.12))
	var box := _center_box()
	box.add_child(_label("LENDAS DE AÇO", 60, Color(1, 0.85, 0.4)))
	box.add_child(_label("Protótipo offline — escolha seu personagem", 24))
	for id in Data.classes.keys():
		var c: Dictionary = Data.classes[id]
		var prof: Dictionary = Data.save.profiles[id]
		box.add_child(_button("%s (Nv %d) — %s" % [c.name, int(prof.level), c.desc], func(): select_class(id), Vector2(760, 80)))
	var rb := _button("Apagar progresso", Callable(), Vector2(360, 50))
	rb.pressed.connect(_on_reset.bind(rb))
	box.add_child(rb)

func _on_reset(btn: Button) -> void:
	if btn.text == "Apagar progresso":
		btn.text = "Toque de novo para confirmar"
	else:
		Data.reset_save()
		show_menu()

func select_class(id: String) -> void:
	cur_class = id
	Data.save.last_class = id
	show_hub()

func show_hub() -> void:
	state = "hub"
	_clear(ui)
	_bg(Color(0.08, 0.1, 0.14))
	var c: Dictionary = Data.classes[cur_class]
	var prof := profile()
	var lv := int(prof.level)
	var box := _center_box()
	box.add_child(_label("%s — Nível %d" % [c.name, lv], 44, Color.html(c.color)))
	if lv < Data.MAX_LEVEL:
		box.add_child(_label("XP %d / %d      Ouro: %d" % [int(prof.xp), Data.xp_needed(lv), int(Data.save.gold)], 24))
	else:
		box.add_child(_label("Nível máximo      Ouro: %d" % int(Data.save.gold), 24))
	var st := Data.calc_stats(cur_class)
	box.add_child(_label("Vida %d   Energia %d   Ataque %d   Defesa %d   Crítico %d%%" % [int(st.hp), int(st.energy), int(st.atk), int(st.def), int(st.crit)], 22))
	for s in c.skills:
		var ok: bool = lv >= int(s.unlock)
		box.add_child(_label("%s %s%s" % ["•" if ok else "x", s.name, "" if ok else "  (libera no nível %d)" % int(s.unlock)], 20, Color.WHITE if ok else Color(0.6, 0.6, 0.6)))
	box.add_child(_button("Iniciar missão: " + str(Data.mission.name), start_mission, Vector2(560, 76)))
	box.add_child(_label("Equipamento: %d/3 (equipa o melhor automaticamente)" % prof.equipped.values().filter(func(x): return x.has("stats")).size(), 20, Color(0.8, 0.8, 0.8)))
	box.add_child(_button("Trocar personagem", show_menu, Vector2(560, 64)))

# ================= Inventário =================
func _item_text(it: Dictionary) -> String:
	var parts: Array = []
	for k in it.stats:
		parts.append("%s +%d" % [Data.items.stat_names[k], int(it.stats[k])])
	return "[%s] %s: %s" % [it.label, it.name, ", ".join(parts)]

func show_inventory() -> void:
	state = "inventory"
	_clear(ui)
	_bg(Color(0.08, 0.1, 0.14))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	ui.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	margin.add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 8)
	h.add_child(left)
	var prof := profile()
	left.add_child(_label("Equipado — %s (Ouro: %d)" % [Data.classes[cur_class].name, int(Data.save.gold)], 24, Color(1, 0.85, 0.4)))
	for slot in ["weapon", "armor", "accessory"]:
		var it: Dictionary = prof.equipped[slot]
		var sl: String = Data.items.slots[slot].label
		var l := _label("%s: %s" % [sl, _item_text(it) if it.has("stats") else "(vazio)"], 18, Color.html(it.color) if it.has("color") else Color(0.6, 0.6, 0.6))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		left.add_child(l)
	var detail := _label("Toque em um item da mochila.", 20)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(500, 130)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(detail)
	var eq := _button("Equipar", _equip_selected, Vector2(240, 56))
	var sell := _button("Vender", _sell_selected, Vector2(240, 56))
	var row := HBoxContainer.new()
	row.add_child(eq)
	row.add_child(sell)
	left.add_child(row)
	left.add_child(_button("Voltar", show_hub, Vector2(300, 56)))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var inv: Array = Data.save.inventory
	right.add_child(_label("Mochila (%d/%d)" % [inv.size(), MAX_INV], 24))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(600, 540)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 20)
	for i in inv.size():
		var it: Dictionary = inv[i]
		list.add_item(_item_text(it))
		list.set_item_custom_fg_color(i, Color.html(it.color))
	list.item_selected.connect(_on_inv_selected.bind(detail))
	right.add_child(list)
	inv_sel = -1

func _on_inv_selected(idx: int, detail: Label) -> void:
	inv_sel = idx
	var it: Dictionary = Data.save.inventory[idx]
	var old: Dictionary = profile().equipped[it.slot]
	var diff: float = Data.power(it) - Data.power(old)
	var verdict := "MELHOR (+%d poder)" % int(diff) if diff > 0.0 else ("PIOR (%d poder)" % int(diff) if diff < 0.0 else "IGUAL")
	detail.text = "%s\nValor de venda: %d ouro\nComparado ao equipado: %s" % [_item_text(it), Data.price(it), verdict]
	detail.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if diff > 0.0 else (Color(1, 0.5, 0.5) if diff < 0.0 else Color.WHITE))

func _equip_selected() -> void:
	var inv: Array = Data.save.inventory
	if inv_sel < 0 or inv_sel >= inv.size():
		return
	var it: Dictionary = inv[inv_sel]
	var prof := profile()
	var old: Dictionary = prof.equipped[it.slot]
	prof.equipped[it.slot] = it
	inv.remove_at(inv_sel)
	if old.has("stats"):
		inv.append(old)
	Data.write_save()
	show_inventory()

func _sell_selected() -> void:
	var inv: Array = Data.save.inventory
	if inv_sel < 0 or inv_sel >= inv.size():
		return
	Data.save.gold = int(Data.save.gold) + Data.price(inv[inv_sel])
	inv.remove_at(inv_sel)
	Data.write_save()
	show_inventory()

# ================= Missão =================
func start_mission() -> void:
	_clear(ui)
	state = "mission"
	Engine.time_scale = 1.0
	room_idx = 0
	mission_time = 0.0
	hits_taken = 0
	deaths = 0
	lives = 3
	gained_xp = 0
	gained_gold = 0
	kills = 0
	combo = 0
	max_combo = 0
	var pl := preload("res://player.gd").new()
	add_child(pl)
	pl.setup(self, cur_class, profile())
	player = pl
	_build_hud()
	_build_touch()
	_build_room(0)

func _solid(r: Rect2, col: Color, one_way: bool = false) -> void:
	var b := StaticBody2D.new()
	b.position = r.position
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.size / 2.0
	cs.one_way_collision = one_way
	b.add_child(cs)
	var v := ColorRect.new()
	v.size = r.size
	v.color = col
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	if col.a > 0.0:
		var top := ColorRect.new()
		top.size = Vector2(r.size.x, 5)
		top.color = col.lightened(0.45)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(top)
	room_node.add_child(b)

func _build_room(idx: int) -> void:
	changing_room = true
	if room_node:
		room_node.queue_free()
	room_node = Node2D.new()
	add_child(room_node)
	move_child(room_node, 0)
	var room: Dictionary = Data.mission.rooms[idx]
	is_boss_room = room.has("boss")
	room_width = 1500.0 if is_boss_room else 2200.0
	room_cleared = false
	portal_open = false
	portal_node = null
	boss_ref = null
	# Fundo (decoração; não tem colisão)
	var bgc := Color.html(room.bg)
	var bg := ColorRect.new()
	bg.position = Vector2(0, -300)
	bg.size = Vector2(room_width, 1100)
	bg.color = bgc
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_node.add_child(bg)
	for i in 14:
		var col := ColorRect.new()
		var w := 60.0 + (i % 3) * 40.0
		var hgt := 220.0 + (i % 4) * 70.0
		col.size = Vector2(w, hgt)
		col.position = Vector2(i * room_width / 14.0 + 20.0, FLOOR_Y - hgt)
		col.color = bgc.lightened(0.08 + 0.04 * (i % 3))
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room_node.add_child(col)
	# Camada de colisão
	_solid(Rect2(0, FLOOR_Y, room_width, 120), Color.html(room.ground))
	_solid(Rect2(-60, -1000, 60, 2200), Color(0, 0, 0, 0))
	_solid(Rect2(room_width, -1000, 60, 2200), Color(0, 0, 0, 0))
	for pl in room.platforms:
		_solid(Rect2(float(pl[0]), float(pl[1]), float(pl[2]), 18), Color.html(room.plat), true)
	if not is_boss_room:
		portal_node = ColorRect.new()
		portal_node.size = Vector2(70, 140)
		portal_node.position = Vector2(room_width - 120.0, FLOOR_Y - 140.0)
		portal_node.color = Color(0.5, 0.1, 0.1, 0.9)
		portal_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room_node.add_child(portal_node)
		portal_rect = Rect2(portal_node.position, portal_node.size)
		waves_left = (room.waves as Array).duplicate(true)
		wave_timer = 0.8
	else:
		waves_left = []
		boss_ref = spawn_monster(room.boss, Vector2(room_width - 350.0, 400.0))
	player.cam.limit_right = int(room_width)
	player.reset_to(Vector2(120, 560))
	changing_room = false
	toast(room.name)

func spawn_monster(id: String, pos: Vector2):
	var e := preload("res://enemy.gd").new()
	room_node.add_child(e)
	e.setup(self, id, Data.monsters[id], pos)
	return e

func _spawn_wave() -> void:
	var w: Array = waves_left.pop_front()
	for id in w:
		var side := 1.0 if randf() > 0.5 else -1.0
		var x := clampf(player.global_position.x + side * randf_range(450.0, 800.0), 150.0, room_width - 150.0)
		var y := 300.0 if Data.monsters[id].get("flying", false) else 450.0
		spawn_monster(id, Vector2(x, y))
	wave_timer = -1.0

func _open_portal() -> void:
	room_cleared = true
	portal_open = true
	if portal_node:
		portal_node.color = Color(0.2, 1.0, 0.6, 0.9)
	toast("Portal aberto! Siga para a direita.")

func _next_room() -> void:
	changing_room = true
	room_idx += 1
	var heal := 0.25
	if room_idx >= Data.mission.rooms.size() - 1:
		heal = 0.5
	player.hp = minf(player.max_hp, player.hp + player.max_hp * heal)
	player.energy = float(player.st.energy)
	_build_room(room_idx)

func _process(delta: float) -> void:
	if state != "mission" or player == null:
		return
	mission_time += delta
	combo_timer -= delta
	if combo_timer <= 0.0:
		combo = 0
	toast_t -= delta
	if not changing_room and not is_boss_room and not room_cleared:
		var alive := get_tree().get_nodes_in_group("enemies").size()
		if alive == 0:
			if wave_timer < 0.0:
				wave_timer = 1.0
			wave_timer -= delta
			if wave_timer <= 0.0:
				if waves_left.size() > 0:
					_spawn_wave()
				else:
					_open_portal()
	if portal_open and not changing_room and not player.dead and player.get_rect().intersects(portal_rect):
		_next_room()
	_update_hud()

# ================= Eventos de combate =================
func register_hit() -> void:
	combo += 1
	combo_timer = 2.0
	max_combo = maxi(max_combo, combo)

func on_enemy_died(e) -> void:
	kills += 1
	gained_xp += e.xp
	gained_gold += e.gold
	if e.is_boss:
		hitstop(0.2)
		toast("Chefe derrotado!")
		get_tree().create_timer(2.0).timeout.connect(_finish_mission.bind(true))

func on_player_died() -> void:
	deaths += 1
	lives -= 1
	combo = 0
	if lives <= 0:
		toast("Derrota...")
		get_tree().create_timer(1.2).timeout.connect(_finish_mission.bind(false))
	else:
		toast("Você caiu! Vidas restantes: %d" % lives)
		get_tree().create_timer(1.5).timeout.connect(_respawn_player)

func _respawn_player() -> void:
	if state == "mission" and is_instance_valid(player) and player.dead:
		player.respawn(Vector2(120, 560))

func hitstop(t: float) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0

func spawn_fx(r: Rect2, col: Color, dur: float = 0.15) -> void:
	if room_node == null:
		return
	var f := ColorRect.new()
	f.position = r.position
	f.size = r.size
	f.color = col
	f.z_index = 50
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_node.add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "modulate:a", 0.0, dur)
	tw.tween_callback(f.queue_free)

func spawn_text(pos: Vector2, text: String, col: Color, size: int = 22) -> void:
	if room_node == null:
		return
	var l := Label.new()
	l.text = text
	l.position = pos - Vector2(20, 0)
	l.z_index = 100
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	room_node.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", pos.y - 50.0, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func toast(t: String) -> void:
	if refs.has("toast"):
		refs.toast.text = t
		toast_t = 2.5

# ================= HUD e controles de toque =================
func _view_w() -> float:
	return get_viewport().get_visible_rect().size.x

func _hud_bar(pos: Vector2, sz: Vector2, col: Color) -> Dictionary:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = sz
	bg.color = Color(0, 0, 0, 0.6)
	var fill := ColorRect.new()
	fill.position = pos
	fill.size = sz
	fill.color = col
	hud.add_child(bg)
	hud.add_child(fill)
	return {"bg": bg, "fill": fill, "w": sz.x}

func _set_bar(b: Dictionary, ratio: float) -> void:
	var f: ColorRect = b.fill
	f.size = Vector2(float(b.w) * clampf(ratio, 0.0, 1.0), f.size.y)

func _hud_label(pos: Vector2, size: int, width: float = 0.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
		l.size = Vector2(width, 0)
	hud.add_child(l)
	return l

func _build_hud() -> void:
	_clear(hud)
	refs = {}
	var vw := _view_w()
	refs.hp = _hud_bar(Vector2(20, 20), Vector2(320, 26), Color(0.85, 0.2, 0.2))
	refs.en = _hud_bar(Vector2(20, 52), Vector2(320, 16), Color(0.25, 0.55, 1.0))
	refs.hp_t = _hud_label(Vector2(26, 18), 18)
	refs.lv = _hud_label(Vector2(20, 72), 18)
	refs.enemies = _hud_label(Vector2(vw / 2.0 - 200.0, 8), 24, 400.0, HORIZONTAL_ALIGNMENT_CENTER)
	refs.obj = _hud_label(Vector2(vw - 600.0, 16), 20, 410.0, HORIZONTAL_ALIGNMENT_RIGHT)
	refs.combo = _hud_label(Vector2(20, 280), 44)
	refs.toast = _hud_label(Vector2(vw / 2.0 - 300.0, 120), 32, 600.0, HORIZONTAL_ALIGNMENT_CENTER)
	refs.boss = _hud_bar(Vector2(vw / 2.0 - 300.0, 48), Vector2(600, 20), Color(0.75, 0.15, 0.5))
	refs.boss_l = _hud_label(Vector2(vw / 2.0 - 300.0, 66), 18, 600.0, HORIZONTAL_ALIGNMENT_CENTER)
	var ex := Button.new()
	ex.text = "Sair"
	ex.position = Vector2(vw - 180.0, 10)
	ex.custom_minimum_size = Vector2(160, 48)
	ex.add_theme_font_size_override("font_size", 22)
	ex.pressed.connect(func(): _finish_mission(false))
	hud.add_child(ex)

func _touch_btn(action: String, center: Vector2, sz: Vector2, text: String, col: Color) -> Label:
	var b := TouchScreenButton.new()
	b.action = action
	b.position = center
	var sh := RectangleShape2D.new()
	sh.size = sz
	b.shape = sh
	var bgc := ColorRect.new()
	bgc.size = sz
	bgc.position = -sz / 2.0
	bgc.color = col
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bgc)
	var l := Label.new()
	l.text = text
	l.size = sz
	l.position = -sz / 2.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	touch.add_child(b)
	return l

func _build_touch() -> void:
	_clear(touch)
	var vw := _view_w()
	var dx := vw - 1280.0
	var grey := Color(1, 1, 1, 0.18)
	_touch_btn("move_left", Vector2(110, 610), Vector2(140, 140), "<", grey)
	_touch_btn("move_right", Vector2(270, 610), Vector2(140, 140), ">", grey)
	_touch_btn("attack", Vector2(1175 + dx, 625), Vector2(170, 150), "ATAQUE", Color(1, 0.4, 0.3, 0.35))
	_touch_btn("jump", Vector2(1010 + dx, 640), Vector2(120, 120), "PULO", Color(0.4, 0.8, 1, 0.3))
	_touch_btn("dodge", Vector2(875 + dx, 655), Vector2(90, 90), "ESQ", Color(0.8, 0.8, 0.4, 0.3))
	var lbls: Array = []
	var skills: Array = Data.classes[cur_class].skills
	for i in 3:
		lbls.append(_touch_btn("skill%d" % (i + 1), Vector2(1215 + dx, 295 + i * 95), Vector2(90, 85), str(skills[i].short), Color.html(Data.classes[cur_class].color) * Color(1, 1, 1, 0.45)))
	refs.skill_lbls = lbls

func _update_hud() -> void:
	var p = player
	if p == null or not refs.has("hp"):
		return
	_set_bar(refs.hp, p.hp / p.max_hp)
	_set_bar(refs.en, p.energy / float(p.st.energy))
	refs.hp_t.text = "%d / %d" % [int(p.hp), int(p.max_hp)]
	refs.lv.text = "%s  Nv %d   Vidas: %d" % [Data.classes[cur_class].name, p.level, lives]
	var alive := get_tree().get_nodes_in_group("enemies").size()
	if is_boss_room:
		refs.enemies.text = "CHEFE"
		refs.obj.text = "Derrote o chefe"
	else:
		refs.enemies.text = "Inimigos: %d   Ondas restantes: %d" % [alive, waves_left.size()]
		refs.obj.text = "Vá ao portal (direita)" if room_cleared else "Elimine os inimigos"
	refs.combo.text = "%d HITS" % combo if combo >= 2 else ""
	var tl: Label = refs.toast
	tl.modulate.a = clampf(toast_t, 0.0, 1.0)
	var show_boss: bool = boss_ref != null and is_instance_valid(boss_ref) and not boss_ref.dead
	for k in ["bg", "fill"]:
		(refs.boss[k] as ColorRect).visible = show_boss
	refs.boss_l.visible = show_boss
	if show_boss:
		_set_bar(refs.boss, boss_ref.hp / boss_ref.max_hp)
		refs.boss_l.text = "%s  (Fase %d)" % [Data.monsters[boss_ref.id].name, boss_ref.phase]
	var skills: Array = Data.classes[cur_class].skills
	var lbls: Array = refs.get("skill_lbls", [])
	for i in lbls.size():
		var l: Label = lbls[i]
		var s: Dictionary = skills[i]
		if p.level < int(s.unlock):
			l.text = "Nv %d" % int(s.unlock)
			l.modulate = Color(1, 1, 1, 0.4)
		elif p.cds[i] > 0.0:
			l.text = "%.1f" % p.cds[i]
			l.modulate = Color(1, 1, 1, 0.5)
		else:
			l.text = str(s.short)
			l.modulate = Color(1, 1, 1, 1.0) if p.energy >= float(s.cost) else Color(1, 1, 1, 0.5)

# ================= Fim da missão =================
func _clear_mission() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null
	if room_node != null and is_instance_valid(room_node):
		room_node.queue_free()
	room_node = null
	if hud:
		_clear(hud)
	if touch:
		_clear(touch)
	refs = {}
	boss_ref = null
	Engine.time_scale = 1.0

func _finish_mission(victory: bool) -> void:
	if state != "mission":
		return
	state = "results"
	var score: float = 100.0 - deaths * 20.0 - hits_taken * 2.0 - maxf(0.0, mission_time - 420.0) / 6.0
	var grade := "-"
	if victory:
		if score >= 85.0:
			grade = "S"
		elif score >= 70.0:
			grade = "A"
		elif score >= 50.0:
			grade = "B"
		else:
			grade = "C"
	var mult := 0.4
	if victory:
		mult = float(Data.mission.grade_multiplier[grade])
	var xp := int(gained_xp * mult)
	var gold := int(gained_gold * mult)
	var prof := profile()
	var lv_before := int(prof.level)
	Data.add_xp(prof, xp)
	Data.save.gold = int(Data.save.gold) + gold
	var lines: Array = []
	if victory:
		var n: int = int(Data.mission.drops.base) + (1 if grade == "S" else 0)
		for i in n:
			var it := Data.roll_item(int(prof.level), float(Data.mission.drops.boss_bonus))
			var cur_it: Dictionary = prof.equipped[it.slot]
			if Data.power(it) > Data.power(cur_it):
				prof.equipped[it.slot] = it
				lines.append(["EQUIPADO: " + _item_text(it), Color.html(it.color)])
				if cur_it.has("stats"):
					Data.save.gold = int(Data.save.gold) + Data.price(cur_it)
			else:
				var pr := Data.price(it)
				Data.save.gold = int(Data.save.gold) + pr
				lines.append(["%s (vendido +%d ouro)" % [_item_text(it), pr], Color(0.7, 0.7, 0.7)])
	Data.write_save()
	var t := mission_time
	var stats_text := "Tempo %d:%02d   Combo máx. %d   Golpes recebidos %d   Quedas %d   Abates %d" % [int(t) / 60, int(t) % 60, max_combo, hits_taken, deaths, kills]
	var lv_after := int(prof.level)
	_clear_mission()
	_clear(ui)
	_bg(Color(0.07, 0.08, 0.12))
	var box := _center_box()
	box.add_child(_label("VITÓRIA!" if victory else "MISSÃO ENCERRADA", 52, Color(1, 0.85, 0.4) if victory else Color(1, 0.5, 0.5)))
	box.add_child(_label("Nota: %s" % grade, 44))
	box.add_child(_label(stats_text, 22))
	box.add_child(_label("+%d XP    +%d ouro" % [xp, gold], 28, Color(0.6, 1, 0.6)))
	if lv_after > lv_before:
		box.add_child(_label("NÍVEL %d!" % lv_after, 36, Color(1, 0.9, 0.3)))
	for ln in lines:
		box.add_child(_label(ln[0], 20, ln[1]))
	box.add_child(_button("Jogar de novo", start_mission, Vector2(420, 64)))
	box.add_child(_button("Voltar ao hub", show_hub, Vector2(420, 64)))
