class_name MatchRules
extends RefCounted
## Направление правил, не заявление о точном воспроизведении аниме.
## LEGACY сохраняет авторские бонусы прежней версии для сравнения и старых сценариев.
enum Ruleset { ANIME_INSPIRED, LEGACY }

static func author_bonuses(ruleset: int) -> bool:
	return ruleset == Ruleset.LEGACY
