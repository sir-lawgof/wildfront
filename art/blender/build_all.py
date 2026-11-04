"""Builds every generated model (or a subset) and exports .glb files into the Godot project.

Run through tools/build_assets.py, or directly:
  blender --background --factory-startup --python art/blender/build_all.py -- [--only id1,id2] [--list]

Each asset module exposes ASSETS = [{"id", "category", "build", "animations"?}]. Output goes to
assets/models/<category>/<id>.glb. If art/manual/<id>.blend exists, that file is exported instead
(manual override, same export settings).
"""
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from lib import cli, export, palette  # noqa: E402


def collect():
    import importlib
    assets = []
    for pkg in ("props", "characters", "gear", "fx"):
        d = os.path.join(HERE, pkg)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".py") and not fn.startswith("_"):
                mod = importlib.import_module("%s.%s" % (pkg, fn[:-3]))
                assets.extend(getattr(mod, "ASSETS", []))
                if hasattr(mod, "assets"):
                    assets.extend(mod.assets())
    ids = [a["id"] for a in assets]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        raise SystemExit("duplicate asset ids: %s" % sorted(dup))
    return assets


def main():
    assets = collect()
    if cli.flag("--list"):
        for a in assets:
            print("ASSET", a["category"], a["id"])
        return
    only = cli.opt("--only")
    if only:
        want = set(only.split(","))
        missing = want - {a["id"] for a in assets}
        if missing:
            raise SystemExit("unknown asset ids: %s" % sorted(missing))
        assets = [a for a in assets if a["id"] in want]
    t0 = time.time()
    failed = []
    for a in assets:
        out = os.path.join(palette.ROOT, "assets", "models", a["category"], a["id"] + ".glb")
        manual = os.path.join(palette.ROOT, "art", "manual", a["id"] + ".blend")
        try:
            if os.path.exists(manual):
                export.export_manual(manual, out, a.get("animations", False))
                print("BUILT", a["id"], "(manual override)")
                continue
            export.reset_scene()
            a["build"]()
            export.export_glb(out, animations=a.get("animations", False))
            print("BUILT", a["id"])
        except Exception:  # keep going, report at the end
            traceback.print_exc()
            failed.append(a["id"])
    print("DONE %d assets in %.1fs, %d failed" % (len(assets), time.time() - t0, len(failed)))
    if failed:
        print("FAILED", ",".join(failed))
        sys.exit(1)


main()
