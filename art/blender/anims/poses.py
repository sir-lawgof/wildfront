"""Pose library (ASSETS.md section 9). A pose is a dict: bone -> (x, y, z) rotation in degrees, plus an optional
"loc": (x, y, z) offset of the hips in tiles.

Rotations are about the WORLD axes at the bone's head, applied on top of the parent's pose (so a forearm angle
is relative to its upper arm). Blender axes: X = character's left, -Y = forward, Z = up.

  x+  tips the front down. Upright bones (spine, chest, head) lean forward / nod.
      Hanging bones (arms, thighs, shins) swing BACKWARD, so raising an arm forward is NEGATIVE x,
      bending an elbow is negative x on the forearm, a knee bend is positive x on the shin.
      Weapons are modelled pointing forward at rest: the weapon's pitch is the sum of the arm's x angles
      (0 = forward, -90 = up, +90 = down, -180 = back over the shoulder).
  y+  tips the top toward the character's left; hanging bones swing toward the character's RIGHT.
      Left arm out to the side = negative y; right arm out to the side = positive y.
  z+  turns toward the character's left (counter-clockwise seen from above).

Mirror a pose left/right with mirror(): it swaps _L/_R bones and flips y and z.
"""

BONES_ANIMATED = ["root", "hips", "spine", "chest", "neck", "head", "upperarm_L", "forearm_L", "hand_L",
                  "upperarm_R", "forearm_R", "hand_R", "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]


def P(**kw):
    return dict(kw)


def mirror(p):
    out = {}
    for k, v in p.items():
        if k == "loc":
            out[k] = (-v[0], v[1], v[2])
            continue
        nk = k[:-2] + "_R" if k.endswith("_L") else (k[:-2] + "_L" if k.endswith("_R") else k)
        out[nk] = (v[0], -v[1], -v[2])
    return out


def merge(*poses):
    """Later poses override earlier ones bone by bone."""
    out = {}
    for p in poses:
        out.update(p)
    return out


def add(a, b):
    """Sum two poses (b is an offset on top of a)."""
    out = dict(a)
    for k, v in b.items():
        if k in out:
            out[k] = tuple(x + y for x, y in zip(out[k], v))
        else:
            out[k] = v
    return out


def scale(p, k):
    return {b: tuple(c * k for c in v) for b, v in p.items()}


def only(p, prefixes):
    return {b: v for b, v in p.items() if b.startswith(tuple(prefixes))}


def without(p, prefixes):
    return {b: v for b, v in p.items() if not b.startswith(tuple(prefixes))}


# --------------------------------------------------------------------------- base poses
REST = P()

# Relaxed stance: arms a little out, slight elbow bend, weight even.
RELAXED = P(upperarm_L=(2, -6, 0), forearm_L=(-12, 0, 0), upperarm_R=(2, 6, 0), forearm_R=(-12, 0, 0),
            thigh_L=(0, -2, 0), thigh_R=(0, 2, 0), chest=(-1, 0, 0))

# ---- weapon-arm stances (right arm holds the weapon socket; left arm free or helping)
ARMS = {
    "unarmed": only(RELAXED, ["upperarm", "forearm", "hand"]),
    # one-handed melee / wand / whip / claws: weapon angled up-forward in front of the body
    "1h": P(upperarm_R=(-12, 10, 0), forearm_R=(-58, 0, 0), hand_R=(10, 0, -10),
            upperarm_L=(4, -8, 0), forearm_L=(-25, 0, 0)),
    # two-handed melee: blade resting diagonally across the front, both hands near the hilt
    "2h": P(upperarm_R=(-22, 14, 0), forearm_R=(-62, 0, 20), hand_R=(30, 0, -30),
            upperarm_L=(-30, 22, 0), forearm_L=(-60, 0, -20), hand_L=(0, 0, 0)),
    # bow: held low at the side, slightly forward
    "bow": P(upperarm_R=(-6, 8, 0), forearm_R=(-28, 0, 0), hand_R=(10, 0, 0),
             upperarm_L=(2, -6, 0), forearm_L=(-15, 0, 0)),
    # crossbow: held level at the hip, left hand under the stock
    "xbow": P(upperarm_R=(-6, 8, 0), forearm_R=(-70, 0, 0), hand_R=(70, 0, 0),
              upperarm_L=(-20, 18, 0), forearm_L=(-60, 0, 0)),
    # staff: planted upright beside the body
    "staff": P(upperarm_R=(-8, 8, 0), forearm_R=(-48, 0, 0), hand_R=(52, 0, 0),
               upperarm_L=(2, -6, 0), forearm_L=(-15, 0, 0)),
    # thrown weapons (knives, javelins): held ready at shoulder height
    "throw": P(upperarm_R=(-20, 16, 0), forearm_R=(-80, 0, 0), hand_R=(50, 0, 0),
               upperarm_L=(2, -6, 0), forearm_L=(-20, 0, 0)),
}
STANCES = list(ARMS.keys())

# --------------------------------------------------------------------------- locomotion
# Walk: contact (left foot forward) and passing (right leg lifted).
WALK_CONTACT = P(thigh_L=(-24, 0, 0), shin_L=(6, 0, 0), foot_L=(-8, 0, 0),
                 thigh_R=(20, 0, 0), shin_R=(22, 0, 0), foot_R=(12, 0, 0),
                 upperarm_L=(18, -6, 0), forearm_L=(-12, 0, 0), upperarm_R=(-18, 6, 0), forearm_R=(-24, 0, 0),
                 spine=(2, 0, -4), chest=(0, 0, -3), loc=(0, 0, -0.02))
WALK_PASS = P(thigh_L=(2, 0, 0), shin_L=(2, 0, 0), foot_L=(0, 0, 0),
              thigh_R=(-14, 0, 0), shin_R=(48, 0, 0), foot_R=(-10, 0, 0),
              upperarm_L=(2, -6, 0), forearm_L=(-14, 0, 0), upperarm_R=(-2, 6, 0), forearm_R=(-16, 0, 0),
              spine=(2, 0, 0), loc=(0, 0, 0.025))
RUN_CONTACT = P(thigh_L=(-42, 0, 0), shin_L=(18, 0, 0), foot_L=(-12, 0, 0),
                thigh_R=(30, 0, 0), shin_R=(60, 0, 0), foot_R=(20, 0, 0),
                upperarm_L=(36, -8, 0), forearm_L=(-70, 0, 0), upperarm_R=(-36, 8, 0), forearm_R=(-80, 0, 0),
                spine=(12, 0, -8), chest=(2, 0, -5), head=(-10, 0, 8), loc=(0, 0, -0.04))
RUN_PASS = P(thigh_L=(-4, 0, 0), shin_L=(20, 0, 0), foot_L=(0, 0, 0),
             thigh_R=(-30, 0, 0), shin_R=(100, 0, 0), foot_R=(-10, 0, 0),
             upperarm_L=(4, -8, 0), forearm_L=(-75, 0, 0), upperarm_R=(-4, 8, 0), forearm_R=(-75, 0, 0),
             spine=(12, 0, 0), head=(-10, 0, 0), loc=(0, 0, 0.06))

IDLE_IN = P(chest=(-2, 0, 0), head=(1, 0, 0), loc=(0, 0, 0.004))
IDLE_OUT = P(chest=(1, 0, 0), head=(-1, 0, 0), loc=(0, 0, -0.006))
