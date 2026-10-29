class_name BattleParticipant
extends RefCounted
## Личность игрока, боец, сторона боя и команда — разные идентификаторы.
## side_id локален для боя; team_id = -1 означает отсутствие команды.

var player_id: int
var creature_uid: int
var side_id: int
var team_id: int

func _init(player: int = -1, creature: int = -1, side: int = -1, team: int = -1) -> void:
	player_id = player
	creature_uid = creature
	side_id = side
	team_id = team

func clone() -> BattleParticipant:
	return BattleParticipant.new(player_id, creature_uid, side_id, team_id)
