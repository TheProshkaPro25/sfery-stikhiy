class_name MatchState
extends RefCounted
## Полное состояние матча. Мутируется только MatchController.

var players: Array[PlayerState] = []
var slots: Array[SlotState] = []
var creatures: Dictionary = {}  # uid(int) -> CreatureState
var turn: int = 0
var phase: int = 0
var active_player: int = 0
## Финальный бой: у кого-то осталось одно живое существо (преимущество стихии ×2 до конца матча).
var final_round: bool = false
## Счётчик розыгрышей способностей (метка времени для порядка прикреплённых карт).
var play_stamp: int = 0


func _init() -> void:
	for i in range(2):
		players.append(PlayerState.new(i))
	for i in range(6):
		slots.append(SlotState.new())


func creature(uid: int) -> CreatureState:
	return creatures.get(uid) as CreatureState


func alive_count(player: int) -> int:
	var n: int = 0
	for uid in players[player].creature_uids:
		var c: CreatureState = creatures[uid]
		if c.alive:
			n += 1
	return n


func dead_count(player: int) -> int:
	return players[player].creature_uids.size() - alive_count(player)


## Существа игрока в зоне использованных (для «Наследия»).
func used_count(player: int) -> int:
	var n: int = 0
	for uid in players[player].creature_uids:
		var c: CreatureState = creatures[uid]
		if c.used:
			n += 1
	return n


## Копия состояния с точки зрения for_player: чужие закрытые карты арены и чужие руки замаскированы.
## for_player = -1 даёт вид наблюдателя (скрыто всё скрытое).
func duplicate_view(for_player: int) -> MatchState:
	var v: MatchState = MatchState.new()
	v.turn = turn
	v.phase = phase
	v.active_player = active_player
	v.final_round = final_round
	v.play_stamp = play_stamp
	for i in range(2):
		v.players[i] = players[i].clone(i != for_player)
	for i in range(slots.size()):
		var s: SlotState = slots[i]
		var mask: bool = (not s.revealed) and s.card_owner != for_player
		v.slots[i] = s.clone(mask)
	for uid in creatures:
		var c: CreatureState = creatures[uid]
		v.creatures[uid] = c.clone()
	return v
