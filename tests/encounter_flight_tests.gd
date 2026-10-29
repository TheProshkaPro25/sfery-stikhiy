extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, msg: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(msg)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 CardDB.load_all()
 var rare := CardDB.creature(CardDB.RARE_SHADOW_ID)
 check(rare != null and rare.attribute == Attr.A.SHADOW, "Редкий боец существует и относится к Тени")
 check(not CardDB.creature_ids().has(CardDB.RARE_SHADOW_ID), "Редкая встреча не попадает в обычный пул")
 var encounters := 0
 for seed_value in range(4000):
  var rng := RandomNumberGenerator.new()
  rng.seed = seed_value
  var probe := RandomNumberGenerator.new()
  probe.seed = seed_value
  var expected := probe.randf() < 0.10
  var deck := CardDB.opponent_deck(rng)
  var ids: Array = []
  var gates: Array = []
  var abilities: Array = []
  for d in deck.creatures: ids.append(d.id)
  for c in deck.arena: gates.append(c.id)
  for c in deck.abilities: abilities.append(c.id)
  var found := ids.has(CardDB.RARE_SHADOW_ID)
  check(found == expected, "Один независимый бросок 10%%, seed %d" % seed_value)
  check(CardDB.deck_error(ids, gates, abilities).is_empty(), "Легальная команда/карты, seed %d" % seed_value)
  if found: encounters += 1
 check(encounters > 280 and encounters < 520, "Частота встреч близка к 10%%: %d/4000" % encounters)
 for definition in CardDB.all_creatures():
  var actor := CreatureAnim.new()
  root.add_child(actor)
  actor.set_process(false)
  actor.set_model(CreatureModels.build(definition), definition)
  actor.idle_on = true
  for f in range(120): actor._process(1.0 / 60)
  if actor._flyer:
   var low := INF
   var high := -INF
   for f in range(240):
    actor._process(1.0 / 60)
    low = minf(low, actor.position.y)
    high = maxf(high, actor.position.y)
   check(low > actor.get_height() * 0.16, "Парит над полем: %s" % definition.id)
   check(high - low < actor.get_height() * 0.04, "Мягкое покачивание: %s" % definition.id)
   actor.lunge(actor.get_height() * 0.2)
   for f in range(100):
    actor._process(1.0 / 60)
    check(actor.position.y > actor.get_height() * 0.15, "Не падает на землю при атаке: %s" % definition.id)
  else:
   check(is_zero_approx(actor.position.y), "Наземный вид не парит: %s" % definition.id)
  actor.free()
  CreatureModels.clear()
  await process_frame
 print("Встречи/полёт: %d проверок, %d ошибок, редких %d/4000" % [checks, failures, encounters])
 quit(1 if failures else 0)
