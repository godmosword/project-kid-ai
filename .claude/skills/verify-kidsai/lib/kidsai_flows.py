"""control-kidsai 的真實點擊流程（XCUITest）：drive、record --flow、snapshot。

流程測試在 app/KidsAIUITests/Flows.swift，每支一個類別。
Xcode 27 上 UI 測試執行期間只要有螢幕錄影，xcodebuild 就會卡在收尾（卡住後模擬器要重開），
所以 record --flow 不錄影：測試自己約每 0.5 秒截一張圖（frame-NNN.png），點擊前兩格記下被點元素的位置（taps.json），
CLI 再把截圖以 4 fps 接成縮時影片，並在點擊那兩格畫框標出「點了這裡」。
"""

import shlex

from kidsai_core import *  # noqa: F401,F403
from kidsai_core import Context, Fail  # 型別註記用
from kidsai_evidence import *  # noqa: F401,F403

# 流程名稱 → XCUITest 類別（-only-testing:KidsAIUITests/<類別>）
FLOWS = {
    "map-to-unit1": "FlowMapToUnit1",
    "say-together": "FlowSayTogether",
    "sandbox-pick-and-react": "FlowSandboxPickAndReact",
    "drag-tap-to-place": "FlowDragTapToPlace",
    "story-branch": "FlowStoryBranch",
    "sticker": "FlowSticker",
    "choice-answer": "FlowChoiceAnswer",
    "sandbox-graded": "FlowSandboxGraded",
    "hold-to-exit": "FlowHoldToExit",
    "background-resume": "FlowBackgroundResume",
}
FLAG_POLLS = 900        # ×0.2 秒＝180 秒：等測試寫 done／failed（安裝 runner、啟動 App、旁白）
EXIT_AFTER_FLAG = 150   # ×0.2 秒＝30 秒：旗標出現後等 xcodebuild 收尾；還沒結束就視為卡住
FPS = 4
TAP_COLOR = "0xFF6B00"


def require_fresh_runner(ctx: Context) -> None:
    stamp = read_json(verify_dir(ctx) / "build.json", {}) or {}
    if not stamp.get("runner_fingerprint"):
        raise Fail(EXIT_STALE, "還沒有 build UI 測試 runner", "control-kidsai build --for-testing")
    if stamp.get("source_fingerprint") != source_fingerprint(ctx) or stamp["runner_fingerprint"] != runner_fingerprint(ctx):
        raise Fail(EXIT_STALE, "UI 測試 runner 和目前原始碼不一致（舊 build 錄的不算證據）", "control-kidsai build --for-testing")


def test_command(ctx: Context, udid: str, test_class: str, result: Path) -> list:
    return ["xcodebuild", "test-without-building", "-project", "KidsAI.xcodeproj", "-scheme", "KidsAI",
            "-destination", f"id={udid}", "-derivedDataPath", "build",
            f"-only-testing:KidsAIUITests/{test_class}", "-resultBundlePath", str(result)]


def result_path(ctx: Context, label: str) -> Path:
    folder = verify_dir(ctx) / "_xcresult"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{ctx.now():%Y%m%d-%H%M%S}-{label}.xcresult"


def check_flow(name: str) -> str:
    if name not in FLOWS:
        raise Fail(EXIT_USAGE, f"沒有這支流程：{name}", f"可用：{', '.join(sorted(FLOWS))}")
    return FLOWS[name]


def cmd_drive(ctx: Context, a) -> dict:
    """只跑流程（不截圖）：證明流程能通過，給連跑穩定性檢查用。"""
    test_class = check_flow(a.flow)
    d = require_device(ctx)
    require_fresh_runner(ctx)
    outcome = run_flow(ctx, d, test_class, f"drive-{a.flow}", frames=False)
    if not outcome["passed"]:
        raise Fail(EXIT_EVIDENCE, f"流程 {a.flow} 沒有通過", f"open {outcome['xcresult']} 看失敗步驟與截圖")
    return {"ok": True, "flow": a.flow, "passed": True, "xcodebuild_hung": outcome["hung"], "xcresult": outcome["xcresult"]}


def run_flow(ctx: Context, d: dict, test_class: str, label: str, frames: bool, extra_env: Optional[dict] = None) -> dict:
    """跑一支流程測試，以測試自己寫的 done／failed 判斷通過。
    xcodebuild 在旗標之後 30 秒還沒結束（Xcode 27 偶爾卡在收尾）：停掉它並重開專用模擬器，免得下一次也卡住。"""
    folder = handshake_dir(ctx, label)
    result = result_path(ctx, label)
    env = {"TEST_RUNNER_KIDSAI_HANDSHAKE": str(folder)}
    if not frames:
        env["TEST_RUNNER_KIDSAI_FRAMES"] = "0"
    env.update(extra_env or {})
    s = session(ctx)
    s["xcodebuild"] = spawn_test(ctx, test_command(ctx, d["udid"], test_class, result), folder, env)
    save_session(ctx, s)
    flag, code, hung = None, None, False
    try:
        flag = wait_flag(ctx, folder, FLAG_POLLS)
        code = test_exit_code(ctx, folder, EXIT_AFTER_FLAG if flag in ("done", "failed") else 1)
        hung = code is None
    finally:
        s = session(ctx)
        if not (folder / "exit").exists():
            stop_process(ctx, s.get("xcodebuild") or {}, group=True)
            reset_simulator(ctx, d)
        s.pop("xcodebuild", None)
        save_session(ctx, s)
    if flag is None:
        raise Fail(EXIT_EXTERNAL, "測試沒有跑完（沒有 done／failed）；已重開模擬器", "再跑一次；仍失敗就 control-kidsai doctor")
    return {"passed": flag == "done" and code in (0, None), "hung": hung, "code": code, "folder": folder,
            "xcresult": str(result.relative_to(ctx.repo))}


def wait_flag(ctx: Context, folder: Path, polls: int) -> Optional[str]:
    """等測試的 done／failed；xcodebuild 先結束（exit）也停止等待。"""
    for _ in range(polls):
        for name in ("done", "failed"):
            if (folder / name).exists():
                return name
        if (folder / "exit").exists():  # xcodebuild 已結束卻沒有旗標：測試沒跑到 tearDown，算失敗
            return "failed"
        ctx.sleep(0.2)
    return None


def reset_simulator(ctx: Context, d: dict) -> None:
    """xcodebuild 卡住後模擬器會一直卡：重開專用模擬器並恢復 status bar。"""
    ctx.runner.run(["xcrun", "simctl", "shutdown", d["udid"]])
    ctx.runner.run(["xcrun", "simctl", "boot", d["udid"]])
    ctx.runner.run(["xcrun", "simctl", "bootstatus", d["udid"], "-b"])
    ctx.runner.run(["xcrun", "simctl", "status_bar", d["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                    "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported", "--batteryState", "charged",
                    "--batteryLevel", "100", "--operatorName", ""])


def handshake_dir(ctx: Context, label: str) -> Path:
    folder = verify_dir(ctx) / "_handshake" / label
    if folder.exists():
        for old in folder.iterdir():
            old.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def spawn_test(ctx: Context, cmd: list, folder: Path, env: dict) -> dict:
    """背景啟動 xcodebuild；結束碼寫進握手資料夾的 exit 檔（CLI 不必持有程序物件）。
    用 caffeinate -i 包住：Mac 閒置睡著時模擬器會停住，測試會慢到逾時（2026-09-27 實測）。"""
    shell = f"caffeinate -i {shlex.join(cmd)}; echo $? > {shlex.quote(str(folder / 'exit'))}"
    pid = ctx.runner.popen(["/bin/sh", "-c", shell], folder / "xcodebuild.log", env=env, cwd=ctx.repo / "app")
    return {"pid": pid, "identity": ps_identity(ctx, pid)}


def test_exit_code(ctx: Context, folder: Path, polls: int) -> Optional[int]:
    """等 xcodebuild 結束（exit 檔）；逾時回傳 None。"""
    for _ in range(polls):
        if (folder / "exit").exists():
            try:
                return int((folder / "exit").read_text().strip())
            except ValueError:
                return None
        ctx.sleep(0.2)
    return None


def tap_filter(taps: list) -> str:
    """點擊那幾格畫一個框（ffmpeg drawbox；n 從 0 起算，frame-001 是 n=0）。"""
    boxes = []
    for tap in taps:
        try:
            n, x, y, w, h = (int(tap[k]) for k in ("frame", "x", "y", "w", "h"))
        except (KeyError, TypeError, ValueError):
            continue
        boxes.append(f"drawbox=x={x}:y={y}:w={w}:h={h}:color={TAP_COLOR}@1:t=18:enable='eq(n\\,{n - 1})'")
    return ",".join(boxes + ["scale=720:-2", "format=yuv420p"])


def record_flow(ctx: Context, a) -> dict:
    """錄一支真實點擊流程：測試裡的截圖接成 ≤20 秒的縮時影片（點擊處畫框）＋最終截圖；失敗就不留證據（exit 6）。"""
    test_class = check_flow(a.flow)
    folder_run = run_dir(ctx, a.run)
    d = require_device(ctx)
    require_fresh_runner(ctx)
    name = a.flow
    if (folder_run / f"{name}.mp4").exists():
        raise Fail(EXIT_USAGE, f"這個 run 已經錄過 {name}", "用新的 run")
    outcome = run_flow(ctx, d, test_class, f"{a.run}-{name}", frames=True)
    folder = outcome["folder"]
    if not outcome["passed"]:
        raise Fail(EXIT_EVIDENCE, f"流程 {name} 沒有通過（xcodebuild {outcome['code']}），不留證據", f"open {outcome['xcresult']} 看失敗步驟")
    frames = sorted(folder.glob("frame-*.png"))
    if len(frames) < 3:
        raise Fail(EXIT_EVIDENCE, "截圖太少，看不出點擊前後", "確認流程有呼叫 Frames.begin／tap／end")
    taps = read_json(folder / "taps.json", []) or []
    raw = tmp_dir(ctx) / f"{a.run}-{name}.mp4"
    run_ok(ctx, ["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-start_number", "1", "-i", str(folder / "frame-%03d.png"),
                 "-vf", tap_filter(taps), "-c:v", "libx264", "-r", str(FPS), str(raw)])
    probe = ctx.runner.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(raw)])
    try:
        duration = float(json.loads(probe.stdout)["format"]["duration"])
    except (ValueError, KeyError, TypeError):
        raise Fail(EXIT_EVIDENCE, "接出來的影片讀不出來", "確認有 ffmpeg：brew install ffmpeg")
    if not 0 < duration <= MAX_SECONDS + 1:
        raise Fail(EXIT_EVIDENCE, f"影片 {duration:.1f} 秒，超過 {MAX_SECONDS} 秒", "縮短流程")
    end = folder_run / f"{name}-end.png"
    run_ok(ctx, ["sips", "-s", "format", "png", str(frames[-1]), "--out", str(end)])
    files = finalize_video(ctx, a.run, name, raw)
    files["files"].append(add_file(ctx, a.run, end, "screenshot"))
    for leftover in folder.iterdir():
        leftover.unlink()
    return {"ok": True, "flow": name, "duration": round(duration, 1), "frames": len(frames), "taps": len(taps), **files,
            "xcodebuild_hung": outcome["hung"], "xcresult": outcome["xcresult"]}


def cmd_snapshot(ctx: Context, a) -> dict:
    """跑 SnapshotTree 測試，把目前畫面的無障礙元素樹存成 <name>.json（kind a11y）。"""
    name = check_name(a.name, "name")
    folder_run = run_dir(ctx, a.run)
    if (folder_run / f"{name}.json").exists():
        raise Fail(EXIT_USAGE, f"{name}.json 已經存在", "換一個 --name")
    d = require_device(ctx)
    require_fresh_runner(ctx)
    launch = []
    if a.unit is not None:
        launch += ["-openUnit", str(a.unit)]
    if a.beat is not None:
        launch += ["-beat", str(a.beat)]
    outcome = run_flow(ctx, d, "SnapshotTree", f"{a.run}-{name}", frames=False,
                       extra_env={"TEST_RUNNER_KIDSAI_LAUNCH": " ".join(launch)})
    folder = outcome["folder"]
    tree = folder / "tree.txt"
    if not outcome["passed"] or not tree.exists():
        raise Fail(EXIT_EVIDENCE, "沒有取得無障礙元素樹", f"open {outcome['xcresult']}")
    out = folder_run / f"{name}.json"
    write_json(out, {"launch": launch, "tree": tree.read_text(errors="replace")})
    for flag in folder.iterdir():
        flag.unlink()
    if leaks_in(ctx, out.read_text()):
        out.unlink()
        raise Fail(EXIT_EVIDENCE, "元素樹含本機路徑、使用者名稱或裝置 ID，已丟棄", "回報這個情況")
    return {"ok": True, "file": add_file(ctx, a.run, out, "a11y")}
