"""control-kidsai 的證據：run、截圖、錄影、清理、發布。"""

from kidsai_core import *  # noqa: F401,F403
from kidsai_core import Context, Fail  # 型別註記用


# ---------------------------------------------------------------- run 與證據

def run_dir(ctx: Context, run_id: str) -> Path:
    if not re.match(r"^\d{8}-\d{6}-[0-9a-f]{7}(-\d+)?$", run_id or ""):
        raise Fail(EXIT_USAGE, f"run-id 格式不對：{run_id!r}", "用 run new 的輸出")
    path = verify_dir(ctx) / run_id
    if not path.is_dir():
        raise Fail(EXIT_USAGE, f"找不到 run {run_id}", "control-kidsai run new --feature <id> --entry <entry>")
    return path


def add_file(ctx: Context, run_id: str, path: Path, kind: str) -> dict:
    manifest_path = run_dir(ctx, run_id) / "manifest.json"
    manifest = read_json(manifest_path)
    entry = {"name": path.name, "sha256": sha256_file(path), "bytes": path.stat().st_size, "kind": kind}
    manifest["files"] = [f for f in manifest["files"] if f["name"] != path.name] + [entry]
    manifest["visual_review"] = None  # 內容變了就要重看
    write_json(manifest_path, manifest)
    return entry


def cmd_run(ctx: Context, a) -> dict:
    feature, entry = check_name(a.feature, "feature"), check_name(a.entry, "entry")
    d = require_device(ctx, booted=False)
    sha = git(ctx, "rev-parse", "HEAD").strip()
    dirty = bool(git(ctx, "status", "--porcelain", "--", "app", "content").strip())
    taken = {p.name for p in verify_dir(ctx).iterdir()} if verify_dir(ctx).exists() else set()
    run_id = make_run_id(ctx.now(), sha, taken)
    manifest = {"sha": sha, "dirty": dirty, **describe(ctx, d), "simulator": ctx.sim, "feature": feature, "entry": entry,
                "files": [], "captured_at": ctx.now().isoformat(), "visual_review": None}
    write_json(verify_dir(ctx) / run_id / "manifest.json", manifest)
    return {"ok": True, "run": run_id, "dir": f".verify/{run_id}"}


def cmd_screenshot(ctx: Context, a) -> dict:
    name = check_name(a.name, "name")
    folder = run_dir(ctx, a.run)
    d = require_device(ctx)
    final = folder / f"{name}.png"
    if final.exists():
        raise Fail(EXIT_USAGE, f"{final.name} 已經存在", "換一個 --name")
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "raw.png"
        run_ok(ctx, ["xcrun", "simctl", "io", d["udid"], "screenshot", "--type=png", str(raw)])
        # 重新存檔：去掉中繼資料
        run_ok(ctx, ["sips", "-s", "format", "png", str(raw), "--out", str(final)])
    size = png_size(final)
    return {"ok": True, "file": add_file(ctx, a.run, final, "screenshot"), "pixels": size,
            "warning": None if size == EXPECTED_PIXELS else f"尺寸不是 {EXPECTED_PIXELS}"}


def ps_identity(ctx: Context, pid: int) -> Optional[str]:
    r = ctx.runner.run(["ps", "-p", str(pid), "-o", "lstart=", "-o", "command="])
    return " ".join(r.stdout.split()) if r.returncode == 0 and r.stdout.strip() else None


def tmp_dir(ctx: Context) -> Path:
    path = verify_dir(ctx) / "_tmp"
    path.mkdir(parents=True, exist_ok=True)
    return path


def start_recording(ctx: Context, run_id: str, name: str, udid: str) -> dict:
    """開始錄影；等 simctl 回報 Recording started 才回傳。回傳要記進 session 的資料。"""
    raw, log = tmp_dir(ctx) / f"{run_id}-{name}.mp4", tmp_dir(ctx) / f"{run_id}-{name}.log"
    pid = ctx.runner.popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", str(raw)], log)
    for _ in range(50):  # 最多等約 10 秒
        if "Recording started" in (log.read_text(errors="replace") if log.exists() else ""):
            break
        ctx.sleep(0.2)
    else:
        identity = ps_identity(ctx, pid)
        if identity and "recordVideo" in identity:  # 只停確定是本次啟動的錄影程序
            ctx.kill(pid, signal.SIGTERM)
        raise Fail(EXIT_EVIDENCE, "錄影沒有開始，這段錄影無效", f"看 .verify/_tmp/{log.name}；確認模擬器已開機後重錄")
    watchdog = ctx.runner.popen(["/bin/sh", "-c", f"sleep {MAX_SECONDS}; kill -INT {pid}"], tmp_dir(ctx) / f"{run_id}-{name}.watchdog")
    return {"pid": pid, "identity": ps_identity(ctx, pid), "path": raw.name,
            "watchdog": {"pid": watchdog, "identity": ps_identity(ctx, watchdog)}, "started_at": ctx.now().isoformat()}


def stop_recording(ctx: Context, rec: dict):
    """停錄並驗證影片（可讀、長度 >0 且 ≤20 秒）；回傳 (原始檔, 秒數)。無效時 exit 6。"""
    stopped = stop_process(ctx, rec)
    stop_process(ctx, rec.get("watchdog") or {}, sig=signal.SIGTERM)
    if not stopped:
        raise Fail(EXIT_EVIDENCE, "錄影程序不是本次啟動的（或停不下來），這段錄影無效", "cleanup 後重新錄")
    raw = tmp_dir(ctx) / rec["path"]
    probe = ctx.runner.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(raw)])
    try:
        duration = float(json.loads(probe.stdout)["format"]["duration"])
    except (ValueError, KeyError, TypeError):
        raise Fail(EXIT_EVIDENCE, "錄影檔讀不出來（可能沒寫完）", "重新錄一次；確認有 ffmpeg：brew install ffmpeg")
    if not 0 < duration <= MAX_SECONDS + 1:
        raise Fail(EXIT_EVIDENCE, f"錄影長度 {duration:.1f} 秒，要在 {MAX_SECONDS} 秒內", "縮短操作再錄")
    return raw, duration


def finalize_video(ctx: Context, run_id: str, name: str, raw: Path) -> dict:
    """去掉中繼資料存進 run、另產 GIF，登記進 manifest。"""
    folder = run_dir(ctx, run_id)
    final = folder / f"{name}.mp4"
    run_ok(ctx, ["ffmpeg", "-y", "-v", "error", "-i", str(raw), "-map_metadata", "-1", "-c", "copy", "-movflags", "+faststart", str(final)])
    files = [add_file(ctx, run_id, final, "video")]
    gif = folder / f"{name}.gif"
    made = ctx.runner.run(["ffmpeg", "-y", "-v", "error", "-i", str(final), "-vf",
                           "fps=8,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0", str(gif)])
    warning = None
    if made.returncode == 0 and gif.exists() and gif.stat().st_size <= MAX_BYTES:
        files.append(add_file(ctx, run_id, gif, "gif"))
    else:
        gif.unlink(missing_ok=True)
        warning = "GIF 沒有產生（影片仍有效）"
    for leftover in tmp_dir(ctx).glob(f"{run_id}-{name}.*"):
        leftover.unlink(missing_ok=True)
    return {"files": files, "warning": warning}


def cmd_record(ctx: Context, a) -> dict:
    if a.flow:
        from kidsai_flows import record_flow  # 真實點擊的流程（V2）
        return record_flow(ctx, a)
    if a.action not in ("start", "stop") or not a.name:
        raise Fail(EXIT_USAGE, "用 record start|stop --run <id> --name <n>，或 record --flow <流程> --run <id>", "control-kidsai record --help")
    name = check_name(a.name, "name")
    run_dir(ctx, a.run)
    key = f"{a.run}/{name}"
    s = session(ctx)
    recordings = s.setdefault("recordings", {})
    if a.action == "start":
        d = require_device(ctx)
        if key in recordings:
            raise Fail(EXIT_USAGE, f"{key} 已經在錄", f"control-kidsai record stop --run {a.run} --name {name}")
        recordings[key] = start_recording(ctx, a.run, name, d["udid"])
        save_session(ctx, s)
        return {"ok": True, "recording": key, "max_seconds": MAX_SECONDS}
    rec = recordings.pop(key, None)
    if rec is None:
        raise Fail(EXIT_USAGE, f"{key} 沒有在錄", f"control-kidsai record start --run {a.run} --name {name}")
    save_session(ctx, s)
    raw, duration = stop_recording(ctx, rec)
    return {"ok": True, "duration": round(duration, 1), **finalize_video(ctx, a.run, name, raw)}


def stop_process(ctx: Context, rec: dict, sig=signal.SIGINT, group=False) -> bool:
    """只停身分對得上的程序（防 PID 重用）；已經結束也算停好。
    group=True 時停整個程序群組（xcodebuild 由 /bin/sh 包著，用新的 session 啟動）。"""
    pid = rec.get("pid")
    if not pid:
        return True
    current = ps_identity(ctx, pid)
    if current is None:
        return True
    if current != rec.get("identity"):
        return False
    target = -pid if group else pid
    ctx.kill(target, sig)
    for _ in range(40):
        if ps_identity(ctx, pid) is None:
            return True
        ctx.sleep(0.25)
    ctx.kill(target, signal.SIGTERM)
    return False


def cmd_cleanup(ctx: Context, a) -> dict:
    s = session(ctx)
    plan = (["stop xcodebuild"] if s.get("xcodebuild") else []) + [f"stop recording {k}" for k in s.get("recordings", {})]
    plan += ["terminate app"] if s.get("launched") else []
    plan += [f"shutdown {ctx.sim}"] if s.get("booted_by_us") else []
    if a.dry_run:
        return {"ok": True, "dry_run": True, "would": plan, "evidence_kept": ".verify/<run>/"}
    failed, left = [], {}
    if s.get("xcodebuild") and not stop_process(ctx, s["xcodebuild"], group=True):
        failed.append("xcodebuild")
    for key, rec in s.get("recordings", {}).items():
        if stop_process(ctx, rec) and stop_process(ctx, rec.get("watchdog") or {}, sig=signal.SIGTERM):
            continue
        failed.append(f"recording {key}")
        left[key] = rec
    d = find_device(ctx) if (s.get("launched") or s.get("booted_by_us")) else None
    if d and s.get("launched") and d.get("state") == "Booted":
        ctx.runner.run(["xcrun", "simctl", "terminate", d["udid"], BUNDLE_ID])  # 沒在跑也算關好
    still_booted = False
    if d and s.get("booted_by_us") and d.get("state") == "Booted":
        if ctx.runner.run(["xcrun", "simctl", "shutdown", d["udid"]]).returncode != 0:
            failed.append(f"shutdown {ctx.sim}")
            still_booted = True
    if not left:
        for leftover in (verify_dir(ctx) / "_tmp").glob("*"):
            leftover.unlink(missing_ok=True)
    save_session(ctx, {"recordings": left, "booted_by_us": still_booted} if failed else {})
    if failed:
        raise Fail(EXIT_EXTERNAL, f"有東西沒停下來：{', '.join(failed)}（紀錄保留，可再跑 cleanup）；證據仍在 .verify/<run>/",
                   "再跑一次 control-kidsai cleanup；仍失敗就看 ps 與 xcrun simctl list devices")
    return {"ok": True, "done": plan, "evidence_kept": ".verify/<run>/"}


# ---------------------------------------------------------------- 發布

def validate_run(ctx: Context, run_id: str) -> dict:
    folder = run_dir(ctx, run_id)
    manifest_path = folder / "manifest.json"
    if not manifest_path.exists():
        raise Fail(EXIT_EVIDENCE, "沒有 manifest.json", "用 run new 建立 run")
    text = manifest_path.read_text()
    try:
        manifest = json.loads(text)
    except json.JSONDecodeError:
        raise Fail(EXIT_EVIDENCE, "manifest.json 不是合法的 JSON", "不要手改 manifest；重拍")
    if not isinstance(manifest, dict) or set(manifest) != MANIFEST_KEYS:
        raise Fail(EXIT_EVIDENCE, "manifest 欄位不對", "不要手改 manifest；重拍")
    check_manifest_types(manifest)
    if manifest["simulator"] not in SIMS:
        raise Fail(EXIT_EVIDENCE, f"不是專用模擬器拍的：{manifest['simulator']}", "用 KidsAI-Verify 重拍")
    if leaks_in(ctx, text):
        raise Fail(EXIT_EVIDENCE, "manifest 含本機路徑、使用者名稱或裝置 ID", "不要手改 manifest；重拍")
    listed = {f["name"]: f for f in manifest["files"]}
    if len(listed) != len(manifest["files"]):
        raise Fail(EXIT_EVIDENCE, "manifest 裡有重複的檔名", "不要手改 manifest；重拍")
    for item in folder.iterdir():
        if item.is_symlink() or item.is_dir():
            raise Fail(EXIT_EVIDENCE, f"run 目錄不能有子目錄或連結：{item.name}", "只放 CLI 產生的檔")
        if item.name != "manifest.json" and item.name not in listed:
            raise Fail(EXIT_EVIDENCE, f"{item.name} 不是 CLI 產生的（不在 manifest）", "刪掉它或重拍")
    for name, f in listed.items():
        # 只能是單純檔名：不能有斜線、..（防路徑穿越，CRITICAL-17）
        if not FILE_RE.match(name):
            raise Fail(EXIT_EVIDENCE, f"不允許的檔名：{name!r}", "只能是 [a-z0-9-] 加 .png／.gif／.mp4")
        path = folder / name
        if path.resolve().parent != folder.resolve() or not path.is_file() or path.is_symlink():
            raise Fail(EXIT_EVIDENCE, f"{name} 不在 run 目錄裡", "不要手改 manifest；重拍")
        if path.stat().st_size > MAX_BYTES or path.stat().st_size != f["bytes"]:
            raise Fail(EXIT_EVIDENCE, f"{name} 超過 10 MB 或大小和 manifest 不符", "縮短錄影或重拍")
        if sha256_file(path) != f["sha256"]:
            raise Fail(EXIT_EVIDENCE, f"{name} 的 sha256 和 manifest 不符", "不要改動證據檔；重拍")
        if name.endswith(".json") and (f["kind"] != "a11y" or leaks_in(ctx, path.read_text(errors="replace"))):
            raise Fail(EXIT_EVIDENCE, f"{name} 不是無障礙元素樹，或含本機路徑、使用者名稱、裝置 ID", "重跑 snapshot")
    check_review(manifest, run_id)
    return manifest


def leaks_in(ctx: Context, text: str) -> bool:
    """文字裡有本機路徑、使用者名稱或裝置 ID。"""
    return any(s and s in text for s in (str(ctx.home), str(ctx.repo), "/Users/", ctx.user)) or bool(UUID_RE.search(text))


def check_manifest_types(manifest: dict) -> None:
    ok = (isinstance(manifest["sha"], str) and re.fullmatch(r"[0-9a-f]{40}", manifest["sha"])
          and isinstance(manifest["dirty"], bool)
          and all(isinstance(manifest[k], str) for k in ("device", "runtime", "simulator", "feature", "entry", "captured_at"))
          and NAME_RE.match(manifest["feature"]) and NAME_RE.match(manifest["entry"])
          and isinstance(manifest["files"], list)
          and all(isinstance(f, dict) and set(f) == {"name", "sha256", "bytes", "kind"} and isinstance(f["name"], str)
                  and isinstance(f["sha256"], str) and isinstance(f["bytes"], int) and f["kind"] in KINDS
                  for f in manifest["files"])
          and (manifest["visual_review"] is None or isinstance(manifest["visual_review"], dict)))
    if not ok:
        raise Fail(EXIT_EVIDENCE, "manifest 的欄位型別不對", "不要手改 manifest；重拍")


def check_review(manifest: dict, run_id: str) -> None:
    """畫面審查要逐檔對得上（CRITICAL-18）：每張截圖、GIF 都審過且之後沒被換；每支影片都抽格審過且是同一支。"""
    fix = f"evidence frames --run {run_id}，逐張看過後 evidence review --run {run_id} --ok"
    review = manifest["visual_review"]
    if not review or review.get("ok") is not True:
        raise Fail(EXIT_EVIDENCE, "還沒有做畫面內容審查", fix)
    items = {i.get("name"): i.get("sha256") for i in review.get("items", []) if isinstance(i, dict)}
    videos = review.get("videos") if isinstance(review.get("videos"), dict) else {}
    for f in manifest["files"]:
        if f["kind"] == "video":
            entry = videos.get(f["name"]) or {}
            if entry.get("sha256") != f["sha256"] or not entry.get("frames"):
                raise Fail(EXIT_EVIDENCE, f"{f['name']} 沒有抽格審查，或審查後影片換過", fix)
        elif items.get(f["name"]) != f["sha256"]:
            raise Fail(EXIT_EVIDENCE, f"{f['name']} 沒有審查，或審查後被換過", fix)


def markdown(manifest: dict, pr: int, run_id: str) -> str:
    base = f"{RAW_BASE}/pr-{pr}/{run_id}"
    lines = [f"**{manifest['feature']}**（進入點：`{manifest['entry']}`）— run `{run_id}`，commit `{manifest['sha'][:7]}`，"
             f"{manifest['device']}／{manifest['runtime']}", ""]
    for f in manifest["files"]:
        if f["kind"] in ("screenshot", "gif"):
            lines.append(f"![{f['name']}]({base}/{f['name']})")
    lines += [f"- 影片：[{f['name']}]({base}/{f['name']})" for f in manifest["files"] if f["kind"] == "video"]
    lines.append(f"- [manifest.json]({base}/manifest.json)")
    return "\n".join(lines)


def git_auth(ctx: Context) -> list:
    """只用 Mac 既有的 gh 登入推送；CLI 不讀取、不保存 token。沒有 gh 就拒絕，不退回其他 credential helper。"""
    if not ctx.which("gh") or ctx.runner.run(["gh", "auth", "status"]).returncode != 0:
        raise Fail(EXIT_ENV, "需要已登入的 gh 才能發布", "brew install gh && gh auth login")
    return ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"]


def cmd_evidence(ctx: Context, a) -> dict:
    run_id = a.run or latest_run(ctx)
    if a.action == "frames":
        folder = run_dir(ctx, run_id)
        out = verify_dir(ctx) / "_frames" / run_id
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("*"):
            old.unlink()
        index, frames = {}, []
        for video in sorted(folder.glob("*.mp4")):
            run_ok(ctx, ["ffmpeg", "-y", "-v", "error", "-i", str(video), "-vf", "fps=1/2", str(out / f"{video.stem}-%02d.png")])
            names = sorted(p.name for p in out.glob(f"{video.stem}-*.png"))
            index[video.name] = {"sha256": sha256_file(video), "frames": names}
            frames += [f".verify/_frames/{run_id}/{n}" for n in names]
        write_json(out / "frames.json", index)
        return {"ok": True, "frames": frames, "images": [f".verify/{run_id}/{p.name}" for p in sorted(folder.glob("*.png")) + sorted(folder.glob("*.gif"))]}
    if a.action == "review":
        if not a.ok:
            raise Fail(EXIT_USAGE, "只有逐張看過、確認畫面只有 KidsAI 或專用模擬器的主畫面（沒有通知、沒有其他 App 內容）才能加 --ok",
                       f"control-kidsai evidence review --run {run_id} --ok")
        folder = run_dir(ctx, run_id)
        frames_dir = verify_dir(ctx) / "_frames" / run_id
        index = read_json(frames_dir / "frames.json", {}) or {}
        manifest = read_json(folder / "manifest.json")
        videos = {}
        for f in manifest["files"]:
            if f["kind"] != "video":
                continue
            entry = index.get(f["name"]) or {}
            if entry.get("sha256") != sha256_file(folder / f["name"]) or not entry.get("frames"):
                raise Fail(EXIT_EVIDENCE, f"{f['name']} 還沒抽格（或抽格後影片換過）", f"control-kidsai evidence frames --run {run_id}，逐張看過再 review")
            videos[f["name"]] = {"sha256": entry["sha256"], "frames": len(entry["frames"])}
        items = [{"name": f["name"], "sha256": sha256_file(folder / f["name"])} for f in manifest["files"] if f["kind"] != "video"]
        count = len(items) + sum(v["frames"] for v in videos.values())
        manifest["visual_review"] = {"ok": True, "images_checked": count, "items": items, "videos": videos,
                                     "reviewed_at": ctx.now().isoformat()}
        write_json(folder / "manifest.json", manifest)
        return {"ok": True, "images_checked": count}
    manifest = validate_run(ctx, run_id) if a.action == "publish" else read_json(run_dir(ctx, run_id) / "manifest.json")
    md = markdown(manifest, a.pr, run_id)
    if a.action == "md":
        return {"ok": True, "markdown": md}
    dest = f"pr-{a.pr}/{run_id}"
    files = ["manifest.json"] + [f["name"] for f in manifest["files"]]
    cache = cache_dir(ctx)
    if (cache / dest).exists():  # 唯讀檢查（dry-run 也做；本機有副本時）
        raise Fail(EXIT_EVIDENCE, f"{dest} 已經存在，不覆寫", "用新的 run 重拍")
    if a.dry_run:
        return {"ok": True, "dry_run": True, "dest": dest, "files": files,
                "would": [f"git clone/pull {EVIDENCE_REPO_URL}", f"copy {len(files)} files → {dest}", "git commit", "git push"],
                "markdown": md}
    auth = git_auth(ctx)
    if not (cache / ".git").exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        run_ok(ctx, ["git", *auth, "clone", "--quiet", EVIDENCE_REPO_URL, str(cache)], fix="確認 gh auth status 已登入")
    run_ok(ctx, ["git", "-C", str(cache), *auth, "pull", "--ff-only", "--quiet"])
    if (cache / dest).exists():
        raise Fail(EXIT_EVIDENCE, f"{dest} 已經存在，不覆寫", "用新的 run 重拍")
    (cache / dest).mkdir(parents=True)
    for name in files:
        shutil.copy2(run_dir(ctx, run_id) / name, cache / dest / name)
    run_ok(ctx, ["git", "-C", str(cache), "add", dest])
    run_ok(ctx, ["git", "-C", str(cache), "commit", "--quiet", "-m", f"evidence: pr-{a.pr} {run_id}"])
    if ctx.runner.run(["git", "-C", str(cache), *auth, "push", "--quiet"]).returncode != 0:
        run_ok(ctx, ["git", "-C", str(cache), *auth, "fetch", "--quiet", "origin"])
        if git_in(ctx, cache, "ls-tree", "-r", "--name-only", "origin/main", "--", dest):
            raise Fail(EXIT_EVIDENCE, f"遠端已經有 {dest}，不覆寫", "停下來問 Michael；本機副本可用 git reset --hard origin/main 還原")
        run_ok(ctx, ["git", "-C", str(cache), *auth, "pull", "--rebase", "--quiet"], fix="遠端有衝突：停下來，不要覆寫別人的證據")
        run_ok(ctx, ["git", "-C", str(cache), *auth, "push", "--quiet"])
    commit = git_in(ctx, cache, "rev-parse", "--short", "HEAD")
    return {"ok": True, "published": dest, "commit": commit, "markdown": md}


def git_in(ctx: Context, repo: Path, *args) -> str:
    return run_ok(ctx, ["git", "-C", str(repo), *args]).stdout.strip()


def latest_run(ctx: Context) -> str:
    runs = sorted(p.name for p in verify_dir(ctx).glob("2*") if p.is_dir()) if verify_dir(ctx).exists() else []
    if not runs:
        raise Fail(EXIT_USAGE, "還沒有任何 run", "control-kidsai run new --feature <id> --entry <entry>")
    return runs[-1]


