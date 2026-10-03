"""control-kidsai maintain：每天自動跑 /maintain-verification-skill（驗證層 V4）。

每日流程由 wrapper（本模組）控制：鎖 → 專用 clone → 無頭 Claude Code → 範圍防護與洩漏掃描 → push 與 draft PR → log、通知。
agent 不直接改檔、也不 commit：Claude Code 在無頭模式下不准改 .claude/ 底下的檔案（allow 規則與 acceptEdits 都放不過，
2026-09-29 實測），所以 agent 把改好的完整檔案寫到 .verify/maintain-proposed/<相對於 skill 目錄的路徑>，
由 wrapper 檢查（只准 SKILL.md 與 references/**/*.md、純文字、洩漏掃描）後套用並 commit。
harness（control-kidsai、lib/、maintain/、tests/）不能提案，否則 agent 能改掉防護。push、開 PR、查 PR 只有 wrapper 做。
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
PROPOSED_REL = Path(".verify/maintain-proposed")
MAX_PROPOSAL_BYTES = 200 * 1024
SECRET_RE = re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}"
                       r"|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----")
PROMPT = """/maintain-verification-skill 目標：.claude/skills/verify-kidsai（KidsAI 的驗證 skill）。
規則（每日自動維護，沒有人在旁邊）：
1. 只改 .claude/skills/verify-kidsai/SKILL.md 與 references/ 底下的 .md 文件。harness（control-kidsai、lib/、maintain/、tests/）
   有問題、或產品壞掉，都只寫進 run notes，不要改（改了這次會被丟掉）；也不改 app/、content/。
2. control-kidsai 已設定用模擬器 KidsAI-Maintain；不要用別台。一律寫完整路徑 .claude/skills/verify-kidsai/control-kidsai，不要用變數（權限只認這個寫法）。
3. 不要直接改檔、不要 git add／commit（.claude/ 在這個模式下改不了）。有修正就把改好的「完整檔案」寫到
   .verify/maintain-proposed/<相對於 .claude/skills/verify-kidsai/ 的路徑>，例如
   .verify/maintain-proposed/references/features/unit-flow.md；wrapper 會檢查後套用並 commit。
   不要 push、不要開 PR、不要發布證據、不要合併。control-kidsai 的 fix 若寫 --sim，照做時去掉 --sim（已預設 KidsAI-Maintain）；
   run new 等命令的輸出是 JSON，直接讀，不要用 python 解析。
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
    identity = {key: ctx.runner.run(["git", "-C", str(ctx.repo), "config", f"user.{key}"]).stdout.strip() for key in ("name", "email")}
    config = {"claude": tools["claude"], "gh": tools["gh"], "python": tools["python3"],
              "git_name": identity["name"], "git_email": identity["email"]}  # 每日 PR 的 commit 作者＝這個 repo 設好的身分
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

class Interrupted(Exception):
    """收到系統的結束訊號（SIGTERM／SIGHUP）：照樣收尾，這一輪記成 blocked。"""


TERMINATION_SIGNALS = (signal.SIGTERM, signal.SIGHUP)


def raise_interrupted(signum, frame):
    raise Interrupted(signal.Signals(signum).name)


def set_termination_handler(handler) -> dict:
    """換掉結束訊號的處理方式，回傳原本的（只有主執行緒能換；換不了就什麼都不做）。"""
    previous = {}
    for sig in TERMINATION_SIGNALS:
        try:
            previous[sig] = signal.signal(sig, handler)
        except ValueError:
            break
    return previous


def maintain_run(ctx: Context, a) -> dict:
    date = ctx.now().strftime("%Y-%m-%d")
    no_push = a.no_push or os.environ.get("KIDSAI_MAINTAIN_NO_PUSH") == "1"
    acquired, stale = acquire_lock(ctx)
    if stale is not None:
        record_interrupted(ctx, date, stale)
    if not acquired:
        result = {"outcome": "skip", "reason": "另一次每日維護還在跑", "pr": None}
    else:
        previous = set_termination_handler(raise_interrupted)
        try:
            result = daily(ctx, a.ref or DEFAULT_REF, f"maintain/verify-kidsai-{date}", no_push)
        except Interrupted as signal_name:
            result = blocked(f"這次每日維護被系統中斷（{signal_name}）")
        finally:
            set_termination_handler(signal.SIG_IGN)  # 收尾時再收到結束訊號也要把鎖放掉
            try:
                shutdown_sim(ctx)
                release_lock(ctx)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
    return record(ctx, date, result)


def record_interrupted(ctx: Context, today: str, stale: dict) -> None:
    """上一輪沒有跑完（被強制結束、關機或當機，連收尾都沒做）：補一筆 blocked 並通知。"""
    started = stale.get("started")
    try:
        date = datetime.datetime.fromisoformat(started).strftime("%Y-%m-%d")
    except (TypeError, ValueError):
        date, started = today, "時間不明"
    record(ctx, date, blocked(f"上一次每日維護（{started}）沒有跑完就中斷了：可能被系統結束、強制關機或當機"))


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
    config = read_json(maintain_root(ctx) / "config.json", {}) or {}
    for key in ("name", "email"):
        if config.get(f"git_{key}"):
            gitc(ctx, "config", f"user.{key}", config[f"git_{key}"])
    base = gitc(ctx, "rev-parse", "HEAD").stdout.strip()
    notes_file = clone / NOTES_REL
    if notes_file.exists():
        notes_file.unlink()
    shutil.rmtree(clone / PROPOSED_REL, ignore_errors=True)
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
    log = log_dir(ctx) / f"{ctx.now().strftime('%Y-%m-%d-%H%M%S')}.claude.log"  # 每次一個檔，同一天多跑不覆蓋
    code = ctx.runner.run_logged([claude, "-p", PROMPT, "--settings", str(settings), "--permission-mode", "default"],
                                 log, cwd=str(clone), env={"KIDSAI_SIM": MAINTAIN_SIM, "KIDSAI_MAINTAIN_AGENT": "1"},
                                 timeout=AGENT_TIMEOUT)
    if code is None:
        return blocked("claude timeout（90 分鐘）")
    if code != 0:
        last = next((line.strip() for line in reversed(log.read_text(errors="replace").splitlines()) if line.strip()), "") if log.exists() else ""
        if leaks_in(ctx, last) or SECRET_RE.search(last):  # 截短前就檢查；reason 會進 state.json、每日 log 與 macOS 通知
            last = "最後一行含本機資訊或金鑰樣式，已略去；見 claude log"
        last = last[:120]
        return blocked(f"claude 非 0 結束（{code}）：{last}")  # 例如額度用完：You've hit your session limit
    return None


def judge(ctx: Context, base: str, notes: Optional[str], branch: str, no_push: bool) -> dict:
    """依 git 狀態、提案與 run notes 判定結果；三者矛盾一律 blocked。"""
    violations = agent_git_changes(ctx, base)
    if violations:
        return blocked("scope violation：" + "；".join(violations[:5]))
    if notes is None:
        return blocked("run notes 缺漏")
    proposals, problems = read_proposals(ctx)
    if problems:
        return blocked("；".join(problems[:5]), notes)
    declared = notes.strip().splitlines()[0].strip() if notes.strip() else ""
    if declared.startswith("outcome: blocked"):
        return blocked("agent 回報 blocked：" + declared.partition("blocked")[2].lstrip(": ").strip(), notes)
    if declared == "outcome: clean":
        return blocked("run notes 說 clean，但有提案", notes) if proposals else {"outcome": "clean", "reason": "", "pr": None,
                                                                                    "notes": notes}
    if declared != "outcome: changed":
        return blocked("run notes 第一行看不懂", notes)
    if not proposals:
        return blocked("run notes 說 changed，但沒有提案", notes)
    problem = apply_proposals(ctx, proposals, branch, base)
    if problem:
        return blocked(problem, notes)
    violations = scope_violations(ctx, base)  # wrapper 自己的 commit 再檢查一次
    if violations:
        return blocked("scope violation：" + "；".join(violations[:5]), notes)
    binary = [line.split("\t", 2)[2] for line in gitc(ctx, "diff", "--numstat", base, "HEAD").stdout.splitlines()
              if line.startswith("-\t-\t")]
    if binary:
        return blocked(f"binary 檔掃描不了內容，不自動 push：{binary[0]}", notes)
    leak = leak_in_diff(ctx, base)
    if leak:
        return blocked(f"leak：要 push 的內容有{leak}", notes)
    return ship(ctx, branch, notes, no_push)


def agent_git_changes(ctx: Context, base: str) -> list:
    """agent 不該動 git：有任何 commit、index 或工作樹改動（.verify/ 除外）就是越界。"""
    names = gitc(ctx, "diff", "--name-only", base, "HEAD").stdout.split()
    return [f"agent 自己 commit 了 {p}" for p in names] + [f"agent 改了 {p}" for p in dirty_paths(ctx)]


def read_proposals(ctx: Context) -> tuple:
    """讀 .verify/maintain-proposed/：只准 SKILL.md 與 references/**/*.md、不准 symlink、要是 UTF-8 純文字。"""
    root = clone_dir(ctx) / PROPOSED_REL
    proposals, problems = {}, []
    if not root.exists():
        return proposals, problems
    for path in sorted(root.rglob("*")):
        if path.is_dir() and not path.is_symlink():
            continue
        target = SKILL_PREFIX + path.relative_to(root).as_posix()
        if path.is_symlink() or not agent_editable(target):
            problems.append(f"scope violation：不能提案 {target}")
            continue
        data = path.read_bytes()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = None
        if text is None or len(data) > MAX_PROPOSAL_BYTES or any(ord(ch) < 32 and ch not in "\n\t\r" or ch == "\x7f"
                                                                 for ch in text):
            problems.append(f"binary 或過大的提案不能自動套用：{target}")
            continue
        proposals[target] = text
    return proposals, problems


def apply_proposals(ctx: Context, proposals: dict, branch: str, base: str) -> str:
    """把提案寫進 skill 目錄並由 wrapper commit；成功回傳空字串，否則回傳 blocked 的原因。"""
    clone = clone_dir(ctx)
    for target in proposals:
        problem = unsafe_target(clone, target)
        if problem:
            return problem
    changed = [target for target, text in proposals.items()
               if not (clone / target).is_file() or (clone / target).read_text(errors="replace") != text]
    if not changed:
        return "提案和現有內容一樣，run notes 卻說 changed"
    for target in changed:
        (clone / target).parent.mkdir(parents=True, exist_ok=True)
        (clone / target).write_text(proposals[target])
    date = branch.removeprefix("maintain/verify-kidsai-")
    if (gitc(ctx, "add", "--", *changed).returncode != 0
            or gitc(ctx, "commit", "-q", "-m", f"docs: 每日維護 {date}：{len(changed)} 個驗證文件修正").returncode != 0
            or gitc(ctx, "rev-list", "--count", f"{base}..HEAD").stdout.strip() != "1"):
        return "wrapper 套用提案後 git add／commit 失敗"
    return ""


def unsafe_target(clone: Path, target: str) -> str:
    """目標路徑的每一層都不能是 symlink，解析後也要在 skill 目錄裡（不寫穿到外面）。"""
    skill = (clone / SKILL_PREFIX).resolve()
    path = clone / target
    for part in [path, *path.parents]:
        if part == clone:
            break
        if part.is_symlink():
            return f"scope violation：{target} 經過 symlink {part.relative_to(clone)}"
    resolved = path.resolve()
    if resolved != skill and skill not in resolved.parents:
        return f"scope violation：{target} 解析到 skill 目錄外"
    return ""


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
    """SKILL.md 或 references/ 底下的 .md；其他副檔名（例如 .py）可能被當成程式執行。"""
    return path == AGENT_EDITABLE[0] or (path.startswith(AGENT_EDITABLE[1]) and path.endswith(".md"))


def dirty_paths(ctx: Context) -> list:
    out = gitc(ctx, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout
    return [entry[3:] for entry in out.split("\0") if len(entry) > 3]


def leak_in_diff(ctx: Context, base: str) -> str:
    """要 push 的新增內容與 commit 訊息（agent 可能把讀到的東西寫進訊息）。"""
    added = "\n".join(line[1:] for line in gitc(ctx, "diff", base, "HEAD").stdout.splitlines()
                      if line.startswith("+") and not line.startswith("+++"))
    added += "\n" + gitc(ctx, "log", "--format=%an%n%ae%n%B", f"{base}..HEAD").stdout
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
    # agent 可能改了字級沒改回來；還原，免得下次 doctor 的 text-size 擋住（沒開機時這步失敗也無妨）
    ctx.runner.run([sys.executable, str(cli), "--sim", MAINTAIN_SIM, "sim", "text-size", "--size", "default"])
    ctx.runner.run([sys.executable, str(cli), "--sim", MAINTAIN_SIM, "sim", "shutdown"])


# ---------------------------------------------------------------- 鎖、紀錄、通知

def lock_dir(ctx: Context) -> Path:
    return maintain_root(ctx) / ".lock"


def acquire_lock(ctx: Context) -> tuple:
    """回傳（拿到鎖了嗎, 上一輪留下的舊鎖資訊或 None）。舊鎖＝上一輪沒有收尾就結束了。"""
    lock = lock_dir(ctx)
    lock.parent.mkdir(parents=True, exist_ok=True)
    stale = None
    try:
        lock.mkdir()
    except FileExistsError:
        owner = {}
        try:
            owner = read_json(lock / "owner.json", {}) or {}
            started = datetime.datetime.fromisoformat(owner["started"])
            busy = pid_alive(ctx, owner.get("pid")) and ctx.now() - started < LOCK_STALE
        except (ValueError, TypeError, KeyError, AttributeError):
            busy = False  # 鎖檔壞了：當成上次中斷留下的
        if busy:
            return False, None
        stale = {"started": owner.get("started") if isinstance(owner, dict) else None}
        shutil.rmtree(lock)  # 上次當掉或被中斷留下的鎖
        lock.mkdir()
    write_json(lock / "owner.json", {"pid": os.getpid(), "started": ctx.now().isoformat()})
    return True, stale


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
