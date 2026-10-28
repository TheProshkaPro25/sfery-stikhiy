"""Бесшовная петля из WAV: хвост кроссфейдится в начало, затем OGG через ffmpeg.
Запуск: python tools/audio/make_loop.py in.wav out.ogg [кроссфейд_сек]"""
import subprocess
import sys
import wave

import numpy as np

src, dst = sys.argv[1], sys.argv[2]
xf_s = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
w = wave.open(src)
ch, sr = w.getnchannels(), w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, ch).astype(np.float32) / 32768
x = x[int(0.25 * sr): len(x) - int(0.4 * sr)]  # у MusicGen края бывают рваными
xf = int(xf_s * sr)
ramp = np.linspace(0, 1, xf)[:, None]
head, body, tail = x[:xf], x[xf:-xf], x[-xf:]
# равная мощность: хвост гаснет, начало нарастает
mixed = tail * np.cos(ramp * np.pi / 2) + head * np.sin(ramp * np.pi / 2)
loop = np.concatenate([mixed, body])
loop = loop / (np.abs(loop).max() + 1e-9) * 0.89
tmp = dst + ".tmp.wav"
with wave.open(tmp, "wb") as o:
    o.setnchannels(ch); o.setsampwidth(2); o.setframerate(sr)
    o.writeframes((loop * 32767).astype(np.int16).tobytes())
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
import os; os.remove(tmp)
print(dst, f"{len(loop) / sr:.1f}s")
