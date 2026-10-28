"""3D-модели существ по концептам через Hunyuan3D-2 (mini-turbo форма + paint-turbo текстура), fp16.

Этапы запускаются отдельно (меньше пик памяти; Godot в это время не запускать):
  systemd-run --user --scope -p MemoryMax=9G ~/ai/Hunyuan3D-2/.venv/bin/python tools/ai_models/gen_meshes.py shape [id...]
  systemd-run --user --scope -p MemoryMax=9G ~/ai/Hunyuan3D-2/.venv/bin/python tools/ai_models/gen_meshes.py paint [id...]
Вход: tools/ai_models/concepts/<id>_<seed>.png (seed из PICK, по умолчанию 11).
Выход: tools/ai_models/meshes/<id>_shape.glb, затем <id>.glb (с текстурой).
Веса Hunyuan3D — TENCENT HUNYUAN NON-COMMERCIAL LICENSE.
"""
import gc
import os
import sys

sys.path.insert(0, os.path.expanduser("~/ai/Hunyuan3D-2"))

import torch  # noqa: E402
from PIL import Image  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CONCEPTS = os.path.join(HERE, "concepts")
OUT = os.path.join(HERE, os.environ.get("MESH_DIR", "meshes"))  # MESH_DIR=meshes21 — формы от Hunyuan3D 2.1
IDS = ["zharovik", "peplohvost", "magmozavr", "iskren", "vihrekryl", "shkvalnik", "neboklyuv", "luminar",
       "solncegriv", "zarnica", "granitrog", "valunnik", "kvarcevik", "sumrachnik", "mglokryl", "polunochnik",
       "mareolit", "glubinnik", "penorog", "ledostruy"]
# Выбранные концепты Z-Image (battle-anime 2007, органические, без футуризма) (concepts/<id>_<pick>.png).
PICK = {
    "zharovik": "c11", "peplohvost": "c11", "magmozavr": "c23", "iskren": "c11", "vihrekryl": "c23",
    "shkvalnik": "c11", "neboklyuv": "c11", "luminar": "c11", "solncegriv": "c11", "zarnica": "c11",
    "granitrog": "c11", "valunnik": "c23", "kvarcevik": "c11", "sumrachnik": "c11", "mglokryl": "c23",
    "polunochnik": "c11", "mareolit": "c23", "glubinnik": "c23", "penorog": "c11", "ledostruy": "c11",
}


def concept(cid):
    return os.path.join(CONCEPTS, f"{cid}_{PICK.get(cid, 11)}.png")


def cut_background(cid):
    from hy3dgen.rembg import BackgroundRemover
    path = os.path.join(OUT, f"{cid}_rgba.png")
    if not os.path.exists(path):
        img = Image.open(concept(cid)).convert("RGB")
        BackgroundRemover()(img).save(path)
    return Image.open(path).convert("RGBA")


def stage_shape(ids):
    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline, FloaterRemover, DegenerateFaceRemover, FaceReducer
    pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        "tencent/Hunyuan3D-2mini", subfolder="hunyuan3d-dit-v2-mini-turbo", use_safetensors=True,
        device="cuda", dtype=torch.float16)
    pipe.enable_flashvdm(topk_mode="merge")
    for cid in ids:
        dst = os.path.join(OUT, f"{cid}_shape.glb")
        if os.path.exists(dst):
            continue
        img = cut_background(cid)
        mesh = pipe(image=img, num_inference_steps=5, octree_resolution=256, num_chunks=6000,
                    generator=torch.manual_seed(7), output_type="trimesh")[0]
        mesh = FloaterRemover()(mesh)
        mesh = DegenerateFaceRemover()(mesh)
        mesh = FaceReducer()(mesh, max_facenum=24000)
        mesh.export(dst)
        print("shape ok", cid, len(mesh.faces), flush=True)
        torch.cuda.empty_cache()


INT8 = os.environ.get("INT8") == "1"  # int8 weight-only (torchao) для линейных слоёв: вдвое меньше RAM при выгрузке


def _int8_patch():
    """Квантует каждую модель сразу после её загрузки на GPU (пик VRAM как у fp16, дальше ~вдвое меньше)."""
    from torchao.quantization import quantize_, Int8WeightOnlyConfig
    from hy3dgen.texgen.utils import dehighlight_utils, multiview_utils

    def q(pipeline):
        for name in ("unet",):  # энкодеры в int8 дают NaN -> чёрная текстура
            mod = getattr(pipeline, name, None)
            if mod is not None:
                quantize_(mod, Int8WeightOnlyConfig())
        torch.cuda.empty_cache()

    for cls in (dehighlight_utils.Light_Shadow_Remover, multiview_utils.Multiview_Diffusion_Net):
        orig = cls.__init__

        def init(self, config, _orig=orig):
            _orig(self, config)
            q(self.pipeline)
            print("int8:", type(self).__name__, round(torch.cuda.memory_allocated() / 1e9, 2), "GB VRAM", flush=True)
        cls.__init__ = init


def stage_reduce(ids):
    """Упростить формы (например, из Hunyuan3D 2.1) до 24k граней, как у 2.0."""
    import trimesh
    from hy3dgen.shapegen import FloaterRemover, DegenerateFaceRemover, FaceReducer
    for cid in ids:
        p = os.path.join(OUT, f"{cid}_shape.glb")
        mesh = trimesh.load(p, force="mesh")
        mesh = FaceReducer()(DegenerateFaceRemover()(FloaterRemover()(mesh)), max_facenum=24000)
        mesh.export(p)
        print("reduce ok", cid, len(mesh.faces), flush=True)


def stage_paint(ids):
    import trimesh
    from hy3dgen.texgen import Hunyuan3DPaintPipeline
    if INT8:
        _int8_patch()
    pipe = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2", subfolder="hunyuan3d-paint-v2-0-turbo")
    # меньше рендер/текстура — меньше пик RAM (2048 ронял систему)
    pipe.config.render_size = 1024
    pipe.config.texture_size = 1024
    pipe.render.set_default_render_resolution(1024)
    pipe.render.set_default_texture_resolution(1024)
    pipe.enable_model_cpu_offload()  # и для int8: целиком (5.5 ГБ) с активациями не влезает в 8 ГБ
    for cid in ids:
        src = os.path.join(OUT, f"{cid}_shape.glb")
        dst = os.path.join(OUT, f"{cid}_int8.glb" if INT8 else f"{cid}.glb")
        if os.path.exists(dst) or not os.path.exists(src):
            continue
        mesh = trimesh.load(src, force="mesh")
        img = cut_background(cid)
        mesh = pipe(mesh, image=img)
        mesh.export(dst)
        print("paint ok", cid, flush=True)
        gc.collect()
        torch.cuda.empty_cache()


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    stage = sys.argv[1]
    ids = sys.argv[2:] or IDS
    {"shape": stage_shape, "paint": stage_paint, "reduce": stage_reduce}[stage](ids)
