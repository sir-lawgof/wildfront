"""Wildfront asset pipeline driver (ASSETS.md section 5). Paths to Blender and Godot come from art/tools.json.

  python tools/build_assets.py                 build everything: palette -> Blender -> Godot import -> checks
  python tools/build_assets.py --only a,b      rebuild only these asset ids (then import + checks)
  python tools/build_assets.py check           import + checks only (coverage, naming, budgets)
  python tools/build_assets.py shots ID[,ID] [--sheet] [--anims a,b|all] [--loadout melee:1]
                                               screenshot mode of the asset viewer (opens a window briefly)
  python tools/build_assets.py icons           render inventory icons from the models
  python tools/build_assets.py tools           check that the tool paths work (--version)

Exit code 0 = success.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT_PATH = "res://tools/import/model_post_import.gd"


def tools():
    with open(os.path.join(ROOT, "art", "tools.json"), encoding="utf-8") as f:
        t = json.load(f)
    for k in ("blender", "godot"):
        if not os.path.isfile(t.get(k, "")):
            sys.exit("art/tools.json: '%s' path doesn't exist: %s" % (k, t.get(k)))
    return t


def run(cmd, quiet_filter=None, timeout=900):
    print(">", " ".join('"%s"' % c if " " in c else c for c in cmd), flush=True)
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       timeout=timeout)
    out = (p.stdout or "") + (p.stderr or "")
    for line in out.splitlines():
        if quiet_filter is None or quiet_filter(line):
            print("  " + line)
    return p.returncode, out


def check_tools():
    t = tools()
    for k in ("blender", "godot"):
        code, out = run([t[k], "--version"], quiet_filter=lambda l: bool(l.strip()) and "Color management" not in l)
        if code != 0:
            sys.exit("%s --version failed" % k)
    return t


def blender_build(t, only=None):
    cmd = [t["blender"], "--background", "--factory-startup", "--python-exit-code", "1",
           "--python", os.path.join(ROOT, "art", "blender", "build_all.py"), "--"]
    if only:
        cmd += ["--only", only]
    code, out = run(cmd, quiet_filter=lambda l: l.startswith(("BUILT", "DONE", "FAILED", "Traceback", "  File", "Error"))
                    or "Error" in l)
    if code != 0:
        sys.exit("Blender build failed")


def patch_import_files():
    """Make sure every model's .import uses our post-import script (project defaults only apply to new files)."""
    models = os.path.join(ROOT, "assets", "models")
    for dirpath, _, files in os.walk(models):
        for fn in files:
            if not fn.endswith(".glb.import"):
                continue
            p = os.path.join(dirpath, fn)
            with open(p, encoding="utf-8") as f:
                s = f.read()
            s2 = re.sub(r'^import_script/path=.*$', 'import_script/path="%s"' % SCRIPT_PATH, s, flags=re.M)
            s2 = re.sub(r'^meshes/generate_lods=.*$', 'meshes/generate_lods=false', s2, flags=re.M)
            s2 = re.sub(r'^meshes/ensure_tangents=.*$', 'meshes/ensure_tangents=false', s2, flags=re.M)
            if s2 != s:
                with open(p, "w", encoding="utf-8", newline="\n") as f:
                    f.write(s2)


def godot_import(t):
    patch_import_files()
    code, out = run([t["godot"], "--headless", "--path", ROOT, "--import"],
                    quiet_filter=lambda l: "[assets]" in l or "SCRIPT ERROR" in l or "Parse Error" in l)
    patch_import_files()  # files seen for the first time got their .import now: patch and import again
    code, out = run([t["godot"], "--headless", "--path", ROOT, "--import"],
                    quiet_filter=lambda l: "[assets]" in l or "SCRIPT ERROR" in l or "Parse Error" in l)
    if code != 0:
        sys.exit("Godot import failed")


def godot_check(t):
    code, out = run([t["godot"], "--headless", "--path", ROOT, "--script", "res://tools/dev/check_assets.gd"],
                    quiet_filter=lambda l: l.startswith(("CHECK", "FAIL", "OK", "WARN")) or "SCRIPT ERROR" in l)
    if code != 0:
        sys.exit("Asset check failed")


def shots(t, ids, extra=None):
    os.makedirs(os.path.join(ROOT, "art", "previews"), exist_ok=True)
    cmd = [t["godot"], "--path", ROOT, "res://tools/dev/asset_viewer.tscn", "--", "--shots", ",".join(ids)]
    cmd += extra or []
    code, out = run(cmd, quiet_filter=lambda l: l.startswith(("SHOT", "ERROR", "FAIL")) or "SCRIPT ERROR" in l)
    if code != 0:
        sys.exit("Screenshot mode failed")


def main():
    a = sys.argv[1:]
    if a and a[0] == "tools":
        check_tools()
        return
    t = tools()
    if a and a[0] == "check":
        godot_import(t)
        godot_check(t)
        return
    if a and a[0] == "shots":
        # shots <id,id,...> [viewer options passed through, e.g. --sheet --anims walk,run --loadout melee:1]
        shots(t, a[1].split(",") if len(a) > 1 else ["base_body"], a[2:])
        return
    if a and a[0] == "icons":
        code, out = run([t["godot"], "--path", ROOT, "res://tools/dev/asset_viewer.tscn", "--", "--icons"],
                        quiet_filter=lambda l: l.startswith(("ICON", "ERROR")) or "SCRIPT ERROR" in l)
        sys.exit(code)
    only = None
    if "--only" in a:
        only = a[a.index("--only") + 1]
    run([sys.executable, os.path.join(ROOT, "art", "palette", "make_palette.py")])
    code, _ = run([t["godot"], "--headless", "--path", ROOT, "--script", "res://tools/dev/gen_gear_visuals.gd"],
                  quiet_filter=lambda l: l.startswith(("VISUALS", "MISSING")) or "SCRIPT ERROR" in l, timeout=120)
    if code != 0:
        sys.exit("gear_visuals.json generation failed")
    blender_build(t, only)
    godot_import(t)
    godot_check(t)
    print("assets: OK")


if __name__ == "__main__":
    main()
