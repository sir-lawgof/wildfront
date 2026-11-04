"""Animation clips built from the pose library (ASSETS.md section 9).

Each clip: name, length (s), keys [(time_s, pose, ease)], impact (s, attacks/casts/eat only), loop.
'ease' says how the motion arrives INTO that key: linear | in | out | inout | const.
Looping clips get a -loop suffix in the exported name (Godot loops them and strips the suffix).

WEAPON_SETS maps every weapon type / unique weapon to its stance, attack clip and special-attack clip.
The build writes both tables to data/art/anim_sets.json, which the game reads (impact times included).
"""
from .poses import (ARMS, IDLE_IN, IDLE_OUT, RELAXED, RUN_CONTACT, RUN_PASS, STANCES, WALK_CONTACT, WALK_PASS, P,
                    add, merge, mirror, only, without)

FIGHT_LEGS = P(thigh_L=(-10, -3, 0), shin_L=(10, 0, 0), foot_L=(0, 0, 0),
               thigh_R=(10, 3, 0), shin_R=(8, 0, 0), foot_R=(-6, 0, 0), loc=(0, 0, -0.015))

LEGS_BONES = ["thigh", "shin", "foot", "loc"]
ARM_BONES = ["upperarm", "forearm", "hand"]


class Clip:
    def __init__(self, name, length, keys, impact=None, loop=False, extra_impacts=None):
        self.name = name
        self.length = length
        self.keys = keys
        self.impact = impact
        self.loop = loop
        self.extra_impacts = extra_impacts or []

    @property
    def export_name(self):
        return self.name + "-loop" if self.loop else self.name


def stance_pose(stance):
    return merge(RELAXED, ARMS[stance])


def fight(stance, *overrides):
    return merge(stance_pose(stance), FIGHT_LEGS, *overrides)


# --------------------------------------------------------------------------- locomotion
def _suffix(stance):
    return "" if stance == "unarmed" else "_" + stance


def idle(stance):
    base = stance_pose(stance)
    return Clip("idle" + _suffix(stance), 2.4, [
        (0.0, add(base, IDLE_OUT), "inout"),
        (1.2, add(base, IDLE_IN), "inout"),
        (2.4, add(base, IDLE_OUT), "inout"),
    ], loop=True)


def _loco_keys(contact, passing, stance, length, arm_sway):
    keys = []
    frames = [(0.0, contact), (0.25, passing), (0.5, mirror(contact)), (0.75, mirror(passing)), (1.0, contact)]
    for i, (f, pose) in enumerate(frames):
        p = merge(RELAXED, pose)
        if stance != "unarmed":
            arms = dict(ARMS[stance])
            sway = arm_sway if i % 2 == 0 else 0.0
            sgn = 1.0 if i in (0, 4) else -1.0
            # right arm keeps its weapon pose with a little bob; a free left arm still swings with the stride
            arms["upperarm_R"] = tuple(a + b for a, b in zip(arms["upperarm_R"], (sgn * sway * 0.25, 0, 0)))
            if stance in ("1h", "bow", "staff", "throw"):
                arms["upperarm_L"] = pose.get("upperarm_L", arms.get("upperarm_L"))
                if f in (0.0, 0.5, 1.0):
                    arms["forearm_L"] = pose.get("forearm_L", arms.get("forearm_L"))
            p = merge(p, arms)
        keys.append((f * length, p, "inout"))
    return keys


def walk(stance):
    return Clip("walk" + _suffix(stance), 1.0, _loco_keys(WALK_CONTACT, WALK_PASS, stance, 1.0, 10.0), loop=True)


def run(stance):
    return Clip("run" + _suffix(stance), 0.8, _loco_keys(RUN_CONTACT, RUN_PASS, stance, 0.8, 16.0), loop=True)


# Distance covered by one full cycle, used to match playback to tile speed (1 tile/tick walk, 2 tiles/tick run).
CYCLE_TILES = {"walk": 1.2, "run": 2.0}


# --------------------------------------------------------------------------- general
def general():
    s = stance_pose("unarmed")
    eat_hand = P(upperarm_L=(-42, 34, 0), forearm_L=(-118, 0, 0), hand_L=(0, 0, 0))
    drink_hand = P(upperarm_L=(-62, 30, 0), forearm_L=(-128, 0, 0), hand_L=(20, 0, 0))
    block = P(upperarm_L=(-72, 28, 0), forearm_L=(-72, 0, 0), hand_L=(0, 0, 0), spine=(-6, 0, 8), loc=(0, 0.03, -0.02))
    death_a = P(thigh_L=(-22, 0, 0), shin_L=(42, 0, 0), thigh_R=(-18, 0, 0), shin_R=(38, 0, 0), spine=(16, 0, 0),
                head=(12, 0, 0), upperarm_L=(10, -10, 0), upperarm_R=(10, 10, 0), loc=(0, 0, -0.12))
    death_b = P(root=(-86, 0, 0), thigh_L=(-14, -4, 0), shin_L=(20, 0, 0), thigh_R=(-6, 6, 0), shin_R=(14, 0, 0),
                spine=(-6, 0, 0), head=(-10, 0, 10), upperarm_L=(-30, -70, 0), forearm_L=(-20, 0, 0),
                upperarm_R=(-20, 66, 0), forearm_R=(-30, 0, 0), loc=(0, 0, -0.04))
    death_c = merge(death_b, P(root=(-90, 0, 0), head=(-14, 0, 12)))
    crouch = P(thigh_L=(-72, -4, 0), shin_L=(112, 0, 0), foot_L=(-40, 0, 0), thigh_R=(-72, 4, 0), shin_R=(112, 0, 0),
               foot_R=(-40, 0, 0), spine=(30, 0, 0), head=(-22, 0, 0), upperarm_L=(-20, -10, 0),
               upperarm_R=(-20, 10, 0), loc=(0, 0.06, -0.30))
    spread = P(upperarm_L=(-20, -55, 0), forearm_L=(-20, 0, 0), upperarm_R=(-20, 55, 0), forearm_R=(-20, 0, 0),
               head=(-10, 0, 0), chest=(-6, 0, 0))
    pray = P(upperarm_L=(-34, 26, 0), forearm_L=(-86, 0, 0), upperarm_R=(-34, -26, 0), forearm_R=(-86, 0, 0),
             head=(16, 0, 0), spine=(4, 0, 0))
    return [
        Clip("eat", 0.9, [(0.0, s, "inout"), (0.3, merge(s, eat_hand, P(head=(8, 0, 0))), "out"),
                          (0.45, merge(s, eat_hand, P(head=(16, 0, 0))), "inout"),
                          (0.6, merge(s, eat_hand, P(head=(6, 0, 0))), "inout"), (0.9, s, "inout")], impact=0.45),
        Clip("drink", 0.9, [(0.0, s, "inout"), (0.3, merge(s, drink_hand, P(head=(-20, 0, 0), spine=(-6, 0, 0))), "out"),
                            (0.6, merge(s, drink_hand, P(head=(-24, 0, 0), spine=(-6, 0, 0))), "inout"),
                            (0.9, s, "inout")], impact=0.45),
        Clip("block", 0.6, [(0.0, s, "inout"), (0.15, merge(s, block), "out"), (0.35, merge(s, block), "inout"),
                            (0.6, s, "inout")], impact=0.15),
        Clip("hit_react", 0.45, [(0.0, s, "inout"),
                                 (0.1, merge(s, P(spine=(-10, 0, 0), chest=(-6, 0, 0), head=(-12, 0, 0),
                                                  loc=(0, 0.04, -0.01))), "out"),
                                 (0.45, s, "inout")]),
        Clip("death", 1.3, [(0.0, s, "inout"), (0.25, merge(s, death_a), "out"), (1.0, death_b, "in"),
                            (1.15, death_c, "out"), (1.3, death_b, "inout")]),
        Clip("spawn", 0.9, [(0.0, merge(s, crouch), "const"), (0.45, merge(s, spread), "out"), (0.9, s, "inout")]),
        Clip("pray_toggle", 0.5, [(0.0, s, "inout"), (0.2, merge(s, pray), "out"), (0.32, merge(s, pray), "inout"),
                                  (0.5, s, "inout")]),
    ]


# --------------------------------------------------------------------------- attacks
def attacks():
    c = []
    # Stab: pull back, thrust forward (weapon pitch 0 = forward)
    st = "1h"
    pull = P(upperarm_R=(24, 14, 0), forearm_R=(-96, 0, 0), hand_R=(72, 0, 0), spine=(0, 0, -14), chest=(0, 0, -6))
    thrust = P(upperarm_R=(-80, 4, 0), forearm_R=(-4, 0, 0), hand_R=(84, 0, 0), spine=(8, 0, 12), chest=(4, 0, 6),
               thigh_L=(-30, -3, 0), shin_L=(32, 0, 0), thigh_R=(18, 3, 0), loc=(0, -0.04, -0.05))
    c.append(Clip("attack_stab", 0.7, [(0.0, fight(st), "inout"), (0.2, fight(st, pull), "out"),
                                       (0.36, fight(st, thrust), "linear"), (0.48, fight(st, thrust), "inout"),
                                       (0.7, fight(st), "inout")], impact=0.36))
    # Slash: wind up high on the right, sweep across to the left
    up = P(upperarm_R=(-128, 42, 0), forearm_R=(-40, 0, 0), hand_R=(30, 0, 30), spine=(0, 0, -22), chest=(0, 0, -10))
    hit = P(upperarm_R=(-76, -26, 0), forearm_R=(-20, 0, 0), hand_R=(62, 0, -40), spine=(4, 0, 20), chest=(2, 0, 10),
            thigh_L=(-22, -3, 0), shin_L=(24, 0, 0))
    through = P(upperarm_R=(-56, -40, 0), forearm_R=(-30, 0, 0), hand_R=(62, 0, -40), spine=(4, 0, 28), chest=(2, 0, 12))
    c.append(Clip("attack_slash", 0.75, [(0.0, fight(st), "inout"), (0.22, fight(st, up), "out"),
                                         (0.34, fight(st, hit), "linear"), (0.45, fight(st, through), "out"),
                                         (0.75, fight(st), "inout")], impact=0.34))
    # Crush: overhead and down
    raise_ = P(upperarm_R=(-165, 10, 0), forearm_R=(-45, 0, 0), hand_R=(20, 0, 0), spine=(-10, 0, -6), loc=(0, 0, 0.01))
    smash = P(upperarm_R=(-58, 4, 0), forearm_R=(-10, 0, 0), hand_R=(88, 0, 0), spine=(18, 0, 4), chest=(8, 0, 0),
              thigh_L=(-24, -3, 0), shin_L=(30, 0, 0), shin_R=(20, 0, 0), loc=(0, -0.02, -0.07))
    c.append(Clip("attack_crush", 0.85, [(0.0, fight(st), "inout"), (0.25, fight(st, raise_), "out"),
                                         (0.42, fight(st, smash), "in"), (0.56, fight(st, smash), "inout"),
                                         (0.85, fight(st), "inout")], impact=0.42))
    # Whip: quick flick
    cock = P(upperarm_R=(-112, 30, 0), forearm_R=(-82, 0, 0), hand_R=(0, 0, 0), spine=(0, 0, -10))
    snap = P(upperarm_R=(-72, 0, 0), forearm_R=(0, 0, 0), hand_R=(62, 0, 0), spine=(4, 0, 10))
    c.append(Clip("attack_whip", 0.6, [(0.0, fight(st), "inout"), (0.15, fight(st, cock), "out"),
                                       (0.3, fight(st, snap), "linear"), (0.38, fight(st, snap), "inout"),
                                       (0.6, fight(st), "inout")], impact=0.3))
    # Two-handed: both arms over the right shoulder, big downward cut
    st2 = "2h"
    up2 = P(upperarm_R=(-150, 30, 0), forearm_R=(-40, 0, 0), hand_R=(30, 0, 0), upperarm_L=(-140, 40, 0),
            forearm_L=(-50, 0, 0), spine=(-8, 0, -25), chest=(0, 0, -8))
    cut2 = P(upperarm_R=(-62, -8, 0), forearm_R=(-10, 0, 0), hand_R=(72, 0, 0), upperarm_L=(-60, 12, 0),
             forearm_L=(-20, 0, 0), spine=(20, 0, 14), chest=(6, 0, 4), thigh_L=(-30, -3, 0), shin_L=(36, 0, 0),
             loc=(0, -0.03, -0.08))
    c.append(Clip("attack_2h", 1.0, [(0.0, fight(st2), "inout"), (0.3, fight(st2, up2), "out"),
                                     (0.5, fight(st2, cut2), "in"), (0.66, fight(st2, cut2), "inout"),
                                     (1.0, fight(st2), "inout")], impact=0.5))
    # Bow: right arm holds the bow out in front, left hand draws to the chin and releases
    sb = "bow"
    aim = P(upperarm_R=(-88, 6, 0), forearm_R=(0, 0, 0), hand_R=(88, 0, 0), upperarm_L=(-86, 32, 0),
            forearm_L=(-10, 0, 0), spine=(0, 0, 8), head=(4, 0, 0))
    draw = merge(aim, P(upperarm_L=(-78, 14, 0), forearm_L=(-122, 0, 0)))
    loose = merge(aim, P(upperarm_L=(-70, 4, 0), forearm_L=(-142, 0, 0), spine=(-3, 0, 8)))
    c.append(Clip("shoot_bow", 0.8, [(0.0, fight(sb), "inout"), (0.18, fight(sb, aim), "out"),
                                     (0.4, fight(sb, draw), "inout"), (0.45, fight(sb, loose), "linear"),
                                     (0.6, fight(sb, loose), "inout"), (0.8, fight(sb), "inout")], impact=0.45))
    # Crossbow: shoulder, fire, recoil
    sx = "xbow"
    shoulder = P(upperarm_R=(-82, 6, 0), forearm_R=(-8, 0, 0), hand_R=(90, 0, 0), upperarm_L=(-76, 32, 0),
                 forearm_L=(-40, 0, 0), head=(8, 0, 0))
    recoil = merge(shoulder, P(upperarm_R=(-92, 6, 0), upperarm_L=(-84, 32, 0), spine=(-6, 0, 0), loc=(0, 0.03, 0)))
    c.append(Clip("shoot_crossbow", 0.7, [(0.0, fight(sx), "inout"), (0.2, fight(sx, shoulder), "out"),
                                          (0.33, fight(sx, shoulder), "inout"), (0.36, fight(sx, recoil), "linear"),
                                          (0.7, fight(sx), "inout")], impact=0.35))
    # Throw: overhand
    sth = "throw"
    back = P(upperarm_R=(-150, 22, 0), forearm_R=(-60, 0, 0), hand_R=(30, 0, 0), upperarm_L=(-60, -8, 0),
             spine=(-8, 0, -15))
    release = P(upperarm_R=(-70, 0, 0), forearm_R=(-5, 0, 0), hand_R=(60, 0, 0), upperarm_L=(10, -8, 0),
                spine=(10, 0, 15), thigh_L=(-24, -3, 0), shin_L=(26, 0, 0))
    c.append(Clip("throw", 0.7, [(0.0, fight(sth), "inout"), (0.2, fight(sth, back), "out"),
                                 (0.34, fight(sth, release), "linear"), (0.45, fight(sth, release), "inout"),
                                 (0.7, fight(sth), "inout")], impact=0.34))
    # Casting: gather at the chest, thrust the free hand forward
    sm = "staff"
    gather = P(upperarm_L=(-30, 22, 0), forearm_L=(-112, 0, 0), upperarm_R=(-40, 8, 0), forearm_R=(-60, 0, 0),
               hand_R=(60, 0, 0), spine=(-4, 0, -6))
    push = P(upperarm_L=(-88, 8, 0), forearm_L=(0, 0, 0), hand_L=(-10, 0, 0), upperarm_R=(-30, 8, 0),
             forearm_R=(-60, 0, 0), hand_R=(50, 0, 0), spine=(6, 0, 8))
    c.append(Clip("cast_projectile", 0.8, [(0.0, fight(sm), "inout"), (0.25, fight(sm, gather), "out"),
                                           (0.42, fight(sm, push), "linear"), (0.55, fight(sm, push), "inout"),
                                           (0.8, fight(sm), "inout")], impact=0.42))
    arms_up = P(upperarm_L=(-160, -10, 0), forearm_L=(-20, 0, 0), upperarm_R=(-160, 10, 0), forearm_R=(-20, 0, 0),
                hand_R=(20, 0, 0), head=(-15, 0, 0), chest=(-6, 0, 0))
    slam = P(upperarm_L=(-62, 6, 0), forearm_L=(-10, 0, 0), upperarm_R=(-62, -6, 0), forearm_R=(-10, 0, 0),
             hand_R=(70, 0, 0), spine=(20, 0, 0), thigh_L=(-26, -3, 0), shin_L=(40, 0, 0), shin_R=(30, 0, 0),
             loc=(0, 0, -0.08))
    c.append(Clip("cast_area", 1.0, [(0.0, fight(sm), "inout"), (0.35, fight(sm, arms_up), "out"),
                                     (0.55, fight(sm, slam), "in"), (0.7, fight(sm, slam), "inout"),
                                     (1.0, fight(sm), "inout")], impact=0.55))
    return c


def _spin_keys(stance, t0, t1, pose, turns=1.0, steps=4):
    """Keys that spin the whole body around (root z) while holding a pose."""
    keys = []
    n = int(steps * turns)
    for i in range(1, n + 1):
        t = t0 + (t1 - t0) * i / n
        keys.append((t, fight(stance, pose, P(root=(0, 0, -360.0 * turns * i / n))), "linear"))
    return keys


def specials():
    """One spec_<weapon> clip per weapon with a special attack, built from the attack poses."""
    c = []
    a = {x.name: x for x in attacks()}

    def key_pose(clip, i):
        return a[clip].keys[i][1]

    st, s2, sb, sx, sth, sm = "1h", "2h", "bow", "xbow", "throw", "staff"
    stab_pull, stab_hit = key_pose("attack_stab", 1), key_pose("attack_stab", 2)
    slash_up, slash_hit, slash_thru = key_pose("attack_slash", 1), key_pose("attack_slash", 2), key_pose("attack_slash", 3)
    crush_up, crush_hit = key_pose("attack_crush", 1), key_pose("attack_crush", 2)
    up2, cut2 = key_pose("attack_2h", 1), key_pose("attack_2h", 2)
    aim, draw, loose = key_pose("shoot_bow", 1), key_pose("shoot_bow", 2), key_pose("shoot_bow", 3)
    shoulder, recoil = key_pose("shoot_crossbow", 1), key_pose("shoot_crossbow", 3)
    t_back, t_rel = key_pose("throw", 1), key_pose("throw", 2)
    gather, push = key_pose("cast_projectile", 1), key_pose("cast_projectile", 2)
    arms_up, slam = key_pose("cast_area", 1), key_pose("cast_area", 2)
    jump = P(loc=(0, -0.05, 0.28), thigh_L=(-40, 0, 0), shin_L=(70, 0, 0), thigh_R=(-30, 0, 0), shin_R=(80, 0, 0))
    kneel = P(thigh_L=(-80, -4, 0), shin_L=(84, 0, 0), foot_L=(-4, 0, 0), thigh_R=(30, 4, 0), shin_R=(110, 0, 0),
              foot_R=(40, 0, 0), loc=(0, 0.06, -0.24))
    roar = P(upperarm_L=(-150, -30, 0), upperarm_R=(-150, 30, 0), forearm_L=(-20, 0, 0), forearm_R=(-20, 0, 0),
             spine=(-12, 0, 0), chest=(-8, 0, 0), head=(-25, 0, 0))
    sky = P(upperarm_R=(-160, 10, 0), forearm_R=(-10, 0, 0), hand_R=(0, 0, 0), head=(-25, 0, 0), chest=(-8, 0, 0))

    # dagger: two quick stabs
    c.append(Clip("spec_dagger", 0.9, [(0.0, fight(st), "inout"), (0.14, stab_pull, "out"), (0.3, stab_hit, "linear"),
                                        (0.42, stab_pull, "inout"), (0.55, merge(stab_hit, P(spine=(8, 0, 20))), "linear"),
                                        (0.68, stab_hit, "inout"), (0.9, fight(st), "inout")],
                  impact=0.3, extra_impacts=[0.55]))
    # scimitar: spinning slash
    c.append(Clip("spec_scimitar", 0.95, [(0.0, fight(st), "inout"), (0.12, slash_up, "out")]
                  + _spin_keys(st, 0.12, 0.48, without(slash_hit, ["root"]))
                  + [(0.62, slash_thru, "out"), (0.95, fight(st), "inout")], impact=0.48))
    # longsword: leaping slash
    c.append(Clip("spec_longsword", 1.0, [(0.0, fight(st), "inout"), (0.25, merge(slash_up, jump), "out"),
                                           (0.5, slash_hit, "in"), (0.62, slash_thru, "out"), (1.0, fight(st), "inout")],
                  impact=0.5))
    # battleaxe: roar, then chop
    c.append(Clip("spec_battleaxe", 1.15, [(0.0, fight(st), "inout"), (0.35, fight(st, roar), "out"),
                                            (0.5, fight(st, roar), "inout"), (0.62, crush_up, "out"),
                                            (0.78, crush_hit, "in"), (0.9, crush_hit, "inout"), (1.15, fight(st), "inout")],
                  impact=0.78))
    # warhammer: jumping overhead smash
    c.append(Clip("spec_warhammer", 1.0, [(0.0, fight(st), "inout"), (0.3, merge(crush_up, jump), "out"),
                                           (0.55, merge(crush_hit, P(loc=(0, -0.04, -0.1))), "in"),
                                           (0.7, crush_hit, "inout"), (1.0, fight(st), "inout")], impact=0.55))
    # bows: two arrows in quick succession
    for name in ("spec_shortbow", "spec_longbow"):
        c.append(Clip(name, 0.95, [(0.0, fight(sb), "inout"), (0.15, aim, "out"), (0.3, draw, "inout"),
                                    (0.34, loose, "linear"), (0.5, draw, "inout"), (0.56, loose, "linear"),
                                    (0.72, loose, "inout"), (0.95, fight(sb), "inout")],
                      impact=0.34, extra_impacts=[0.56]))
    # crossbow: kneel and fire a pinning bolt
    c.append(Clip("spec_crossbow", 0.95, [(0.0, fight(sx), "inout"), (0.25, merge(shoulder, kneel), "out"),
                                           (0.45, merge(shoulder, kneel), "inout"), (0.48, merge(recoil, kneel), "linear"),
                                           (0.7, merge(shoulder, kneel), "inout"), (0.95, fight(sx), "inout")], impact=0.48))
    # throwing knives: wide fanning throw
    fan = merge(t_rel, P(upperarm_R=(-75, -40, 0), spine=(10, 0, 30)))
    c.append(Clip("spec_throwing_knives", 0.8, [(0.0, fight(sth), "inout"), (0.2, merge(t_back, P(spine=(-8, 0, -30))), "out"),
                                                 (0.36, fan, "linear"), (0.5, fan, "inout"), (0.8, fight(sth), "inout")],
                  impact=0.36))
    # whip: overhead circle then snap
    whirl = P(upperarm_R=(-170, 10, 0), forearm_R=(-20, 0, 0), hand_R=(0, 0, 0))
    c.append(Clip("spec_whip", 0.9, [(0.0, fight(st), "inout"), (0.2, fight(st, whirl), "out"),
                                      (0.35, fight(st, merge(whirl, P(upperarm_R=(-150, 50, 0)))), "linear"),
                                      (0.55, key_pose("attack_whip", 2), "linear"),
                                      (0.65, key_pose("attack_whip", 2), "inout"), (0.9, fight(st), "inout")], impact=0.55))
    # stone maul: instant, fast heavy crush
    c.append(Clip("spec_stone_maul", 0.6, [(0.0, fight(s2), "inout"), (0.12, up2, "out"), (0.25, cut2, "in"),
                                            (0.38, cut2, "inout"), (0.6, fight(s2), "inout")], impact=0.25))
    # greatblade: big leap with a two-handed cut
    c.append(Clip("spec_greatblade", 1.2, [(0.0, fight(s2), "inout"), (0.35, merge(up2, jump), "out"),
                                            (0.6, merge(cut2, P(loc=(0, -0.06, -0.12))), "in"), (0.78, cut2, "inout"),
                                            (1.2, fight(s2), "inout")], impact=0.6))
    # claws: four alternating slashes
    l_hit = P(upperarm_L=(-70, 26, 0), forearm_L=(-20, 0, 0), spine=(4, 0, -16))
    r_hit = P(upperarm_R=(-70, -26, 0), forearm_R=(-20, 0, 0), spine=(4, 0, 16))
    c.append(Clip("spec_claws", 1.0, [(0.0, fight(st), "inout"), (0.12, fight(st, P(spine=(0, 0, -10))), "out"),
                                       (0.25, fight(st, r_hit), "linear"), (0.4, fight(st, l_hit), "linear"),
                                       (0.55, fight(st, r_hit), "linear"), (0.7, fight(st, l_hit), "linear"),
                                       (1.0, fight(st), "inout")], impact=0.25, extra_impacts=[0.4, 0.55, 0.7]))
    # void blade: spinning thrust
    c.append(Clip("spec_void_blade", 0.95, [(0.0, fight(st), "inout"), (0.15, stab_pull, "out")]
                  + _spin_keys(st, 0.15, 0.4, without(stab_pull, ["root"]), turns=1.0)
                  + [(0.48, stab_hit, "linear"), (0.62, stab_hit, "inout"), (0.95, fight(st), "inout")], impact=0.48))
    # javelins: run-up throw
    c.append(Clip("spec_javelins", 0.9, [(0.0, fight(sth), "inout"),
                                          (0.25, merge(t_back, P(thigh_L=(-30, 0, 0), shin_L=(40, 0, 0), loc=(0, 0.04, 0.04))), "out"),
                                          (0.45, merge(t_rel, P(loc=(0, -0.08, -0.04))), "linear"),
                                          (0.6, t_rel, "inout"), (0.9, fight(sth), "inout")], impact=0.45))
    # duskbow: draw toward the sky and loose a volley
    sky_draw = merge(draw, P(upperarm_R=(-120, 6, 0), upperarm_L=(-110, 14, 0), head=(-14, 0, 0), spine=(-10, 0, 8)))
    sky_loose = merge(loose, P(upperarm_R=(-120, 6, 0), upperarm_L=(-100, 4, 0), head=(-14, 0, 0), spine=(-12, 0, 8)))
    c.append(Clip("spec_duskbow", 1.0, [(0.0, fight(sb), "inout"), (0.25, merge(aim, P(upperarm_R=(-120, 6, 0))), "out"),
                                         (0.5, sky_draw, "inout"), (0.55, sky_loose, "linear"), (0.75, sky_loose, "inout"),
                                         (1.0, fight(sb), "inout")], impact=0.55))
    # heavy ballista: kneel, brace, heavy recoil
    heavy_recoil = merge(recoil, kneel, P(spine=(-14, 0, 0), loc=(0, 0.1, -0.24)))
    c.append(Clip("spec_heavy_ballista", 1.0, [(0.0, fight(sx), "inout"), (0.3, merge(shoulder, kneel), "out"),
                                                (0.48, merge(shoulder, kneel), "inout"), (0.5, heavy_recoil, "linear"),
                                                (0.75, merge(shoulder, kneel), "inout"), (1.0, fight(sx), "inout")], impact=0.5))
    # sunfire crossbow: raise high, fire downward
    high = merge(shoulder, P(upperarm_R=(-110, 6, 0), upperarm_L=(-100, 32, 0), head=(-8, 0, 0)))
    c.append(Clip("spec_sunfire_crossbow", 0.85, [(0.0, fight(sx), "inout"), (0.25, high, "out"),
                                                   (0.4, merge(high, P(upperarm_R=(-118, 6, 0), loc=(0, 0.04, 0))), "linear"),
                                                   (0.55, high, "inout"), (0.85, fight(sx), "inout")], impact=0.4))
    # eruption staff: staff raised, slammed into the ground
    c.append(Clip("spec_eruption_staff", 1.1, [(0.0, fight(sm), "inout"), (0.35, fight(sm, sky), "out"),
                                                (0.55, fight(sm, slam, P(upperarm_R=(-40, 8, 0), forearm_R=(-30, 0, 0), hand_R=(80, 0, 0))), "in"),
                                                (0.75, fight(sm, slam), "inout"), (1.1, fight(sm), "inout")], impact=0.55))
    # tempest staff: staff to the sky, then point at the target
    point = merge(push, P(upperarm_R=(-85, 8, 0), forearm_R=(0, 0, 0), hand_R=(90, 0, 0)))
    c.append(Clip("spec_tempest_staff", 1.0, [(0.0, fight(sm), "inout"), (0.3, fight(sm, sky), "out"),
                                               (0.45, fight(sm, sky, P(upperarm_L=(-150, -20, 0))), "inout"),
                                               (0.55, fight(sm, point), "linear"), (0.72, fight(sm, point), "inout"),
                                               (1.0, fight(sm), "inout")], impact=0.55))
    return c


def all_clips():
    out = []
    for s in STANCES:
        out += [idle(s), walk(s), run(s)]
    return out + general() + attacks() + specials()


# --------------------------------------------------------------------------- weapon sets
# key: item id (uniques) or weapon_type (tiered). "attack" may differ per item; "cast" picks spells.
WEAPON_SETS = {
    "unarmed":          {"stance": "unarmed", "attack": "attack_stab"},
    "dagger":           {"stance": "1h", "attack": "attack_stab", "spec": "spec_dagger"},
    "scimitar":         {"stance": "1h", "attack": "attack_slash", "spec": "spec_scimitar"},
    "longsword":        {"stance": "1h", "attack": "attack_slash", "spec": "spec_longsword"},
    "battleaxe":        {"stance": "1h", "attack": "attack_slash", "spec": "spec_battleaxe"},
    "warhammer":        {"stance": "1h", "attack": "attack_crush", "spec": "spec_warhammer"},
    "shortbow":         {"stance": "bow", "attack": "shoot_bow", "spec": "spec_shortbow"},
    "longbow":          {"stance": "bow", "attack": "shoot_bow", "spec": "spec_longbow"},
    "crossbow":         {"stance": "xbow", "attack": "shoot_crossbow", "spec": "spec_crossbow"},
    "throwing_knives":  {"stance": "throw", "attack": "throw", "spec": "spec_throwing_knives"},
    "staff":            {"stance": "staff", "attack": "cast_projectile"},
    "wand":             {"stance": "1h", "attack": "cast_projectile"},
    "whip":             {"stance": "1h", "attack": "attack_whip", "spec": "spec_whip"},
    "stone_maul":       {"stance": "2h", "attack": "attack_2h", "spec": "spec_stone_maul"},
    "greatblade":       {"stance": "2h", "attack": "attack_2h", "spec": "spec_greatblade"},
    "claws":            {"stance": "1h", "attack": "attack_slash", "spec": "spec_claws"},
    "void_blade":       {"stance": "1h", "attack": "attack_stab", "spec": "spec_void_blade"},
    "javelins":         {"stance": "throw", "attack": "throw", "spec": "spec_javelins"},
    "duskbow":          {"stance": "bow", "attack": "shoot_bow", "spec": "spec_duskbow"},
    "heavy_ballista":   {"stance": "xbow", "attack": "shoot_crossbow", "spec": "spec_heavy_ballista"},
    "sunfire_crossbow": {"stance": "xbow", "attack": "shoot_crossbow", "spec": "spec_sunfire_crossbow"},
    "forbidden_staff":  {"stance": "staff", "attack": "cast_projectile"},
    "eruption_staff":   {"stance": "staff", "attack": "cast_projectile", "spec": "spec_eruption_staff"},
    "tempest_staff":    {"stance": "staff", "attack": "cast_projectile", "spec": "spec_tempest_staff"},
}


def anim_sets_json():
    clips = {c.name: c for c in all_clips()}
    sets = {}
    for k, v in WEAPON_SETS.items():
        s = _suffix(v["stance"])
        entry = {"stance": v["stance"], "idle": "idle" + s, "walk": "walk" + s, "run": "run" + s,
                 "attack": {"clip": v["attack"], "impact": clips[v["attack"]].impact}}
        if "spec" in v:
            entry["spec"] = {"clip": v["spec"], "impact": clips[v["spec"]].impact}
        sets[k] = entry
    return {
        "_doc": "GENERATED by art/blender/anims/clips.py (edit there, then rebuild). Weapon set -> stance, locomotion "
                "and attack clips. 'impact' = seconds from clip start to the hit / release / bite frame; the client "
                "lines it up with the server tick. cycle_tiles = tiles covered by one walk/run cycle.",
        "cycle_tiles": CYCLE_TILES,
        "casts": {"projectile": {"clip": "cast_projectile", "impact": clips["cast_projectile"].impact},
                  "area": {"clip": "cast_area", "impact": clips["cast_area"].impact}},
        "general": {n: {"clip": n, "length": clips[n].length, "impact": clips[n].impact}
                    for n in ("eat", "drink", "block", "hit_react", "death", "spawn", "pray_toggle")},
        "required": sorted(clips.keys()),
        "clips": {n: {"length": c.length, "impact": c.impact, "loop": c.loop,
                      **({"extra_impacts": c.extra_impacts} if c.extra_impacts else {})}
                  for n, c in sorted(clips.items())},
        "sets": sets,
    }
