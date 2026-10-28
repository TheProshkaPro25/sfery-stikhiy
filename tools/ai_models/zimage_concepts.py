"""Концепты существ через Z-Image-Turbo (int8 ConvRot, Apache 2.0) на локальном сервере ComfyUI.

Сервер (отдельно, Godot и Hunyuan в это время не запускать):
  cd ~/ai/ComfyUI && .venv/bin/python main.py --use-sage-attention --listen 127.0.0.1 --port 8188
Клиент:
  python3 tools/ai_models/zimage_concepts.py [id...]
Пишет tools/ai_models/concepts/<id>_z<seed>.png. Описания существ общие с gen_concepts.py.
"""
import json
import os
import shutil
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from gen_concepts import CREATURES  # noqa: E402

SERVER = "http://127.0.0.1:8188"
COMFY_OUT = os.path.expanduser("~/ai/ComfyUI/output")
OUT = os.path.join(os.path.dirname(__file__), "concepts")
STYLE = ("Full body shot of one living fantasy beast in a powerful battle stance, front three-quarter view, centered, whole body "
         "visible with margin, isolated on a plain pure white background, no ground, no shadow. 2007 Japanese battle anime monster "
         "design: organic living creature with natural anatomy, scales, fur, feathers, horns, bone and natural armor plates, "
         "bold saturated elemental colors, clean large readable shapes, glowing eyes, sharp claws, fierce expression, cel-shaded anime render. "
         "Medieval fantasy, NOT futuristic: no robots, no mecha, no machines, no sci-fi armor, no metal panels, no tech details, "
         "no visor, no armor suit. Animals keep animal bodies (four legs for beasts). Not cute, not chibi. "
         "No text, no people, no riders, only one creature.")
SUFFIX = "c"  # battle-anime 2007, органические фэнтези-существа без футуризма: <id>_c<seed>.png


def workflow(prompt: str, seed: int, prefix: str) -> dict:
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_int8_convrot.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b_fp8_mixed.safetensors", "type": "lumina2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 3}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "6": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["5", 0]}},
        "7": {"class_type": "EmptySD3LatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "8": {"class_type": "KSampler", "inputs": {"model": ["4", 0], "positive": ["5", 0], "negative": ["6", 0],
                                                     "latent_image": ["7", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                                                     "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1.0}},
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": prefix}},
    }


def post(path: str, data: dict) -> dict:
    req = urllib.request.Request(SERVER + path, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30).read())


def get(path: str) -> dict:
    return json.loads(urllib.request.urlopen(SERVER + path, timeout=30).read())


def run(cid: str, seed: int) -> str:
    dst = os.path.join(OUT, f"{cid}_{SUFFIX}{seed}.png")
    if os.path.exists(dst):
        return dst
    prefix = f"zimg_{cid}_{seed}"
    pid = post("/prompt", {"prompt": workflow(f"{CREATURES[cid]}. {STYLE}", seed, prefix)})["prompt_id"]
    t0 = time.time()
    while True:
        h = get(f"/history/{pid}")
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(f"{cid}: ошибка ComfyUI: {st}")
            imgs = [im for node in h[pid]["outputs"].values() for im in node.get("images", [])]
            if imgs:
                src = os.path.join(COMFY_OUT, imgs[0].get("subfolder", ""), imgs[0]["filename"])
                shutil.copy(src, dst)
                print(f"ok {cid} seed={seed} {time.time() - t0:.1f}s", flush=True)
                return dst
        time.sleep(1.0)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for cid in (sys.argv[1:] or list(CREATURES)):
        for seed in (11, 23):
            run(cid, seed)
