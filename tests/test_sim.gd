extends TestCase
## Tick-order rules (GDD 2): eating delays, combo eating, equips per tick, prayers,
## freezes, projectile delay, death and respawn.


func _put_adjacent(sim: Sim) -> void:
	var a: Fighter = sim.fighters[1]
	var b: Fighter = sim.fighters[2]
	a.pos = Vector2i(10, 30)
	b.pos = Vector2i(11, 30)
	a.spawn_shield = 0
	b.spawn_shield = 0


func test_walk_and_run_speeds() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	a.pos = Vector2i(5, 30)
	a.running = false
	sim.queue_intent(1, {"type": "move", "x": 15, "y": 30})
	sim.step()
	eq(a.pos, Vector2i(6, 30), "walk = 1 tile")
	sim.queue_intent(1, {"type": "run", "on": true})
	sim.step()
	eq(a.pos, Vector2i(8, 30), "run = 2 tiles")
	check(a.run_energy < 100.0, "running drains energy")


func test_eating_delays_attack_and_combo() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	a.hp = 50
	a.inventory[0] = {"id": "pike", "doses": 1}
	a.inventory[1] = {"id": "pike", "doses": 1}
	a.inventory[2] = {"id": "kelp_roll", "doses": 1}
	a.attack_timer = 0
	sim.queue_intent(1, {"type": "use", "slot": 0})
	sim.queue_intent(1, {"type": "use", "slot": 1})
	sim.queue_intent(1, {"type": "use", "slot": 2})
	sim.step()
	eq(a.hp, 50 + 20 + 18, "main food + combo in one tick, second main food rejected")
	check(a.inventory[1] != null, "second pike not eaten")
	check(a.attack_timer >= 3, "eating delays attack (timer %d)" % a.attack_timer)


func test_equips_limited_per_tick() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	for i in range(28):
		a.inventory[i] = null
	var ids := ["leather_coif", "leather_body", "leather_chaps", "leather_vambraces", "leather_boots",
		"woven_hat", "woven_robe_top", "woven_robe_bottom", "woven_gloves", "woven_boots"]
	for i in range(ids.size()):
		a.inventory[i] = {"id": ids[i], "doses": 1}
		sim.queue_intent(1, {"type": "equip", "slot": i})
	sim.step()
	eq(a.action_queue.size(), 2, "8 equips this tick, 2 carried to next")
	sim.step()
	eq(a.action_queue.size(), 0, "rest next tick")
	eq(a.equipment["body"], "woven_robe_top", "last body wins")


func test_two_handed_moves_shield_to_inventory() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	a.inventory[0] = {"id": "oak_shortbow", "doses": 1}
	sim.queue_intent(1, {"type": "equip", "slot": 0})
	sim.step()
	eq(a.equipment["weapon"], "oak_shortbow", "bow equipped")
	eq(a.equipment["shield"], "", "shield removed")
	check(a.count_item("bronze_scimitar") == 1 and a.count_item("bronze_kiteshield") == 1, "both went to inventory")


func test_protection_prayer_blocks_damage() -> void:
	var sim := make_duel()
	_put_adjacent(sim)
	var a: Fighter = sim.fighters[1]
	var b: Fighter = sim.fighters[2]
	sim.queue_intent(2, {"type": "prayer", "id": "ward_blades"})
	sim.step()
	check(b.has_prayer("ward_blades"), "prayer on")
	var h := sim.make_attack(a, b, "melee", {"fixed_damage": 10, "force_hit": true})
	eq(int(h["dmg"]), Combat.protect_damage(10), "10 reduced through Ward of Blades")
	check(int(h["dmg"]) < 10, "the ward blocks something")
	var h2 := sim.make_attack(a, b, "ranged", {"fixed_damage": 10, "force_hit": true})
	eq(int(h2["dmg"]), 10, "wrong ward doesn't help")


func test_prayer_drains_and_turns_off() -> void:
	var sim := make_duel()
	var b: Fighter = sim.fighters[2]
	b.prayer_points = 1
	sim.queue_intent(2, {"type": "prayer", "id": "ward_blades"})
	for i in range(12):
		sim.step()
	eq(b.prayer_points, 0, "drained")
	check(b.active_prayers.is_empty(), "all prayers off at 0")


func test_projectile_delay() -> void:
	var sim := make_duel("archer", "warrior")
	var a: Fighter = sim.fighters[1]
	var b: Fighter = sim.fighters[2]
	a.pos = Vector2i(10, 30)
	b.pos = Vector2i(16, 30)
	a.spawn_shield = 0
	b.spawn_shield = 0
	b.frozen_ticks = 50
	sim.queue_intent(1, {"type": "attack", "target": 2})
	sim.step()
	eq(sim.pending_hits.size(), 1, "arrow in flight")
	eq(int(sim.pending_hits[0]["land"]), sim.tick + Combat.hit_delay("ranged", 6), "lands after travel")


func test_freeze_and_immunity() -> void:
	var sim := make_duel()
	var b: Fighter = sim.fighters[2]
	check(sim._freeze(b, 8), "freeze lands")
	check(not sim._freeze(b, 8), "can't refreeze while frozen")
	for i in range(8):
		sim.step()
	eq(b.frozen_ticks, 0, "freeze ended")
	check(b.freeze_immune_ticks > 0, "immune after freeze")
	check(not sim._freeze(b, 8), "immune")


func test_frozen_player_cannot_move() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	a.pos = Vector2i(5, 30)
	sim._freeze(a, 8)
	sim.queue_intent(1, {"type": "move", "x": 15, "y": 30})
	sim.step()
	eq(a.pos, Vector2i(5, 30), "frozen")


func test_melee_needs_cardinal_adjacency() -> void:
	var sim := make_duel()
	var a: Fighter = sim.fighters[1]
	var b: Fighter = sim.fighters[2]
	a.pos = Vector2i(10, 30)
	b.pos = Vector2i(11, 31)
	check(not sim._in_attack_position(a, b, "melee"), "no diagonal melee")
	b.pos = Vector2i(11, 30)
	check(sim._in_attack_position(a, b, "melee"), "cardinal ok")


func test_fight_to_death_and_respawn() -> void:
	var sim := Sim.new()
	sim.setup("clan_clash", "castle_courtyard", {"seed": 7, "pre_ticks": 1})
	var unl := Progression.unlocked_set({"melee": 1, "ranged": 1, "magic": 1})
	sim.add_fighter("A", 0, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "skirmish"}), unl)
	sim.add_fighter("B", 1, false, Loadout.build(DB.classes["defaults"]["warrior"], unl, {"supply": "skirmish"}), unl)
	var b: Fighter = sim.fighters[2]
	sim.step()
	b.hp = 5
	b.inventory.fill(null)
	sim.queue_intent(1, {"type": "attack", "target": 2})
	var died := false
	for i in range(400):
		sim.step()
		if b.dead:
			died = true
			break
	check(died, "B died")
	eq(sim.scores[0], 1, "team score")
	eq((sim.fighters[1] as Fighter).kills, 1, "kill credited")
	for i in range(12):
		sim.step()
	check(not b.dead and b.hp == 99, "B respawned at full HP")


func test_bot_vs_bot_match_runs() -> void:
	var server := MatchServerCore.new()
	server.setup({"mode": "clan_clash", "map": "frostgate_ruins", "seed": 3, "pre_ticks": 1, "player": {}})
	for i in range(300):
		server.tick()
	var kills := 0
	for f in server.sim.fighters.values():
		kills += (f as Fighter).kills
	check(kills > 0, "bots got kills in 3 minutes (%d)" % kills)
