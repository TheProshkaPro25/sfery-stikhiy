# Состояние 0.2.8 — 2026-10-30

**Не выключать компьютер: автор отменил выключение. `.codex/` не трогать.**

Проект `/home/loq/Документы/game/sfery_stikhiy`, GitHub `TheProshkaPro25/sfery-stikhiy`.
Работа продолжена с checkpoint763907c. Код/модели0.2.8 прошли проверки; выполняются финальная упаковка и публикация. Релиз0.2.7 остаётся с прежним предупреждением о дефектах.

## Принятые изменения
- Stone: один настоящий восстановленный внешний меш, новый запечённый atlas4096, без внутренних маскирующих сфер.9конкретных прежних проходов закрыты. После сглаживания весов сохранены контактные концы лап;1893проверки опоры проходят.
- Tide: **anatomy13**, прежние U-отростки вырезаны, сама наружная стенка закрыта. Новые задние ноги — собственные средние ноги tide. Корни внутри брюшка, плавное закрепление hips, свободные стопы. Ранние anatomy6/11/12 не считать финальными: сначала оставалась сфера/складки, потом обнаружено подвешенное крепление. Новый tests/beetle_attachment подтверждает attachment на rest и5реальных позах из Godot.
- Ratnik:6разделённых body/cape, настоящее GPU Cloth Sim3.0.0 с телом/полом, toon-материалом, wind/inertia и fallback. Финальный GPU QA893493/0, pinned seam error0. Геометрический общий край закреплён даже на UV-дубликатах. Nativebody8weights/cape4weights.
- Ликорез, полётные ноги и6Колоссаров из checkpoint просмотрены. Другие подозревавшиеся сетки без доказанного дефекта не резались.

## Проверки и доказательства
`SESSION_LOG.md` содержит полный результат и обнаруженные/отклонённые кандидаты.
`tools/checkpoints/release028-validation.json` — hashes15GLB, отчёты проверок, GPU/деформации, ZIP.
`tools/_tmp/review028/` — реальные before/after, длинные движения, все исходные логи/буферы GPU.
`build/review028_before_after.jpg` — итоговое сравнение; при обновлении tide пересобрать лист из proof-tide-after, т.к. старый мог показывать anatomy12.

Основные проверки проходят:1180/435/1893/374/22680/67/9869,AI0failures,1197костей,1164idleканала.
Отдельно: beetle_integrity, beetle_tunnels, beetle_attachment --poses, cloth_integrity, kolossar_integrity.
Окончательная Windows-сборка: `build/win028`, архив `build/Sfery_Stikhiy_v0.2.8_win64.zip` и `.sha256`.
Старый предварительный архив с подвешенными корнями исключён из build: `tools/_tmp/review028/rejected-pre-attachment.zip`.

## На момент записи осталось
1. Финальные pack-матчи уже прошли:17/20ходов,13боёв,exit0,без engine errors. ZIP CRC OK, SHA c477c0a08666cb89e7ea6b0165314f165dfcbcb783b6fb2c0e0660460179c9ac.
2. Compare JPG и validation manifest обновлены финальным tide13/attachment/архивом/матчами.
3. Сохранить commit/tag v0.2.8, fast-forward push в origin/master (основа d39045a), GitHub release с новым ZIP, SHA и before/after. `.codex/` не включать.
4. Записать успешную публикацию сюда/в журнал. Компьютер не выключать.

## Сохранность
Backups все в tools/_tmp: stone028-base, stone028-geometry, stone028-atlas-base, water-beetle027-base, gpucloth028-base, likorez028-base, kolossar-arms028-base.
Каменный pipeline: repair_stone → Blender bake → fill_bake_misses → apply_baked_atlas → compact → smooth_repaired_beetle_weights.
Water rebuild: repair_water_beetle.py (idempotent anatomy13) → compact. Не возвращать старые ellipsoid/fan caps.
Cloth rebuild: split_gpu_capes.py (источник gpucloth028-base), runtime creature_cloth.gd. Полный путь воспроизведения в tools/models/README.md.

Ограничения: одна исходная tide-cape bending edge пропускается; на выходе общего autoplay есть cached-resource diagnostics, без новых invalid-RID. NativeWindows не запускался (нет Wine); PCK проверяется Linux/Vulkan и CRC. Не объявлять доказанным отсутствие любого растяжения: финальные диагностические числа сохранены отдельно от проверки дыр/attachment.
