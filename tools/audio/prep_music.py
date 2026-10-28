"""Музыка из Suno (mp3/wav) → бесшовная петля OGG с ровной громкостью.

Запуск: python tools/audio/prep_music.py [имя ...]
Берёт assets/music/<имя>.mp3 (или .wav), пишет assets/audio/music/<имя>.ogg. Без имён — все файлы из assets/music.
Шаги: декод ffmpeg → обрезка тишины по краям → кроссфейд хвоста в начало (равная мощность) →
громкость EBU R128 −23 LUFS, пик −2 dBTP (Suno отдаёт ~−15 LUFS — поверх эффектов это глушит игрока).
Короткие треки без петли (victory, defeat) — только обрезка и громкость.
"""
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "assets", "music")
DST = os.path.join(ROOT, "assets", "audio", "music")
SR = 44100
LUFS = -23.0
XFADE = 4.0                      # секунды кроссфейда в петле
NO_LOOP = {"victory", "defeat"}  # одноразовые темы


def decode(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def trim(x, db=-50.0):
    """Срезать тишину по краям (порог по огибающей 50 мс)."""
    env = np.abs(x).max(axis=1)
    win = int(0.05 * SR)
    env = np.convolve(env, np.ones(win) / win, mode="same")
    on = np.nonzero(env > 10 ** (db / 20))[0]
    return x[on[0]:on[-1] + 1] if len(on) else x


def loopify(x, xf_s=XFADE):
    """Хвост гаснет, начало нарастает — склейка без щелчка и без провала громкости."""
    xf = min(int(xf_s * SR), len(x) // 4)
    ramp = np.linspace(0, 1, xf)[:, None]
    mixed = x[-xf:] * np.cos(ramp * np.pi / 2) + x[:xf] * np.sin(ramp * np.pi / 2)
    return np.concatenate([mixed, x[xf:-xf]])


def encode(x, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", "-",
                    "-af", f"loudnorm=I={LUFS}:TP=-2:LRA=11", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", "5", dst],
                   input=x.astype(np.float32).tobytes(), check=True)


def main():
    names = sys.argv[1:] or sorted({os.path.splitext(f)[0] for f in os.listdir(SRC)
                                    if f.lower().endswith((".mp3", ".wav", ".ogg", ".flac"))})
    for n in names:
        src = next((os.path.join(SRC, n + e) for e in (".mp3", ".wav", ".flac", ".ogg")
                    if os.path.exists(os.path.join(SRC, n + e))), None)
        if src is None:
            print("нет исходника:", n)
            continue
        x = trim(decode(src))
        if n not in NO_LOOP:
            x = loopify(x)
        dst = os.path.join(DST, n + ".ogg")
        encode(x, dst)
        print(f"{dst}: {len(x) / SR:.1f} с{'' if n in NO_LOOP else ', петля'}")


if __name__ == "__main__":
    main()
