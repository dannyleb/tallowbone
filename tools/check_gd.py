"""Catches GDScript mistakes gdparse can't, each of which stops the whole
script compiling:
- `var x := ...` where the value is Variant, which Godot refuses to infer.
  Flags `:=` from a subscript of an array literal, from `.get(...)`, or
  from arithmetic on a loop variable over an untyped list. Heuristic: a
  flag may be fine, but look.
- A local variable used outside the block it was declared in (a line
  left behind after a loop or branch it belonged to).
Run before pushing:
  python3 tools/check_gd.py
"""
import glob
import re
import sys

from gdtoolkit.parser import parser
from lark import Token, Tree

# Statements that open a block of their own.
BLOCKS = {"for_stmt", "for_stmt_typed", "while_stmt", "if_branch", "elif_branch", "else_branch", "match_branch", "lambda"}
VARS = {"func_var_assigned", "func_var_inf", "func_var_typed_assgnd", "func_var_typed", "func_var_empty"}


def _names(node):
    """Every name a function declares as a local (vars, loop variables,
    match captures, arguments)."""
    out = set()
    for t in node.iter_subtrees():
        if t.data in VARS or t.data in ("for_stmt", "for_stmt_typed", "var_capture_pattern", "func_arg_regular", "func_arg_typed", "func_arg_inf"):
            first = t.children[0] if t.children else None
            if isinstance(first, Token) and first.type == "NAME":
                out.add(first.value)
    return out


def _walk(node, scopes, locals_, members, found):
    if isinstance(node, Token):
        if node.type == "NAME" and node.value in locals_ and node.value not in members and not any(node.value in s for s in scopes):
            found.append((node.line, node.value))
        return
    kind = node.data
    if kind == "getattr":
        _walk(node.children[0], scopes, locals_, members, found)
        return
    if kind == "eq_dict_element":
        _walk(node.children[1], scopes, locals_, members, found)
        return
    if kind in ("func_arg_regular", "func_arg_typed", "func_arg_inf"):
        scopes[-1].add(node.children[0].value)
        for c in node.children[1:]:
            _walk(c, scopes, locals_, members, found)
        return
    if kind == "func_var_stmt":
        var = node.children[0]
        for c in var.children[1:]:
            _walk(c, scopes, locals_, members, found)
        scopes[-1].add(var.children[0].value)
        return
    if kind == "var_capture_pattern":
        scopes[-1].add(node.children[0].value)
        return
    if kind in BLOCKS:
        scope = set()
        children = node.children
        if kind in ("for_stmt", "for_stmt_typed"):
            scope.add(children[0].value)
            children = children[1:]
        scopes.append(scope)
        for c in children:
            _walk(c, scopes, locals_, members, found)
        scopes.pop()
        return
    for c in node.children:
        _walk(c, scopes, locals_, members, found)


def check_scopes(path):
    tree = parser.parse(open(path).read(), gather_metadata=True)
    members = set()
    for t in tree.children:
        if isinstance(t, Tree) and t.data in ("class_var_stmt", "const_stmt"):
            members.add(t.children[0].children[0].value)
    found = []
    for fn in tree.find_data("func_def"):
        _walk(Tree("block", fn.children), [set()], _names(fn), members, found)
    return sorted(set(found))

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
for path in sorted(glob.glob("scripts/**/*.gd", recursive=True) + glob.glob("tests/*.gd")):
    for line, name in check_scopes(path):
        print(f"{path}:{line}: '{name}' is used outside the block it was declared in")
        bad += 1
print(f"{bad} to look at" if bad else "gdscript ok")
sys.exit(1 if bad else 0)
