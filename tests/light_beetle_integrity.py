"""Protect accepted030 Light anatomy and the reviewed 035 geometry delta.

The immutable v16 reference restores the original ankles and repairs sockets.
Any later surface change requires an explicit reviewed face/attribute whitelist;
unchanged vertex arrays alone do not prove that a triangulated shape is intact.
Run attachment and actual-pose intersection checks separately.

Requires the preserved accepted030, pre030, pre029 and immutable v16 GLBs at the
default paths below (or explicit source/reference paths). Keep
those source artifacts, or their exact reproducible recipe, with the repair
archive: a reviewed whitelist pins v16 by SHA256 and cannot use a regenerated
approximation as its reference. Experimental v18/v21 files are not dependencies.

Validate the accepted final with:
  python tests/light_beetle_integrity.py <model.glb> \
    --whitelist tests/fixtures/light035_contract.json
"""
import argparse
import copy
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import trimesh
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/models"))
from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import globals_of


def image_payloads(doc, data):
    result = []
    for image in doc.get("images", []):
        metadata = {k: v for k, v in image.items() if k != "bufferView"}
        if "bufferView" in image:
            view = doc["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            metadata["bytes"] = data[start:start + view["byteLength"]]
        result.append(metadata)
    return result


def dense_weights(doc, data, primitive):
    vertices = len(accessor(doc, data, primitive["attributes"]["POSITION"]))
    count = len(doc["skins"][0]["joints"])
    result = np.zeros((vertices, count))
    for group in (0, 1):
        joints = accessor(doc, data, primitive["attributes"][f"JOINTS_{group}"])
        weights = accessor(doc, data, primitive["attributes"][f"WEIGHTS_{group}"])
        assert joints.min() >= 0 and joints.max() < count, "invalid joint slot"
        assert np.isfinite(weights).all() and (weights >= 0).all(), "invalid skin weight"
        np.add.at(result, (np.arange(vertices)[:, None], joints), weights)
    assert np.max(abs(result.sum(axis=1) - 1)) < 2e-6, "skin is not normalized"
    assert ((result > 0).sum(axis=1) <= 8).all()
    return result


def face_keys(faces):
    """Ignore triangle ordering, while preserving orientation and multiplicity."""
    keys = []
    for face in faces:
        i = int(np.argmin(face))
        keys.append(tuple(np.roll(face, -i).tolist()))
    assert len(set(keys)) == len(keys), "duplicate faces"
    return set(keys)


def coordinate_faces(vertices, faces, decimals=6):
    points = np.round(vertices, decimals) if decimals is not None else vertices
    return {tuple(sorted(tuple(points[i]) for i in face)) for face in faces}


def flip_boundary(faces):
    """Oriented rim of the reviewed two-triangle diagonal flip."""
    edges = Counter((int(a), int(b)) for face in faces for a, b in zip(face, np.roll(face, -1)))
    return Counter({edge: count - edges[edge[::-1]] for edge, count in edges.items()
                    if count > edges[edge[::-1]]})


def check_rig_and_clips(doc, data, old, old_data, stride_by_bone=None):
    expected_nodes = copy.deepcopy(old["nodes"])
    for node in expected_nodes:
        if "mesh" in node:
            node.setdefault("extras", {}).update(sfery_rigid_limbs=True,
                                                  sfery_turn_stance=True,
                                                  sfery_middle_stride=.85)
            if stride_by_bone is not None:
                node["extras"]["sfery_stride_by_bone"] = stride_by_bone
    assert doc["nodes"] == expected_nodes, "rest skeleton or runtime markers changed"
    for field in ("materials", "textures", "samplers", "scenes", "scene"):
        assert doc.get(field) == old.get(field), (field, "changed")
    assert image_payloads(doc, data) == image_payloads(old, old_data), "texture payload changed"
    assert len(doc["skins"]) == len(old["skins"])
    for skin, original in zip(doc["skins"], old["skins"]):
        assert {k: v for k, v in skin.items() if k != "inverseBindMatrices"} == {
            k: v for k, v in original.items() if k != "inverseBindMatrices"}
        assert np.array_equal(accessor(doc, data, skin["inverseBindMatrices"]),
                              accessor(old, old_data, original["inverseBindMatrices"]))
    assert len(doc["animations"]) == len(old["animations"])
    lower = ("forearm.", "hand.", "shin.", "foot.", "rear_shin.", "rear_foot.")
    for clip, original in zip(doc["animations"], old["animations"]):
        assert clip["name"] == original["name"] and clip["channels"] == original["channels"]
        assert len(clip["samplers"]) == len(original["samplers"])
        for index, (sampler, previous) in enumerate(zip(clip["samplers"], original["samplers"])):
            assert {k: v for k, v in sampler.items() if k not in ("input", "output")} == {
                k: v for k, v in previous.items() if k not in ("input", "output")}
            assert np.array_equal(accessor(doc, data, sampler["input"]),
                                  accessor(old, old_data, previous["input"])), "animation timing changed"
            before = accessor(old, old_data, previous["output"])
            after = accessor(doc, data, sampler["output"])
            assert before.shape == after.shape and np.isfinite(after).all()
            targets = [c["target"] for c in original["channels"] if c["sampler"] == index]
            if not targets:
                assert np.array_equal(after, before), "unused historical sampler changed"
                continue
            assert len(targets) == 1, "unexpected shared animation sampler"
            target = targets[0]
            node = old["nodes"][target["node"]]
            name, path = node.get("name", ""), target["path"]
            if name.startswith(lower):
                rest = node.get(path, {"rotation": [0, 0, 0, 1], "translation": [0, 0, 0], "scale": [1, 1, 1]}[path])
                expected = np.tile(rest, (len(before), 1)).astype(before.dtype)
                assert np.array_equal(after, expected), (clip["name"], name, path, "lower joint is not at rest")
                continue
            factor = None
            if path == "rotation":
                if clip["name"] != "idle": factor = {"chest": .2, "head": .35, "shell": 0}.get(name)
                if clip["name"] == "idle" and name in ("chest", "head"): factor = .3
                if clip["name"] == "stance" and name == "hips": factor = .3
            if factor is None:
                assert np.array_equal(after, before), (clip["name"], name, path, "protected channel changed")
            else:
                rest = Rotation.from_quat(node.get("rotation", [0, 0, 0, 1]))
                expected = rest * Rotation.from_rotvec((rest.inv() * Rotation.from_quat(before)).as_rotvec() * factor)
                assert np.max(abs(np.linalg.norm(after, axis=1) - 1)) < 2e-6
                assert np.max((expected.inv() * Rotation.from_quat(after)).magnitude()) < 5e-7, (clip["name"], name, "wrong rotation limit")


def check_reference(reference, reference_data, source, source_data, original, original_data, pre030, pre030_data):
    parts = list(triangles(reference, reference_data))
    old_parts = list(triangles(source, source_data))
    original_part = next(triangles(original, original_data))
    before = coordinate_faces(old_parts[0][1], old_parts[0][2])
    restored = coordinate_faces(parts[0][1], parts[0][2])
    authored = coordinate_faces(original_part[1], original_part[2])
    assert before <= restored, "035 reference removed accepted030 exterior"
    assert len(restored - before) == 2574 and restored - before <= authored, "original ankles were not restored exactly"
    previous_caps = coordinate_faces(old_parts[1][1], old_parts[1][2])
    current_caps = coordinate_faces(parts[1][1], parts[1][2])
    assert len(previous_caps & current_caps) == 574, "accepted030 closures changed"
    # Some historical exterior triangles were reassigned to cap material in
    # 030. Compare against both older body surfaces to isolate the 137 truly
    # new plate-removal closures, rather than freezing every old029 cap defect.
    preceding_surface = set()
    for _, vertices, faces in list(triangles(pre030, pre030_data))[:2]:
        preceding_surface |= coordinate_faces(vertices, faces, decimals=None)
    protected030 = coordinate_faces(old_parts[1][1], old_parts[1][2], decimals=None) - preceding_surface
    assert len(protected030) == 137, "unexpected accepted030 cut-face contract"
    assert protected030 <= coordinate_faces(parts[1][1], parts[1][2], decimals=None)
    return protected030


def check_geometry(doc, data, reference, reference_data, whitelist, protected030=None):
    parts = list(triangles(doc, data))
    reference_parts = list(triangles(reference, reference_data))
    assert len(parts) == len(reference_parts) == 6
    names = [doc["nodes"][i]["name"] for i in doc["skins"][0]["joints"]]
    seam_weights = {}
    for index, ((p, vertices, faces), (rp, rv, rf)) in enumerate(zip(parts, reference_parts)):
        assert p.get("material") == rp.get("material") and p.get("mode", 4) == rp.get("mode", 4)
        assert p["attributes"].keys() == rp["attributes"].keys()
        expected_faces = face_keys(rf)
        if index == 0:
            removed = face_keys(np.asarray(whitelist.get("removed_faces", []), dtype=int).reshape(-1, 3))
            added = face_keys(np.asarray(whitelist.get("added_faces", []), dtype=int).reshape(-1, 3))
            assert removed <= expected_faces and not (added & (expected_faces - removed))
            expected_faces = (expected_faces - removed) | added
        elif index == 1 and "cap_flip" in whitelist:
            delta = whitelist["cap_flip"]
            removed = np.asarray(delta["removed_faces"], dtype=int)
            added = np.asarray(delta["added_faces"], dtype=int)
            assert removed.shape == added.shape == (2, 3), "cap exception is only one diagonal flip"
            assert len(np.unique(removed)) == 4 and set(removed.ravel()) == set(added.ravel())
            assert flip_boundary(removed) == flip_boundary(added), "cap flip changes its oriented rim"
            old_keys, new_keys = face_keys(removed), face_keys(added)
            assert len(flip_boundary(removed)) == 4 and not (old_keys & new_keys)
            assert old_keys <= expected_faces and not (new_keys & (expected_faces - old_keys))
            expected_faces = (expected_faces - old_keys) | new_keys
        assert face_keys(faces) == expected_faces, (index, "unreviewed triangulation change")
        for name in p["attributes"]:
            if name.startswith(("JOINTS_", "WEIGHTS_")): continue
            values = accessor(doc, data, p["attributes"][name])
            expected = accessor(reference, reference_data, rp["attributes"][name])
            if index < 2 and name in whitelist.get("attributes", {}):
                change = whitelist["attributes"][name]
                expected[np.asarray(change["indices"], dtype=int)] = np.asarray(change["values"], dtype=expected.dtype)
            assert np.array_equal(values, expected), (index, name, "unreviewed attribute change")
        weights = dense_weights(doc, data, p)
        # Include material/UV duplicates across primitives, but ignore unused
        # accessor rows: static closure alone cannot detect a skin seam.
        for vertex in np.unique(faces):
            key = tuple(np.round(vertices[vertex], 6))
            previous = seam_weights.setdefault(key, weights[vertex])
            assert np.max(abs(previous - weights[vertex])) <= 2e-6, (index, int(vertex), "deforming skin seam")
        expected_weights = dense_weights(reference, reference_data, rp)
        if index < 2 and "weights" in whitelist:
            change = whitelist["weights"]
            expected_weights[np.asarray(change["indices"], dtype=int)] = np.asarray(change["values"])
        assert np.max(abs(weights - expected_weights)) < 2e-6, (index, "unreviewed skin change")
        if index >= 2:
            joint = names.index("rear_thigh." + ("L" if index < 4 else "R"))
            assert weights[:, joint].min() > .99999, "rear socket is not rigid"
        # Whitelisted clearance may repair old029 cap defects, but none of
        # the actual accepted030 plate-removal cut surfaces may move.
        if index == 1 and protected030 is not None:
            assert protected030 <= coordinate_faces(vertices, faces, decimals=None), "accepted030 cut geometry changed"
    for start in (0, 2, 4):
        v = np.concatenate([parts[start][1], parts[start + 1][1]])
        f = np.concatenate([parts[start][2], parts[start + 1][2] + len(parts[start][1])])
        mesh = trimesh.Trimesh(v, f, process=True)
        assert mesh.is_watertight and mesh.is_winding_consistent and mesh.area_faces.min() > 1e-13
        assert len(mesh.split(only_watertight=False)) == 1, "detached exterior scrap"
    g = globals_of(doc)
    nodes = {n.get("name"): i for i, n in enumerate(doc["nodes"])}
    center = g[nodes["chest"]][:3, 3]
    forward = g[nodes["head"]][:3, 3] - center
    forward[1] = 0
    forward /= np.linalg.norm(forward)
    for _, vertices, faces in parts[:2]:
        used = vertices[np.unique(faces)]
        assert not ((((used - center) @ forward) < -.315) & (used[:, 1] < .06)).any(), "removed030 rear plates returned"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("--source", type=Path, default=ROOT / "tools/_tmp/repair035-light/base/rogozhuk_light.glb")
    parser.add_argument("--original", type=Path, default=ROOT / "tools/_tmp/repair029/base/rogozhuk_light.glb")
    parser.add_argument("--pre030", type=Path, default=ROOT / "tools/_tmp/repair030/base/rogozhuk_light.glb")
    parser.add_argument("--reference", type=Path, default=ROOT / "tools/_tmp/repair035-light/candidate-v16/rogozhuk_light.glb")
    parser.add_argument("--whitelist", type=Path)
    args = parser.parse_args()
    doc, data = read_glb(args.model)
    source, source_data = read_glb(args.source)
    original, original_data = read_glb(args.original)
    pre030, pre030_data = read_glb(args.pre030)
    reference, reference_data = read_glb(args.reference)
    whitelist = json.loads(args.whitelist.read_text()) if args.whitelist else {}
    if whitelist:
        assert whitelist["reference_sha256"] == hashlib.sha256(args.reference.read_bytes()).hexdigest(), "wrong whitelist reference"
    check_rig_and_clips(doc, data, source, source_data, whitelist.get("stride_by_bone"))
    protected030 = check_reference(reference, reference_data, source, source_data, original, original_data, pre030, pre030_data)
    expected_asset = copy.deepcopy(reference["asset"])
    if "asset_extras" in whitelist: expected_asset["extras"] = whitelist["asset_extras"]
    assert doc["asset"] == expected_asset, "unreviewed asset markers"
    check_geometry(doc, data, reference, reference_data, whitelist, protected030)
    print("Light035 PASS: exact reviewed surface delta; original ankles, accepted030 plate removal/closures, rigid sockets, rest/bind/textures and clip formulas protected")


if __name__ == "__main__":
    main()
