"""Command-line args for scripts run as: blender --background --python build_all.py -- [args]."""
import sys


def args():
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def opt(name, default=None):
    a = args()
    if name in a:
        i = a.index(name)
        if i + 1 < len(a):
            return a[i + 1]
    return default


def flag(name):
    return name in args()
