"""control-kidsai 的真實點擊流程（XCUITest）：drive、record --flow、snapshot。

流程測試在 app/KidsAIUITests/Flows.swift，每支一個類別。錄影用握手同步：
測試到了前置狀態寫 ready → CLI 開始錄影後寫 go → 測試點擊 → 到最終狀態寫 done（失敗寫 failed）
→ CLI 截圖、停錄後寫 end → 測試結束。錄影還在跑時結束測試，xcodebuild 會卡在收尾，所以一定先停錄。
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
}
READY_POLLS = 600   # ×0.2 秒＝120 秒（含安裝 runner、啟動 App、旁白）
DONE_POLLS = 300    # ×0.2 秒＝60 秒
EXIT_POLLS = 600   # ×0.2 秒＝120 秒（xcodebuild 收尾、寫 xcresult）


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
    """只跑流程（不錄影）：證明流程能通過，給連跑穩定性檢查用。"""
    test_class = check_flow(a.flow)
    d = require_device(ctx)
    require_fresh_runner(ctx)
    result = result_path(ctx, a.flow)
    r = ctx.runner.run(test_command(ctx, d["udid"], test_class, result), cwd=ctx.repo / "app")
    if r.returncode == 65:
        raise Fail(EXIT_EVIDENCE, f"流程 {a.flow} 沒有通過", f"open {result.relative_to(ctx.repo)} 看失敗步驟與截圖")
    if r.returncode != 0:
        raise Fail(EXIT_EXTERNAL, f"xcodebuild 失敗（{r.returncode}）：{(r.stderr or r.stdout).strip()[-400:]}", "control-kidsai doctor")
    return {"ok": True, "flow": a.flow, "passed": True, "xcresult": str(result.relative_to(ctx.repo))}


def handshake_dir(ctx: Context, label: str) -> Path:
    folder = verify_dir(ctx) / "_handshake" / label
    if folder.exists():
        for old in folder.iterdir():
            old.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def wait_for(ctx: Context, folder: Path, names: tuple, polls: int) -> Optional[str]:
    """等握手旗標或 xcodebuild 結束（exit 檔）；回傳先出現的那個名稱。"""
    for _ in range(polls):
        for name in names + ("exit",):
            if (folder / name).exists():
                return name
        ctx.sleep(0.2)
    return None


def spawn_test(ctx: Context, cmd: list, folder: Path) -> dict:
    """背景啟動 xcodebuild；結束碼寫進握手資料夾的 exit 檔（CLI 不必持有程序物件）。"""
    shell = f"{shlex.join(cmd)}; echo $? > {shlex.quote(str(folder / 'exit'))}"
    pid = ctx.runner.popen(["/bin/sh", "-c", shell], folder / "xcodebuild.log",
                           env={"TEST_RUNNER_KIDSAI_HANDSHAKE": str(folder)}, cwd=ctx.repo / "app")
    return {"pid": pid, "identity": ps_identity(ctx, pid)}


def release(folder: Path) -> None:
    """錄影停好了：寫 end 讓測試結束。"""
    if not (folder / "end").exists():
        (folder / ".end.tmp").write_text("end")
        (folder / ".end.tmp").rename(folder / "end")


def test_exit_code(ctx: Context, folder: Path) -> Optional[int]:
    if wait_for(ctx, folder, (), EXIT_POLLS) != "exit":
        return None
    try:
        return int((folder / "exit").read_text().strip())
    except ValueError:
        return None


def record_flow(ctx: Context, a) -> dict:
    """錄一支真實點擊流程：前置畫面 → 點擊 → 最終狀態，≤20 秒；失敗就丟棄這段錄影（exit 6）。"""
    test_class = check_flow(a.flow)
    folder_run = run_dir(ctx, a.run)
    d = require_device(ctx)
    require_fresh_runner(ctx)
    name = a.flow
    if (folder_run / f"{name}.mp4").exists():
        raise Fail(EXIT_USAGE, f"這個 run 已經錄過 {name}", "用新的 run")
    folder = handshake_dir(ctx, f"{a.run}-{name}")
    result = result_path(ctx, name)
    s = session(ctx)
    s["xcodebuild"] = spawn_test(ctx, test_command(ctx, d["udid"], test_class, result), folder)
    save_session(ctx, s)
    rec = None
    try:
        if wait_for(ctx, folder, ("ready", "failed"), READY_POLLS) != "ready":
            raise Fail(EXIT_EVIDENCE, f"流程 {name} 沒有到達前置狀態（沒有 ready）", f"control-kidsai drive --flow {name} 看失敗原因")
        rec = start_recording(ctx, a.run, name, d["udid"])
        s["recordings"] = {**s.get("recordings", {}), f"{a.run}/{name}": rec}
        save_session(ctx, s)
        (folder / ".go.tmp").write_text("go")
        (folder / ".go.tmp").rename(folder / "go")
        outcome = wait_for(ctx, folder, ("done", "failed"), DONE_POLLS)
        shot = tmp_dir(ctx) / f"{a.run}-{name}-end.png"
        if outcome == "done":
            run_ok(ctx, ["xcrun", "simctl", "io", d["udid"], "screenshot", "--type=png", str(shot)])
        raw, duration = stop_recording(ctx, rec)
        rec = None
        release(folder)
        code = test_exit_code(ctx, folder)
        if outcome != "done" or code != 0:
            raise Fail(EXIT_EVIDENCE, f"流程 {name} 沒有通過（{outcome or '逾時'}，xcodebuild {code}），這段錄影不算證據",
                       f"open {result.relative_to(ctx.repo)} 看失敗步驟")
    finally:
        if rec is not None:
            stop_process(ctx, rec)
            stop_process(ctx, rec.get("watchdog") or {}, sig=signal.SIGTERM)
        release(folder)  # 讓測試結束（不管成功或失敗）
        test_exit_code(ctx, folder)
        s = session(ctx)
        if not (folder / "exit").exists():
            stop_process(ctx, s.get("xcodebuild") or {}, group=True)
        s.pop("xcodebuild", None)
        s.get("recordings", {}).pop(f"{a.run}/{name}", None)
        save_session(ctx, s)
    end = folder_run / f"{name}-end.png"
    run_ok(ctx, ["sips", "-s", "format", "png", str(shot), "--out", str(end)])
    shot.unlink(missing_ok=True)
    files = finalize_video(ctx, a.run, name, raw)
    files["files"].append(add_file(ctx, a.run, end, "screenshot"))
    for flag in folder.iterdir():
        flag.unlink()
    return {"ok": True, "flow": name, "duration": round(duration, 1), **files, "xcresult": str(result.relative_to(ctx.repo))}


def cmd_snapshot(ctx: Context, a) -> dict:
    """跑 SnapshotTree 測試，把目前畫面的無障礙元素樹存成 <name>.json（kind a11y）。"""
    name = check_name(a.name, "name")
    folder_run = run_dir(ctx, a.run)
    if (folder_run / f"{name}.json").exists():
        raise Fail(EXIT_USAGE, f"{name}.json 已經存在", "換一個 --name")
    d = require_device(ctx)
    require_fresh_runner(ctx)
    folder = handshake_dir(ctx, f"{a.run}-{name}")
    launch = []
    if a.unit is not None:
        launch += ["-openUnit", str(a.unit)]
    if a.beat is not None:
        launch += ["-beat", str(a.beat)]
    result = result_path(ctx, name)
    r = ctx.runner.run(test_command(ctx, d["udid"], "SnapshotTree", result), cwd=ctx.repo / "app",
                       env={"TEST_RUNNER_KIDSAI_HANDSHAKE": str(folder), "TEST_RUNNER_KIDSAI_LAUNCH": " ".join(launch)})
    tree = folder / "tree.txt"
    if r.returncode != 0 or not tree.exists():
        raise Fail(EXIT_EVIDENCE, "沒有取得無障礙元素樹", f"open {result.relative_to(ctx.repo)}")
    out = folder_run / f"{name}.json"
    write_json(out, {"launch": launch, "tree": tree.read_text(errors="replace")})
    for flag in folder.iterdir():
        flag.unlink()
    if leaks_in(ctx, out.read_text()):
        out.unlink()
        raise Fail(EXIT_EVIDENCE, "元素樹含本機路徑、使用者名稱或裝置 ID，已丟棄", "回報這個情況")
    return {"ok": True, "file": add_file(ctx, a.run, out, "a11y")}
