#!/usr/bin/env python3
"""Runs the game's ?bench benchmark (scripts/bench.gd) in real browsers.

    python3 tools/bench_web.py <web build dir> <out dir>

Serves the web build on localhost, opens it in Firefox and Chrome, each on
its own virtual display (Xvfb), waits for the game to POST its results,
and writes bench.json and bench.md to the out dir, with a screenshot and
the browser's log for each run. CI runs it on every push to main. A
browser that isn't installed is skipped; one that never reports back
(WebGL missing, or the game hung) is listed as such.

The machine has no GPU, so the browsers draw with the CPU (Mesa llvmpipe,
SwiftShader): absolute numbers are far slower than a real machine. What
matters is how they compare: which system costs what, and Firefox against
Chrome.
"""
import http.server
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

PORT = 8060

# label, browser, screen size, device pixel ratio, query, timeout (s)
RUNS = [
    ("Firefox, 1280x720", "firefox", (1280, 720), 1, "bench", 600),
    ("Chrome, 1280x720", "chrome", (1280, 720), 1, "bench", 600),
    ("Firefox, 1280x720 at 2x (2560x1440 pixels, like a Retina screen)", "firefox", (2560, 1440), 2, "bench=quick", 360),
]

FIREFOX_PREFS = {
    "browser.shell.checkDefaultBrowser": False,
    "browser.startup.homepage_override.mstone": "ignore",
    "browser.aboutwelcome.enabled": False,
    "trailhead.firstrun.didSeeAboutWelcome": True,
    "datareporting.policy.dataSubmissionEnabled": False,
    "datareporting.policy.firstRunURL": "",
    "toolkit.telemetry.reportingpolicy.firstRun": False,
    "browser.sessionstore.resume_from_crash": False,
    "browser.tabs.warnOnClose": False,
    "media.autoplay.default": 0,
    "webgl.force-enabled": True,
    "devtools.console.stdout.content": True,
}

results = {}
current = {"label": None}


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/bench" and current["label"]:
            try:
                results[current["label"]] = json.loads(body)
            except ValueError:
                results[current["label"]] = {"error": "unreadable result"}
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass


def find(*names):
    for n in names:
        path = shutil.which(n)
        if path:
            return path
    return None


def browser_command(browser, profile, size, dpr, url):
    # Window sizes are in CSS pixels; the screen is in device pixels.
    w, h = size[0] // dpr, size[1] // dpr
    if browser == "firefox":
        exe = find("firefox")
        if not exe:
            return None
        with open(os.path.join(profile, "user.js"), "w") as f:
            prefs = dict(FIREFOX_PREFS)
            prefs["layout.css.devPixelsPerPx"] = f"{dpr:.1f}"
            for k, v in prefs.items():
                f.write(f"user_pref({json.dumps(k)}, {json.dumps(v)});\n")
        # No window manager on the virtual display: set the window size the
        # way Firefox remembers it.
        with open(os.path.join(profile, "xulstore.json"), "w") as f:
            json.dump({"chrome://browser/content/browser.xhtml": {"main-window": {
                "screenX": "0", "screenY": "0", "width": str(w), "height": str(h), "sizemode": "normal"}}}, f)
        return [exe, "--no-remote", "--new-instance", "--profile", profile, "--kiosk", url]
    exe = find("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")
    if not exe:
        return None
    return [exe, "--no-first-run", "--no-default-browser-check", "--disable-default-apps", f"--user-data-dir={profile}",
            "--no-sandbox", f"--window-size={w},{h}", "--window-position=0,0",
            f"--force-device-scale-factor={dpr}", "--autoplay-policy=no-user-gesture-required",
            "--ignore-gpu-blocklist", "--enable-unsafe-swiftshader", "--enable-logging=stderr", "--v=0", f"--app={url}"]


def run(index, label, browser, size, dpr, query, timeout, out):
    display = f":{90 + index}"
    slug = "".join(c if c.isalnum() else "-" for c in label.lower()).strip("-")[:40]
    profile = tempfile.mkdtemp(prefix="bench-")
    cmd = browser_command(browser, profile, size, dpr, f"http://localhost:{PORT}/index.html?{query}")
    if cmd is None:
        results[label] = {"error": f"{browser} isn't installed", "seconds": 0}
        return
    xvfb = subprocess.Popen(["Xvfb", display, "-screen", "0", f"{size[0]}x{size[1]}x24", "-nolisten", "tcp"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    env = dict(os.environ, DISPLAY=display)
    log = open(os.path.join(out, f"{slug}.log"), "w")
    current["label"] = label
    started = time.time()
    proc = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    while label not in results and time.time() - started < timeout and proc.poll() is None:
        time.sleep(1.0)
    elapsed = time.time() - started
    if shutil.which("import"):
        subprocess.run(["import", "-display", display, "-window", "root", os.path.join(out, f"{slug}.png")],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    if label not in results:
        why = "the browser exited" if proc.poll() is not None else f"no result after {timeout} s"
        results[label] = {"error": f"{why} (WebGL unavailable, or the game hung): see {slug}.log and {slug}.png"}
    results[label]["seconds"] = round(elapsed, 1)
    current["label"] = None
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    xvfb.terminate()
    log.close()
    shutil.rmtree(profile, ignore_errors=True)


def main():
    web, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    handler = lambda *a, **k: Handler(*a, directory=web, **k)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for i, (label, browser, size, dpr, query, timeout) in enumerate(RUNS):
        print(f"--- {label}", flush=True)
        run(i, label, browser, size, dpr, query, timeout, out)
        r = results[label]
        print(r.get("summary") or r.get("error"), f"({r['seconds']} s)", flush=True)
    server.shutdown()

    with open(os.path.join(out, "bench.json"), "w") as f:
        json.dump(results, f, indent=1)
    md = ["# Browser benchmark", "",
          "CPU-drawn (no GPU on the CI machine): compare rows, not absolute speed.", ""]
    for label, _, _, _, _, _ in RUNS:
        r = results[label]
        md += [f"## {label}", "", "```", r.get("summary") or r.get("error", "?"), "```", ""]
    text = "\n".join(md)
    with open(os.path.join(out, "bench.md"), "w") as f:
        f.write(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(text)


if __name__ == "__main__":
    main()
