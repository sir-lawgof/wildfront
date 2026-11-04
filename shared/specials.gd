class_name Specials
extends RefCounted
## Special attacks (GDD 2 "Special attacks", GDD 7 weapon table). Each handler queues
## one or more hits through Sim.make_attack. The Sim has already paid the energy cost.


static func perform(sim: Sim, f: Fighter, t: Fighter, spec_id: String, style: String) -> void:
	match spec_id:
		"double_hit":
			sim.make_attack(f, t, "melee", {"acc_mult": 1.15, "dmg_mult": 1.15, "spec": spec_id})
			sim.make_attack(f, t, "melee", {"acc_mult": 1.15, "dmg_mult": 1.15, "spec": spec_id})
		"sever":
			sim.make_attack(f, t, "melee", {"acc_mult": 1.2, "spec": spec_id, "effects": {"ward_block": 5}})
		"cleave":
			sim.make_attack(f, t, "melee", {"dmg_mult": 1.25, "spec": spec_id})
		"rampage":
			var base_str := int(f.base_levels["strength"])
			f.levels["strength"] = int(f.levels["strength"]) + int(floor(base_str * 0.20))
			f.levels["attack"] = maxi(1, int(f.levels["attack"]) - int(floor(int(f.base_levels["attack"]) * 0.10)))
			f.levels["defence"] = maxi(1, int(f.levels["defence"]) - int(floor(int(f.base_levels["defence"]) * 0.10)))
			sim.msg(f.id, "You feel a surge of rage!")
			sim.make_attack(f, t, "melee", {"spec": spec_id})
		"armour_break":
			sim.make_attack(f, t, "melee", {"spec": spec_id, "effects": {"def_drain": 0.30}})
		"energy_drain":
			sim.make_attack(f, t, "melee", {"spec": spec_id, "effects": {"energy_drain": 0.10}})
		"instant_maul":
			sim.make_attack(f, t, "melee", {"spec": spec_id})
		"greatblade":
			sim.make_attack(f, t, "melee", {"acc_mult": 2.0, "dmg_mult": 1.375, "spec": spec_id})
		"claws":
			_claws(sim, f, t)
		"void_strike":
			var mx := Combat.fighter_max_hit(f, "melee")
			var lo := int(floor(mx * 0.5))
			var hi := int(floor(mx * 1.5))
			sim.make_attack(f, t, "magic", {"force_hit": true, "fixed_damage": sim.rng.randi_range(lo, hi), "spec": spec_id, "delay": 0, "proj": "void"})
		"twin_shot":
			sim.make_attack(f, t, "ranged", {"acc_mult": 0.9, "spec": spec_id})
			sim.make_attack(f, t, "ranged", {"acc_mult": 0.9, "spec": spec_id, "delay_add": 1})
		"pinning_bolt":
			sim.make_attack(f, t, "ranged", {"acc_mult": 1.25, "spec": spec_id, "effects": {"freeze": 5}})
		"fan":
			for i in range(3):
				sim.make_attack(f, t, "ranged", {"spec": spec_id})
		"bleed":
			sim.make_attack(f, t, "ranged", {"spec": spec_id, "effects": {"bleed": true}})
		"dusk_volley":
			sim.make_attack(f, t, "ranged", {"spec": spec_id, "min_damage": 8})
			sim.make_attack(f, t, "ranged", {"spec": spec_id, "min_damage": 8, "delay_add": 1})
		"ballista_shot":
			sim.make_attack(f, t, "ranged", {"acc_mult": 1.25, "dmg_mult": 1.25, "spec": spec_id})
		"sunfire_shot":
			sim.make_attack(f, t, "ranged", {"acc_mult": 2.0, "spec": spec_id})
		"eruption":
			sim.make_attack(f, t, "magic", {"max_override": 50, "spec": spec_id, "proj": "eruption"})
		"chain_lightning":
			var spell := f.current_spell()
			var mx := 30
			if spell != "":
				mx = Combat.fighter_max_hit(f, "magic", spell)
			sim.make_attack(f, t, "magic", {"max_override": mx, "spec": spec_id, "proj": "storm"})
			var extra := 0
			for o in sim.fighters.values():
				if extra >= 2:
					break
				var other: Fighter = o
				if other == t or not other.is_alive() or not sim.rules.can_attack(f, other):
					continue
				if MapGrid.chebyshev(other.pos, t.pos) <= 3:
					sim.make_attack(f, other, "magic", {"max_override": mx, "spec": spec_id, "proj": "storm"})
					extra += 1
		_:
			sim.make_attack(f, t, style, {"spec": spec_id})


## Four hits in a cascade: the first accurate roll decides the pattern.
static func _claws(sim: Sim, f: Fighter, t: Fighter) -> void:
	var mx := Combat.fighter_max_hit(f, "melee")
	var hits: Array = [0, 0, 0, 0]
	var att := Combat.attack_roll(f, "melee")
	var dfn := Combat.defence_roll(t, "melee")
	var chance := Combat.hit_chance(att, dfn)
	var landed := -1
	for i in range(4):
		if sim.rng.randf() < chance:
			landed = i
			break
	match landed:
		0:
			hits[0] = sim.rng.randi_range(mx / 2, maxi(mx / 2, mx - 1))
			hits[1] = hits[0] / 2
			hits[2] = hits[1] / 2
			hits[3] = hits[2] + 1
		1:
			hits[1] = sim.rng.randi_range(mx * 3 / 8, mx * 7 / 8)
			hits[2] = hits[1] / 2
			hits[3] = hits[2] + 1
		2:
			hits[2] = sim.rng.randi_range(mx / 4, mx * 3 / 4)
			hits[3] = hits[2] + 1
		3:
			hits[3] = sim.rng.randi_range(mx / 4, mx * 5 / 4)
		_:
			hits = [0, 0, 1, 1] if sim.rng.randf() < 0.5 else [0, 0, 0, 0]
	for i in range(4):
		var d := int(hits[i])
		sim.make_attack(f, t, "melee", {"fixed_damage": d, "force_hit": d > 0, "spec": "claws", "delay": 0 if i < 2 else 1})
