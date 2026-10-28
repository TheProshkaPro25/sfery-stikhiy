"""Существо по концепту через официальный Space microsoft/TRELLIS.2 (HF ZeroGPU) — для тех, кому не хватает 8 ГБ локально.

Запуск: ~/ai/Hunyuan3D-2/.venv/bin/python tools/ai_models/trellis2_hf.py magmozavr [...]
Квота ZeroGPU маленькая; с токеном HF (HF_TOKEN или ~/.cache/huggingface/token) её больше.
Вход: concepts/<id>_<pick>.png (PICK из gen_meshes.py). Выход: meshes_tr2/<id>.glb
"""
import os
import shutil
import sys
import time

from gradio_client import Client, handle_file

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "meshes_tr2")
RESOLUTION = os.environ.get("TR2_RES", "1536")
PICK = {  # копия из gen_meshes.py (тот импортирует torch/hy3dgen)
    "zharovik": "c11", "peplohvost": "c11", "magmozavr": "c23", "iskren": "c11", "vihrekryl": "c23",
    "shkvalnik": "c11", "neboklyuv": "c11", "luminar": "c11", "solncegriv": "c11", "zarnica": "c11",
    "granitrog": "c11", "valunnik": "c23", "kvarcevik": "c11", "sumrachnik": "c11", "mglokryl": "c23",
    "polunochnik": "c11", "mareolit": "c23", "glubinnik": "c23", "penorog": "c11", "ledostruy": "c11",
}


def run(c: Client, cid: str):
    dst = os.path.join(OUT, f"{cid}.glb")
    if os.path.exists(dst):
        return
    t0 = time.time()
    img = handle_file(os.path.join(HERE, "concepts", f"{cid}_{PICK.get(cid, 'c11')}.png"))
    c.predict(api_name="/start_session")
    prep = c.predict(img, api_name="/preprocess_image")
    c.predict(handle_file(prep), 0, RESOLUTION, api_name="/image_to_3d")
    glb, _ = c.predict(150000, 2048, api_name="/extract_glb")  # как в trellis2.py: 150k граней, текстура 2048
    shutil.copy(glb, dst)
    print(f"ok {cid} {time.time() - t0:.0f}s", flush=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    client = Client("microsoft/TRELLIS.2", verbose=False)
    for cid in sys.argv[1:]:
        try:
            run(client, cid)
        except Exception as e:  # квота/очередь — идём дальше
            print(f"fail {cid}: {str(e)[:300]}", flush=True)
