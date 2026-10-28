"""Переводит baseColor-текстуру .glb из линейного цвета в sRGB (на месте).

Только для TRELLIS.2: его текстуры ~в 3 раза темнее концепта (0.125 против 0.377 ≈ 0.377^2.2) — осветление
кривой sRGB возвращает яркость. Это не ошибка запекания: Pixal3D через тот же BakeTextureFromVoxel даёт
цвета как на концепте, ей поправка не нужна. Повторно не применяется: в asset.extras ставится метка.
Запуск: ~/ai/Hunyuan3D-2/.venv/bin/python tools/ai_models/fix_albedo.py tools/ai_models/meshes_tr2/*.glb
"""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

MARK = "sfery_albedo_srgb"


def to_srgb(lin: np.ndarray) -> np.ndarray:
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def fix(path: str) -> str:
    b = open(path, "rb").read()
    jlen = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jlen])
    if j.get("asset", {}).get("extras", {}).get(MARK):
        return "skip"
    boff = 20 + jlen
    blen = struct.unpack("<I", b[boff:boff + 4])[0]
    binc = b[boff + 8:boff + 8 + blen]

    tex_ids = {m["pbrMetallicRoughness"]["baseColorTexture"]["index"]
               for m in j["materials"] if "baseColorTexture" in m.get("pbrMetallicRoughness", {})}
    img_ids = {j["textures"][t]["source"] for t in tex_ids}
    # пересобрать бинарный чанк: bufferView-ы картинок baseColor заменяются, остальные копируются
    new_views = {}
    for i in img_ids:
        bv = j["bufferViews"][j["images"][i]["bufferView"]]
        o = bv.get("byteOffset", 0)
        im = Image.open(io.BytesIO(binc[o:o + bv["byteLength"]]))
        a = np.asarray(im.convert("RGBA")).astype(np.float32) / 255.0
        a[..., :3] = to_srgb(a[..., :3])
        out = io.BytesIO()
        Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).convert(im.mode).save(out, "PNG")
        new_views[j["images"][i]["bufferView"]] = out.getvalue()
    data = bytearray()
    for vi, bv in enumerate(j["bufferViews"]):
        o = bv.get("byteOffset", 0)
        chunk = new_views.get(vi, binc[o:o + bv["byteLength"]])
        while len(data) % 4:
            data += b"\0"
        bv["byteOffset"] = len(data)
        bv["byteLength"] = len(chunk)
        data += chunk
    while len(data) % 4:
        data += b"\0"
    j["buffers"][0]["byteLength"] = len(data)
    j.setdefault("asset", {}).setdefault("extras", {})[MARK] = True
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(data)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(data), 0x004E4942) + bytes(data))
    return f"ok ({len(img_ids)} img)"


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(p, fix(p))
