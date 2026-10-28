"""Существо по концепту через TRELLIS.2 (int8 ConvRot, MIT) на сервере ComfyUI: форма + PBR-текстура сразу.

Берёт официальный шаблон ComfyUI 3d_pixal3d_trellis2_image_to_model, выбирает ветку TRELLIS.2,
переводит UI-граф в API-запрос (по /object_info) и отправляет его.
Сервер: cd ~/ai/ComfyUI && .venv/bin/python main.py --listen 127.0.0.1 --port 8188
Клиент: python3 tools/ai_models/trellis2.py vihrekryl [...]
Вход: tools/ai_models/concepts/<id>_<pick>.png (PICK из gen_meshes.py). Выход: tools/ai_models/meshes_tr2/<id>.glb
"""
import glob
import json
import os
import shutil
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
SERVER = "http://127.0.0.1:8188"
COMFY = os.path.expanduser("~/ai/ComfyUI")
HERE = os.path.dirname(os.path.abspath(__file__))
# TR2_ENGINE=pixal — ветка Pixal3D того же шаблона (Tencent ARC, MIT): проецирует концепт на модель, цвета как на картинке
PIXAL = os.environ.get("TR2_ENGINE") == "pixal"
ENGINE_SWITCHES = {314, 315, 318}  # conditioning x2 и UNet: on_true = TRELLIS.2, on_false = Pixal3D
OUT = os.path.join(HERE, os.environ.get("TR2_OUT") or ("meshes_px" if PIXAL else "meshes_tr2"))  # TR2_OUT — для сравнений
TEMPLATE = glob.glob(os.path.join(COMFY, ".venv/lib/python*/site-packages/comfyui_workflow_templates_json/templates/"
                                         "3d_pixal3d_trellis2_image_to_model.json"))[0]
PASS = {"PreviewImage", "MaskPreview"}  # в шаблоне эти узлы пропускают вход дальше
# Под нашу игру и 8 ГБ: меньше граней и текстура 2048 вместо 4096.
OVERRIDES = {
    186: {"target_face_count": 150000, "placement_mode": "midpoint"},
    288: {"value": 2048},
    # RemeshMesh: sign_mode — динамический список, его подпараметры идут как "sign_mode.<имя>"
    # TR2_REMESH=640 — для тяжёлых существ, которым 768 не влезает в 8 ГБ
    241: {"resolution": int(os.environ.get("TR2_REMESH", 768)), "band": 1.0,
          "project_back": 0.0, "fix_poles": False, "smooth_iters": 20, "drop_small_components": 0.01,
          "precluster_max_verts": 20000000,
          # solid (тетраэдризация в float64) на сложных формах не влезает в 8 ГБ -> TR2_SIGN=udf
          **({"sign_mode": "udf", "sign_mode.qef": False, "sign_mode.drop_inverted_components": True,
              "sign_mode.drop_enclosed_components": True} if os.environ.get("TR2_SIGN") == "udf" else
             {"sign_mode": "solid", "sign_mode.fill": 20.0, "sign_mode.qef": False})},
    94: {"target_resolution": 1024},  # 1536 из шаблона: OOM на VaeDecodeShapeTrellis у большинства существ
    322: {"width": 1024, "height": 1024},
    312: {"background": "#000000"},  # тип COLOR, как в шаблоне
}
REPLACE = {241}  # параметры узла задаются целиком здесь (UI-значения шаблона сдвинуты)
# Плотная сетка до упрощения при запекании (147) не влезает в 8 ГБ (OOM на части существ); на 150k граней не нужна.
DROP = {147: ("reference_mesh",)}


def call(path, data=None):
    req = urllib.request.Request(SERVER + path, data=json.dumps(data).encode() if data else None,
                                 headers={"Content-Type": "application/json"})
    body = urllib.request.urlopen(req, timeout=120).read()
    return json.loads(body) if body else {}


def build(image_name: str, prefix: str) -> dict:
    t = json.load(open(TEMPLATE))
    info = call("/object_info")
    nodes = {n["id"]: n for n in t["nodes"]}
    links = {}
    for lk in t["links"]:
        links[lk[0]] = (lk[1], lk[2])

    def src(nid, slot):
        """Источник с учётом проходных узлов и переключателей (ветка TRELLIS.2 = on_true)."""
        n = nodes[nid]
        if n["type"] in PASS:
            lk = n["inputs"][0]["link"]
            return src(*links[lk])
        if n["type"] == "ComfySwitchNode":
            want = "on_false" if PIXAL and nid in ENGINE_SWITCHES else "on_true"
            for i in n["inputs"]:
                if i["name"] == want and i.get("link") is not None:
                    return src(*links[i["link"]])
        if n["type"] == "PrimitiveBoolean":
            return None
        return (nid, slot)

    api = {}

    def add(nid):
        key = str(nid)
        if key in api:
            return
        n = nodes[nid]
        spec = info[n["type"]]["input"]
        order = list(spec.get("required", {}).items()) + list(spec.get("optional", {}).items())
        linked = {i["name"]: i["link"] for i in n.get("inputs", []) if i.get("link") is not None}
        widget_linked = {i["name"] for i in n.get("inputs", []) if i.get("link") is not None and i.get("widget")}
        vals = list(n.get("widgets_values") or [])
        inputs = {}
        for name, conf in order:
            if name in linked:
                s = src(*links[linked[name]])
                if s is None:
                    continue
                add(s[0])
                inputs[name] = [str(s[0]), s[1]]
                # у входа-виджета, подключённого линком, значение в widgets_values всё равно есть
                if name in widget_linked and vals:
                    vals.pop(0)
                continue
            if not _is_widget(conf) or not vals:
                continue
            inputs[name] = vals.pop(0)
            if name in ("seed", "noise_seed", "value") and vals and vals[0] in ("fixed", "randomize", "increment", "decrement"):
                vals.pop(0)
        if nid in REPLACE:
            inputs = {k: v for k, v in inputs.items() if isinstance(v, list)}
        inputs.update(OVERRIDES.get(nid, {}))
        if nid == 12 and os.environ.get("TR2_TEX_SEED"):  # KSampler текстуры: тёмные концепты иногда дают чёрную текстуру
            inputs["seed"] = int(os.environ["TR2_TEX_SEED"])
        if nid in (18, 23) and os.environ.get("TR2_SEED"):  # KSampler формы: другой seed — другая (иногда легче) форма
            inputs["seed"] = int(os.environ["TR2_SEED"])
        for name in DROP.get(nid, ()):
            inputs.pop(name, None)
        api[key] = {"class_type": n["type"], "inputs": inputs}

    nodes[122]["widgets_values"] = [image_name, "image"]
    nodes[322]["widgets_values"] = [prefix, "", 1024, 1024]  # filename_prefix, viewport_state, width, height
    add(322)
    if PIXAL and os.environ.get("TR2_PAINT") == "1":
        # photo paint из Atelier3D (custom_nodes/atelier3d, MIT): мелкие детали концепта поверх запечённого цвета,
        # по камере Pixal3D (fov от MoGe). Маска кадрируется так же, как картинка (ImageCropToMask 312).
        frame = {k: api["312"]["inputs"][k] for k in ("masks", "width", "height", "pad_factor", "grow_mask", "background")}
        api["px_mask_img"] = {"class_type": "MaskToImage", "inputs": {"mask": ["192", 0]}}
        api["px_mask_crop"] = {"class_type": "ImageCropToMask", "inputs": {"images": ["px_mask_img", 0], **frame}}
        api["px_mask"] = {"class_type": "ImageToMask", "inputs": {"image": ["px_mask_crop", 0], "channel": "red"}}
        api["px_paint"] = {"class_type": "AtelierProjectImage", "inputs": {
            "mesh": ["196", 0], "base_color": ["147", 0], "image": ["312", 0], "mask": ["px_mask", 0],
            "fov": ["242", 0], "azimuth": 0.0, "distance_scale": 1.0, "strength": 1.0, "detail_sigma": 12.0}}
        api["210"]["inputs"]["base_color"] = ["px_paint", 0]
    if os.environ.get("TR2_RES") == "512":
        # официальный режим 512 без каскада: форма и текстура из первого KSampler формы (18), без апсемпла (94/23).
        # Для тяжёлых существ, у которых декод каскада 1024 не влезает в 8 ГБ.
        api["92"]["inputs"]["samples"] = ["18", 0]
        api["98"]["inputs"].update(positive=["91", 0], negative=["91", 1], shape_latent=["18", 0])
        api.pop("94", None)
        api.pop("23", None)
    return api


def _is_widget(conf) -> bool:
    typ = conf[0]
    return isinstance(typ, list) or typ in ("INT", "FLOAT", "STRING", "BOOLEAN", "COMBO", "LOAD_3D")


def run(cid: str, pick: str):
    from PIL import Image
    dst = os.path.join(OUT, f"{cid}.glb")
    if os.path.exists(dst):
        return
    name = f"tr2_{cid}.png"
    src = os.path.join(HERE, "concepts", f"{cid}.png")  # стихийные версии видов (variants.py): concepts/<вид>_<стихия>.png
    if not os.path.exists(src):
        src = os.path.join(HERE, "concepts", f"{cid}_{pick}.png")
    Image.open(src).convert("RGB").save(os.path.join(COMFY, "input", name))
    prefix = f"3d/tr2_{cid}_{int(time.time())}"
    # выгрузить модели и кэш от прошлого существа: OOM часто из-за остатков, а не из-за самого существа
    call("/free", {"unload_models": True, "free_memory": True})
    time.sleep(3)
    pid = call("/prompt", {"prompt": build(name, prefix)})["prompt_id"]
    t0 = time.time()
    while True:
        h = call(f"/history/{pid}")
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                msgs = [m for m in st.get("messages", []) if m[0] == "execution_error"]
                err = msgs[0][1] if msgs else {}
                raise RuntimeError(f"{cid}: {err.get('node_type')}: {err.get('exception_message', '')[:300]}")
            out_dir = os.path.join(COMFY, "output", os.path.dirname(prefix))
            files = sorted(f for f in os.listdir(out_dir) if f.startswith(os.path.basename(prefix)) and f.endswith(".glb"))
            if files:
                shutil.copy(os.path.join(out_dir, files[-1]), dst)
                if not PIXAL:  # TRELLIS.2 выдаёт цвета ~в 3 раза темнее концепта; Pixal3D — как на концепте
                    from fix_albedo import fix
                    fix(dst)
                print(f"ok {cid} {time.time() - t0:.0f}s", flush=True)
                return
            if st.get("completed"):
                raise RuntimeError(f"{cid}: готово, но .glb не найден в {out_dir}")
        time.sleep(3)


if __name__ == "__main__":
    from gen_meshes import PICK
    os.makedirs(OUT, exist_ok=True)
    if sys.argv[1] == "--dump":
        print(json.dumps(build("x.png", "3d/x"), indent=1, ensure_ascii=False))
        sys.exit()
    for cid in sys.argv[1:]:
        run(cid, PICK.get(cid, "c11"))
