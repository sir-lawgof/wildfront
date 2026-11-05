class_name Icons
extends RefCounted
## Procedural 32x32 pixel-art icons for items, prayers, spells and overheads.
## Placeholder art until M11; everything is original and drawn in code.

const S := 32
static var _cache: Dictionary = {}


static func _img() -> Image:
	return Image.create(S, S, false, Image.FORMAT_RGBA8)


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(S):
		for x in range(S):
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				img.set_pixel(x, y, c)


static func _ring(img: Image, cx: float, cy: float, r: float, w: float, c: Color) -> void:
	for y in range(S):
		for x in range(S):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= r and d >= r - w:
				img.set_pixel(x, y, c)


static func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)) * 2.0) + 1
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		var r := int(ceil(w / 2.0))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if Vector2(dx, dy).length() <= w / 2.0 + 0.01:
					_px(img, int(p.x + dx), int(p.y + dy), c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


static func _outline(img: Image, c: Color = Color(0, 0, 0, 0.9)) -> void:
	var src := img.duplicate()
	for y in range(S):
		for x in range(S):
			if src.get_pixel(x, y).a > 0.1:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < S and q.y < S and src.get_pixel(q.x, q.y).a > 0.5:
					img.set_pixel(x, y, c)
					break


# ---------------------------------------------------------------- items

static func item(id: String) -> Texture2D:
	var key := "item:" + id
	if _cache.has(key):
		return _cache[key]
	var it := DB.item(id)
	var img := _img()
	var col := Color.html(str(it.get("color", "#888888")))
	var wood := Color("7a5230")
	var slot := str(it.get("slot", ""))
	var mesh := str(it.get("mesh", ""))
	if slot == "weapon":
		_draw_weapon(img, mesh, col, wood)
	elif slot == "":
		_draw_consumable(img, it, col)
	else:
		_draw_armour(img, slot, str(it.get("armour_class", "")), col)
	_outline(img)
	var t := _tex(img)
	_cache[key] = t
	return t


static func _draw_weapon(img: Image, mesh: String, col: Color, wood: Color) -> void:
	var hi := col.lightened(0.35)
	match mesh:
		"dagger", "knife":
			_line(img, Vector2(10, 22), Vector2(22, 10), 3, col)
			_line(img, Vector2(11, 21), Vector2(20, 12), 1, hi)
			_line(img, Vector2(8, 18), Vector2(14, 24), 2, Color("555555"))
			_line(img, Vector2(6, 26), Vector2(10, 22), 2, wood)
		"scimitar":
			_line(img, Vector2(8, 24), Vector2(16, 14), 3, col)
			_line(img, Vector2(16, 14), Vector2(26, 8), 3, col)
			_line(img, Vector2(17, 13), Vector2(25, 9), 1, hi)
			_line(img, Vector2(4, 22), Vector2(10, 28), 2, Color("555555"))
			_line(img, Vector2(3, 29), Vector2(7, 25), 2, wood)
		"sword", "greatsword":
			var w := 4.0 if mesh == "greatsword" else 3.0
			_line(img, Vector2(8, 24), Vector2(27, 5), w, col)
			_line(img, Vector2(9, 22), Vector2(26, 6), 1, hi)
			_line(img, Vector2(4, 20), Vector2(12, 28), 2, Color("555555"))
			_line(img, Vector2(3, 29), Vector2(7, 25), 2, wood)
		"axe":
			_line(img, Vector2(6, 28), Vector2(22, 8), 2, wood)
			_disc(img, 22, 10, 7, col)
			_disc(img, 26, 14, 4, Color(0, 0, 0, 0))
		"hammer", "maul":
			_line(img, Vector2(6, 28), Vector2(20, 10), 2, wood)
			var big := 5 if mesh == "maul" else 4
			_rect(img, 15 - big, 3, 12 + big, 9 + big / 2, col)
			_rect(img, 16 - big, 4, 3, 7, hi)
		"bow", "longbow":
			for i in range(23):
				var t := float(i) / 22.0
				var y := 4 + t * 24
				var x := 10 + sin(t * PI) * (11 if mesh == "longbow" else 9)
				_line(img, Vector2(x, y), Vector2(x, y), 2.5, col)
			_line(img, Vector2(10, 4), Vector2(10, 28), 1, Color("e8e8e8"))
		"crossbow":
			_line(img, Vector2(6, 26), Vector2(24, 8), 3, wood)
			_line(img, Vector2(10, 6), Vector2(26, 22), 2, col)
			_line(img, Vector2(10, 6), Vector2(24, 8), 1, Color("e8e8e8"))
			_line(img, Vector2(26, 22), Vector2(24, 8), 1, Color("e8e8e8"))
		"staff", "wand":
			var len := 26.0 if mesh == "staff" else 16.0
			_line(img, Vector2(6, 28), Vector2(6 + len * 0.7, 28 - len * 0.85), 2, wood)
			_disc(img, 6 + len * 0.7 + 1, 28 - len * 0.85 - 1, 4, col)
			_disc(img, 6 + len * 0.7, 28 - len * 0.85 - 2, 1.5, col.lightened(0.6))
		"whip":
			for i in range(20):
				var t := float(i) / 19.0
				_line(img, Vector2(5 + t * 22, 26 - t * 18 + sin(t * 9.0) * 3), Vector2(5 + t * 22, 26 - t * 18 + sin(t * 9.0) * 3), 2, col)
			_line(img, Vector2(3, 29), Vector2(7, 25), 3, Color("3a2a1a"))
		"claws":
			for k in range(3):
				_line(img, Vector2(8 + k * 6, 26), Vector2(14 + k * 6, 8), 2, col)
			_rect(img, 6, 24, 20, 5, Color("444444"))
		"javelin":
			_line(img, Vector2(4, 28), Vector2(26, 6), 2, wood)
			_line(img, Vector2(22, 10), Vector2(28, 4), 3, col)
		_:
			_disc(img, 16, 16, 8, col)


static func _draw_armour(img: Image, slot: String, cls: String, col: Color) -> void:
	var hi := col.lightened(0.3)
	var dk := col.darkened(0.3)
	match slot:
		"head":
			if cls == "robe":
				for i in range(14):
					_line(img, Vector2(16 - i * 0.7, 4 + i), Vector2(16 + i * 0.7, 4 + i), 1, col)
				_rect(img, 5, 18, 22, 4, dk)
			else:
				_disc(img, 16, 17, 10, col)
				_rect(img, 6, 17, 20, 11, col)
				if cls == "plate":
					_rect(img, 10, 18, 12, 2, Color.BLACK)
					_rect(img, 15, 18, 2, 8, Color.BLACK)
				_disc(img, 12, 12, 2, hi)
		"body":
			_rect(img, 8, 6, 16, 22, col)
			_rect(img, 3, 6, 6, 12, dk)
			_rect(img, 23, 6, 6, 12, dk)
			_rect(img, 12, 6, 8, 3, Color(0, 0, 0, 0))
			_rect(img, 10, 10, 3, 14, hi)
		"legs":
			_rect(img, 8, 4, 16, 6, col)
			_rect(img, 8, 10, 7, 18, col)
			_rect(img, 17, 10, 7, 18, col)
			_rect(img, 9, 11, 2, 15, hi)
		"shield":
			if cls == "" and col.v < 0.5:
				_rect(img, 7, 6, 18, 22, col)
				_rect(img, 9, 8, 14, 18, col.lightened(0.5))
			else:
				for y in range(4, 29):
					var hw := 11.0 if y < 16 else 11.0 * (1.0 - float(y - 16) / 13.0)
					_line(img, Vector2(16 - hw, y), Vector2(16 + hw, y), 1, col)
				_line(img, Vector2(16, 6), Vector2(16, 24), 2, hi)
		"feet":
			_rect(img, 5, 14, 9, 12, col)
			_rect(img, 3, 22, 11, 5, dk)
			_rect(img, 18, 14, 9, 12, col)
			_rect(img, 16, 22, 11, 5, dk)
		"hands":
			_rect(img, 6, 10, 9, 14, col)
			_rect(img, 17, 10, 9, 14, col)
			_rect(img, 6, 22, 9, 4, dk)
			_rect(img, 17, 22, 9, 4, dk)
		"cape":
			for y in range(4, 29):
				var hw := 5.0 + (y - 4) * 0.4
				_line(img, Vector2(16 - hw, y), Vector2(16 + hw, y), 1, col)
			_rect(img, 10, 4, 12, 3, dk)
		"neck":
			_ring(img, 16, 12, 9, 1.5, Color("c8a040"))
			_disc(img, 16, 23, 5, col)
		"ring":
			_ring(img, 16, 18, 8, 3, Color("d8b040"))
			_disc(img, 16, 10, 4, col)
		"ammo":
			for k in range(3):
				_line(img, Vector2(6 + k * 5, 27), Vector2(16 + k * 5, 5), 1.5, Color("8a6a40"))
				_line(img, Vector2(15 + k * 5, 7), Vector2(17 + k * 5, 3), 2.5, col)
				_line(img, Vector2(5 + k * 5, 27), Vector2(8 + k * 5, 24), 2, Color("e8e8e8"))
		_:
			_disc(img, 16, 16, 9, col)


static func _draw_consumable(img: Image, it: Dictionary, col: Color) -> void:
	if str(it.get("kind", "")) == "food":
		if str(it.get("timer", "")) == "combo":
			_disc(img, 16, 16, 10, Color("2f5a2a"))
			_ring(img, 16, 16, 7, 2, col)
			_disc(img, 16, 16, 3, Color("d8c070"))
		else:
			for x in range(5, 24):
				var hw := sin(float(x - 5) / 19.0 * PI) * 6.0
				_line(img, Vector2(x, 16 - hw), Vector2(x, 16 + hw), 1, col)
			for k in range(6):
				_line(img, Vector2(24, 16), Vector2(29, 10 + k * 2.4), 1, col.darkened(0.2))
			_disc(img, 9, 14, 1.2, Color.BLACK)
	else:
		_rect(img, 10, 10, 12, 18, Color(0.85, 0.9, 1.0, 0.5))
		_rect(img, 13, 4, 6, 6, Color(0.85, 0.9, 1.0, 0.5))
		_rect(img, 12, 2, 8, 3, Color("8a6a40"))
		_rect(img, 11, 14, 10, 13, col)
		_rect(img, 12, 15, 2, 10, col.lightened(0.4))


# ---------------------------------------------------------------- prayers / spells

static func _ward_symbol(img: Image, style: String, c: Color) -> void:
	match style:
		"melee":
			_line(img, Vector2(9, 23), Vector2(23, 9), 3, c)
			_line(img, Vector2(23, 23), Vector2(9, 9), 3, c)
		"ranged":
			_line(img, Vector2(7, 25), Vector2(25, 7), 2, c)
			_line(img, Vector2(25, 7), Vector2(18, 8), 2, c)
			_line(img, Vector2(25, 7), Vector2(24, 14), 2, c)
			_line(img, Vector2(7, 25), Vector2(7, 20), 2, c)
			_line(img, Vector2(7, 25), Vector2(12, 25), 2, c)
		"magic":
			for k in range(8):
				var a := k * PI / 4.0
				_line(img, Vector2(16, 16), Vector2(16 + cos(a) * 11, 16 + sin(a) * 11), 2 if k % 2 == 0 else 1, c)
			_disc(img, 16, 16, 4, c)


static func prayer(id: String, active: bool = false) -> Texture2D:
	var key := "prayer:%s:%s" % [id, active]
	if _cache.has(key):
		return _cache[key]
	var img := _img()
	var p: Dictionary = DB.prayers.get(id, {})
	var track := str(p.get("track", "combat"))
	var bg: Color = {"melee": Color("8a2a20"), "ranged": Color("2a6a2a"), "magic": Color("2a3f8a"), "combat": Color("6a5a2a")}.get(track, Color("555555"))
	if active:
		_disc(img, 16, 16, 15, Color("ffe066"))
	_disc(img, 16, 16, 13, bg)
	var fg := Color("f0e8d0")
	if p.has("protect"):
		_ward_symbol(img, str(p["protect"]), fg)
	else:
		var mult: Dictionary = p.get("mult", {})
		if mult.has("defence") and mult.size() == 1:
			_rect(img, 10, 8, 12, 14, fg)
			_line(img, Vector2(10, 22), Vector2(16, 27), 2, fg)
			_line(img, Vector2(22, 22), Vector2(16, 27), 2, fg)
		elif mult.has("attack") and mult.size() == 1:
			_disc(img, 16, 16, 7, fg)
			_disc(img, 16, 16, 4, bg)
			_disc(img, 16, 16, 2, fg)
		elif mult.has("strength") and mult.size() == 1:
			_rect(img, 9, 12, 14, 8, fg)
			_disc(img, 9, 16, 5, fg)
		elif mult.size() >= 2:
			for k in range(5):
				var a := -PI / 2 + k * TAU / 5.0
				_line(img, Vector2(16, 16), Vector2(16 + cos(a) * 10, 16 + sin(a) * 10), 3, fg)
		else:
			var sp := str(p.get("special", ""))
			match sp:
				"mending":
					_rect(img, 14, 7, 4, 18, fg)
					_rect(img, 7, 14, 18, 4, fg)
				"sap":
					_line(img, Vector2(10, 8), Vector2(22, 24), 3, fg)
					_line(img, Vector2(22, 8), Vector2(10, 24), 1, fg)
				"last_rites":
					_disc(img, 16, 18, 7, fg)
					_rect(img, 15, 5, 2, 8, fg)
				"reckoning":
					for k in range(6):
						var a := k * TAU / 6.0
						_line(img, Vector2(16 + cos(a) * 4, 16 + sin(a) * 4), Vector2(16 + cos(a) * 11, 16 + sin(a) * 11), 2, fg)
				_:
					_ring(img, 16, 16, 9, 2, fg)
	var t := _tex(img)
	_cache[key] = t
	return t


## Overhead icon drawn above a player's head (wards and other overhead prayers).
static func overhead(id: String) -> Texture2D:
	var key := "ovh:" + id
	if _cache.has(key):
		return _cache[key]
	var img := _img()
	var p: Dictionary = DB.prayers.get(id, {})
	var c := Color("f4f0e0")
	if p.has("protect"):
		_ward_symbol(img, str(p["protect"]), c)
	else:
		var tmp := prayer(id).get_image()
		img = tmp
	_outline(img, Color(0.1, 0.05, 0.0, 1.0))
	var t := _tex(img)
	_cache[key] = t
	return t


static func family_color(fam: String) -> Color:
	return {"ember": Color("ff7a1a"), "frost": Color("7fe0ff"), "leech": Color("b01830"), "storm": Color("9a5aff"),
		"binding": Color("4fbf3f"), "arrow": Color("c8a070"), "bolt": Color("b0b0b8"), "knife": Color("d8d8e0"),
		"guardian": Color("ffd23f"), "void": Color("8a3aff"), "eruption": Color("ff5a1a")}.get(fam, Color.WHITE)


static func spell(id: String, unlocked: bool = true) -> Texture2D:
	var key := "spell:%s:%s" % [id, unlocked]
	if _cache.has(key):
		return _cache[key]
	var img := _img()
	var sp: Dictionary = DB.spells.get(id, {})
	var c := family_color(str(sp.get("family", "ember")))
	if not unlocked:
		c = Color(0.3, 0.3, 0.3)
	var area := int(sp.get("area", 1)) > 1
	_disc(img, 16, 16, 12 if area else 9, c.darkened(0.3))
	_disc(img, 16, 16, 7 if area else 5, c)
	if int(sp.get("freeze", 0)) > 0:
		for k in range(6):
			var a := k * TAU / 6.0
			_line(img, Vector2(16, 16), Vector2(16 + cos(a) * 13, 16 + sin(a) * 13), 1, Color("e0f8ff") if unlocked else Color(0.5, 0.5, 0.5))
	_disc(img, 13, 13, 2, Color(1, 1, 1, 0.8))
	_outline(img)
	var t := _tex(img)
	_cache[key] = t
	return t


## Simple coloured blob used for hitsplats.
static func splat(kind: String) -> Texture2D:
	var key := "splat:" + kind
	if _cache.has(key):
		return _cache[key]
	var img := _img()
	var c: Color = {"hit": Color("b81c1c"), "block": Color("2a5ac8"), "poison": Color("2f8a2f"), "heal": Color("c8338f")}.get(kind, Color("b81c1c"))
	for k in range(7):
		var a := k * TAU / 7.0
		_disc(img, 16 + cos(a) * 5, 16 + sin(a) * 5, 8, c)
	_disc(img, 16, 16, 10, c)
	_disc(img, 12, 11, 3, c.lightened(0.3))
	_outline(img, Color(0.15, 0, 0, 1))
	var t := _tex(img)
	_cache[key] = t
	return t


static func white() -> Texture2D:
	if _cache.has("white"):
		return _cache["white"]
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var t := _tex(img)
	_cache["white"] = t
	return t
