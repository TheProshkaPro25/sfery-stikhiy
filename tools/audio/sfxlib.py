"""Примитивы обработки записанных звуков для build_sfx.py (моно, float32, 44.1 кГц).

Источники — распакованные CC0/CC-BY паки (OpenGameArt, Kenney), каталог SFX_SRC вне репозитория;
ключ источника — путь файла относительно SFX_SRC (список паков и лицензий — CREDITS.md).
"""
import os
import subprocess
import tempfile

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, resample_poly, sosfilt

SR = 44100
SRC_DIR = os.environ.get("SFX_SRC", "")
_cache: dict = {}
used: set = set()  # ключи источников, реально попавшие в сборку (для CREDITS.md)


def load(key: str) -> np.ndarray:
    """Исходник целиком: моно, SR."""
    used.add(key)
    if key not in _cache:
        x, sr = sf.read(os.path.join(SRC_DIR, key), always_2d=True, dtype="float32")
        x = x.mean(axis=1)
        if sr != SR:
            g = np.gcd(sr, SR)
            x = resample_poly(x, SR // g, sr // g).astype(np.float32)
        x = x - np.mean(x)  # убираем постоянную составляющую
        _cache[key] = x
    return _cache[key].copy()


def env_rms(x: np.ndarray, win: float = 0.02) -> np.ndarray:
    n = max(1, min(int(win * SR), len(x)))
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, "same") + 1e-12)


def seg(x: np.ndarray, t0: float, dur: float | None = None) -> np.ndarray:
    a = int(t0 * SR)
    return x[a:] if dur is None else x[a: a + int(dur * SR)]


def loudest(x: np.ndarray, dur: float, skip: int = 0) -> np.ndarray:
    """Окно длиной dur с наибольшей энергией (skip — взять следующее по громкости непересекающееся)."""
    n = int(dur * SR)
    if len(x) <= n:
        return x
    e = np.convolve(x * x, np.ones(n), "valid")
    for _ in range(skip):
        i = int(np.argmax(e))
        e[max(0, i - n): i + n] = -1
    i = int(np.argmax(e))
    return x[i: i + n]


def trim(x: np.ndarray, db: float = -40.0, pre: float = 0.004, post: float = 0.03) -> np.ndarray:
    """Срезает тишину по краям (порог относительно пика огибающей)."""
    e = env_rms(x, 0.01)
    thr = e.max() * 10 ** (db / 20)
    idx = np.where(e > thr)[0]
    if not len(idx):
        return x
    a = max(0, idx[0] - int(pre * SR))
    b = min(len(x), idx[-1] + int(post * SR))
    return fade(x[a:b], 0.003, 0.02)


def fade(x: np.ndarray, fin: float = 0.0, fout: float = 0.0) -> np.ndarray:
    x = x.copy()
    a, b = min(len(x), int(fin * SR)), min(len(x), int(fout * SR))
    if a > 0:
        x[:a] *= np.linspace(0, 1, a) ** 2
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def db(x: np.ndarray, g: float) -> np.ndarray:
    return x * (10 ** (g / 20))


def pitch(x: np.ndarray, semis: float) -> np.ndarray:
    """Сдвиг высоты ресемплингом (вместе с темпом, как у плёнки): ниже = длиннее и тяжелее."""
    if abs(semis) < 1e-3:
        return x
    ratio = 2 ** (semis / 12)
    up, down = int(round(1000 / ratio)), 1000
    g = np.gcd(up, down)
    return resample_poly(x, up // g, down // g).astype(np.float32)


def _sos(kind: str, f, order: int = 2):
    return butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return sosfilt(_sos("lowpass", f, order), x).astype(np.float32)


def hp(x, f, order=2):
    return sosfilt(_sos("highpass", f, order), x).astype(np.float32)


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("bandpass", [lo, hi], order), x).astype(np.float32)


def shelf_low(x, f, g_db):
    """Простая полка НЧ: подмешиваем отфильтрованный низ."""
    return x + db(lp(x, f), g_db) - lp(x, f) if g_db < 0 else x + lp(x, f) * (10 ** (g_db / 20) - 1)


def sat(x, drive=2.0):
    """Мягкое насыщение tanh (плотность, «жар»)."""
    p = np.abs(x).max() + 1e-9
    return (np.tanh(x / p * drive) / np.tanh(drive) * p).astype(np.float32)


def rev(x):
    return x[::-1].copy()


_ir_cache: dict = {}


def reverb(x, wet=0.25, decay=1.2, bright=6000.0, seed=3):
    """Свёртка с экспоненциально затухающим шумом (тёмный зал). Хвост добавляется."""
    key = (decay, bright, seed)
    if key not in _ir_cache:
        r = np.random.default_rng(seed)
        n = int(decay * SR)
        t = np.arange(n) / SR
        ir = r.standard_normal(n) * np.exp(-6.9 * t / decay)
        ir = lp(ir.astype(np.float32), bright)
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        _ir_cache[key] = (ir / np.sqrt(np.sum(ir ** 2))).astype(np.float32)
    ir = _ir_cache[key]
    y = np.concatenate([x, np.zeros(len(ir), np.float32)])
    w = fftconvolve(y, ir)[: len(y)].astype(np.float32)
    return y * (1 - wet * 0.5) + w * wet


def chorus(x, depth=0.004, rate=0.7, mix=0.5):
    """Модулированная задержка (вода, «текучесть»)."""
    n = len(x)
    t = np.arange(n) / SR
    d = (depth * (1 + np.sin(2 * np.pi * rate * t)) / 2 + 0.002) * SR
    idx = np.clip(np.arange(n) - d, 0, n - 1)
    i0 = idx.astype(int)
    fr = idx - i0
    y = x[i0] * (1 - fr) + x[np.minimum(i0 + 1, n - 1)] * fr
    return (x * (1 - mix) + y * mix).astype(np.float32)


def tremolo(x, rate=7.0, depth=0.5):
    t = np.arange(len(x)) / SR
    return (x * (1 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)))).astype(np.float32)


def fit(x, dur):
    """Обрезать/дополнить до длины dur с плавным хвостом."""
    n = int(dur * SR)
    if len(x) >= n:
        return fade(x[:n], 0, min(0.08, dur / 4))
    return np.concatenate([x, np.zeros(n - len(x), np.float32)])


def follow(layer, guide, smooth=0.04, floor=0.0):
    """Огибающая guide накладывается на layer (слой стихии «дышит» вместе с голосом)."""
    n = len(guide)
    layer = fit(layer, (n + 1) / SR)[:n]
    e = env_rms(guide, smooth)
    e = e / (e.max() + 1e-9)
    return layer * (floor + (1 - floor) * e)


def mix(*parts):
    """parts: (сигнал, сдвиг_сек, усиление_дБ)."""
    n = max(int(o * SR) + len(s) for s, o, _ in parts)
    y = np.zeros(n, np.float32)
    for s, o, g in parts:
        a = int(o * SR)
        y[a: a + len(s)] += db(s, g)
    return y


def norm(x, rms_db=-16.0, peak_db=-1.0):
    """Громкость: RMS активной части к rms_db (≈ LUFS для широкополосных звуков), пик не выше peak_db.
    Если пик упирается — сначала мягкое насыщение до +4 дБ, потом пиковое ограничение."""
    e = env_rms(x, 0.05)
    act = x[e > e.max() * 0.1]
    rms = np.sqrt(np.mean(act ** 2)) + 1e-9
    y = x * (10 ** (rms_db / 20) / rms)
    lim = 10 ** (peak_db / 20)
    pk = np.abs(y).max()
    if pk > lim:
        over = min(pk / lim, 10 ** (4 / 20))  # до 4 дБ прячем в мягкое насыщение
        soft = lim * over
        y = np.where(np.abs(y) > soft * 0.5, np.sign(y) * (soft * 0.5 + soft * 0.5 * np.tanh((np.abs(y) - soft * 0.5) / (soft * 0.5))), y)
        pk = np.abs(y).max()
        if pk > lim:
            y = y * (lim / pk)
    return y.astype(np.float32)


def loopify(x, xf=0.35):
    """Бесшовная петля: хвост равномощно кроссфейдится в начало."""
    n = int(xf * SR)
    r = np.linspace(0, 1, n)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    return np.concatenate([tail * np.cos(r * np.pi / 2) + head * np.sin(r * np.pi / 2), body]).astype(np.float32)


def write_ogg(path: str, x: np.ndarray, quality: int = 5) -> float:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        tmp = t.name
    sf.write(tmp, np.clip(x, -1, 1), SR, subtype="PCM_16")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-ac", "1", "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.remove(tmp)
    return len(x) / SR
