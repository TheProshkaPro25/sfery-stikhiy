"""Сборка звуков «Сфер Стихий» из записанных CC0/CC-BY паков (+ синтезированные слои gen_sfx.py).

Запуск:
    SFX_SRC=/путь/к/sfx_src  python tools/audio/build_sfx.py
Нужны: numpy, scipy, soundfile, ffmpeg (libvorbis). Пишет OGG (моно, 44.1 кГц, q5) в
assets/audio/sfx/ и assets/audio/creatures/, и таблицу CREDITS.md в корне проекта.

SFX_SRC — каталог с распакованными паками (каждый в своей папке, имена — ключи PACKS ниже).
Скачать паки: ссылки в PACKS (OpenGameArt, прямые zip). Исходники в репозиторий не кладём.

Существа: 8 видов × 6 стихий × (appear, attack) = 96 файлов. Основа — записанный голос,
подобранный по виду; стихия — обработка голоса + записанный слой (огонь — магический огненный удар и треск,
вода — всплески и бульканье, буря — порывы воздуха, камень — осыпь и удары камня, свет — колокольчики
и стекло, тьма — реверс голоса и «тени»).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import gen_sfx as g  # noqa: E402  синтезированные слои (детерминированные)
from sfxlib import (SR, bp, chorus, db, fade, fit, follow, hp, load, loopify, lp, mix,  # noqa: E402
                    norm, pitch, reverb, rev, sat, seg, tremolo, trim, write_ogg)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "audio")

# Папка в SFX_SRC -> (название, автор, лицензия, ссылка). Только CC0 / CC-BY.
PACKS = {
    "oga_80-CC0-creature-SFX_0": ("80 CC0 creature SFX", "rubberduck", "CC0", "https://opengameart.org/content/80-cc0-creature-sfx"),
    "oga_100-CC0-SFX_0": ("100 CC0 SFX", "rubberduck", "CC0", "https://opengameart.org/content/100-cc0-sfx"),
    "oga_sfx_100_v2": ("100 CC0 SFX #2", "rubberduck", "CC0", "https://opengameart.org/content/100-cc0-sfx-2"),
    "oga_sfx_breaking_and_falling": ("75 CC0 breaking / falling / hit sfx", "rubberduck", "CC0", "https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx"),
    "oga_rpg_sound_pack": ("RPG Sound Pack", "artisticdude", "CC0", "https://opengameart.org/content/rpg-sound-pack"),
    "oga_kenney_interfaceSounds": ("Interface Sounds", "Kenney (www.kenney.nl)", "CC0", "https://opengameart.org/content/interface-sounds"),
    "oga_UI_SFX_Set": ("51 UI sound effects", "Kenney (www.kenney.nl)", "CC0", "https://opengameart.org/content/51-ui-sound-effects-buttons-switches-and-clicks"),
    "oga_Fantasy_Sound_Library": ("Fantasy Sound Effects Library", "Little Robot Sound Factory (www.littlerobotsoundfactory.com)", "CC-BY 3.0", "https://opengameart.org/content/fantasy-sound-effects-library"),
    "oga_Magic_SFX_Preview_Pack": ("Magic SFX Sample", "ViRiX (David McKee)", "CC-BY 3.0", "https://opengameart.org/content/magic-sfx-sample"),
}
C = "oga_80-CC0-creature-SFX_0/"
S1 = "oga_100-CC0-SFX_0/"
S2 = "oga_sfx_100_v2/sfx100v2_"
BF = "oga_sfx_breaking_and_falling/bfh1_"
R = "oga_rpg_sound_pack/RPG Sound Pack/"
KI = "oga_kenney_interfaceSounds/Audio/"
KU = "oga_UI_SFX_Set/"
FA = "oga_Fantasy_Sound_Library/Fantasy Sound Library/Wav/"
MG = "oga_Magic_SFX_Preview_Pack/"

credits_rows: list = []  # (файл в игре, [ключи источников], синтез?)


def L(key, t0=0.0, dur=None, db_=-42):
    """Записанный исходник: отрезок и обрезка тишины."""
    return trim(seg(load(key), t0, dur), db_)


def synth(x):
    return np.asarray(x, np.float32)


def out(rel, x, rms_db=-18.0, peak_db=-1.0, synth_used=False, tail=True):
    y = norm(trim(x, -55) if tail else x, rms_db, peak_db)
    write_ogg(os.path.join(OUT, rel), y)
    credits_rows.append((rel, list(_taken), synth_used))
    _taken.clear()


_taken: list = []
_orig_load = load


def load(key):  # noqa: F811  — запоминаем, какие файлы взяты в текущий звук
    _taken.append(key)
    return _orig_load(key)


# ---------------------------------------------------------------- интерфейс

def ui():
    out("sfx/ui_hover.ogg", L(KU + "rollover2.wav"), -30)
    out("sfx/ui_click.ogg", mix((L(KI + "click_001.ogg"), 0, 0), (L(KU + "click3.wav"), 0, -8)), -24)
    sel = mix((L(KI + "select_003.ogg"), 0, 0), (L(R + "inventory/cloth.wav"), 0, -10))
    out("sfx/card_select.ogg", reverb(sel, 0.12, 0.5), -22)
    # карта ворот ложится на стол: бумага + глухой деревянный стук
    pl = mix((L(S1 + "paper_01.ogg"), 0, 0), (lp(L(S1 + "wooden_02.ogg"), 1800), 0.03, -2), (L(KI + "drop_002.ogg"), 0.02, -9))
    out("sfx/card_place.ogg", reverb(pl, 0.12, 0.5), -20)
    # открытие ворот: шорох карты, низкий гонг, тяжёлая дверь, магическое мерцание
    gong = pitch(L(S1 + "gong_02.ogg"), -5)
    door = lp(pitch(L(R + "world/door.wav"), -3), 3500)
    shim = L(MG + "Misc 02.wav")
    fl = mix((L(S1 + "paper_02.ogg"), 0, -4), (door, 0.05, -3), (gong, 0.12, -2), (shim, 0.15, 2))
    out("sfx/card_flip.ogg", reverb(fl, 0.25, 1.4), -18)
    # захват карты: монетный звон + подтверждение + шорох карты
    # без монет и звоночков: шорох карты, низкий удар металла и гонг вниз — «трофей взят»
    cap = mix((L(S1 + "paper_03.ogg"), 0, -2), (synth(g.metal_hit(110, 1.0, 0.4)), 0.08, -4),
              (synth(g.boom(0.9, 48, 2.0, 0.8)), 0.08, -8), (pitch(L(S1 + "gong_01.ogg"), -9), 0.1, -6))
    out("sfx/card_capture.ogg", reverb(lp(cap, 6000), 0.18, 1.0), -19, synth_used=True)
    # начало хода: глухой удар-«барабан» и короткий низкий металл, без колокольчика
    tb = mix((synth(g.boom(0.7, 62, 1.5, 0.9)), 0, 0), (synth(g.metal_hit(140, 0.6, 0.3)), 0.01, -8))
    out("sfx/turn_start.ogg", reverb(lp(tb, 4000), 0.22, 1.2), -22, synth_used=True)


# ---------------------------------------------------------------- шар

def ball():
    th = mix((pitch(L(S2 + "air_03.ogg"), -4), 0, 0), (pitch(L(R + "battle/swing2.wav"), -5), 0.02, -3),
             (synth(g.heavy_whoosh(0.4, 250, 2200, 1.0)), 0, -14))
    out("sfx/ball_throw.ogg", reverb(th, 0.1, 0.5), -18, synth_used=True)
    for i, (k, p) in enumerate([(BF + "rock_hit_01.ogg", -2), (S2 + "stones_01.ogg", 0), (BF + "hit_05.ogg", 1)]):
        x = fit(lp(pitch(L(k), p), 7000), 0.35)
        out(f"sfx/ball_bounce_{i + 1}.ogg", fade(x, 0, 0.05), -20)
    # качение: синтезированный шорох (петля) + записанная каменная осыпь, отфильтрованная в мягкий гул
    rl = np.concatenate([L(S2 + "stones_02.ogg"), L(S2 + "stones_03.ogg"), L(S2 + "stones_01.ogg")])
    rl = lp(pitch(rl, -7), 1800)
    n = len(rl)
    base = g.bp(g.noise(n / SR + 0.2), 300, 2500)[: n]
    base = base * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * np.arange(n) / SR))
    loop = mix((rl, 0, 0), (synth(base) * 0.3, 0, -6))
    loop = loopify(loop[: int(1.6 * SR)], 0.3)
    out("sfx/ball_roll_loop.ogg", loop, -22, synth_used=True, tail=False)
    land = mix((L(BF + "rock_falling_03.ogg"), 0, -2), (lp(L(S1 + "slam_02.ogg"), 2500), 0, -2),
               (synth(g.boom(0.4, 80, 1.2, 0.8)), 0, -8))
    out("sfx/ball_land.ogg", reverb(land, 0.15, 0.8), -17, synth_used=True)
    # раскрытие: щелчок сферы, подъём энергии (заклинание), удар появления
    op = mix((L(R + "inventory/metal-small2.wav"), 0, -6), (L(FA + "Spell_00.wav"), 0.05, -2),
             (L(MG + "Healing Full.wav", 0.15, 1.3), 0.1, -6),
             (lp(L(MG + "Fire impact 1.wav", 0, 1.6), 900), 0.5, -2), (synth(g.boom(1.0, 45, 3.0, 1.0)), 0.5, -8))
    out("sfx/capsule_open.ogg", reverb(op, 0.22, 1.6), -17, synth_used=True)


# ---------------------------------------------------------------- бой

def battle():
    bs = mix((pitch(L(S1 + "gong_01.ogg"), -9), 0, 0), (L(FA + "Trap_01.wav"), 0, -6),
             (synth(g.boom(1.4, 40, 3.0, 1.0)), 0, -6), (pitch(L(S1 + "gong_02.ogg"), -12), 0.7, -3),
             (synth(g.boom(1.0, 45, 2.5, 0.9)), 0.7, -8))
    out("sfx/battle_start.ogg", reverb(bs, 0.25, 1.8), -17, synth_used=True)
    cl = mix((L(BF + "hit_01.ogg"), 0, 0), (L(S1 + "slam_01.ogg"), 0, -3), (L(R + "inventory/metal-ringing.wav"), 0.01, -9),
             (synth(g.boom(0.9, 42, 3.5, 1.0)), 0, -6), (pitch(L(S2 + "air_03.ogg"), -6), 0, -8))
    out("sfx/clash.ogg", reverb(sat(cl, 1.6), 0.2, 1.2), -15, synth_used=True)
    up = mix((L(FA + "Spell_01.wav"), 0, 0), (L(MG + "Ice attack 2.wav"), 0.05, -9))
    out("sfx/power_up.ogg", reverb(up, 0.2, 1.0), -19)
    dn = mix((pitch(L(FA + "Spell_01.wav"), -10), 0, 0), (lp(pitch(L(MG + "Wind effects 5.wav"), -5), 1500), 0, -6))
    out("sfx/power_down.ogg", reverb(dn, 0.2, 1.0), -20)
    ms = mix((pitch(L(S2 + "air_02.ogg"), -3), 0, 0), (pitch(L(R + "battle/swing3.wav"), -6), 0.05, -4))
    out("sfx/miss.ogg", reverb(ms, 0.15, 0.8), -20)
    van = mix((L(MG + "Wind effects 5.wav"), 0, 0), (rev(L(FA + "Spell_00.wav")), 0, -6))
    out("sfx/vanish.ogg", reverb(lp(van, 5000), 0.25, 1.2), -20)
    el = mix((L(BF + "rock_breaking_01.ogg"), 0, 0), (L(MG + "Fire impact 1.wav", 0, 2.0), 0.02, -2),
             (synth(g.boom(1.2, 38, 2.5, 0.9)), 0.03, -6), (pitch(L(R + "NPC/shade/shade8.wav"), -8), 0.1, -8))
    out("sfx/eliminated.ogg", reverb(lp(el, 6000), 0.3, 1.8), -15, synth_used=True)
    # победа/поражение — без джинглов: тяжёлые удары, пауэр-аккорд без терции, гул (серьёзный тон)
    win = mix((synth(g.boom(1.4, 50, 2.5, 1.0)), 0, 0), (L(BF + "rock_breaking_01.ogg"), 0, -6),
              (synth(g.stinger(1.6, 55, minor=False)), 0.02, -4), (pitch(L(S1 + "gong_02.ogg"), -10), 0.05, -9))
    out("sfx/battle_win.ogg", fade(reverb(win, 0.25, 1.6), 0, 0.4), -18, synth_used=True)
    lose = mix((synth(g.boom(1.0, 40, 1.5, 0.9)), 0, 0), (synth(g.whoosh(1.0, 1600, 160, 0.4, 1.0)), 0, -6),
               (lp(pitch(L(S1 + "gong_02.ogg"), -14), 1200), 0.1, -6))
    out("sfx/battle_lose.ogg", fade(reverb(lp(lose, 3000), 0.3, 1.6), 0, 0.5), -20, synth_used=True)
    vic = mix((synth(g.energy_rise(1.1, 60, 420, 0.8)), 0, -4), (synth(g.boom(2.0, 46, 2.5, 1.0)), 1.1, 0),
              (L(S1 + "explosion.ogg"), 1.1, -8), (synth(g.stinger(3.2, 49, minor=False)), 1.12, -2),
              (synth(g.stinger(2.4, 73.4, minor=False)), 1.9, -9), (pitch(L(S1 + "gong_02.ogg"), -8), 1.12, -8))
    out("sfx/victory.ogg", fade(reverb(vic, 0.3, 2.0), 0, 1.2), -17, synth_used=True)
    df = mix((synth(g.stinger(3.4, 41.2, minor=True)), 0, 0), (synth(g.boom(1.6, 36, 1.2, 1.0)), 0, -4),
             (lp(pitch(L(S1 + "gong_02.ogg"), -14), 1500), 0.2, -5), (lp(L(BF + "rock_falling_01.ogg"), 1500), 0.4, -12))
    out("sfx/defeat.ogg", fade(reverb(lp(df, 2600), 0.3, 2.0), 0, 1.2), -19, synth_used=True)
    # ловушка ворот: механизм ловушки + треск + провал силы
    tr = mix((L(FA + "Trap_00.wav"), 0, 0), (L(FA + "Trap_02.wav"), 0.15, -3), (L(BF + "breaking_02.ogg"), 0.02, -6),
             (pitch(L(FA + "Spell_01.wav"), -10), 0.35, -6))
    out("sfx/gate_trap.ogg", reverb(tr, 0.2, 1.2), -16)


# ---------------------------------------------------------------- способности

def abilities():
    out("sfx/ability_play.ogg", reverb(mix((L(FA + "Spell_04.wav", 0, 2.4), 0, 0), (L(MG + "Misc 02.wav"), 0.6, 0)), 0.2, 1.2), -18)
    can = mix((rev(L(FA + "Spell_00.wav")), 0, -2), (L(KI + "error_006.ogg"), 0.5, -6), (L(BF + "glass_breaking_02.ogg"), 0.5, -8))
    out("sfx/ability_cancel.ogg", reverb(can, 0.2, 1.0), -19)
    out("sfx/ability_fusion.ogg", reverb(mix((L(FA + "Spell_02.wav"), 0, 0), (L(MG + "Healing Full.wav"), 0.3, -4)), 0.2, 1.2), -18)
    fire = mix((L(MG + "Fire impact 1.wav", 0, 2.4), 0, 0), (synth(g.element_layer(0, 1.5, np.random.default_rng(5))), 0.1, -4))
    out("sfx/ability_fire.ogg", reverb(fire, 0.15, 1.0), -17, synth_used=True)
    gale = mix((L(MG + "Wind effects 5.wav"), 0, 0), (L(S2 + "air_01.ogg"), 0.1, -4))
    out("sfx/ability_gale.ogg", reverb(gale, 0.15, 1.0), -18)
    # свет: сияние без колокольчиков — магический гул + нарастание энергии вверх
    light = mix((L(MG + "Healing Full.wav"), 0, 0), (synth(g.energy_rise(0.9, 200, 1400, 0.7)), 0, -8))
    out("sfx/ability_light.ogg", reverb(lp(light, 9000), 0.3, 1.6), -19, synth_used=True)
    stone = mix((L(BF + "rock_breaking_02.ogg"), 0, 0), (L(BF + "rock_falling_01.ogg"), 0.2, -3), (synth(g.boom(0.9, 45, 2.0, 1.0)), 0, -6))
    out("sfx/ability_stone.ogg", reverb(stone, 0.2, 1.2), -16, synth_used=True)
    shadow = mix((pitch(L(R + "NPC/shade/shade12.wav"), -5), 0.15, -2), (rev(reverb(L(FA + "Spell_00.wav"), 0.6, 1.2)), 0, -6))
    out("sfx/ability_shadow.ogg", reverb(lp(shadow, 6000), 0.25, 1.4), -19)
    tide = mix((L(S1 + "splash_01.ogg"), 0, 0), (L(R + "inventory/bubble3.wav"), 0.15, -4), (L(MG + "Ice attack 2.wav"), 0.0, -8))
    out("sfx/ability_tide.ogg", reverb(chorus(tide, 0.005, 0.8, 0.4), 0.2, 1.0), -18)


# ---------------------------------------------------------------- существа

ATTRS = ["fire", "gale", "light", "stone", "shadow", "tide"]
ATTR_PITCH = [0.0, 1.0, 2.0, -3.0, -2.0, -1.0]  # стихия чуть сдвигает голос: свет выше, камень ниже
# вид -> {kind: [(ключ, полутоны, [доп. слои (ключ, сдвиг, дБ, полутоны)]) ...]}; вариант = стихия % len
SPECIES = {
    "dragnar": {
        "appear": [(FA + "Dragon_Growl_00.wav", -1, []), (FA + "Dragon_Growl_01.wav", -2, []), (C + "roar_02.ogg", -4, [(C + "monster_07.ogg", 0.1, -6, -2)])],
        "attack": [(C + "roar_03.ogg", -4, []), (C + "monster_06.ogg", -3, []), (C + "monster_01.ogg", -5, [])],
    },
    "klykar": {
        "appear": [(C + "howl.ogg", -2, [(C + "grunt_02.ogg", 0.5, -6, -2)]), (R + "NPC/misc/wolfman.wav", -2, [(C + "howl.ogg", 0.25, -4, -3)]),
                   (C + "barking_01.ogg", -3, [(C + "grunt_02.ogg", 0.2, -4, -3)])],
        "attack": [(C + "barking_02.ogg", -3, []), (C + "barking_01.ogg", -2, []), (R + "NPC/misc/wolfman.wav", -1, [])],
    },
    "grifalon": {
        "appear": [(C + "scream_01.ogg", -2, [(S2 + "air_02.ogg", 0, -6, -2)]), (C + "scream_02.ogg", -1, [(S2 + "air_02.ogg", 0, -6, -3)]),
                   (C + "alien_04.ogg", -3, [(C + "scream_01.ogg", 0.3, -4, -3)])],
        "attack": [(C + "alien_03.ogg", -2, []), (C + "scream_02.ogg", 0, []), (C + "alien_02.ogg", -3, [])],
    },
    "kolossar": {
        "appear": [(R + "NPC/giant/giant2.wav", -2, [(R + "NPC/giant/giant5.wav", 0.6, -3, -3)]), (R + "NPC/giant/giant5.wav", -2, []),
                   (C + "troll_01.ogg", -3, [(R + "NPC/giant/giant2.wav", 0.4, -4, -3)])],
        "attack": [(R + "NPC/giant/giant1.wav", -2, []), (R + "NPC/giant/giant4.wav", -2, []), (R + "NPC/ogre/ogre3.wav", -3, [])],
    },
    "rogozhuk": {
        "appear": [(C + "bug_04.ogg", -2, [(R + "NPC/beetle/bite-small3.wav", 0.35, -3, -2)]), (C + "bug_02.ogg", -3, [(C + "bug_03.ogg", 0.3, -3, -3)]),
                   (C + "alien_05.ogg", -4, [(R + "NPC/beetle/bite-small.wav", 0.3, -2, -3)])],
        "attack": [(R + "NPC/beetle/bite-small.wav", -2, [(C + "bug_03.ogg", 0.05, -4, -2)]), (R + "NPC/beetle/bite-small3.wav", -3, []), (C + "bug_03.ogg", -3, [])],
    },
    "levian": {
        "appear": [(C + "spit_02.ogg", -4, [(C + "burble_01.ogg", 0.2, -6, -4)]), (C + "burble_01.ogg", -5, [(C + "spit_02.ogg", 0.3, -3, -3)]),
                   (C + "weird_05.ogg", -2, [(C + "spit_01.ogg", 0.25, -3, -3)])],
        "attack": [(C + "spit_01.ogg", -3, []), (C + "spit_03.ogg", -3, []), (C + "spit_02.ogg", -2, [])],
    },
    "ratnik": {
        "appear": [(R + "battle/sword-unsheathe.wav", 0, [(C + "grunt_04.ogg", 0.25, -2, -3), (R + "inventory/chainmail1.wav", 0.0, -8, 0)]),
                   (R + "battle/sword-unsheathe2.wav", 0, [(C + "grunt_05.ogg", 0.25, -2, -3), (R + "inventory/armor-light.wav", 0.0, -6, 0)]),
                   (R + "battle/sword-unsheathe5.wav", 0, [(C + "grunt_01.ogg", 0.2, -2, -3), (R + "inventory/chainmail2.wav", 0.0, -8, 0)])],
        "attack": [(R + "battle/swing.wav", -2, [(R + "inventory/metal-small1.wav", 0.12, -4, -3), (C + "grunt_05.ogg", 0.0, -4, -3)]),
                   (R + "battle/swing2.wav", -2, [(R + "inventory/metal-ringing.wav", 0.1, -6, -4), (C + "grunt_04.ogg", 0.0, -4, -3)]),
                   (R + "battle/swing3.wav", -2, [(R + "inventory/metal-small3.wav", 0.1, -4, -3), (C + "grunt_01.ogg", 0.0, -4, -4)])],
    },
    "gorgul": {
        "appear": [(R + "NPC/shade/shade8.wav", -3, [(BF + "rock_falling_01.ogg", 0.1, -8, -2)]), (R + "NPC/shade/shade9.wav", -3, [(BF + "rock_falling_05.ogg", 0.1, -8, -2)]),
                   (R + "NPC/shade/shade12.wav", -4, [(BF + "rock_falling_09.ogg", 0.1, -8, -2)])],
        "attack": [(R + "NPC/shade/shade14.wav", -3, [(BF + "rock_hit_01.ogg", 0.05, -6, -3)]), (R + "NPC/shade/shade5.wav", -3, [(BF + "rock_hit_01.ogg", 0.05, -6, -4)]),
                   (R + "NPC/shade/shade15.wav", -4, [(S2 + "stones_02.ogg", 0.05, -6, -3)])],
    },
}

# записанные слои стихий: (appear, attack)
ELEM_LAYER = {
    "fire": ((MG + "Fire impact 1.wav", 0.0, 2.2), (MG + "Fire impact 1.wav", 0.0, 1.2)),
    "gale": ((S2 + "air_01.ogg", 0.0, None), (S2 + "air_02.ogg", 0.0, None)),
    "light": ((MG + "Healing Full.wav", 0.1, 2.0), (MG + "Misc 02.wav", 0.0, None)),
    "stone": ((BF + "rock_breaking_01.ogg", 0.0, None), (BF + "rock_falling_03.ogg", 0.0, None)),
    "shadow": ((R + "NPC/shade/shade7.wav", 0.0, None), (R + "NPC/shade/shade2.wav", 0.0, None)),
    "tide": ((S1 + "splash_02.ogg", 0.0, None), (R + "inventory/bubble2.wav", 0.0, None)),
}


def voice_fx(v, attr, kind="appear"):
    """Окраска голоса стихией."""
    if attr == "fire":
        return hp(sat(v, 2.4), 70)
    if attr == "gale":
        return chorus(tremolo(hp(v, 160), 11.0, 0.25), 0.003, 1.3, 0.35)
    if attr == "light":
        octave = hp(pitch(v, 12)[: len(v)], 900)
        return mix((v, 0, 0), (octave, 0, -12))
    if attr == "stone":
        return lp(v, 5000) + lp(v, 220) * 0.8
    if attr == "shadow":
        pre = rev(reverb(rev(v), 0.8, 0.9 if kind == "appear" else 0.3))  # реверсный хвост-предвестник (в атаке короткий — не опаздывать к удару)
        return mix((lp(pre, 4500), 0, -6), (lp(v, 7000), len(pre) / SR - len(v) / SR, 0))
    if attr == "tide":
        return lp(chorus(v, 0.006, 0.6, 0.5), 5000)
    return v


def creature(species, ai, kind):
    attr = ATTRS[ai]
    variants = SPECIES[species][kind]
    key, semis, extra = variants[ai % len(variants)]
    semis += ATTR_PITCH[ai] * (0.5 if species == "ratnik" else 1.0)
    v = pitch(L(key), semis)
    parts = [(v, 0, 0)]
    for k, off, gdb, p in extra:
        parts.append((pitch(L(k), p + ATTR_PITCH[ai] * 0.5), off, gdb))
    v = mix(*parts)
    v = fit(v, 2.6 if kind == "appear" else 1.4)
    v = trim(v, -45)
    v = voice_fx(v, attr, kind)
    lk, t0, dur = ELEM_LAYER[attr][0 if kind == "appear" else 1]
    layer = L(lk, t0, dur)
    if attr == "stone":
        layer = lp(pitch(layer, -3), 4000)
    if attr == "shadow":
        layer = rev(lp(pitch(layer, -6), 3000))
    if attr == "light":
        layer = hp(layer, 1500)
    layer = fit(layer, max(len(v) / SR, 0.3))
    syn = synth(g.element_layer(ai, len(v) / SR, np.random.default_rng(200 + ai)))
    lay = mix((follow(layer, v, 0.05, 0.35), 0, 0), (follow(syn, v, 0.05, 0.3), 0, -6))
    y = mix((v, 0, 0), (lay, 0, -7 if kind == "appear" else -9))
    if kind == "appear":
        y = mix((y, 0, 0), (synth(g.boom(0.8, 50, 2.0, 0.6)), 0, -14))
    y = reverb(y, 0.16 if kind == "attack" else 0.22, 0.9)
    out(f"creatures/{species}_{attr}_{kind}.ogg", y, -16, synth_used=True)


def creatures():
    for sp in SPECIES:
        for ai in range(6):
            for kind in ("appear", "attack"):
                creature(sp, ai, kind)


# ---------------------------------------------------------------- CREDITS.md

def write_credits():
    lines = [
        "# Авторы и лицензии",
        "",
        "## Звуковые эффекты",
        "",
        "Все звуки собраны скриптом `tools/audio/build_sfx.py` из записанных паков ниже (обработка: обрезка, сдвиг высоты,",
        "фильтры, реверберация, слоение, нормализация громкости, OGG Vorbis). Часть звуков содержит синтезированные слои",
        "(`tools/audio/gen_sfx.py`, собственная разработка проекта). Музыка — отдельно (делается автором игры).",
        "",
        "### Паки-источники",
        "",
        "| Пак | Автор | Лицензия | Ссылка |",
        "|---|---|---|---|",
    ]
    packs_used = sorted({k.split("/")[0] for _, ks, _ in credits_rows for k in ks})
    for p in packs_used:
        n, a, lic, url = PACKS[p]
        lines.append(f"| {n} | {a} | {lic} | {url} |")
    lines += [
        "",
        "CC-BY 3.0 требует указания автора: Little Robot Sound Factory (www.littlerobotsoundfactory.com) — Fantasy Sound",
        "Effects Library; ViRiX (David McKee) — Magic SFX Sample. Лицензия: https://creativecommons.org/licenses/by/3.0/.",
        "CC0 — авторство не обязательно, указано из уважения.",
        "",
        "### Файл в игре → источники",
        "",
        "| Файл | Источник (пак / файл) | Автор | Лицензия | Синт. слой |",
        "|---|---|---|---|---|",
    ]
    for rel, keys, syn in credits_rows:
        uniq = list(dict.fromkeys(keys))
        src = "; ".join(f"{PACKS[k.split('/')[0]][0]} / {os.path.basename(k)}" for k in uniq)
        authors = ", ".join(dict.fromkeys(PACKS[k.split("/")[0]][1].split(" (")[0] for k in uniq))
        lics = ", ".join(dict.fromkeys(PACKS[k.split("/")[0]][2] for k in uniq))
        lines.append(f"| assets/audio/{rel} | {src} | {authors} | {lics} | {'да' if syn else '—'} |")
    open(os.path.join(ROOT, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    if not os.path.isdir(os.environ.get("SFX_SRC", "")):
        sys.exit("укажите SFX_SRC — каталог с распакованными паками (см. PACKS)")
    ui()
    ball()
    battle()
    abilities()
    creatures()
    write_credits()
    print("готово:", len(credits_rows), "файлов")
