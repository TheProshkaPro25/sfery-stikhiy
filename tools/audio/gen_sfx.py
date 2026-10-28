"""Процедурные звуковые эффекты «Сфер Стихий»: серьёзный боевой стиль (тяжёлые удары, металл, энергия, низ).

Сейчас в игре записанные звуки (tools/audio/build_sfx.py); отсюда build_sfx.py берёт синтезированные слои
(boom, heavy_whoosh, element_layer...). Отдельный запуск пишет старые WAV-версии в tools/audio/synth_out/
(с .gdignore — Godot их не импортирует), для сравнения:
    ~/ai/Hunyuan3D-2/.venv/bin/python tools/audio/gen_sfx.py
Всё детерминировано (фиксированные seed), перегенерация даёт те же файлы.
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "synth_out")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- примитивы

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env_ad(n, attack=0.005, decay=0.2, curve=4.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) * curve / max(decay, 1e-4))
    return a * d


def env_asr(n, attack=0.01, release=0.05):
    e = np.ones(n)
    na, nr = int(attack * SR), int(release * SR)
    if na > 0:
        e[:na] = np.linspace(0, 1, na)
    if nr > 0:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def osc(freq, dur, kind="sine", phase=0.0):
    """freq: число или массив мгновенной частоты."""
    n = int(dur * SR)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)[:n]
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":  # аддитивная пила, без алиасинга до ~10 кГц
        out = np.zeros(n)
        for k in range(1, 30):
            mask = f * k < 12000
            out += mask * np.sin(ph * k) / k
        return out * 0.6
    if kind == "square":
        out = np.zeros(n)
        for k in range(1, 30, 2):
            mask = f * k < 12000
            out += mask * np.sin(ph * k) / k
        return out * 0.8
    raise ValueError(kind)


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def lp(x, cutoff, order=2):
    sos = butter(order, min(cutoff, SR * 0.45), "low", fs=SR, output="sos")
    return sosfilt(sos, x)


def hp(x, cutoff, order=2):
    sos = butter(order, cutoff, "high", fs=SR, output="sos")
    return sosfilt(sos, x)


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return sosfilt(sos, x)


def sweep_filter(x, f0, f1, kind="band", q=0.3, steps=48):
    """Фильтр с плавно меняющейся частотой (блоками) - для свистов."""
    n = len(x)
    out = np.zeros(n)
    edges = np.linspace(0, n, steps + 1).astype(int)
    zi = None
    for i in range(steps):
        a, b = edges[i], edges[i + 1]
        fc = f0 * (f1 / f0) ** (i / max(steps - 1, 1))
        lo, hi = fc * (1 - q), min(fc * (1 + q), SR * 0.45)
        bb, aa = butter(2, [lo, hi], "band", fs=SR)
        if zi is None or len(zi) != max(len(aa), len(bb)) - 1:
            zi = np.zeros(max(len(aa), len(bb)) - 1)
        out[a:b], zi = lfilter(bb, aa, x[a:b], zi=zi)
    return out


def reverb(x, mix=0.25, size=1.0, tail=1.2):
    """Простой Шрёдер: 4 гребёнки + 2 всепропускающих. Хвост добавляется в конец."""
    pad = np.concatenate([x, np.zeros(int(tail * SR))])
    combs = [0.0297, 0.0371, 0.0411, 0.0437]
    wet = np.zeros_like(pad)
    for d in combs:
        dl = int(d * size * SR)
        g = 0.78
        b = np.zeros(dl + 1); b[0] = 1
        a = np.zeros(dl + 1); a[0] = 1; a[dl] = -g
        wet += lfilter(b, a, pad)
    for d, g in [(0.005, 0.7), (0.0017, 0.7)]:
        dl = int(d * SR)
        b = np.zeros(dl + 1); b[0] = -g; b[dl] = 1
        a = np.zeros(dl + 1); a[0] = 1; a[dl] = -g
        wet = lfilter(b, a, wet)
    wet = lp(wet, 6000) / len(combs)
    return pad * (1 - mix) + wet * mix


def place(buf, x, at):
    i = int(at * SR)
    end = min(len(buf), i + len(x))
    buf[i:end] += x[: end - i]
    return buf


def silence(dur):
    return np.zeros(int(dur * SR))


def bell(freq, dur=0.6, bright=1.0, decay=None):
    """Колокольчик: синус + негармонические обертоны, быстрая атака."""
    n = int(dur * SR)
    decay = decay or dur
    out = np.zeros(n)
    for ratio, amp, dk in [(1, 1, 1), (2.0, 0.35 * bright, 1.6), (2.76, 0.25 * bright, 2.2), (5.4, 0.12 * bright, 3.5)]:
        out += amp * osc(freq * ratio, dur) * env_ad(n, 0.002, decay / dk, 5)
    return out


def sparkle(dur=0.6, base=2600, count=9, seed=1, spread=0.45):
    """«Кира-кира»: россыпь коротких высоких колокольчиков."""
    r = np.random.default_rng(seed)
    buf = silence(dur + 0.4)
    pent = [1, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2]
    for i in range(count):
        at = spread * dur * (i / count) + r.uniform(0, 0.03)
        f = base * r.choice(pent) * r.choice([1, 2])
        place(buf, bell(f, 0.25, 0.6) * r.uniform(0.25, 0.6), at)
    return buf


def whoosh(dur, f0, f1, q=0.35, level=1.0):
    n = noise(dur)
    s = sweep_filter(n, f0, f1, q=q)
    e = np.sin(np.linspace(0, np.pi, len(s))) ** 1.5
    return s * e * level


def thump(freq=90, dur=0.25, drop=2.0):
    n = int(dur * SR)
    f = freq * np.exp(-np.arange(n) / SR * 18) * drop + freq
    return osc(f, dur) * env_ad(n, 0.001, dur * 0.6, 5)


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade_out(x, dur=0.03):
    n = int(dur * SR)
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def save(rel, x, peak=0.8):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = fade_out(norm(x, peak))
    # обрезаем тишину в хвосте
    nz = np.where(np.abs(x) > 0.0015)[0]
    if len(nz):
        x = x[: min(len(x), nz[-1] + int(0.02 * SR))]
        x = fade_out(x, 0.01)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def note(semi, base=440.0):
    return base * 2 ** (semi / 12)


# ---------------------------------------------------------------- интерфейс, шар, бой (серьёзный стиль)

def drive(x, amt=2.0):
    """Мягкое насыщение (tanh): плотность и «вес» без хруста."""
    return np.tanh(x * amt) / np.tanh(amt)


def boom(dur=1.2, f0=55, drop=2.5, level=1.0):
    """Низкий удар-бум с саб-падением высоты."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + drop * np.exp(-t * 14))
    body = osc(f, dur) * env_ad(n, 0.002, dur * 0.7, 3.5)
    click = lp(noise(dur), 2500) * env_ad(n, 0.0005, 0.03, 5) * 0.5
    return drive(body + click, 1.6) * level


def metal_hit(freq=180, dur=0.8, bright=1.0):
    """Металлический удар: негармоничные низкие обертоны, без «звона колокольчика»."""
    n = int(dur * SR)
    out = np.zeros(n)
    for ratio, amp, dk in [(1, 1, 1), (1.47, 0.7, 1.3), (2.09, 0.5, 1.8), (2.56, 0.35 * bright, 2.5), (3.91, 0.2 * bright, 3.5)]:
        out += amp * osc(freq * ratio, dur) * env_ad(n, 0.001, dur / dk, 4)
    out += bp(noise(dur), 1500, 6000) * env_ad(n, 0.0005, 0.02, 5) * 0.4
    return out


def energy_rise(dur=0.8, f0=80, f1=600, level=1.0):
    """Нарастание энергии: детюн-пилы + шум с открывающимся фильтром."""
    n = int(dur * SR)
    f = np.geomspace(f0, f1, n)
    tone = (osc(f, dur, "saw") + osc(f * 1.007, dur, "saw") + 0.5 * osc(f * 0.5, dur, "saw")) * 0.4
    tone = sweep_filter(tone, 300, 4000, q=0.7)
    hiss = sweep_filter(noise(dur), 500, 7000, q=0.4) * 0.5
    e = np.linspace(0, 1, n) ** 2
    return drive((tone + hiss) * e, 1.5) * level


def heavy_whoosh(dur=0.5, f0=300, f1=1800, level=1.0):
    """Свист с весом: шумовая полоса + низкий гул."""
    w = whoosh(dur, f0, f1, 0.5, 1.0)
    n = len(w)
    rumble = lp(noise(dur), 220) * np.sin(np.linspace(0, np.pi, n)) * 1.2
    return (w + rumble) * level


def stinger(dur=1.2, root=55, minor=True):
    """Короткий аккорд-«удар» (пауэр-аккорд из насыщенных пил), без мажорной сладости."""
    n = int(dur * SR)
    x = np.zeros(n)
    for semi, a in [(0, 1.0), (7, 0.7), (12, 0.5)] + ([(3 + 12, 0.25)] if minor else []):
        f = root * 2 ** (semi / 12)
        x += a * (osc(f, dur, "saw") + osc(f * 1.004, dur, "saw"))
    x = lp(x, 2200) * env_ad(n, 0.005, dur * 0.8, 2.5)
    return drive(x * 0.5, 2.5)


def ui_sounds():
    n = int(0.03 * SR)
    hover = bp(noise(0.03), 2000, 6000) * env_ad(n, 0.0005, 0.012, 5)
    save("sfx/ui_hover.wav", hover, 0.25)

    click = silence(0.15)
    place(click, metal_hit(900, 0.08, 0.6) * 0.6, 0)
    place(click, lp(noise(0.02), 4000) * env_ad(int(0.02 * SR), 0.0003, 0.006, 5), 0)
    save("sfx/ui_click.wav", click, 0.5)

    sel = silence(0.35)
    place(sel, heavy_whoosh(0.18, 900, 3500, 0.5), 0)
    place(sel, metal_hit(420, 0.25, 0.5) * 0.6, 0.08)
    save("sfx/card_select.wav", reverb(sel, 0.12, tail=0.3), 0.6)

    pl = silence(0.5)
    place(pl, boom(0.35, 70, 1.5, 0.9), 0)
    place(pl, lp(noise(0.08), 3000) * env_ad(int(0.08 * SR), 0.0005, 0.03, 5) * 0.5, 0)
    save("sfx/card_place.wav", reverb(pl, 0.12, tail=0.3), 0.7)

    flip = silence(1.2)
    place(flip, heavy_whoosh(0.25, 400, 3000, 0.8), 0)
    place(flip, metal_hit(150, 0.9, 0.8), 0.18)
    place(flip, boom(0.7, 50, 2.0, 0.7), 0.18)
    save("sfx/card_flip.wav", reverb(flip, 0.25, tail=0.8), 0.8)

    turn = silence(0.8)
    place(turn, metal_hit(110, 0.7, 0.4) * 0.8, 0)
    save("sfx/turn_start.wav", reverb(turn, 0.25, tail=0.6), 0.45)


def ball_sounds():
    th = np.concatenate([heavy_whoosh(0.4, 250, 2200, 1.0), silence(0.1)])
    save("sfx/ball_throw.wav", reverb(th, 0.1, tail=0.2), 0.7)

    for i, f in enumerate([1300, 1500, 1700]):
        n = int(0.08 * SR)
        knock = metal_hit(f, 0.08, 0.7) * 0.7 + bp(noise(0.08), 2500, 8000) * env_ad(n, 0.0002, 0.006, 6) * 0.5
        save(f"sfx/ball_bounce_{i + 1}.wav", knock, 0.5)

    dur = 1.0
    r = bp(noise(dur + 0.2), 300, 2500)[int(0.1 * SR): int(0.1 * SR) + int(dur * SR)]
    t = t_axis(dur)
    r *= 0.7 + 0.3 * np.sin(2 * np.pi * 9 * t)
    xf = int(0.05 * SR)
    r[:xf] = r[:xf] * np.linspace(0, 1, xf) + r[-xf:] * np.linspace(1, 0, xf)
    r = r[:-xf]
    path = os.path.join(ROOT, "sfx/ball_roll_loop.wav")
    x = norm(r, 0.35)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

    land = silence(0.6)
    place(land, metal_hit(600, 0.3, 0.6), 0)
    place(land, boom(0.3, 90, 1.0, 0.5), 0)
    save("sfx/ball_land.wav", reverb(land, 0.15, tail=0.4), 0.65)

    # раскрытие: механический щелчок-раскрытие, всплеск энергии, тяжёлый удар появления
    op = silence(2.0)
    place(op, metal_hit(800, 0.12, 0.8) * 0.7, 0)
    place(op, metal_hit(1100, 0.1, 0.8) * 0.5, 0.06)
    place(op, energy_rise(0.45, 90, 700, 0.8), 0.08)
    place(op, boom(1.2, 45, 3.0, 1.0), 0.52)
    place(op, heavy_whoosh(0.6, 2500, 300, 0.6), 0.5)
    save("sfx/capsule_open.wav", reverb(op, 0.25, size=1.3, tail=1.0), 0.85)

    miss = silence(0.6)
    n = int(0.4 * SR)
    place(miss, osc(np.geomspace(300, 90, n), 0.4, "saw") * env_ad(n, 0.005, 0.35, 3) * 0.4, 0)
    miss = lp(miss, 1500)
    save("sfx/miss.wav", reverb(miss, 0.15, tail=0.3), 0.5)

    van = np.concatenate([heavy_whoosh(0.5, 2500, 200, 0.8), silence(0.2)])
    save("sfx/vanish.wav", reverb(van, 0.2, tail=0.4), 0.55)


def battle_sounds():
    bs = silence(2.2)
    place(bs, boom(1.4, 40, 3.0, 1.0), 0)
    place(bs, metal_hit(95, 1.4, 0.7) * 0.7, 0)
    place(bs, energy_rise(0.6, 60, 400, 0.5), 0.25)
    place(bs, stinger(1.3, 55, True) * 0.8, 0.85)
    place(bs, boom(1.0, 45, 2.5, 0.9), 0.85)
    save("sfx/battle_start.wav", reverb(bs, 0.25, size=1.4, tail=1.0), 0.9)

    ab = silence(1.8)
    place(ab, energy_rise(0.7, 70, 900, 1.0), 0)
    place(ab, boom(0.9, 50, 2.5, 0.9), 0.7)
    place(ab, heavy_whoosh(0.5, 3000, 400, 0.6), 0.7)
    place(ab, metal_hit(220, 0.8, 0.8) * 0.5, 0.7)
    save("sfx/ability_play.wav", reverb(ab, 0.25, size=1.3, tail=0.9), 0.85)

    can = silence(1.2)
    n = int(0.5 * SR)
    place(can, energy_rise(0.35, 300, 1200, 0.6), 0)
    place(can, osc(np.geomspace(800, 60, n), 0.5, "saw") * env_ad(n, 0.002, 0.45, 3) * 0.5, 0.33)
    place(can, bp(noise(0.3), 2000, 8000) * env_ad(int(0.3 * SR), 0.0005, 0.1, 5) * 0.6, 0.33)
    place(can, boom(0.5, 60, 1.5, 0.6), 0.33)
    save("sfx/ability_cancel.wav", reverb(drive(can, 1.4), 0.2, tail=0.6), 0.75)

    up = np.concatenate([energy_rise(0.6, 100, 800, 0.9), silence(0.3)])
    place(up, metal_hit(330, 0.4, 0.5) * 0.4, 0.58)
    save("sfx/power_up.wav", reverb(up, 0.2, tail=0.4), 0.6)

    n = int(0.6 * SR)
    dn = osc(np.geomspace(500, 70, n), 0.6, "saw") * env_ad(n, 0.005, 0.55, 3) * 0.5
    save("sfx/power_down.wav", reverb(lp(dn, 1800), 0.2, tail=0.4), 0.55)

    hit = silence(1.4)
    place(hit, boom(1.0, 42, 3.5, 1.0), 0)
    place(hit, hp(noise(0.2), 1200) * env_ad(int(0.2 * SR), 0.0003, 0.05, 6) * 1.0, 0)
    place(hit, metal_hit(140, 0.9, 1.0) * 0.6, 0)
    place(hit, heavy_whoosh(0.4, 1500, 200, 0.5), 0.02)
    save("sfx/clash.wav", reverb(drive(hit, 1.3), 0.2, size=1.4, tail=0.8), 0.95)

    win = silence(1.4)
    place(win, stinger(1.2, 73.4, False) * 0.9, 0)
    place(win, boom(0.6, 55, 2.0, 0.6), 0)
    save("sfx/battle_win.wav", reverb(win, 0.25, tail=0.8), 0.7)

    lose = silence(1.4)
    place(lose, stinger(1.2, 49, True) * 0.8, 0)
    n = int(1.0 * SR)
    place(lose, osc(np.geomspace(200, 50, n), 1.0, "saw") * env_ad(n, 0.01, 0.9, 3) * 0.25, 0.1)
    save("sfx/battle_lose.wav", reverb(lp(lose, 2500), 0.25, tail=0.8), 0.6)

    cap = silence(1.3)
    place(cap, heavy_whoosh(0.4, 600, 3000, 0.8), 0)
    place(cap, metal_hit(260, 0.9, 0.9) * 0.8, 0.35)
    place(cap, boom(0.6, 65, 1.5, 0.6), 0.35)
    save("sfx/card_capture.wav", reverb(cap, 0.25, tail=0.7), 0.75)

    el = silence(1.8)
    n = int(1.0 * SR)
    place(el, osc(np.geomspace(400, 35, n), 1.0, "saw") * env_ad(n, 0.005, 0.9, 2.5) * 0.5, 0)
    place(el, heavy_whoosh(0.9, 3000, 150, 0.8), 0)
    place(el, boom(1.2, 38, 2.5, 0.9), 0.05)
    save("sfx/eliminated.wav", reverb(lp(drive(el, 1.4), 3500), 0.3, size=1.4, tail=1.0), 0.8)


def jingles():
    v = silence(3.5)
    for i, (root, at) in enumerate([(55, 0.0), (65.4, 0.35), (73.4, 0.7)]):
        place(v, stinger(1.0 if i < 2 else 2.4, root, False) * 0.8, at)
        place(v, boom(0.8, 45, 2.0, 0.7), at)
    save("sfx/victory.wav", reverb(v, 0.3, size=1.4, tail=1.2), 0.8)

    d = silence(3.5)
    for i, (root, at) in enumerate([(55, 0.0), (51.9, 0.5), (41.2, 1.0)]):
        place(d, stinger(1.0 if i < 2 else 2.4, root, True) * 0.7, at)
    place(d, boom(2.0, 35, 2.0, 0.8), 1.0)
    save("sfx/defeat.wav", reverb(lp(d, 2000), 0.3, size=1.4, tail=1.2), 0.7)


# ---------------------------------------------------------------- существа

VOWELS = {  # форманты (Гц): а, о, у, и, э
    "a": (800, 1200, 2600), "o": (500, 900, 2400), "u": (350, 800, 2300),
    "i": (300, 2300, 3000), "e": (500, 1800, 2600),
}


def voice(pitch_curve, vowel="a", buzz=0.0, breath=0.1, vib=(6.0, 0.03)):
    """Голосоподобный тон: пила с вибрато через форманты гласной."""
    n = len(pitch_curve)
    dur = n / SR
    t = np.arange(n) / SR
    f = pitch_curve * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t))
    src = osc(f, dur, "saw")
    if buzz > 0:
        src = src * (1 - buzz) + buzz * osc(f, dur, "square")
    src += breath * hp(noise(dur), 1500)
    out = np.zeros(n)
    for i, fm in enumerate(VOWELS[vowel]):
        out += bp(src, fm * 0.8, fm * 1.25) * [1.0, 0.6, 0.25][i]
    return out


def contour(points, dur):
    """points: [(доля времени, частота)], экспоненциальная интерполяция."""
    n = int(dur * SR)
    xs = np.array([p[0] for p in points]) * n
    ys = np.log(np.array([p[1] for p in points]))
    return np.exp(np.interp(np.arange(n), xs, ys))


def cry_shape(arch, scale, kind, r):
    """kind: 'appear' (на выход) или 'attack' (в бою)."""
    j = lambda: r.uniform(0.93, 1.07)
    if arch == "knight":
        d = 0.35 if kind == "appear" else 0.25
        c = contour([(0, 260 * j()), (0.3, 330 * j()), (1, 220)], d) * scale
        return voice(c, "a", breath=0.15) * env_asr(len(c), 0.01, 0.12)
    if arch == "centaur":
        d = 0.6
        c = contour([(0, 700 * j()), (0.15, 900), (1, 450)], d) * scale
        x = voice(c, "e", vib=(18, 0.08)) * env_asr(len(c), 0.02, 0.2)
        return x
    if arch == "cyclops":
        d = 0.55
        c = contour([(0, 120 * j()), (0.4, 150), (1, 95)], d) * scale
        return voice(c, "o", buzz=0.3, breath=0.05, vib=(4, 0.02)) * env_asr(len(c), 0.03, 0.2)
    if arch == "flying_eye":
        d = 0.35
        c = contour([(0, 420 * j()), (0.5, 600 * j()), (1, 380)], d * 1.6) * scale
        return voice(c, "u", buzz=0.4, vib=(9, 0.08), breath=0.2) * env_asr(len(c), 0.04, 0.2)
    if arch == "dragon":
        d = 0.8 if kind == "appear" else 0.6
        c = contour([(0, 95 * j()), (0.35, 140 * j()), (1, 80)], d) * scale
        x = voice(c, "a", buzz=0.4, breath=0.3, vib=(5, 0.03))
        x *= 0.75 + 0.25 * np.sin(2 * np.pi * 28 * np.arange(len(x)) / SR)  # рычание
        return x * env_asr(len(x), 0.04, 0.3)
    if arch == "golem":
        d = 0.6
        c = contour([(0, 75 * j()), (0.5, 90), (1, 65)], d) * scale
        x = voice(c, "o", buzz=0.5, breath=0.05, vib=(3, 0.01))
        x += lp(noise(d), 400) * 0.6 * env_ad(len(x), 0.02, d, 2)
        return x * env_asr(len(x), 0.05, 0.25)
    if arch == "serpent":
        d = 0.6
        hiss = bp(noise(d), 3000, 9000) * env_asr(int(d * SR), 0.1, 0.25) * 0.8
        c = contour([(0, 300 * j()), (1, 260)], d) * scale
        return hiss + voice(c, "e", breath=0.4) * env_asr(len(c), 0.05, 0.3) * 0.5
    if arch == "bird":  # хищный клёкот
        d = 0.55 if kind == "appear" else 0.4
        c = contour([(0, 900 * j()), (0.25, 1300 * j()), (1, 700)], d) * scale
        x = voice(c, "e", buzz=0.3, breath=0.5, vib=(30, 0.05))
        return x * env_asr(len(x), 0.01, 0.2)
    if arch == "wolf":
        d = 0.7 if kind == "appear" else 0.35
        c = contour([(0, 330 * j()), (0.4, 520 * j()), (1, 300)], d) * scale
        return voice(c, "u", breath=0.1, vib=(5, 0.025)) * env_asr(len(c), 0.05, 0.25)
    if arch == "beetle":
        buf = silence(0.5)
        for k in range(4):
            ck = bp(noise(0.03), 2000, 7000) * env_ad(int(0.03 * SR), 0.0005, 0.01, 5)
            place(buf, ck, k * 0.06)
        d = 0.3
        c = contour([(0, 180 * j()), (1, 230)], d) * scale
        place(buf, voice(c, "e", buzz=0.8, breath=0.0, vib=(40, 0.04)) * env_asr(len(c), 0.02, 0.1) * 0.6, 0.18)
        return buf
    raise ValueError(arch)


def element_layer(attr, dur, r):
    """Окраска стихии: 0 пламя,1 буря,2 свет,3 камень,4 тень,5 прилив."""
    n = int(dur * SR)
    if attr == 0:  # потрескивание
        crack = np.zeros(n)
        for _ in range(14):
            i = r.integers(0, n - 300)
            crack[i:i + 200] += hp(noise(200 / SR), 2000) * np.exp(-np.arange(200) / 30) * r.uniform(0.3, 1)
        return crack * 0.35
    if attr == 1:  # порыв
        return whoosh(dur, 600, 2500, 0.6, 0.35)
    if attr == 2:  # искры
        x = hp(noise(dur), 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 23 * np.arange(n) / SR)) * env_asr(n, 0.05, 0.2)
        return x * 0.3
    if attr == 3:  # скрежет
        return lp(noise(dur), 300) * env_ad(n, 0.01, dur, 2) * 0.4
    if attr == 4:  # шёпот в реверсе
        x = whoosh(dur, 3000, 1200, 0.5, 0.3)
        return x[::-1]
    if attr == 5:  # шум воды
        x = lp(noise(dur), 900) * np.sin(np.linspace(0, np.pi, n)) * 0.8
        return x
    return np.zeros(n)


CREATURES = [  # id, архетип, стихия, базовая сила (для высоты голоса)
    ("creature_zharovik", "dragon", 0, 340), ("creature_peplohvost", "wolf", 0, 300),
    ("creature_magmozavr", "dragon", 0, 390), ("creature_iskren", "flying_eye", 0, 290),
    ("creature_vihrekryl", "bird", 1, 300), ("creature_shkvalnik", "centaur", 1, 350),
    ("creature_neboklyuv", "bird", 1, 380), ("creature_luminar", "knight", 2, 330),
    ("creature_solncegriv", "centaur", 2, 380), ("creature_zarnica", "beetle", 2, 290),
    ("creature_granitrog", "cyclops", 3, 370), ("creature_valunnik", "golem", 3, 400),
    ("creature_kvarcevik", "golem", 3, 310), ("creature_sumrachnik", "knight", 4, 350),
    ("creature_mglokryl", "flying_eye", 4, 300), ("creature_polunochnik", "cyclops", 4, 390),
    ("creature_mareolit", "serpent", 5, 320), ("creature_glubinnik", "serpent", 5, 390),
    ("creature_penorog", "beetle", 5, 300), ("creature_ledostruy", "wolf", 5, 350),
]


def creature_sounds():
    for i, (cid, arch, attr, power) in enumerate(CREATURES):
        r = np.random.default_rng(100 + i)
        scale = (1.25 - (power - 290) / 110 * 0.4) * 0.62  # ниже и серьёзнее; сильнее - ниже
        for kind in ("appear", "attack"):
            x = cry_shape(arch, scale, kind, r)
            x = x / (np.max(np.abs(x)) + 1e-9)
            x = drive(x * 1.4 + boom(len(x) / SR, 45, 1.0, 0.25)[: len(x)], 2.0)
            x = x + element_layer(attr, len(x) / SR, r)[: len(x)]
            name = cid.replace("creature_", "")
            save(f"creatures/{name}_{kind}.wav", reverb(x, 0.18, tail=0.4), 0.75)


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "sfx"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "creatures"), exist_ok=True)
    open(os.path.join(ROOT, ".gdignore"), "w").close()
    ui_sounds()
    ball_sounds()
    battle_sounds()
    jingles()
    creature_sounds()
    files = sum(len(f) for _, _, f in os.walk(ROOT))
    print("готово, файлов:", files)
