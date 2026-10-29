class_name BattleContext
extends RefCounted
## Состав отдельного боя. Хранит и 3–4 участников; расчёт/очерёдность пока поддерживают только дуэль.
## Несколько игроков могут принадлежать одной стороне/команде; игрок может выставить несколько бойцов.
## Уникален creature_uid, player_id может повторяться.

var slot: int = -1
var participants: Array[BattleParticipant] = []

func add(participant: BattleParticipant) -> bool:
	if participant == null or participant.player_id < 0 or participant.creature_uid < 0 or participant.side_id < 0:
		return false
	for p in participants:
		if p.creature_uid == participant.creature_uid:
			return false
	participants.append(participant.clone())
	return true

## Первый боец игрока; для боя с несколькими бойцами использовать participants_for_player().
func for_player(player_id: int) -> BattleParticipant:
	for p in participants:
		if p.player_id == player_id:
			return p
	return null

func participants_for_player(player_id: int) -> Array[BattleParticipant]:
	var result: Array[BattleParticipant] = []
	for p in participants:
		if p.player_id == player_id:
			result.append(p)
	return result

## Уникальные id игроков на стороне, в порядке добавления бойцов.
func players_on_side(side_id: int) -> Array[int]:
	var result: Array[int] = []
	for p in participants:
		if p.side_id == side_id and not result.has(p.player_id):
			result.append(p.player_id)
	return result

func clone() -> BattleContext:
	var result := BattleContext.new()
	result.slot = slot
	for p in participants:
		result.add(p)
	return result

static func duel(state: MatchState, attacker_uid: int, defender_uid: int, battle_slot: int) -> BattleContext:
	var result := BattleContext.new()
	result.slot = battle_slot
	result.add(BattleParticipant.new(state.creatures[attacker_uid].owner, attacker_uid, 0))
	result.add(BattleParticipant.new(state.creatures[defender_uid].owner, defender_uid, 1))
	return result
