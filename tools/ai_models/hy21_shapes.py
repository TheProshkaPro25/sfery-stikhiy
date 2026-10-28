"""Форма существ через Hunyuan3D 2.1 (fp8 e5m2, all-in-one) на сервере ComfyUI — для сравнения с 2.0 mini-turbo.

Сервер: cd ~/ai/ComfyUI && .venv/bin/python main.py --listen 127.0.0.1 --port 8188
Клиент: python3 tools/ai_models/hy21_shapes.py zharovik glubinnik ...
Вход: tools/ai_models/meshes/<id>_rgba.png (концепт без фона). Выход: tools/ai_models/meshes21/<id>_shape.glb
Веса Hunyuan3D — TENCENT HUNYUAN COMMUNITY LICENSE (некоммерческая).
"""
import json
import os
import shutil
import sys
import time
import urllib.request
import uuid

SERVER = "http://127.0.0.1:8188"
COMFY = os.path.expanduser("~/ai/ComfyUI")
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "meshes")
OUT = os.path.join(HERE, os.environ.get("MESH_DIR", "meshes21"))
OCTREE = int(os.environ.get("OCTREE", "256"))  # 384 — больше деталей
CKPT = "hunyuan_3d_v2.1-fp8-e4m3fn.safetensors"  # из e5m2: модель fp8 e4m3fn, VAE и энкодер fp16


def workflow(image_name: str, prefix: str) -> dict:
    # Повторяет шаблон ComfyUI 3d_hunyuan3d-v2.1: 30 шагов, cfg 5, euler, surface net 0.6.
    return {
        "1": {"class_type": "ImageOnlyCheckpointLoader", "inputs": {"ckpt_name": CKPT}},
        "2": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "3": {"class_type": "CLIPVisionEncode", "inputs": {"clip_vision": ["1", 1], "image": ["2", 0], "crop": "center"}},
        "4": {"class_type": "Hunyuan3Dv2Conditioning", "inputs": {"clip_vision_output": ["3", 0]}},
        "5": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 1.0}},
        "6": {"class_type": "EmptyLatentHunyuan3Dv2", "inputs": {"resolution": 4096, "batch_size": 1}},
        "7": {"class_type": "KSampler", "inputs": {"model": ["5", 0], "positive": ["4", 0], "negative": ["4", 1],
                                                     "latent_image": ["6", 0], "seed": 7, "steps": 30, "cfg": 5.0,
                                                     "sampler_name": "euler", "scheduler": "normal", "denoise": 1.0}},
        "8": {"class_type": "VAEDecodeHunyuan3D", "inputs": {"samples": ["7", 0], "vae": ["1", 2],
                                                               "num_chunks": 8000, "octree_resolution": OCTREE}},
        "9": {"class_type": "VoxelToMesh", "inputs": {"voxel": ["8", 0], "algorithm": "surface net", "threshold": 0.6}},
        "10": {"class_type": "SaveGLB", "inputs": {"mesh": ["9", 0], "filename_prefix": prefix}},
    }


def call(path, data=None):
    req = urllib.request.Request(SERVER + path, data=json.dumps(data).encode() if data else None,
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=60).read())


def run(cid: str):
    dst = os.path.join(OUT, f"{cid}_shape.glb")
    if os.path.exists(dst):
        return
    name = f"hy21_{cid}.png"
    # Прозрачный фон -> белый: LoadImage отбрасывает альфу, под ней мог быть мусор.
    from PIL import Image
    im = Image.open(os.path.join(SRC, f"{cid}_rgba.png")).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    Image.alpha_composite(bg, im).convert("RGB").save(os.path.join(COMFY, "input", name))
    prefix = f"3d/hy21_{cid}_{uuid.uuid4().hex[:6]}"
    pid = call("/prompt", {"prompt": workflow(name, prefix)})["prompt_id"]
    t0 = time.time()
    while True:
        h = call(f"/history/{pid}")
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError(f"{cid}: {json.dumps(st)[:800]}")
            out_dir = os.path.join(COMFY, "output", os.path.dirname(prefix))
            files = sorted(f for f in os.listdir(out_dir) if f.startswith(os.path.basename(prefix)))
            if files:
                shutil.copy(os.path.join(out_dir, files[-1]), dst)
                print(f"ok {cid} {time.time() - t0:.0f}s", flush=True)
                return
        time.sleep(2)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for cid in sys.argv[1:]:
        run(cid)
