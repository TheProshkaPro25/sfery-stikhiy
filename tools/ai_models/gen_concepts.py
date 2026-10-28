"""Концепты существ (картинки для Hunyuan3D): SSD-1B (Apache 2.0), белый фон, существо целиком.

Запуск: systemd-run --user --scope -p MemoryMax=7G ~/ai/Hunyuan3D-2/.venv/bin/python tools/ai_models/gen_concepts.py [id...]
Пишет tools/ai_models/concepts/<id>_<seed>.png (по 2 варианта на существо).
"""
import os
import sys


OUT = os.path.join(os.path.dirname(__file__), "concepts")
STYLE = ("full body single creature, standing on four legs or in neutral battle stance, three-quarter front view, "
         "centered, whole body visible, plain pure white background, no ground shadow, serious dark fantasy anime monster design, "
         "armored plates, sharp details, menacing, game character concept art, clean silhouette, high detail")
NEG = ("background scenery, landscape, text, watermark, logo, multiple creatures, cropped, cut off, frame, cute, chibi, "
       "toy, plush, cartoon, blurry, lowres, human, person, rider")

CREATURES = {
    "zharovik": "fire dragon with molten orange-red scales, glowing ember cracks, large horned head, bat wings folded, long tail with flames",
    "peplohvost": "four-legged quadruped ash-grey and orange fire wolf beast, smoldering fur, tail made of flowing embers and ash, fierce glowing eyes",
    "magmozavr": "massive magma dinosaur dragon, black volcanic rock armor with lava glowing between plates, heavy jaw, spiked back",
    "iskren": "floating fire imp with one large glowing eye, crackling sparks, small flame wings, spiked orange shell",
    "vihrekryl": "wind eagle griffin bird of prey, teal and white feathers, huge blade-like wings spread, sharp beak, storm swirls",
    "shkvalnik": "storm centaur warrior, jade green armor, lightning spear, cloak flowing in wind, horse body with wind runes",
    "neboklyuv": "sky raptor bird, long sharp beak, steel-blue armored feathers, tall crest, talons, majestic",
    "luminar": "holy light knight, golden white plate armor, glowing halo crest, radiant sword and tower shield, tall",
    "solncegriv": "sun lion centaur, golden radiant mane like sun rays, white armor, solar spear",
    "zarnica": "lightning stag beetle, pale gold carapace with electric arcs, huge mandibles, glowing wing cases",
    "granitrog": "granite cyclops brute, one big eye, stone horns, rocky grey-brown skin, heavy fists, moss in cracks",
    "valunnik": "boulder golem, massive body of stacked rocks, glowing amber core, huge stone arms",
    "kvarcevik": "quartz crystal golem, body of translucent pink and white crystal shards, glowing inner light",
    "sumrachnik": "shadow knight, black and violet armor, tattered dark cape, glowing purple eyes, curved blade",
    "mglokryl": "mist bat demon with one big eye, violet membrane wings, smoky dark body, floating",
    "polunochnik": "midnight cyclops ogre, deep purple skin, one glowing violet eye, horned helmet, chains",
    "mareolit": "sea serpent, deep blue scales, fins like sails, coiled body, foam crest, fierce head",
    "glubinnik": "abyssal leviathan serpent, dark navy armored scales, bioluminescent cyan spots, long fangs",
    "penorog": "tide rhinoceros beetle, blue-green shell with foam-white horn, water droplets, armored legs",
    "ledostruy": "four-legged quadruped ice wolf beast, pale blue frost fur, ice crystal spikes along back, cold mist breath",
}


def main():
    import torch
    from diffusers import StableDiffusionXLPipeline
    ids = sys.argv[1:] or list(CREATURES)
    os.makedirs(OUT, exist_ok=True)
    pipe = StableDiffusionXLPipeline.from_pretrained("segmind/SSD-1B", torch_dtype=torch.float16, variant="fp16", use_safetensors=True)
    pipe.enable_model_cpu_offload()  # UNet уходит в RAM перед декодированием (8 ГБ VRAM вместе с игрой)
    pipe.enable_vae_tiling()  # иначе декодирование 1024px не влезает в 8 ГБ вместе с игрой
    pipe.set_progress_bar_config(disable=True)
    for cid in ids:
        for seed in (11, 23):
            path = os.path.join(OUT, f"{cid}_{seed}.png")
            if os.path.exists(path):
                continue
            g = torch.Generator("cuda").manual_seed(seed)
            img = pipe(prompt=f"{CREATURES[cid]}, {STYLE}", negative_prompt=NEG, num_inference_steps=28,
                       guidance_scale=7.0, width=1024, height=1024, generator=g).images[0]
            img.save(path)
            print("ok", path, flush=True)


if __name__ == "__main__":
    main()
