"""fixPages.py -- runs the HomerDev kit's page finisher on this collection.

The finisher itself lives in the kit, scripts\\fixPages.py beside the rules it applies (scripts\\fixEncoding.py), so
every collection and every Homer build shares one copy (12 October 2026; version 3 of this file was a copy of its own,
and titled a page with no heading "Help guide"). Arguments pass through: --pages finishes the published pages without
rebuilding them from their .md.
"""

import os, subprocess, sys

c_sCollection = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(c_sCollection).lower() == "scripts": c_sCollection = os.path.dirname(c_sCollection)


def kitFinisher():
    """The kit's fixPages.py: the HomerDev variable's kit, C:\\HomerDev, then Program Files, then any drive."""
    lsPlaces = [os.environ.get("HomerDev", ""), r"C:\HomerDev", os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "HomerDev")]
    lsPlaces += [s + r":\HomerDev" for s in "DEFGHIJKLMNOPQRSTUVWXYZ"]
    for sKit in lsPlaces:
        sPath = os.path.join(sKit, "scripts", "fixPages.py") if sKit else ""
        if sPath and os.path.isfile(sPath): return sPath
    return ""


if __name__ == "__main__":
    sFinisher = kitFinisher()
    if not sFinisher:
        print("The HomerDev kit's scripts\\fixPages.py was not found. Install or update HomerDev, or set the HomerDev variable to its folder.")
        sys.exit(2)
    sys.exit(subprocess.call([sys.executable, sFinisher, c_sCollection] + sys.argv[1:]))
