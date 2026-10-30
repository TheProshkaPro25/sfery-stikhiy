"""Check the narrow 035 torso repair against the preserved 034 model.

Geometry/UVs, rests/binds, idle, clip times and the four rear surfaces are exact.
Only the first two skins, rest-relative chest/head reaction rotations and the
rigid mesh's .85 middle-stride marker change.
Optional --staged checks semantic equality with an earlier candidate GLB.
"""
import argparse
import copy
from pathlib import Path
import sys

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/models"))
from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import globals_of

SKIN_ATTRIBUTES = {"JOINTS_0", "JOINTS_1", "WEIGHTS_0", "WEIGHTS_1"}


def semantic_document(doc, binary):
    """Resolve storage offsets/indices, retaining the complete GLTF payload."""
    result = copy.deepcopy(doc)

    def value(index):
        spec = doc["accessors"][index]
        array = accessor(doc, binary, index)
        return (spec["componentType"], spec["type"], spec["count"],
                spec.get("normalized", False), array.tobytes())

    for key in ("accessors", "buffers", "bufferViews"):
        result.pop(key, None)
    for mesh in result.get("meshes", []):
        for primitive in mesh["primitives"]:
            primitive["indices"] = value(primitive["indices"])
            primitive["attributes"] = {k: value(v) for k, v in primitive["attributes"].items()}
    for skin in result.get("skins", []):
        skin["inverseBindMatrices"] = value(skin["inverseBindMatrices"])
    for clip in result.get("animations", []):
        for sampler in clip["samplers"]:
            for key in ("input", "output"):
                sampler[key] = value(sampler[key])
    for image in result.get("images", []):
        if "bufferView" in image:
            view = doc["bufferViews"][image.pop("bufferView")]
            offset = view.get("byteOffset", 0)
            image["embedded_bytes"] = binary[offset:offset + view["byteLength"]]
    return result


def dense_weights(doc, binary, primitive, count):
    vertices = len(accessor(doc, binary, primitive["attributes"]["POSITION"]))
    result = np.zeros((vertices, count))
    for group in (0, 1):
        joints = accessor(doc, binary, primitive["attributes"][f"JOINTS_{group}"])
        weights = accessor(doc, binary, primitive["attributes"][f"WEIGHTS_{group}"])
        assert joints.max() < count, "invalid joint slot"
        assert np.isfinite(weights).all() and (weights >= 0).all(), "invalid skin weight"
        np.add.at(result, (np.arange(vertices)[:, None], joints), weights)
    assert np.max(abs(result.sum(axis=1) - 1)) < 2e-6, "unnormalized skin"
    assert ((result > 0).sum(axis=1) <= 8).all(), "more than eight skin influences"
    return result


def verify_skin(doc, binary, old, old_binary, parts, old_parts):
    names = [doc["nodes"][i]["name"] for i in doc["skins"][0]["joints"]]
    hip = names.index("hips")
    thigh = names.index("thigh.R")
    # Geodesic proximity prevents permitting edits on a neighbouring but
    # disconnected shell simply because it is close in 3D.
    vertices = np.concatenate([p[1] for p in old_parts[:2]])
    faces = np.concatenate([old_parts[0][2], old_parts[1][2] + len(old_parts[0][1])])
    _, first, ids = np.unique(np.round(vertices, 6), axis=0, return_index=True, return_inverse=True)
    welded = vertices[first]
    faces = ids[faces]
    edges = np.unique(np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1), axis=0)
    lengths = np.linalg.norm(welded[edges[:, 0]] - welded[edges[:, 1]], axis=1)
    graph = coo_matrix((lengths, edges.T), shape=(len(welded), len(welded))).tocsr()
    seeds = np.unique(ids[len(old_parts[0][1]):][old_parts[1][2]])
    socket_distance = dijkstra(graph, directed=False, indices=seeds, min_only=True, limit=.04)[ids]
    root_seeds = ((welded[:, 0] > .14) & (welded[:, 0] < .185)
                  & (welded[:, 1] > -.17) & (welded[:, 1] < -.11)
                  & (welded[:, 2] > -.10) & (welded[:, 2] < -.055))
    assert root_seeds.any(), "right-root fixture region is empty"
    root_distance = dijkstra(graph, directed=False, indices=np.flatnonzero(root_seeds),
                             min_only=True, limit=.05)[ids]
    transforms = globals_of(old)
    nodes = {n.get("name"): i for i, n in enumerate(old["nodes"])}
    origin = transforms[nodes["chest"]][:3, 3].copy()
    origin[1] = 0
    forward = transforms[nodes["head"]][:3, 3] - transforms[nodes["chest"]][:3, 3]
    forward[1] = 0
    forward /= np.linalg.norm(forward)
    local = (vertices - origin) @ np.column_stack([np.cross([0, 1, 0], forward), [0, 1, 0], forward])
    belly = (abs(local[:, 0]) < .20) & (local[:, 2] < .14) & (local[:, 2] > -.32) & (local[:, 1] > -.27)
    allowed = (socket_distance < .04) | belly | (root_distance < .05)
    offset = 0
    changed_count = 0
    for index, ((primitive, verts, _), (original, _, _)) in enumerate(zip(parts, old_parts)):
        weights = dense_weights(doc, binary, primitive, len(names))
        before = dense_weights(old, old_binary, original, len(names))
        if index >= 2:
            assert np.array_equal(weights, before), "rear skin changed"
            continue
        changed = np.max(abs(weights - before), axis=1) > 2e-6
        changed_count += int(changed.sum())
        assert not (changed & ~allowed[offset:offset + len(verts)]).any(), "skin edit outside sockets/belly/right root"
        distances = root_distance[offset:offset + len(verts)]
        root_region = distances < .05
        assert (weights[~root_region, hip] >= before[~root_region, hip] - 2e-6).all(), "hip influence removed outside right root"
        core = distances == 0
        assert (weights[core, thigh] > .99999).all(), "solid right-root core still blends other bones"
        # Preserve every other bone's relative contribution. Only hips may
        # receive mass generally; thigh.R is additionally allowed in this one
        # geodesic patch. Packing can drop the ninth influence.
        for region, destinations in [(~root_region, [hip]), (root_region, [hip, thigh])]:
            others = ~np.isin(np.arange(len(names)), destinations)
            current = weights[region][:, others]
            previous = before[region][:, others]
            assert not ((current > 2e-6) & (previous == 0)).any(), "new influence outside allowed transfer destinations"
            ratios = np.divide(current, previous, out=np.zeros_like(current), where=previous > 0)
            retained = current > 2e-6
            high = np.max(np.where(retained, ratios, 0), axis=1)
            low = np.min(np.where(retained, ratios, np.inf), axis=1)
            assert (high - low < 2e-5).all(), "unrelated influences rebalanced"
        offset += len(verts)
    assert changed_count > 0, "repair did not change torso skin"
    return changed_count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", nargs="?", type=Path, default=ROOT / "assets/creatures_hd/rogozhuk_stone.glb")
    parser.add_argument("--source", type=Path, default=ROOT / "tools/_tmp/repair035-stone/base/rogozhuk_stone.glb")
    parser.add_argument("--staged", type=Path)
    args = parser.parse_args()
    doc, binary = read_glb(args.model)
    old, old_binary = read_glb(args.source)
    assert doc["asset"].get("extras", {}).get("stone_torso_binding") == 1, "missing 035 marker"
    actual = semantic_document(doc, binary)
    expected = semantic_document(old, old_binary)
    expected["asset"].setdefault("extras", {})["stone_torso_binding"] = 1
    rigid_nodes = [i for i, node in enumerate(old["nodes"])
                   if node.get("extras", {}).get("sfery_rigid_limbs")]
    assert rigid_nodes, "missing rigid mesh"
    for index in rigid_nodes:
        assert "mesh" in old["nodes"][index], "stride marker must belong to rigid mesh"
        assert doc["nodes"][index].get("extras", {}).get("sfery_middle_stride") == .85
        expected["nodes"][index]["extras"]["sfery_middle_stride"] = .85
    parts, old_parts = list(triangles(doc, binary)), list(triangles(old, old_binary))
    assert len(parts) == len(old_parts) == 6
    assert len(doc["meshes"]) == len(old["meshes"]) == 1
    # Permit only four skin attributes on the two body surfaces. The final
    # full-document comparison still checks every other referenced payload.
    for index in range(2):
        for name in SKIN_ATTRIBUTES:
            expected["meshes"][0]["primitives"][index]["attributes"][name] = actual["meshes"][0]["primitives"][index]["attributes"][name]
    changed_tracks = 0
    for clip_index, (clip, original) in enumerate(zip(doc["animations"], old["animations"])):
        if original["name"] == "idle":
            continue
        for channel in original["channels"]:
            node = old["nodes"][channel["target"]["node"]]
            factor = {"chest": .2, "head": .5}.get(node.get("name"))
            if factor is None or channel["target"]["path"] != "rotation":
                continue
            sampler = channel["sampler"]
            before = accessor(old, old_binary, original["samplers"][sampler]["output"])
            after = accessor(doc, binary, clip["samplers"][sampler]["output"])
            rest = Rotation.from_quat(node.get("rotation", [0, 0, 0, 1]))
            delta = rest.inv() * Rotation.from_quat(before)
            target = rest * Rotation.from_rotvec(delta.as_rotvec() * factor)
            assert after.shape == before.shape, "rotation key count changed"
            assert np.isfinite(after).all() and np.max(abs(np.linalg.norm(after, axis=1) - 1)) < 2e-6
            assert np.max((target.inv() * Rotation.from_quat(after)).magnitude()) < 2e-7, (original["name"], node["name"], "wrong rest-relative rotation")
            expected["animations"][clip_index]["samplers"][sampler]["output"] = actual["animations"][clip_index]["samplers"][sampler]["output"]
            changed_tracks += 1
    assert changed_tracks > 0
    assert actual == expected, "payload outside the allowed torso skin/rotation edits changed"
    changed_vertices = verify_skin(doc, binary, old, old_binary, parts, old_parts)
    if args.staged:
        staged, staged_binary = read_glb(args.staged)
        staged_payload = semantic_document(staged, staged_binary)
        staged_payload["asset"].setdefault("extras", {})["stone_torso_binding"] = 1
        for index in rigid_nodes:
            staged_payload["nodes"][index]["extras"]["sfery_middle_stride"] = .85
        # Staged skin was packed between the two transfer passes. Production
        # packs once, so permit float32 rounding only in these weight arrays.
        for index in range(2):
            for name in ("WEIGHTS_0", "WEIGHTS_1"):
                current = doc["meshes"][0]["primitives"][index]["attributes"][name]
                previous = staged["meshes"][0]["primitives"][index]["attributes"][name]
                a = accessor(doc, binary, current)
                b = accessor(staged, staged_binary, previous)
                assert a.shape == b.shape and np.max(abs(a - b)) <= 1e-7, "staged weight values differ"
                current_value = actual["meshes"][0]["primitives"][index]["attributes"][name]
                staged_value = staged_payload["meshes"][0]["primitives"][index]["attributes"][name]
                assert current_value[:4] == staged_value[:4], "staged weight layout differs"
                staged_payload["meshes"][0]["primitives"][index]["attributes"][name] = current_value
        assert actual == staged_payload, "final does not match staged payload"
    print(f"Stone torso: exact geometry/UV/rest/bind/idle/times/rear surfaces; {changed_tracks} permitted rotation tracks; {changed_vertices} local skin edits; staged match={bool(args.staged)}")


if __name__ == "__main__":
    main()
