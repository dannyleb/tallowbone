"""Catches shader mistakes Godot would only report in CI: names that are
reserved words in GLSL (a variable called `flat` or `sample` breaks the
whole shader). Run before pushing:  python3 tools/check_shaders.py
"""
import glob
import re
import sys

RESERVED = set("""
attribute const uniform varying layout centroid flat smooth noperspective break continue do for while
switch case default if else in out inout invariant discard return struct precision lowp mediump highp
input output common partition active asm class union enum typedef template this resource goto inline
noinline public static extern external interface long short double half fixed unsigned superp sizeof
cast namespace using filter sample patch subroutine buffer shared coherent volatile restrict readonly
writeonly instance global group
""".split())
TYPES = r"(?:float|int|uint|bool|vec[234]|ivec[234]|uvec[234]|bvec[234]|mat[234])"

bad = 0
for path in sorted(glob.glob("shaders/*.gdshader")):
    for i, line in enumerate(open(path), 1):
        code = line.split("//", 1)[0]
        for m in re.finditer(TYPES + r"\s+([A-Za-z_]\w*)", code):
            if m.group(1) in RESERVED:
                print(f"{path}:{i}: '{m.group(1)}' is reserved in GLSL")
                bad += 1
print(f"{bad} problem(s)" if bad else "shaders ok")
sys.exit(1 if bad else 0)
