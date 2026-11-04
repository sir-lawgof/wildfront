extends TestCase
## OSRS formula checks against known values (GDD 2 "Accuracy and damage").


func test_effective_level() -> void:
	eq(Combat.effective_level(99, 1.0, 3), 110, "99 + aggressive")
	eq(Combat.effective_level(118, 1.23, 3), 156, "super combat + Valor/Piety")
	eq(Combat.effective_level(99, 1.15, 0), 121, "99 * 1.15")


func test_max_hit_known_values() -> void:
	# 99 Strength, aggressive, no gear: max hit 11.
	eq(Combat.max_hit(110, 0), 11, "bare-handed 99 str")
	# 99 Strength aggressive with only a +82 strength weapon (whip-like): 25.
	eq(Combat.max_hit(110, 82), 25, "+82 strength")
	# Boosted + prayer with +120 strength bonus.
	eq(Combat.max_hit(156, 120), 45, "maxed setup")


func test_hit_chance() -> void:
	near(Combat.hit_chance(10000, 5000), 1.0 - 5002.0 / 20002.0, 1e-6, "A > D")
	near(Combat.hit_chance(5000, 10000), 5000.0 / 20002.0, 1e-6, "A < D")
	near(Combat.hit_chance(1000, 1000), 1000.0 / 2002.0, 1e-6, "A == D uses second branch")
	eq(Combat.max_roll(107, 30), 107 * 94, "max roll")


func test_magic_max_hit() -> void:
	eq(Combat.magic_max_hit(24, 0.0), 24, "no bonus")
	eq(Combat.magic_max_hit(30, 10.0), 33, "+10%")


func test_hit_delays() -> void:
	eq(Combat.hit_delay("melee", 1), 0, "melee lands same tick")
	eq(Combat.hit_delay("ranged", 1), 1, "ranged close")
	eq(Combat.hit_delay("ranged", 9), 3, "ranged far")
	eq(Combat.hit_delay("magic", 1), 1, "magic close")
	eq(Combat.hit_delay("magic", 10), 4, "magic far")


func test_protection_cuts_40_percent() -> void:
	eq(Combat.protect_damage(20), 12, "20 -> 12")
	eq(Combat.protect_damage(1), 0, "1 -> 0")


func test_fighter_rolls_use_gear() -> void:
	var sim := make_duel("warrior", "battlemage")
	var w: Fighter = sim.fighters[1]
	var m: Fighter = sim.fighters[2]
	# Mage in robes is easier to hit with melee than the warrior in plate.
	check(Combat.defence_roll(m, "melee") < Combat.defence_roll(w, "melee"), "robes weak to melee")
	# Warrior in plate is easier to hit with magic than the mage.
	check(Combat.defence_roll(w, "magic") < Combat.defence_roll(m, "magic"), "plate weak to magic")
	eq(Combat.base_max_hit(w, "melee"), 14, "bronze scimitar max hit at 99 aggressive")
	eq(Combat.fighter_max_hit(w, "melee"), int(floor(14 * float(DB.rule("damage_scale", 1.0)))), "damage_scale applied")
