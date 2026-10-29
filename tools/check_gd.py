"""Catches a GDScript mistake gdparse can't: `var x := ...` where the value
is Variant, which Godot refuses to infer (and then the whole script fails
to compile). Flags `:=` from a subscript of an array literal, from
`.get(...)`, or from arithmetic on a loop variable over an untyped list.
Heuristic: a flag may be fine, but look. Run before pushing:
  python3 tools/check_gd.py
"""
import glob
import re
import sys

bad = 0
for path in sorted(glob.glob("scripts/**/*.gd", recursive=True) + glob.glob("tests/*.gd")):
    variant_names = set()
    for i, line in enumerate(open(path), 1):
        code = line.split("#", 1)[0]
        if re.match(r"\s*func ", code):
            variant_names = set()
        m = re.match(r"\s*for\s+(\w+)\s+in\s+(.+):\s*$", code)
        if m and not re.match(r"(range\(|\d|[A-Z_]+\s*$|\w+\.size\(\))", m.group(2).strip()):
            # Untyped iteration: a list literal or an untyped Array.
            if m.group(2).strip().startswith("["):
                variant_names.add(m.group(1))
        m = re.match(r"\s*var\s+(\w+)\s*:=\s*(.+)$", code)
        if not m:
            continue
        rhs = m.group(2)
        why = None
        if re.search(r"\]\s*\[", rhs) or re.match(r"\[.*\]\s*\[", rhs):
            why = "subscript of a list literal"
        elif ".get(" in rhs and "get_node" not in rhs:
            why = ".get() returns Variant"
        else:
            # What's left once calls (typed results) and ternary conditions
            # are taken out is the arithmetic the type comes from.
            bare = rhs
            while True:
                stripped = re.sub(r"\b\w+\([^()]*\)", "CALL", bare)
                if stripped == bare:
                    break
                bare = stripped
            bare = re.sub(r"\bif\b.*?\belse\b", "if COND else", bare)
            for n in variant_names:
                if re.search(r"\b" + n + r"\b", bare):
                    why = f"arithmetic on loop variable '{n}' over a list literal"
                    break
        if why:
            print(f"{path}:{i}: var {m.group(1)} := ... ({why}); give it a type")
            bad += 1
print(f"{bad} to look at" if bad else "gdscript ok")
sys.exit(1 if bad else 0)
