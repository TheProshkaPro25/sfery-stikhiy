extends SceneTree

var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	CardDB.load_all()
	var ids: Array = CardDB.creature_ids()
	var state := MatchState.new()
	state.creatures[0] = CreatureState.new(0, ids[0], 0)
	state.creatures[1] = CreatureState.new(1, ids[1], 1)
	state.players[0].creature_uids.assign([0])
	state.players[1].creature_uids.assign([1])
	state.players[0].ability_hand.assign([&"ability_fire_boost"])
	state.players[1].ability_hand.assign([&"", &"", &""])
	var ai := AIPlayer.new(0, 7, -1.0, AIPlayer.Difficulty.HARD)
	var r := BattleResult.new()
	r.attacker_uid = 0
	r.defender_uid = 1
	r.slot = 0
	r.powers.assign([100, 300])
	check(ai.choose_ability(state, r, []) == &"", "явно пустой список способностей означает пас")
	state.players[0].arena_hand.assign([&"arena_field_fire"])
	check(ai.choose_setup(state, [], false).is_empty(), "явно пустой список мест не допускает выкладку")
	check(ai._foe_plays_left(state, r, 0) == MatchController.MAX_BATTLE_ABILITIES, "соперник может отвечать")
	r.plays = [[1, &"ability_fire_boost"]]
	check(ai._foe_plays_left(state, r, 0) == MatchController.MAX_BATTLE_ABILITIES - 1, "прикреплённая карта расходует лимит обмена")
	r.battle_plays = [[1, &"ability_fire_boost"]]
	r.plays = r.battle_plays.duplicate(true)
	check(ai._foe_plays_left(state, r, 0) == MatchController.MAX_BATTLE_ABILITIES - 1, "карта обмена расходует лимит")
	r.passed[1] = true
	check(ai._foe_plays_left(state, r, 0) == 0 and ai._foe_plays_left(state, r, 0, true) > 0, "после собственной карты соперник может ответить снова")
	var dragon := CreatureDef.make(&"ai_test_dragon", "dragon", Attr.A.FIRE, 300, Color.WHITE)
	dragon.species = &"dragnar"
	CardDB._creatures[String(dragon.id)] = dragon
	state.creatures[0].def_id = dragon.id
	r.plays = []
	check(not ai._forecast_legal(state, r, &"ability_dragnar_heart", 0), "слияние нельзя разыграть первым")
	check(ai._forecast_legal(state, r, &"ability_dragnar_heart", 0, &"ability_gale_gust"), "слияние допустимо вторым поверх основной карты")
	check(not ai._forecast_legal(state, r, &"ability_ratnik_oath", 0, &"ability_gale_gust"), "прогноз не использует способность чужого вида")
	# Два усиления вместе спасают проигрывающего бойца; после ответа игрока план пересчитывается.
	var strong := CreatureDef.make(&"ai_test_strong", "strong", Attr.A.FIRE, 450, Color.WHITE)
	strong.species = &"dragnar"
	CardDB._creatures[String(strong.id)] = strong
	for id in [&"ai_test_boost_a", &"ai_test_boost_b", &"ai_test_enemy_boost"]:
		CardDB._cards[String(id)] = CardDef.make(id, "boost", 1, &"boost", {"amount": 80}, "")
	var gate := CardDef.make(&"ai_test_gate", "gate", 0, &"none", {}, "")
	gate.params["g"] = [0, 0, 0, 0, 0, 0]
	CardDB._cards[String(gate.id)] = gate
	state.creatures[1].def_id = strong.id
	state.creatures[1].slot = 0
	state.slots[0].has_card = true
	state.slots[0].card_id = gate.id
	state.slots[0].card_owner = 0
	state.slots[0].occupant_uid = 1
	state.players[0].ability_hand.assign([&"ai_test_boost_a", &"ai_test_boost_b"])
	var normal := AIPlayer.new(0, 9, -1.0, AIPlayer.Difficulty.NORMAL)
	var before: BattleResult = PowerCalc.compute_seq(state, 0, 1, 0, [])
	var first: StringName = normal.choose_ability(state, before, state.players[0].ability_hand)
	check(first != &"", "Боец начинает выигрышную комбинацию из двух карт")
	var after: BattleResult = PowerCalc.compute_seq(state, 0, 1, 0, [[0, first], [1, &"ai_test_enemy_boost"]])
	state.players[0].ability_hand.erase(first)
	check(normal.choose_ability(state, after, state.players[0].ability_hand) == &"", "Боец пересчитывает план после усиления противника")
	# При выборе ворот оценивается реальная защита существа от готового соперника.
	state.creatures[1].slot = -1
	state.slots[0].has_card = false
	state.slots[0].occupant_uid = -1
	state.players[0].arena_hand.assign([gate.id, &"arena_field_fire"])
	var setup: Dictionary = normal.choose_setup(state, [0], false)
	check(setup.get("card_id") == &"arena_field_fire" and setup.get("throw_uid") == 0, "Боец выбирает подходящие ворота и существо")
	state.slots[0].has_card = true
	state.slots[0].card_id = gate.id
	state.slots[0].card_owner = 0
	state.creatures[1].slot = 1
	check(normal._exposure(state, 0, 0) > 0.0, "Угроза учитывает переброс с поля, когда резерв пуст")
	state.creatures[0].def_id = CardDB.RARE_SHADOW_ID
	state.slots[0].card_id = &"arena_dusk_throne"
	check(is_zero_approx(normal._exposure(state, 0, 0)), "Трон сумрака оценивается по исходу, а не только числам силы")
	print("AI tactics: %d failures" % failures)
	quit(1 if failures else 0)
