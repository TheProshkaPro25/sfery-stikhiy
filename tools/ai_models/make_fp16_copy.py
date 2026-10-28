"""Локальная fp16-копия моделей текстурирования Hunyuan3D-2 (paint-turbo и delight) в ~/.cache/hy3dgen.
Hunyuan3DPaintPipeline сначала ищет модели там. fp16 safetensors грузятся через mmap — вдвое меньше RAM,
без пикового удвоения при загрузке .bin. Конвертация по одному тензору (малый пик памяти)."""
import glob
import os
import shutil

import torch
from safetensors import safe_open
from safetensors.torch import save_file

SRC = glob.glob(os.path.expanduser("~/.cache/huggingface/hub/models--tencent--Hunyuan3D-2/snapshots/*"))[0]
DST = os.path.expanduser("~/.cache/hy3dgen/tencent/Hunyuan3D-2")


def to_fp16(t):
    return t.half().contiguous() if t.is_floating_point() else t.contiguous()


def convert(src, dst):
    out = {}
    if src.endswith(".safetensors"):
        with safe_open(src, "pt") as f:
            for k in f.keys():
                out[k] = to_fp16(f.get_tensor(k))
    else:
        sd = torch.load(src, map_location="cpu", mmap=True, weights_only=True)
        for k in list(sd.keys()):
            out[k] = to_fp16(sd[k])
            del sd[k]
    base = os.path.basename(dst)
    dst = dst.replace("pytorch_model.bin", "model.safetensors").replace("diffusion_pytorch_model.bin", "diffusion_pytorch_model.safetensors")
    if base.endswith(".bin"):
        dst = dst[:-4] + ".safetensors"
    save_file(out, dst, metadata={"format": "pt"})
    print("fp16", os.path.relpath(dst, DST), sum(v.numel() for v in out.values()) * 2 / 1e9, "GB", flush=True)


for sub in ("hunyuan3d-paint-v2-0-turbo", "hunyuan3d-delight-v2-0"):
    for root, _dirs, files in os.walk(os.path.join(SRC, sub), followlinks=True):
        rel = os.path.relpath(root, SRC)
        os.makedirs(os.path.join(DST, rel), exist_ok=True)
        names = set(files)
        for name in files:
            s = os.path.join(root, name)
            d = os.path.join(DST, rel, name)
            if name.endswith((".safetensors", ".bin")):
                # .bin пропускаем, если рядом уже есть safetensors (берём его)
                if name.endswith(".bin") and name.replace("pytorch_model.bin", "model.safetensors").replace("diffusion_pytorch_model.bin", "diffusion_pytorch_model.safetensors") in names:
                    continue
                if not os.path.exists(d.replace(".bin", ".safetensors").replace("pytorch_model.safetensors", "model.safetensors")):
                    convert(s, d)
            elif not os.path.exists(d):
                shutil.copy(s, d)
print("готово:", DST)
