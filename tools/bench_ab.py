"""Benchmarks commits one after another on this machine with the desktop
renderer (Forward+ on Vulkan; in CI drawn by the CPU), every one measured
by the same script (this checkout's scripts/bench.gd), so the numbers
compare. CI machines differ by a third from run to run: only numbers from
one machine mean anything side by side.

  python3 tools/bench_ab.py <godot binary> <out dir> <ref> <ref> [...]

The first ref is the baseline. Writes <out dir>/ab.md and each commit's
BENCH lines, and prints the table. CI runs it from
.github/workflows/bench-ab.yml.
"""
import json
import os
import re
import shutil
import subprocess
import sys


def bench(godot, ref, work, out):
    """Checks `ref` out into `work`, imports it, runs the benchmark there;
    returns the result (the BENCH JSON line) or None."""
    subprocess.run(["git", "worktree", "add", "-f", "--detach", work, ref], check=True)
    # The same measuring for every commit.
    shutil.copy("scripts/bench.gd", os.path.join(work, "scripts", "bench.gd"))
    os.makedirs(os.path.join(work, "ci-out"), exist_ok=True)
    open(os.path.join(work, "ci-out", ".gdignore"), "w").close()
    subprocess.run(["timeout", "600", godot, "--headless", "--audio-driver", "Dummy", "--path", work, "--import"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", "timeout", "-k", "10", "1800", godot,
                          "--audio-driver", "Dummy", "--path", work, "--rendering-driver", "vulkan",
                          "--resolution", "1280x720", "--", "--bench", "--bench-quit"],
                         capture_output=True, text=True)
    lines = [line for line in run.stdout.splitlines() if line.startswith("BENCH")]
    with open(os.path.join(out, re.sub(r"[^A-Za-z0-9._-]", "_", ref) + ".txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    for line in lines:
        if line.startswith("BENCH {"):
            return json.loads(line[len("BENCH "):])
    return None


def avg(row):
    spots = row["spots"]
    return sum(s["avg_ms"] for s in spots) / max(1, len(spots))


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    godot, out, refs = sys.argv[1], sys.argv[2], sys.argv[3:]
    for ref in refs:
        if not re.fullmatch(r"[A-Za-z0-9._/-]+", ref):
            sys.exit(f"not a commit or branch name: {ref!r}")
    os.makedirs(out, exist_ok=True)
    cpu = subprocess.run(["sh", "-c", "lscpu | grep 'Model name' | head -1"], capture_output=True, text=True).stdout.strip()
    results = {}
    for i, ref in enumerate(refs):
        print(f"benchmarking {ref}", flush=True)
        results[ref] = bench(godot, ref, os.path.abspath(f"ab-work/{i}"), out)
    configs = []
    for r in results.values():
        for row in (r or {}).get("rows", []):
            if row["config"] not in configs:
                configs.append(row["config"])
    base, last = refs[0], refs[-1]
    head = "| config | " + " | ".join(refs) + f" | {last} vs {base} |"
    lines = [f"Desktop renderer, one machine ({cpu or 'unknown CPU'}); average frame (ms) over the benchmark's spots.", "",
             head, "|" + "---|" * (len(refs) + 2)]
    for config in configs:
        cells = []
        values = []
        for ref in refs:
            row = next((x for x in (results[ref] or {}).get("rows", []) if x["config"] == config), None)
            values.append(avg(row) if row else None)
            cells.append(f"{values[-1]:.1f}" if row else "-")
        change = f"{(values[-1] / values[0] - 1) * 100:+.0f}%" if values[0] and values[-1] else "-"
        lines.append(f"| {config} | " + " | ".join(cells) + f" | {change} |")
    lines.append("")
    for ref in refs:
        r = results[ref]
        if r is None:
            lines.append(f"{ref}: no result (see {ref}.txt)")
            continue
        first = ", ".join(f"{m['spot']} {m['max_ms']:.0f} ms" for m in r.get("first_visit", []))
        lines.append(f"{ref}: title steady after {r['title'].get('settled_s', 0):.1f} s; first visits, worst frame: {first}")
    text = "\n".join(lines) + "\n"
    with open(os.path.join(out, "ab.md"), "w") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
