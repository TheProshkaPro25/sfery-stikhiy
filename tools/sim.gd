extends SceneTree
## Симуляция баланса: N матчей ИИ против ИИ со случайными колодами по правилам (CardDB.random_deck), без физики.
## Запуск: godot --headless -s res://tools/sim.gd -- [n=600] [seed=1] [d0=1] [d1=1] [levels=1] [check=1]
##   n — число матчей; seed — первый seed; d0/d1 — сложность ИИ игроков 0/1 (0 новичок, 1 боец, 2 мастер);
##   levels=1 — дополнительно сравнить уровни сложности (мастер/боец/новичок, стороны меняются);
##   check=1 — код выхода 1, если баланс вне рамок (старт 45–55 %, длина 12–20, каждая стихия 40–60 %).
## Модель броска как в tests/run_tests.gd: с шансом HIT_CHANCE[сложность] шар попадает в цель, иначе соседний слот или промах.

const STEP_CAP: int = 4000
const HIT_CHANCE: Array[float] = [0.55, 0.65, 0.72]
const START_MIN: float = 0.45
const START_MAX: float = 0.55
const LEN_MIN: float = 12.0
const LEN_MAX: float = 20.0
const ELEM_MIN: float = 0.40
const ELEM_MAX: float = 0.60


func _initialize() -> void:
	var args: Dictionary = {"n": "600", "seed": "1", "d0": "1", "d1": "1", "levels": "1", "check": "0"}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	CardDB.load_all()
	var n: int = int(args["n"])
	var seed0: int = int(args["seed"])
	var t0: int = Time.get_ticks_msec()
	var st: Dictionary = run_series(n, seed0, int(args["d0"]), int(args["d1"]))
	var ok: bool = report(st, n)
	if args["levels"] == "1":
		var m: int = maxi(100, n / 3)
		print("")
		print("Уровни сложности (%d матчей на пару, стороны меняются):" % (m * 2))
		for pair in [[2, 1], [1, 0], [2, 0]]:
			var a1: Dictionary = run_series(m, seed0 + 100000, pair[0], pair[1])
			var a2: Dictionary = run_series(m, seed0 + 200000, pair[1], pair[0])
			var w: int = int(a1["wins"][0]) + int(a2["wins"][1])
			print("  %s против %s: побед %.1f %%" % [AIPlayer.difficulty_name(pair[0]), AIPlayer.difficulty_name(pair[1]),
				100.0 * w / float(m * 2)])
	print("")
	print("Время: %.1f с" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(1 if (args["check"] == "1" and not ok) else 0)


## Серия матчей; возвращает накопленную статистику.
func run_series(n: int, seed0: int, d0: int, d1: int) -> Dictionary:
	var st: Dictionary = {
		"wins": [0, 0], "draws": 0, "bad": 0, "turns": 0, "turn_list": [], "reasons": {},
		"elem_games": [0, 0, 0, 0, 0, 0], "elem_wins": [0, 0, 0, 0, 0, 0],
		"battles": 0, "attached": 0, "multi": 0, "gate_throws": 0, "cancels": 0, "traps": {}, "final": 0, "final_comeback": 0,
		"momentum2": 0, "abilities": 0, "standoffs": 0,
	}
	for k in range(n):
		run_match(seed0 + k, d0, d1, st)
	return st


func run_match(seed_value: int, d0: int, d1: int, st: Dictionary) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck0: DeckDef = CardDB.random_deck(rng)
	var deck1: DeckDef = CardDB.random_deck(rng)
	var el: Array[int] = [deck0.creatures[0].attribute, deck1.creatures[0].attribute]
	var ctrl: MatchController = MatchController.new(deck0, deck1, seed_value)
	ctrl.landing_window = true
	var diff: Array[int] = [d0, d1]
	var ais: Array[AIPlayer] = [AIPlayer.new(0, seed_value * 7 + 1, -1.0, d0), AIPlayer.new(1, seed_value * 7 + 2, -1.0, d1)]
	var m: Dictionary = {"final_player": -2, "attached": 0, "multi": 0, "battles": 0, "momentum2": 0, "abilities": 0, "standoffs": 0, "traps": [], "gate_throws": 0, "cancels": 0}
	ctrl.battle_started.connect(func(_s: int, _a: int, _d: int) -> void: m["battles"] += 1)
	ctrl.ability_attached.connect(func(_p: int, _u: int, _c: StringName) -> void: m["attached"] += 1)
	ctrl.ability_cancelled.connect(func(_p: int, _c: StringName) -> void: m["cancels"] += 1)
	ctrl.ability_played.connect(func(_p: int, _c: StringName) -> void: m["abilities"] += 1)
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void:
		if r.plays.size() >= 3:
			m["multi"] += 1)
	ctrl.gate_trap_triggered.connect(func(_s: int, _c: StringName, e: StringName) -> void: (m["traps"] as Array).append(String(e)))
	ctrl.final_round_started.connect(func(p: int) -> void: m["final_player"] = p)
	ctrl.momentum_changed.connect(func(_p: int, v: int) -> void:
		if v >= PowerCalc.MOMENTUM_MAX:
			m["momentum2"] += 1)
	ctrl.standoff.connect(func(_a: int, _d: int) -> void: m["standoffs"] += 1)
	ctrl.start()
	var steps: int = 0
	var pending_uid: int = -1
	var pending_target: int = -1
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER:
		steps += 1
		if steps > STEP_CAP:
			st["bad"] += 1
			print("ЗАВИСАНИЕ: seed=%d" % seed_value)
			return
		var p: int = ctrl.get_active_player()
		var err: Error = OK
		match ctrl.get_phase():
			MatchController.Phase.SETUP:
				var ch: Dictionary = ais[p].choose_setup(ctrl.get_view(p), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
				if ch.is_empty():
					err = ctrl.skip_gate(p)
				elif ch.has("throw_uid"):
					pending_uid = int(ch["throw_uid"])
					pending_target = int(ch["slot"])
					m["gate_throws"] += 1
					err = ctrl.throw_with_gate(p, ch["card_id"], ch["slot"], pending_uid)
				else:
					err = ctrl.place_arena_card(p, ch["card_id"], ch["slot"])
			MatchController.Phase.AFTER_LANDING:
				var at: StringName = ais[p].choose_attach(ctrl.get_view(p), ctrl.get_landed_uid(), ctrl.legal_abilities(p))
				err = ctrl.pass_ability(p) if at == &"" else ctrl.play_ability(p, at)
			MatchController.Phase.AWAIT_THROW:
				var th: Dictionary = ais[p].choose_throw(ctrl.get_view(p))
				pending_uid = th["uid"]
				pending_target = th["target_slot"]
				err = ctrl.select_creature(p, pending_uid)
			MatchController.Phase.AWAIT_LANDING:
				var landing: int = pending_target
				if rng.randf() >= HIT_CHANCE[diff[p]]:
					landing = _near_miss(pending_target, rng)
				ctrl.report_landing(pending_uid, landing)
			MatchController.Phase.ABILITY_WINDOW:
				var pick: StringName = ais[p].choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), ctrl.legal_abilities(p))
				err = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick)
		if err != OK:
			st["bad"] += 1
			print("ОШИБКА действия %d: seed=%d фаза %d" % [err, seed_value, ctrl.get_phase()])
			return
	var w: int = ctrl.winner
	if w < 0:
		st["draws"] += 1
	else:
		st["wins"][w] += 1
	st["turns"] += ctrl.state.turn
	(st["turn_list"] as Array).append(ctrl.state.turn)
	var reason: String = String(ctrl.game_over_reason)
	st["reasons"][reason] = int(st["reasons"].get(reason, 0)) + 1
	if el[0] != el[1]:
		for i in range(2):
			st["elem_games"][el[i]] += 1
			if w == i:
				st["elem_wins"][el[i]] += 1
	for k in ["battles", "attached", "multi", "gate_throws", "cancels", "momentum2", "abilities", "standoffs"]:
		st[k] += int(m[k])
	for e in m["traps"]:
		st["traps"][e] = int(st["traps"].get(e, 0)) + 1
	var fp: int = int(m["final_player"])
	if fp != -2:
		st["final"] += 1
		# камбэк: победил тот, у кого первым осталось одно существо
		if fp >= 0 and w == fp:
			st["final_comeback"] += 1


## Печать отчёта; true — баланс в рамках.
func report(st: Dictionary, n: int) -> bool:
	var played: int = n - int(st["bad"])
	var p0: float = float(st["wins"][0]) / float(maxi(1, played))
	var avg_len: float = float(st["turns"]) / float(maxi(1, played))
	var tl: Array = st["turn_list"]
	tl.sort()
	print("Симуляция %d матчей (сбоев %d): побед P0 %d (%.1f %%), P1 %d, ничьих %d" % [n, st["bad"], st["wins"][0], p0 * 100.0, st["wins"][1], st["draws"]])
	print("  причины: %s" % str(st["reasons"]))
	if not tl.is_empty():
		print("  длина: средняя %.1f хода, медиана %d, 10-й перц. %d, 90-й перц. %d" % [avg_len, tl[tl.size() / 2], tl[tl.size() / 10], tl[tl.size() * 9 / 10]])
	print("  за матч: боёв %.1f, способностей в бою %.1f, прикреплено вне боя %.2f, отмен %.2f, боёв с 3+ картами %.2f, «ворота + бросок» %.2f, тупиков %.2f" % [
		float(st["battles"]) / played, float(st["abilities"]) / played, float(st["attached"]) / played, float(st["cancels"]) / played,
		float(st["multi"]) / played, float(st["gate_throws"]) / played, float(st["standoffs"]) / played])
	print("  ловушки сработали: %s; «Натиск» ×2 набран %.2f раза за матч" % [str(st["traps"]), float(st["momentum2"]) / played])
	print("  финальный раунд в %.0f %% матчей, камбэк (победил тот, у кого осталось одно) %.0f %% из них" % [
		100.0 * st["final"] / played, 100.0 * st["final_comeback"] / maxf(1.0, float(st["final"]))])
	var ok: bool = st["bad"] == 0 and p0 >= START_MIN and p0 <= START_MAX and avg_len >= LEN_MIN and avg_len <= LEN_MAX
	var line: PackedStringArray = PackedStringArray()
	for e in range(6):
		var g: int = st["elem_games"][e]
		var rate: float = float(st["elem_wins"][e]) / float(maxi(1, g))
		if rate < ELEM_MIN or rate > ELEM_MAX:
			ok = false
		line.append("%s %.1f %% (%d)" % [Attr.display_name(e), rate * 100.0, g])
	print("  стихии (без зеркальных матчей): " + ", ".join(line))
	print("  БАЛАНС: %s (старт %.0f–%.0f %%, длина %.0f–%.0f, стихии %.0f–%.0f %%)" % ["в рамках" if ok else "ВНЕ РАМОК",
		START_MIN * 100, START_MAX * 100, LEN_MIN, LEN_MAX, ELEM_MIN * 100, ELEM_MAX * 100])
	return ok


## Промах как у физики: соседний по сетке 2x3 слот или вылет за пределы слотов.
func _near_miss(target: int, rng: RandomNumberGenerator) -> int:
	if target < 0 or rng.randf() < 0.5:
		return -1
	var col: int = target % 3
	var row: int = target / 3
	var near: Array[int] = []
	if col > 0:
		near.append(target - 1)
	if col < 2:
		near.append(target + 1)
	near.append((1 - row) * 3 + col)
	return near[rng.randi_range(0, near.size() - 1)]
