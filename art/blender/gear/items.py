"""Registers one gear asset per entry in data/art/gear_visuals.json (generated from the item data)."""
import json
import os

from lib import palette

from . import armour, weapons

GENERATORS = {}
GENERATORS.update(armour.GENERATORS)
GENERATORS.update(weapons.GENERATORS)


def assets():
    path = os.path.join(palette.ROOT, "data", "art", "gear_visuals.json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        items = json.load(f)["items"]
    out = []
    seen = set()
    for item_id, v in sorted(items.items()):
        model = v.get("model", item_id)
        if model in seen:
            continue
        seen.add(model)
        gen = GENERATORS.get(v["gen"])
        if gen is None:
            raise SystemExit("gear_visuals.json: no generator '%s' for %s" % (v["gen"], item_id))
        out.append({"id": model, "category": "gear", "build": (lambda vv=v, g=gen: g(vv))})
    return out
