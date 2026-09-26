"""control-kidsai 的核心：常數、錯誤、外部命令、模擬器、build 與 doctor。"""


import argparse
import datetime
import getpass
import hashlib
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional
from zoneinfo import ZoneInfo

# 結束碼（固定，測試鎖定）
EXIT_OK, EXIT_USAGE, EXIT_ENV, EXIT_REFUSED, EXIT_EXTERNAL, EXIT_EVIDENCE, EXIT_STALE = 0, 2, 3, 4, 5, 6, 7

SIMS = ("KidsAI-Verify", "KidsAI-Maintain")
BUNDLE_ID = "com.godmosword.kidsai"
EXECUTABLE = "KidsAI"
DEVICE_TYPES = ("iPhone 17e", "iPhone 16e")  # 390×844 pt；iPhone 13／14 在 iOS 27 runtime 不可用
EXPECTED_PIXELS = (1170, 2532)
EVIDENCE_REPO_URL = "https://github.com/godmosword/project-kid-ai-evidence.git"
RAW_BASE = "https://raw.githubusercontent.com/godmosword/project-kid-ai-evidence/main"
TZ = ZoneInfo("Asia/Taipei")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
FILE_RE = re.compile(r"^(?!manifest\.)[a-z0-9][a-z0-9-]{0,63}\.(png|gif|mp4|json)$")
KINDS = {"screenshot", "video", "gif", "a11y"}
UUID_RE = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
ALLOWED_EXT = {".png", ".gif", ".mp4", ".json"}
MAX_BYTES = 10 * 1024 * 1024
MAX_SECONDS = 20
MANIFEST_KEYS = {"sha", "dirty", "device", "runtime", "simulator", "feature", "entry", "files", "captured_at", "visual_review"}
APP_REL = Path("app/build/Build/Products/Debug-iphonesimulator/KidsAI.app")
RUNNER_REL = Path("app/build/Build/Products/Debug-iphonesimulator/KidsAIUITests-Runner.app")
RUNNER_ID = "com.godmosword.kidsai.uitests.xctrunner"


class Fail(Exception):
    """可預期的失敗：帶結束碼與修法。"""

    def __init__(self, code: int, message: str, fix: str = ""):
        super().__init__(message)
        self.code, self.message, self.fix = code, message, fix


@dataclass
class Result:
    returncode: int
    stdout: str
    stderr: str


class Runner:
    """真正的外部命令；測試換成假的。"""

    def run(self, cmd, cwd=None, input=None, env=None) -> Result:
        try:
            p = subprocess.run(cmd, cwd=cwd, input=input, capture_output=True, text=True, errors="replace",
                               env={**os.environ, **env} if env else None)
        except FileNotFoundError as error:
            return Result(127, "", str(error))
        return Result(p.returncode, p.stdout, p.stderr)

    def popen(self, cmd, log_path: Path, env=None, cwd=None) -> int:
        with open(log_path, "wb") as log:
            p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True,
                                 env={**os.environ, **env} if env else None, cwd=cwd)
        return p.pid


@dataclass
class Context:
    repo: Path
    home: Path
    runner: Runner
    now: Callable[[], datetime.datetime] = lambda: datetime.datetime.now(TZ)
    kill: Callable[[int, int], None] = os.kill
    sleep: Callable[[float], None] = time.sleep
    user: str = field(default_factory=getpass.getuser)
    which: Callable[[str], Optional[str]] = shutil.which
    sim: str = "KidsAI-Verify"


# ---------------------------------------------------------------- 小工具

def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")


def read_json(path: Path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def verify_dir(ctx: Context) -> Path:
    return ctx.repo / ".verify"


def session_path(ctx: Context, sim: str) -> Path:
    return verify_dir(ctx) / f"session-{sim}.json"


def cache_dir(ctx: Context) -> Path:
    return ctx.home / "Library/Caches/kidsai-evidence/project-kid-ai-evidence"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def binaries(app: Path) -> list:
    """App 的程式碼：Xcode 的 Debug build 把程式放在 KidsAI.debug.dylib，主執行檔只是啟動用的小殼。"""
    return [p for p in (app / EXECUTABLE, app / f"{EXECUTABLE}.debug.dylib") if p.is_file()]


def binary_fingerprint(app: Path) -> str:
    h = hashlib.sha256()
    for path in binaries(app):
        h.update(path.name.encode())
        h.update(sha256_file(path).encode())
    return h.hexdigest()


def runner_fingerprint(ctx: Context) -> Optional[str]:
    """UI 測試 runner 的程式碼指紋（runner 本體＋KidsAIUITests.xctest）；沒有 build 就是 None。"""
    runner = ctx.repo / RUNNER_REL
    files = [runner / "KidsAIUITests-Runner", runner / "PlugIns/KidsAIUITests.xctest/KidsAIUITests"]
    if not all(f.is_file() for f in files):
        return None
    h = hashlib.sha256()
    for f in files:
        h.update(f.name.encode())
        h.update(sha256_file(f).encode())
    return h.hexdigest()


def check_name(value: str, what: str) -> str:
    if not NAME_RE.match(value or ""):
        raise Fail(EXIT_USAGE, f"{what} 只能用小寫英數與連字號：{value!r}", f"例如 --{what} map-islands")
    return value


def run_ok(ctx: Context, cmd, cwd=None, input=None, fix="", env=None) -> Result:
    r = ctx.runner.run(cmd, cwd=cwd, input=input, env=env) if env else ctx.runner.run(cmd, cwd=cwd, input=input)
    if r.returncode != 0:
        raise Fail(EXIT_EXTERNAL, f"命令失敗（{r.returncode}）：{' '.join(map(str, cmd))}：{(r.stderr or r.stdout).strip()[:400]}", fix)
    return r


def make_run_id(now: datetime.datetime, sha: str, taken: set) -> str:
    base = f"{now.astimezone(TZ):%Y%m%d-%H%M%S}-{sha[:7]}"
    if base not in taken:
        return base
    n = 2
    while f"{base}-{n}" in taken:
        n += 1
    return f"{base}-{n}"


def png_size(path: Path):
    data = path.read_bytes()[:24]
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


# ---------------------------------------------------------------- 模擬器

def devices(ctx: Context) -> list:
    r = run_ok(ctx, ["xcrun", "simctl", "list", "devices", "-j"], fix="確認已安裝 Xcode：xcode-select -p")
    out = []
    for runtime, items in json.loads(r.stdout).get("devices", {}).items():
        out += [dict(d, runtime=runtime) for d in items if d.get("isAvailable", True)]
    return out


def runtimes(ctx: Context) -> list:
    r = run_ok(ctx, ["xcrun", "simctl", "list", "runtimes", "-j"])
    return [rt for rt in json.loads(r.stdout).get("runtimes", []) if rt.get("platform", "iOS") == "iOS" and rt.get("isAvailable")]


def find_device(ctx: Context) -> Optional[dict]:
    return next((d for d in devices(ctx) if d["name"] == ctx.sim), None)


def require_device(ctx: Context, booted=True) -> dict:
    d = find_device(ctx)
    if d is None:
        raise Fail(EXIT_ENV, f"找不到模擬器 {ctx.sim}", f"control-kidsai --sim {ctx.sim} sim ensure")
    if booted and d.get("state") != "Booted":
        raise Fail(EXIT_ENV, f"模擬器 {ctx.sim} 沒有開機", f"control-kidsai --sim {ctx.sim} sim boot")
    return d


def describe(ctx: Context, d: dict) -> dict:
    """機型與 runtime 的名稱（不含 UDID）。"""
    rt = next((r for r in runtimes(ctx) if r["identifier"] == d["runtime"]), {})
    names = {t["identifier"]: t["name"] for t in rt.get("supportedDeviceTypes", [])}
    return {"device": names.get(d.get("deviceTypeIdentifier"), d.get("deviceTypeIdentifier", "?").rsplit(".", 1)[-1].replace("-", " ")),
            "runtime": rt.get("name", d["runtime"].rsplit(".", 1)[-1])}


def session(ctx: Context) -> dict:
    return read_json(session_path(ctx, ctx.sim), {}) or {}


def save_session(ctx: Context, data: dict) -> None:
    write_json(session_path(ctx, ctx.sim), data)


def cmd_sim(ctx: Context, a) -> dict:
    if a.action == "ensure":
        d = find_device(ctx)
        if d:
            return {"ok": True, "created": False, "udid": d["udid"], **describe(ctx, d)}
        rts = sorted(runtimes(ctx), key=lambda r: tuple(int(x) for x in r.get("version", "0").split(".") if x.isdigit()))
        if not rts:
            raise Fail(EXIT_ENV, "沒有可用的 iOS runtime", "在 Xcode ▸ Settings ▸ Components 安裝 iOS Simulator")
        rt = rts[-1]
        types = {t["name"]: t["identifier"] for t in rt.get("supportedDeviceTypes", [])}
        name = next((n for n in DEVICE_TYPES if n in types), None)
        if name is None:
            raise Fail(EXIT_ENV, f"{rt['name']} 不支援 {', '.join(DEVICE_TYPES)}；可用：{', '.join(sorted(types))[:300]}",
                       "安裝支援 iPhone 17e 或 16e 的 iOS runtime")
        r = run_ok(ctx, ["xcrun", "simctl", "create", ctx.sim, types[name], rt["identifier"]])
        return {"ok": True, "created": True, "udid": r.stdout.strip(), "device": name, "runtime": rt["name"]}
    if a.action == "boot":
        d = require_device(ctx, booted=False)
        s = session(ctx)
        if d.get("state") != "Booted":
            run_ok(ctx, ["xcrun", "simctl", "boot", d["udid"]])
            run_ok(ctx, ["xcrun", "simctl", "bootstatus", d["udid"], "-b"])
            s["booted_by_us"] = True
        save_session(ctx, s)
        return {"ok": True, "booted_by_us": s.get("booted_by_us", False)}
    if a.action == "shutdown":
        d = require_device(ctx, booted=False)
        if d.get("state") == "Booted":
            run_ok(ctx, ["xcrun", "simctl", "shutdown", d["udid"]])
        s = session(ctx)
        s["booted_by_us"] = False
        save_session(ctx, s)
        return {"ok": True}
    if a.action == "erase":
        if not a.yes:
            raise Fail(EXIT_REFUSED, f"erase 會清空 {ctx.sim} 的所有資料", f"確定要清空就加 --yes：control-kidsai --sim {ctx.sim} sim erase --yes")
        if a.dry_run:
            return {"ok": True, "dry_run": True, "would": [f"simctl shutdown {ctx.sim}", f"simctl erase {ctx.sim}"]}
        d = require_device(ctx, booted=False)
        if d.get("state") == "Booted":
            run_ok(ctx, ["xcrun", "simctl", "shutdown", d["udid"]])
        run_ok(ctx, ["xcrun", "simctl", "erase", d["udid"]])
        save_session(ctx, {})
        return {"ok": True, "erased": ctx.sim}
    # statusbar
    d = require_device(ctx)
    run_ok(ctx, ["xcrun", "simctl", "status_bar", d["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                 "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported", "--batteryState", "charged",
                 "--batteryLevel", "100", "--operatorName", ""])
    listed = run_ok(ctx, ["xcrun", "simctl", "status_bar", d["udid"], "list"]).stdout
    if "9:41" not in listed:
        raise Fail(EXIT_ENV, "status bar 覆寫沒有生效", f"control-kidsai --sim {ctx.sim} sim statusbar")
    return {"ok": True, "statusbar": "9:41, wifi, 100%"}


# ---------------------------------------------------------------- build／安裝／啟動

def git(ctx: Context, *args) -> str:
    return run_ok(ctx, ["git", *args], cwd=ctx.repo).stdout


def source_fingerprint(ctx: Context) -> str:
    """HEAD＋app／content 的未提交改動＋未追蹤檔內容：原始碼一變就不同。"""
    h = hashlib.sha256()
    h.update(git(ctx, "rev-parse", "HEAD").strip().encode())
    h.update(git(ctx, "diff", "HEAD", "--binary", "--", "app", "content").encode())
    for rel in sorted(filter(None, git(ctx, "ls-files", "--others", "--exclude-standard", "--", "app", "content").splitlines())):
        h.update(rel.encode())
        path = ctx.repo / rel
        if path.is_file():
            h.update(path.read_bytes())
    return h.hexdigest()


def cmd_build(ctx: Context, a) -> dict:
    d = require_device(ctx, booted=False)
    steps = [(["xcodegen", "generate", "--quiet"], "app"),
             (["xcodebuild", "-project", "KidsAI.xcodeproj", "-scheme", "KidsAI", "-configuration", "Debug",
               "-destination", f"id={d['udid']}", "-derivedDataPath", "build", "-quiet",
               "build-for-testing" if a.for_testing else "build"], "app")]
    if a.dry_run:
        return {"ok": True, "dry_run": True, "would": [f"(cd {cwd}) " + " ".join(c) for c, cwd in steps]}
    for cmd, cwd in steps:
        run_ok(ctx, cmd, cwd=ctx.repo / cwd, fix="先在 app/ 手動跑同一個命令看完整錯誤")
    app = ctx.repo / APP_REL
    if not binaries(app):
        raise Fail(EXIT_EXTERNAL, "build 完成但找不到 KidsAI.app", "檢查 app/build/Build/Products/Debug-iphonesimulator/")
    stamp = {"source_fingerprint": source_fingerprint(ctx), "executable_sha256": binary_fingerprint(app),
             "configuration": "Debug", "built_at": ctx.now().isoformat()}
    if a.for_testing:
        # UI 測試 runner 也要記指紋：drive／record --flow 只接受和目前原始碼一致的 runner
        stamp["runner_fingerprint"] = runner_fingerprint(ctx)
        if stamp["runner_fingerprint"] is None:
            raise Fail(EXIT_EXTERNAL, "build-for-testing 完成但找不到 UI 測試 runner", "檢查 app/project.yml 的 KidsAIUITests")
    write_json(verify_dir(ctx) / "build.json", stamp)
    return {"ok": True, **stamp}


def cmd_install(ctx: Context, a) -> dict:
    d = require_device(ctx)
    app = ctx.repo / APP_REL
    if not app.exists():
        raise Fail(EXIT_ENV, "還沒有 build", "control-kidsai build")
    run_ok(ctx, ["xcrun", "simctl", "install", d["udid"], str(app)])
    return {"ok": True, "installed": BUNDLE_ID}


def cmd_launch(ctx: Context, a) -> dict:
    d = require_device(ctx)
    args = []
    if a.unit is not None:
        args += ["-openUnit", str(a.unit)]
    if a.beat is not None:
        args += ["-beat", str(a.beat)]
    if a.events:
        args += ["-events", a.events]
    if a.unlock_all:
        args += ["-unlockAll"]
    ctx.runner.run(["xcrun", "simctl", "terminate", d["udid"], BUNDLE_ID])
    run_ok(ctx, ["xcrun", "simctl", "launch", d["udid"], BUNDLE_ID, *args], fix="control-kidsai install")
    s = session(ctx)
    s["launched"] = True
    save_session(ctx, s)
    return {"ok": True, "launched": BUNDLE_ID, "args": args}


def cmd_terminate(ctx: Context, a) -> dict:
    d = require_device(ctx)
    r = ctx.runner.run(["xcrun", "simctl", "terminate", d["udid"], BUNDLE_ID])
    return {"ok": True, "was_running": r.returncode == 0}


# ---------------------------------------------------------------- doctor

def installed_app(ctx: Context, udid: str) -> Optional[Path]:
    r = ctx.runner.run(["xcrun", "simctl", "get_app_container", udid, BUNDLE_ID, "app"])
    return Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def cmd_doctor(ctx: Context, a) -> dict:
    checks = []

    def add(name, ok, detail, fix="", code=EXIT_ENV):
        checks.append({"check": name, "ok": ok, "detail": detail, "fix": "" if ok else fix, "code": EXIT_OK if ok else code})
        return ok

    def done():
        failed = next((c for c in checks if not c["ok"]), None)
        return {"ok": failed is None, "exit": failed["code"] if failed else EXIT_OK, "checks": checks}

    if not add("xcode", ctx.runner.run(["xcrun", "--find", "simctl"]).returncode == 0, "xcrun simctl", "安裝 Xcode：xcode-select --install"):
        return done()
    d = find_device(ctx)
    if not add("simulator", d is not None, ctx.sim, f"control-kidsai --sim {ctx.sim} sim ensure"):
        return done()
    if not add("booted", d.get("state") == "Booted", d.get("state"), f"control-kidsai --sim {ctx.sim} sim boot"):
        return done()
    udid = d["udid"]
    add("statusbar", "9:41" in ctx.runner.run(["xcrun", "simctl", "status_bar", udid, "list"]).stdout,
        "9:41 覆寫", f"control-kidsai --sim {ctx.sim} sim statusbar")
    listed = ctx.runner.run(["xcrun", "simctl", "listapps", udid])
    converted = ctx.runner.run(["plutil", "-convert", "json", "-o", "-", "-"], input=listed.stdout)
    try:
        apps = json.loads(converted.stdout) if listed.returncode == 0 and converted.returncode == 0 else None
    except json.JSONDecodeError:
        apps = None
    if not add("list-apps", isinstance(apps, dict), "simctl listapps", "重開模擬器：control-kidsai sim shutdown && control-kidsai sim boot",
               code=EXIT_EXTERNAL):
        return done()
    # 允許 KidsAI 本體與它的 UI 測試 runner（xcodebuild test 會安裝）
    others = sorted(k for k, v in apps.items() if isinstance(v, dict) and v.get("ApplicationType") == "User"
                    and k not in (BUNDLE_ID, RUNNER_ID))
    add("only-kidsai", not others, "只裝 KidsAI（與 UI 測試 runner）" if not others else f"另外裝了 {len(others)} 個 App",
        f"control-kidsai --sim {ctx.sim} sim erase --yes，再 build、install")
    app = installed_app(ctx, udid)
    if not add("installed", app is not None, BUNDLE_ID, "control-kidsai build && control-kidsai install"):
        return done()
    # Debug build 才有 KidsAI.debug.dylib 與啟動參數；兩個條件都要成立
    debug = (app / f"{EXECUTABLE}.debug.dylib").is_file() and any(b"-openUnit" in p.read_bytes() for p in binaries(app))
    add("debug-build", debug, "Debug（有 debug.dylib 與啟動參數）", "control-kidsai build && control-kidsai install（只接受 Debug build）")
    stamp = read_json(verify_dir(ctx) / "build.json", {}) or {}
    fresh = bool(stamp) and stamp.get("source_fingerprint") == source_fingerprint(ctx) \
        and bool(binaries(app)) and stamp.get("executable_sha256") == binary_fingerprint(app)
    add("fresh-build", fresh, "安裝的 App 和目前原始碼一致" if fresh else "舊 build：錄的影片不算證據",
        "control-kidsai build && control-kidsai install", code=EXIT_STALE)
    if stamp.get("runner_fingerprint"):
        runner_ok = fresh and stamp["runner_fingerprint"] == runner_fingerprint(ctx)
        add("ui-tests", runner_ok, "UI 測試 runner 和目前原始碼一致" if runner_ok else "UI 測試 runner 是舊的",
            "control-kidsai build --for-testing", code=EXIT_STALE)
    else:
        add("ui-tests", True, "還沒 build --for-testing（只影響 drive、record --flow、snapshot）")
    with tempfile.TemporaryDirectory() as tmp:
        shot = Path(tmp) / "doctor.png"
        taken = ctx.runner.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(shot)])
        size = png_size(shot) if shot.exists() else None
    if not add("screenshot", taken.returncode == 0 and size is not None, "simctl screenshot", "重開模擬器後再試", code=EXIT_EXTERNAL):
        return done()
    add("screen", size == EXPECTED_PIXELS, f"{size}", f"刪除 {ctx.sim} 後用 sim ensure 重建（要 390×844 機型）")
    return done()


