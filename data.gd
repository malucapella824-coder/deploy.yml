extends Node
# Autoload "Data": carrega os JSON, guarda o save local e gera itens.

const SAVE_PATH := "user://save.json"
const MAX_LEVEL := 10

var classes: Dictionary = {}
var monsters: Dictionary = {}
var items: Dictionary = {}
var mission: Dictionary = {}
var save: Dictionary = {}

func _ready() -> void:
	classes = _load_json("res://classes.json")
	monsters = _load_json("res://monsters.json")
	items = _load_json("res://items.json")
	mission = _load_json("res://mission.json")
	load_save()

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Arquivo não encontrado: " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON inválido: " + path)
		return {}
	return parsed

# ---------- Save ----------
func default_profile() -> Dictionary:
	return {"level": 1, "xp": 0, "equipped": {"weapon": {}, "armor": {}, "accessory": {}}}

func fresh_save() -> Dictionary:
	var s := {"profiles": {}, "inventory": [], "gold": 0, "last_class": ""}
	for id in classes.keys():
		s.profiles[id] = default_profile()
	return s

func load_save() -> void:
	save = fresh_save()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var p = JSON.parse_string(f.get_as_text())
		if typeof(p) == TYPE_DICTIONARY and p.has("profiles"):
			save = p
	for id in classes.keys():
		if not save.profiles.has(id):
			save.profiles[id] = default_profile()

func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))

func reset_save() -> void:
	save = fresh_save()
	write_save()

# ---------- Progressão ----------
func xp_needed(level: int) -> int:
	return 40 + level * level * 18

func add_xp(profile: Dictionary, amount: int) -> int:
	var gained := 0
	profile.xp = int(profile.xp) + amount
	while int(profile.level) < MAX_LEVEL and int(profile.xp) >= xp_needed(int(profile.level)):
		profile.xp = int(profile.xp) - xp_needed(int(profile.level))
		profile.level = int(profile.level) + 1
		gained += 1
	if int(profile.level) >= MAX_LEVEL:
		profile.xp = 0
	return gained

func calc_stats(class_id: String) -> Dictionary:
	var c: Dictionary = classes[class_id]
	var prof: Dictionary = save.profiles[class_id]
	var l: int = int(prof.level) - 1
	var g: Dictionary = c.growth
	var st := {
		"hp": float(c.hp) + float(g.hp) * l,
		"energy": float(c.energy) + float(g.energy) * l,
		"atk": float(c.atk) + float(g.atk) * l,
		"def": float(c.def) + float(g.def) * l,
		"crit": 5.0,
		"regen": float(c.regen),
		"speed": float(c.speed)
	}
	for slot in prof.equipped:
		var it: Dictionary = prof.equipped[slot]
		if it.has("stats"):
			for k in it.stats:
				st[k] = float(st[k]) + float(it.stats[k])
	return st

# ---------- Itens ----------
func _roll_rarity(bonus: float) -> Dictionary:
	var ws: Array = []
	var total := 0.0
	for i in items.rarities.size():
		var w: float = float(items.rarities[i].weight)
		if i >= 2:
			w *= (1.0 + bonus)
		ws.append(w)
		total += w
	var roll := randf() * total
	for i in ws.size():
		roll -= float(ws[i])
		if roll <= 0.0:
			return items.rarities[i]
	return items.rarities[0]

func roll_item(level: int, bonus: float = 0.0) -> Dictionary:
	var slot_ids: Array = items.slots.keys()
	var slot: String = slot_ids.pick_random()
	var s: Dictionary = items.slots[slot]
	var r: Dictionary = _roll_rarity(bonus)
	var scale: float = float(r.mult) * (1.0 + 0.1 * (level - 1))
	var stats := {}
	stats[s.main] = maxi(1, int(round(randi_range(int(s.main_range[0]), int(s.main_range[1])) * scale)))
	var pool: Array = items.sub_stats.keys()
	pool.erase(s.main)
	pool.shuffle()
	for i in int(r.subs):
		var k: String = pool[i]
		var rg: Array = items.sub_stats[k]
		stats[k] = maxi(1, int(round(randi_range(int(rg[0]), int(rg[1])) * scale)))
	var bases: Array = s.bases
	return {"slot": slot, "name": str(bases.pick_random()), "rarity": r.id, "label": r.label, "color": r.color, "stats": stats}

func power(it: Dictionary) -> float:
	if not it.has("stats"):
		return 0.0
	var p := 0.0
	for k in it.stats:
		p += float(it.stats[k]) * float(items.power_weights[k])
	return p

func price(it: Dictionary) -> int:
	return int(power(it) * 1.5) + 3
