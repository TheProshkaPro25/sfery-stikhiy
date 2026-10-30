# Опубликовано: 0.2.8 — 2026-10-30

**Компьютер не выключать: автор отменил выключение. `.codex/` не трогать.**

Релиз: https://github.com/TheProshkaPro25/sfery-stikhiy/releases/tag/v0.2.8
Код релиза/tag v0.2.8: `6721f464992904963c5424733cd1c170dd43c272`.
Основная ветка GitHub `master` обновлена до96224a7. Итоговый журнал публикации сохранён следующим ЛОКАЛЬНЫМ коммитом: его отдельный внешний push отклонён auto-review как дополнительный payload вне разрешённого релиза. Повторная публикация сборки не нужна.
Релиз0.2.7 остаётся с прежним предупреждением. Переносить его ZIP в0.2.8 нельзя.

## Сделано
- Stone: настоящий восстановленный внешний меш, новый atlas4096, без внутренних маскирующих сфер.9конкретных прежних проходов закрыты. Сглажены переходы корпуса, сохранены контактные концы лап; опора проверена.
- Tide: **anatomy13**. Сросшиеся U-отростки вырезаны, закрыта сама наружная стенка. Новые задние ноги — собственные средние ноги tide, корни внутри брюшка и плавно закреплены к hips, стопы свободны. Ранние anatomy6/11/12 отклонены, особенно12 с подвешенными закрытыми корнями. Новый attachment-тест проверяет пространственную связь в rest и5реальных позах Godot.
- Ratnik:6разделённых body/cape, настоящее GPU Cloth Sim3.0.0 с телом/полом, toon-материалом, wind/inertia и fallback. GPU QA893493/0, pinned seam error0. Общий геометрический край закреплён и на UV-дубликатах. Body8weights/cape4weights.
- Ликорез, полётные ноги и6Колоссаров из checkpoint просмотрены. Другие подозревавшиеся сетки без доказанного дефекта не резались.

## Проверки и артефакты
Все обязательные шаги передачи0.2.8 завершены, незаконченной сборки нет.
Проверки:1180/435/1893/374/22680/67/9869,AI0failures,1197костей,1164idleканала.
Дополнительно: beetle_integrity, beetle_tunnels, beetle_attachment --poses, cloth_integrity, kolossar_integrity.
**Окончательный экспортированный PCK:**2полныхматча за17/20ходов,13боёв,exit0,без engine errors.
Windows ZIP создан заново, CRC всех5файлов OK; GitHub SHA256 всех3вложений совпали с локальными.

- `build/win028/`: EXE/PCK и лицензии.
- `build/Sfery_Stikhiy_v0.2.8_win64.zip`:840299211bytes.
- SHA256: `c477c0a08666cb89e7ea6b0165314f165dfcbcb783b6fb2c0e0660460179c9ac`.
- `build/review028_before_after.jpg`: финальное сравнение, включая правильный attachment anatomy13.
- `tools/checkpoints/release028-validation.json`: hashes15GLB, GPU/деформации/тесты/архив/публикация.
- `tools/_tmp/review028/`: реальные before/after, длинные движения, логи, GPU buffers; всё в workspace.
- Старый отклонённый ZIP с подвешенными корнями — только `tools/_tmp/review028/rejected-pre-attachment.zip`, не выдавать пользователю.

Публикация сначала была отклонена automatic approval review без прямого разрешения на внешний push. Автор затем явно ответил «Да, опубликовать0.2.8». После этого выполнены push/tag, загрузка3файлов, сравнение SHA и публикация release429219129 (draft=false), ссылка выше проверена. Повторное разрешение для уже выполненного действия не нужно.

## Сохранность и воспроизведение
Backups в tools/_tmp: stone028-base, stone028-geometry, stone028-atlas-base, water-beetle027-base, gpucloth028-base, likorez028-base, kolossar-arms028-base.
Каменный pipeline: repair_stone → Blender bake → fill_bake_misses → apply_baked_atlas → compact → smooth_repaired_beetle_weights.
Water: repair_water_beetle.py (idempotent anatomy13) → compact. Не возвращать ellipsoid/fan caps или старый offset наружу.
Cloth: split_gpu_capes.py (источник gpucloth028-base), runtime creature_cloth.gd. Подробности в tools/models/README.md и addons/godot_gpu_cloth/LOCAL_CHANGES.md.

Честные ограничения: исходная tide-cape bending edge пропускается; на выходе ранних source-autoplay/короткого smoke были cached-resource diagnostics, без новых invalid-RID, окончательная серия из PCK прошла чисто. NativeWindows не запускался (нет Wine): проверены экспорт/PCK Linux/Vulkan/CRC. Не объявлять доказанным отсутствие любого растяжения: диагностические числа сохранены отдельно от проверок дыр/attachment. Ждать конкретной обратной связи автора, не начинать новый массовый проход без причины.
