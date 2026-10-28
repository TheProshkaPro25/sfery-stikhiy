"""Боевая музыка через MusicGen (facebook/musicgen-stereo-medium, локально на GPU).

Запуск (отдельно от Godot/Hunyuan, с ограничением памяти):
  systemd-run --user --scope -p MemoryMax=9G ~/ai/Hunyuan3D-2/.venv/bin/python tools/audio/gen_music.py [вариант...]
Пишет WAV в assets/audio/music/_raw/. Веса модели под лицензией CC-BY-NC 4.0.
"""
import os
import sys
import wave

import numpy as np
import torch
from transformers import AutoProcessor, MusicgenForConditionalGeneration

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "music", "_raw")
MODEL = "facebook/musicgen-stereo-medium"

PROMPTS = {
    "jrock": "energetic japanese garage rock instrumental, fast tight drums, raw overdriven guitar riffs, "
             "driving bass, tense urgent battle theme, live band in a small room, no orchestra, no strings, no synth pads",
    "mathrock": "math rock instrumental, tense and urgent, interlocking tapped guitar riffs, syncopated drum groove, "
                "distorted bass, gritty indie production, minor key, no orchestra, no strings, no synthesizer",
    "posthardcore": "post-hardcore instrumental, tense driving rhythm, crunchy palm-muted guitars, punchy toms and snare, "
                    "dark minor key, energetic, raw live room sound, no orchestra, no cinematic, no synth",
}


def save(path, audio, sr):
    x = audio / (np.abs(audio).max() + 1e-9) * 0.9
    pcm = (x.T * 32767).astype(np.int16)  # (n, ch)
    with wave.open(path, "wb") as w:
        w.setnchannels(pcm.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def main():
    names = sys.argv[1:] or list(PROMPTS)
    os.makedirs(OUT, exist_ok=True)
    proc = AutoProcessor.from_pretrained(MODEL)
    model = MusicgenForConditionalGeneration.from_pretrained(MODEL, torch_dtype=torch.float16).to("cuda")
    sr = model.config.audio_encoder.sampling_rate
    for i, name in enumerate(names):
        torch.manual_seed(1234 + i)
        inputs = proc(text=[PROMPTS[name]], padding=True, return_tensors="pt").to("cuda")
        with torch.inference_mode():
            out = model.generate(**inputs, do_sample=True, guidance_scale=3.0, top_k=250, max_new_tokens=1500)
        audio = out[0].float().cpu().numpy()  # (ch, n)
        path = os.path.join(OUT, f"battle_{name}.wav")
        save(path, audio, sr)
        print("ok", path, audio.shape, sr, flush=True)


if __name__ == "__main__":
    main()
