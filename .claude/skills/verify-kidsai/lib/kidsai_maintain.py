"""control-kidsai maintain：每天自動跑 /maintain-verification-skill（驗證層 V4）。

每日流程由 wrapper（本模組）控制：鎖 → 專用 clone → 無頭 Claude Code → 範圍防護與洩漏掃描 → push 與 draft PR → log、通知。
agent 只在專用 clone 裡改文件（SKILL.md、references/）並 commit；harness（control-kidsai、lib/、maintain/、tests/）
不能改，否則它能先拿掉防護再執行。push、開 PR、查 PR 只有 wrapper 做，而且要先通過防護（不依賴模型守規矩）。
每日維護不發布證據（D-V4b）：agent 的環境有 KIDSAI_MAINTAIN_AGENT=1，control-kidsai 會拒絕 evidence publish、
maintain 與其他模擬器。
"""

import plistlib

from kidsai_core import *  # noqa: F401,F403
from kidsai_core import Context, Fail  # 型別註記用
from kidsai_evidence import leaks_in

LABEL = "com.godmosword.kidsai.maintain-verify"
SKILL_PREFIX = ".claude/skills/verify-kidsai/"
AGENT_EDITABLE = (SKILL_PREFIX + "SKILL.md", SKILL_PREFIX + "references/")  # 檔案或資料夾字首
MAINTAIN_SIM = "KidsAI-Maintain"
DEFAULT_REF = "origin/main"
AGENT_TIMEOUT = 90 * 60
LOCK_STALE = datetime.timedelta(hours=3)
KEEP_LOG_DAYS = 30
KEEP_HISTORY = 30
FLAG_AFTER_BLOCKED_DAYS = 3
NOTES_REL = Path(".verify/maintain-notes.md")
SECRET_RE = re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}"
                       r"|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----")
PROMPT = """/maintain-verification-skill 目標：.claude/skills/verify-kidsai（KidsAI 的驗證 skill）。
規則（每日自動維護，沒有人在旁邊）：
1. 只改 .claude/skills/verify-kidsai/SKILL.md 與 references/ 底下的文件。harness（control-kidsai、lib/、maintain/、tests/）
   有問題、或產品壞掉，都只寫進 run notes，不要改（改了這次會被丟掉）；也不改 app/、content/。
2. control-kidsai 已設定用模擬器 KidsAI-Maintain；不要用別台。一律寫完整路徑 .claude/skills/verify-kidsai/control-kidsai，不要用變數（權限只認這個寫法）。
3. 有修正就 git add 那些檔案並 git commit（訊息用 docs: 或 fix: 開頭，繁體中文）。不要 push、不要開 PR、不要發布證據、不要合併。
4. 結束前把 run notes 寫到 .verify/maintain-notes.md，不要 commit。第一行只能是 `outcome: clean`、`outcome: changed`
   或 `outcome: blocked: <原因>`；接著列：涵蓋的功能、到不了的功能與前提、確認的 drift、發現的產品問題（沒有就寫無）。
5. run notes 與 commit 內容不得有本機路徑、使用者名稱、裝置 ID 或任何金鑰。"""


def maintain_root(ctx: Context) -> Path:
    return ctx.home / "kidsai-maintain"


def clone_dir(ctx: Context) -> Path:
    return maintain_root(ctx) / "project-kid-ai"


def log_dir(ctx: Context) -> Path:
    return ctx.home / "Library/Logs/kidsai-maintain"


def plist_path(ctx: Context) -> Path:
    return ctx.home / "Library/LaunchAgents" / f"{LABEL}.plist"


def bootstrap_path(ctx: Context) -> Path:
    return maintain_root(ctx) / "bin" / "run-daily.sh"


def tool_exists(path: Optional[str]) -> bool:
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def cmd_maintain(ctx: Context, a) -> dict:
    return {"install": maintain_install, "uninstall": maintain_uninstall, "status": maintain_status,
            "run": maintain_run}[a.action](ctx, a)


# ---------------------------------------------------------------- 安裝

def launch_agent(ctx: Context, tools: dict, a) -> dict:
    folders = [str(Path(tool).parent) for tool in tools.values()] + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    env = {"PATH": ":".join(dict.fromkeys(folders)), "HOME": str(ctx.home),
           "KIDSAI_PYTHON": tools["python3"], "KIDSAI_MAINTAIN_REF": a.ref or DEFAULT_REF}
    if a.no_push:
        env["KIDSAI_MAINTAIN_NO_PUSH"] = "1"
    logs = log_dir(ctx)
    return {"Label": LABEL, "ProgramArguments": ["/bin/bash", str(bootstrap_path(ctx))],
            "StartCalendarInterval": {"Hour": 3, "Minute": 17}, "EnvironmentVariables": env, "ProcessType": "Background",
            "StandardOutPath": str(logs / "launchd.out.log"), "StandardErrorPath": str(logs / "launchd.err.log")}


def maintain_install(ctx: Context, a) -> dict:
    tools = {name: ctx.which(name) for name in ("claude", "gh", "git", "python3")}
    missing = [name for name, path in tools.items() if not path]
    if missing:
        raise Fail(EXIT_ENV, f"找不到 {', '.join(missing)}", "確認 claude、gh、git、python3 都在 PATH 裡，再重跑 maintain install")
    source = ctx.repo / SKILL_PREFIX / "maintain" / "run-daily.sh"
    if not source.is_file():
        raise Fail(EXIT_ENV, "找不到 maintain/run-daily.sh", "在 repo 根目錄執行")
    plist = plistlib.dumps(launch_agent(ctx, tools, a)).decode()
    config = {"claude": tools["claude"], "gh": tools["gh"], "python": tools["python3"]}
    result = {"ok": True, "plist_path": str(plist_path(ctx)), "plist": plist, "bootstrap_path": str(bootstrap_path(ctx)),
              "config": config, "schedule": "每天 03:17（Mac 睡著時，醒來後補跑一次）"}
    if a.dry_run:
        return {**result, "dry_run": True}
    for folder in (plist_path(ctx).parent, bootstrap_path(ctx).parent, log_dir(ctx)):
        folder.mkdir(parents=True, exist_ok=True)
    write_json(maintain_root(ctx) / "config.json", config)
    shutil.copyfile(source, bootstrap_path(ctx))
    bootstrap_path(ctx).chmod(0o755)
    plist_path(ctx).write_text(plist)
    domain = f"gui/{os.getuid()}"
    ctx.runner.run(["launchctl", "bootout", f"{domain}/{LABEL}"])  # 重裝：先卸下舊的（沒有也沒關係）
    run_ok(ctx, ["launchctl", "bootstrap", domain, str(plist_path(ctx))], fix="launchctl print gui/$(id -u) 查看")
    return result


def maintain_uninstall(ctx: Context, a) -> dict:
    files = [str(p) for p in (plist_path(ctx), bootstrap_path(ctx)) if p.exists()]
    kept = [str(clone_dir(ctx)), str(log_dir(ctx))]
    if a.dry_run:
        return {"ok": True, "dry_run": True, "would_remove": files, "kept": kept}
    ctx.runner.run(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"])
    for path in (plist_path(ctx), bootstrap_path(ctx)):
        if path.exists():
            path.unlink()
    return {"ok": True, "removed": files, "kept": kept}


def maintain_status(ctx: Context, a) -> dict:
    installed = plist_path(ctx).exists()
    loaded = installed and ctx.runner.run(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"]).returncode == 0
    state = load_state(ctx)
    return {"ok": True, "installed": installed, "loaded": loaded, "schedule": "每天 03:17",
            "recent": state["history"][-5:], "consecutive_blocked": state["consecutive_blocked"]}


# ---------------------------------------------------------------- 每日流程

def maintain_run(ctx: Context, a) -> dict:
    date = ctx.now().strftime("%Y-%m-%d")
    no_push = a.no_push or os.environ.get("KIDSAI_MAINTAIN_NO_PUSH") == "1"
    if not acquire_lock(ctx):
        result = {"outcome": "skip", "reason": "另一次每日維護還在跑", "pr": None}
    else:
        try:
            result = daily(ctx, a.ref or DEFAULT_REF, f"maintain/verify-kidsai-{date}", no_push)
        finally:
            shutdown_sim(ctx)
            release_lock(ctx)
    return record(ctx, date, result)


def daily(ctx: Context, ref: str, branch: str, no_push: bool) -> dict:
    clone = clone_dir(ctx)
    if not (clone / ".git").exists():
        return blocked("沒有專用 clone（run-daily.sh 會建立）")
    for args in (["fetch", "-q", "origin"], ["checkout", "-q", "-f", "-B", branch, ref], ["reset", "-q", "--hard", ref],
                 ["clean", "-q", "-fdx", "-e", ".verify/"]):
        if gitc(ctx, *args).returncode != 0:
            return blocked(f"準備專用 clone 失敗：git {args[0]}")
    if dirty_paths(ctx):
        return blocked("專用 clone 清不乾淨")
    base = gitc(ctx, "rev-parse", "HEAD").stdout.strip()
    notes_file = clone / NOTES_REL
    if notes_file.exists():
        notes_file.unlink()
    outcome = run_agent(ctx, clone)
    if outcome is None:
        outcome = judge(ctx, base, notes_file.read_text() if notes_file.exists() else None, branch, no_push)
    if outcome["outcome"] == "blocked":
        drop_branch(ctx, base, branch)
    return outcome


def run_agent(ctx: Context, clone: Path) -> Optional[dict]:
    """跑無頭 Claude Code；失敗就回傳 blocked，成功回傳 None。"""
    config = read_json(maintain_root(ctx) / "config.json", {}) or {}
    claude = config.get("claude")
    if not tool_exists(claude):
        return blocked("找不到 claude（Node 升級後路徑會變；重跑 control-kidsai maintain install）")
    settings = clone / SKILL_PREFIX / "maintain" / "maintain-settings.json"
    if not settings.is_file():
        return blocked("找不到 maintain-settings.json，不在沒有權限設定的情況下跑 claude")
    log_dir(ctx).mkdir(parents=True, exist_ok=True)
    log = log_dir(ctx) / f"{ctx.now().strftime('%Y-%m-%d')}.claude.log"
    code = ctx.runner.run_logged([claude, "-p", PROMPT, "--settings", str(settings), "--permission-mode", "default"],
                                 log, cwd=str(clone), env={"KIDSAI_SIM": MAINTAIN_SIM, "KIDSAI_MAINTAIN_AGENT": "1"},
                                 timeout=AGENT_TIMEOUT)
    if code is None:
        return blocked("claude timeout（90 分鐘）")
    if code != 0:
        return blocked(f"claude 非 0 結束（{code}）")
    return None


def judge(ctx: Context, base: str, notes: Optional[str], branch: str, no_push: bool) -> dict:
    """依 git 狀態與 run notes 判定結果；兩者矛盾一律 blocked。"""
    violations = scope_violations(ctx, base)
    if violations:
        return blocked("scope violation：" + "；".join(violations[:5]))
    if notes is None:
        return blocked("run notes 缺漏")
    declared = notes.strip().splitlines()[0].strip() if notes.strip() else ""
    commits = int(gitc(ctx, "rev-list", "--count", f"{base}..HEAD").stdout.strip() or 0)
    if declared.startswith("outcome: blocked"):
        return blocked("agent 回報 blocked：" + declared.partition("blocked")[2].lstrip(": ").strip(), notes)
    if declared == "outcome: clean":
        return blocked("run notes 說 clean，但有 commit", notes) if commits else {"outcome": "clean", "reason": "", "pr": None,
                                                                                    "notes": notes}
    if declared != "outcome: changed":
        return blocked("run notes 第一行看不懂", notes)
    if not commits:
        return blocked("run notes 說 changed，但沒有 commit", notes)
    binary = [line.split("\t", 2)[2] for line in gitc(ctx, "diff", "--numstat", base, "HEAD").stdout.splitlines()
              if line.startswith("-\t-\t")]
    if binary:
        return blocked(f"binary 檔掃描不了內容，不自動 push：{binary[0]}", notes)
    leak = leak_in_diff(ctx, base)
    if leak:
        return blocked(f"leak：要 push 的內容有{leak}", notes)
    return ship(ctx, branch, notes, no_push)


def scope_violations(ctx: Context, base: str) -> list:
    """base 到 HEAD 的每個 commit 改動（含刪除、rename 前後路徑、symlink），加上 index、工作樹、未追蹤檔。"""
    problems = []
    raw = gitc(ctx, "diff", "--raw", "-M", "--no-abbrev", "-z", base, "HEAD").stdout.split("\0")
    i = 0
    while i < len(raw) and raw[i].startswith(":"):
        meta = raw[i][1:].split()
        paths = raw[i + 1:i + 3] if meta[4][0] in "RC" else raw[i + 1:i + 2]
        i += 1 + len(paths)
        if meta[1] == "120000":
            problems.append(f"symlink {paths[-1]}")
        problems += [f"改到 {p}" for p in paths if not agent_editable(p)]
    problems += [f"沒 commit 的 {p}" for p in dirty_paths(ctx)]
    return problems


def agent_editable(path: str) -> bool:
    return path == AGENT_EDITABLE[0] or path.startswith(AGENT_EDITABLE[1])


def dirty_paths(ctx: Context) -> list:
    out = gitc(ctx, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout
    return [entry[3:] for entry in out.split("\0") if len(entry) > 3]


def leak_in_diff(ctx: Context, base: str) -> str:
    added = "\n".join(line[1:] for line in gitc(ctx, "diff", base, "HEAD").stdout.splitlines()
                      if line.startswith("+") and not line.startswith("+++"))
    if SECRET_RE.search(added):
        return "金鑰樣式"
    if leaks_in(ctx, added):
        return "本機路徑、使用者名稱或裝置 ID"
    return ""


def ship(ctx: Context, branch: str, notes: str, no_push: bool) -> dict:
    """changed：push 分支並開 draft PR（只有 wrapper 做）。已有未合併的 maintain PR 或查不到時不開新 PR。"""
    result = {"outcome": "changed", "reason": "", "pr": None, "notes": notes}
    if no_push:
        return {**result, "reason": "--no-push：只留本機分支"}
    config = read_json(maintain_root(ctx) / "config.json", {}) or {}
    gh = config.get("gh") or "gh"
    listed = ctx.runner.run([gh, "pr", "list", "--state", "open", "--json", "headRefName", "--limit", "100"], cwd=str(clone_dir(ctx)))
    try:
        open_maintain = [p["headRefName"] for p in json.loads(listed.stdout) if p["headRefName"].startswith("maintain/")]
    except (ValueError, KeyError, TypeError):
        open_maintain = None
    if listed.returncode != 0 or open_maintain is None:
        return {**result, "reason": "查不到 PR 狀態，這次不開 PR（分支留在本機）"}
    if open_maintain:
        return {**result, "reason": f"已有未合併的 maintain PR（{open_maintain[0]}），這次不開新 PR"}
    auth = ["-c", "credential.helper=", "-c", f"credential.helper=!{gh} auth git-credential"]
    if gitc(ctx, *auth, "push", "-q", "-u", "origin", branch).returncode != 0:
        return blocked("push 失敗", notes)
    body = maintain_root(ctx) / "pr-body.md"
    text = "每日自動維護（`/maintain-verification-skill`）找到的修正，只改 `.claude/skills/verify-kidsai/`。\n\n## run notes\n\n" + notes
    if leaks_in(ctx, text) or SECRET_RE.search(text):
        text = "每日自動維護找到的修正。run notes 含本機資訊，只留在 Mac 的 log。"
    body.write_text(text)
    created = ctx.runner.run([gh, "pr", "create", "--draft", "--base", "main", "--head", branch,
                              "--title", f"chore(verify): 每日維護 {branch.removeprefix('maintain/verify-kidsai-')}", "--body-file", str(body)], cwd=str(clone_dir(ctx)))
    if created.returncode != 0:
        return blocked(f"分支 {branch} 已 push，但開 PR 失敗，請手動開 PR 或刪掉遠端分支", notes)
    return {**result, "pr": created.stdout.strip().splitlines()[-1]}


def blocked(reason: str, notes: Optional[str] = None) -> dict:
    return {"outcome": "blocked", "reason": reason, "pr": None, "notes": notes}


def drop_branch(ctx: Context, base: str, branch: str) -> None:
    """blocked：丟掉這次的改動與本機分支，專用 clone 回到乾淨狀態（證據 .verify/ 保留）。"""
    for args in (["checkout", "-q", "-f", "--detach", base], ["branch", "-q", "-D", branch],
                 ["clean", "-q", "-fdx", "-e", ".verify/"]):
        gitc(ctx, *args)


def gitc(ctx: Context, *args) -> Result:
    return ctx.runner.run(["git", "-C", str(clone_dir(ctx)), *args])


def shutdown_sim(ctx: Context) -> None:
    cli = clone_dir(ctx) / SKILL_PREFIX / "control-kidsai"
    ctx.runner.run([sys.executable, str(cli), "--sim", MAINTAIN_SIM, "sim", "shutdown"])


# ---------------------------------------------------------------- 鎖、紀錄、通知

def lock_dir(ctx: Context) -> Path:
    return maintain_root(ctx) / ".lock"


def acquire_lock(ctx: Context) -> bool:
    lock = lock_dir(ctx)
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        lock.mkdir()
    except FileExistsError:
        try:
            owner = read_json(lock / "owner.json", {}) or {}
            started = datetime.datetime.fromisoformat(owner["started"])
            busy = pid_alive(ctx, owner.get("pid")) and ctx.now() - started < LOCK_STALE
        except (ValueError, TypeError, KeyError, AttributeError):
            busy = False  # 鎖檔壞了：當成上次中斷留下的
        if busy:
            return False
        shutil.rmtree(lock)  # 上次當掉或被中斷留下的鎖
        lock.mkdir()
    write_json(lock / "owner.json", {"pid": os.getpid(), "started": ctx.now().isoformat()})
    return True


def release_lock(ctx: Context) -> None:
    shutil.rmtree(lock_dir(ctx), ignore_errors=True)


def pid_alive(ctx: Context, pid) -> bool:
    if not isinstance(pid, int):
        return False
    try:
        ctx.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def load_state(ctx: Context) -> dict:
    state = read_json(maintain_root(ctx) / "state.json", {}) or {}
    return {"history": state.get("history", []), "consecutive_blocked": state.get("consecutive_blocked", 0)}


def record(ctx: Context, date: str, result: dict) -> dict:
    """寫 state、log（保留 30 天）與通知；回傳給 CLI 的結果（blocked 結束碼 5）。"""
    state = load_state(ctx)
    if result["outcome"] == "blocked":
        state["consecutive_blocked"] += 1
    elif result["outcome"] in ("clean", "changed"):
        state["consecutive_blocked"] = 0
    entry = {"date": date, "at": ctx.now().isoformat(), "outcome": result["outcome"], "reason": result["reason"], "pr": result["pr"]}
    state["history"] = (state["history"] + [entry])[-KEEP_HISTORY:]
    write_json(maintain_root(ctx) / "state.json", state)
    logs = log_dir(ctx)
    logs.mkdir(parents=True, exist_ok=True)
    with open(logs / f"{date}.log", "a") as log:
        log.write(json.dumps(entry, ensure_ascii=False) + "\n" + (result.get("notes") or "") + "\n")
    prune_logs(ctx, logs)
    notify(ctx, result, state["consecutive_blocked"])
    out = {"ok": result["outcome"] != "blocked", **{k: v for k, v in result.items() if k != "notes"},
           "consecutive_blocked": state["consecutive_blocked"], "log": str(logs / f"{date}.log")}
    if result["outcome"] == "blocked":
        out["exit"] = EXIT_EXTERNAL
    return out


def prune_logs(ctx: Context, logs: Path) -> None:
    cutoff = (ctx.now() - datetime.timedelta(days=KEEP_LOG_DAYS)).strftime("%Y-%m-%d")
    for path in logs.glob("????-??-??*.log"):
        if path.name[:10] < cutoff:
            path.unlink()


def notify(ctx: Context, result: dict, streak: int) -> None:
    if result["outcome"] == "blocked":
        message = f"blocked：{result['reason']}"
        if streak >= FLAG_AFTER_BLOCKED_DAYS:
            message = f"⚠️ 已連續 {streak} 天 blocked｜{message}"
    elif result["outcome"] == "changed":
        message = f"有修正：{result['pr'] or result['reason']}"
    else:
        return
    text = json.dumps(message.replace("\n", " "), ensure_ascii=False)
    ctx.runner.run(["osascript", "-e", f'display notification {text} with title "KidsAI 每日維護"'])
