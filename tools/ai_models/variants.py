"""Стихийные версии видов (как в Бакугане: один вид — 6 стихий) через Z-Image-Turbo img2img на ComfyUI.

Берёт концепт-образец вида (BASE) и перерисовывает его под стихию с частичным шумом (DENOISE): поза и
силуэт сохраняются, меняются цвет и стихийные детали. Версия в «родной» стихии образца — сам образец.
Сервер: cd ~/ai/ComfyUI && .venv/bin/python main.py --use-sage-attention --listen 127.0.0.1 --port 8188
Клиент: ~/ai/Hunyuan3D-2/.venv/bin/python tools/ai_models/variants.py [вид ...] [--denoise 0.7] [--seed 1]
Выход: tools/ai_models/concepts/<вид>_<стихия>.png  (стихия: fire gale light stone shadow tide)
"""
import argparse
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from zimage_concepts import COMFY_OUT, OUT, get, post  # noqa: E402

COMFY_IN = os.path.expanduser("~/ai/ComfyUI/input")
ATTRS = ["fire", "gale", "light", "stone", "shadow", "tide"]  # порядок = Attr.A
# вид: (образец <id>_<pick>, стихия образца, тело без стихийных деталей)
SPECIES = {
    "dragnar": ("zharovik_c11", "fire", "western dragon, large horned head, bat wings, long tail, four limbs, upright battle stance"),
    "klykar": ("ledostruy_c11", "tide", "four-legged wolf beast, spikes along the back, bushy tail, snarling fangs"),
    "grifalon": ("neboklyuv_c11", None,  # синий образец читается как Прилив — Бурю тоже перерисовываем
                 "sky raptor griffin bird, long sharp beak, tall crest, broad wings, talons"),
    "kolossar": ("granitrog_c11", "stone", "huge cyclops brute golem, one big eye, horns, massive shoulders, heavy fists"),
    "rogozhuk": ("penorog_c11", "tide", "rhinoceros beetle, big curved front horn, domed shell, six armored legs"),
    "levian": ("mareolit_c23", "tide", "sea serpent dragon, coiled long body, sail-like fins, horned fierce head, small claws"),
    "ratnik": ("sumrachnik_c11", "shadow", "armored knight warrior, tattered cape, horned helmet, long curved blade"),
    "gorgul": ("mglokryl_c23", "shadow", "floating bat demon with one big eye, wide membrane wings, horns, small claws"),
}
ELEMENT = {
    "fire": "fire element: molten red-orange scales and armor, glowing ember cracks, flames on tail and wings, lava glow",
    "gale": "wind element: emerald and teal green colors, feather-like fins, swirling wind streams around, storm accents",
    "light": "light element: radiant gold and white colors, glowing halo light, polished golden plates, holy sparkle",
    "stone": "earth element: grey-brown rock plates, granite texture, moss in cracks, crystal shards, heavy stone armor",
    "shadow": "darkness element: black and deep violet colors, smoky dark mist, glowing purple eyes, tattered shadows",
    "tide": "water element: deep blue and cyan colors, fins, water droplets and foam, wet glossy scales, wave accents",
}
# Цвет стихии для перекраски образца перед img2img: иначе Z-Image держится за исходные цвета (красный дракон
# оставался красным даже при denoise 0.8). Перекраска сохраняет светотень (белый фон остаётся белым).
TINT = {"fire": (225, 85, 30), "gale": (40, 175, 125), "light": (245, 205, 90),
        "stone": (135, 118, 98), "shadow": (95, 55, 150), "tide": (35, 110, 210)}
STYLE = ("Full body shot of one fantasy battle creature, same pose and silhouette, centered, whole body visible, "
         "isolated on a plain pure white background, no ground, no shadow. 2007 Japanese battle anime monster design, "
         "bold saturated elemental colors, clean large readable shapes, cel-shaded anime render. No text, only one creature.")


def workflow(image: str, prompt: str, seed: int, denoise: float, prefix: str) -> dict:
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_int8_convrot.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b_fp8_mixed.safetensors", "type": "lumina2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 3}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "6": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["5", 0]}},
        "11": {"class_type": "LoadImage", "inputs": {"image": image}},
        "12": {"class_type": "VAEEncode", "inputs": {"pixels": ["11", 0], "vae": ["3", 0]}},
        "8": {"class_type": "KSampler", "inputs": {"model": ["4", 0], "positive": ["5", 0], "negative": ["6", 0],
                                                     "latent_image": ["12", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                                                     "sampler_name": "res_multistep", "scheduler": "simple", "denoise": denoise}},
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": prefix}},
    }


def tint(src: str, rgb, dst: str):
    """Перекраска в цвет стихии по яркости: тёмное -> тёмный оттенок, светлое -> к белому."""
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255
    lum = (a @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
    t = np.array(rgb, np.float32) / 255
    out = np.where(lum < 0.5, 2 * lum * t, 1 - 2 * (1 - lum) * (1 - t))
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(dst)


def run(species: str, attr: str, seed: int, denoise: float, force: bool) -> str:
    base, home, body = SPECIES[species]
    dst = os.path.join(OUT, f"{species}_{attr}.png")
    if os.path.exists(dst) and not force:
        return dst
    src = os.path.join(OUT, f"{base}.png")
    if attr == home:
        shutil.copy(src, dst)
        return dst
    name = f"var_{species}_{attr}.png"
    tint(src, TINT[attr], os.path.join(COMFY_IN, name))
    prefix = f"variants/{species}_{attr}_{int(time.time())}"
    prompt = f"{STYLE} {body}. {ELEMENT[attr]}."
    pid = post("/prompt", {"prompt": workflow(name, prompt, seed, denoise, prefix)})["prompt_id"]
    while True:
        h = get(f"/history/{pid}")
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(f"{species}_{attr}: {st}")
            files = [f for f in os.listdir(os.path.join(COMFY_OUT, "variants")) if f.startswith(os.path.basename(prefix))]
            if files:
                shutil.copy(os.path.join(COMFY_OUT, "variants", sorted(files)[-1]), dst)
                return dst
        time.sleep(1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("species", nargs="*", default=list(SPECIES))
    ap.add_argument("--denoise", type=float, default=0.8)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--attrs", default=",".join(ATTRS))
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    for sp in a.species:
        for at in a.attrs.split(","):
            print("ok", run(sp, at, a.seed, a.denoise, a.force), flush=True)
