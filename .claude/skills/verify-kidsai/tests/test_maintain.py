"""control-kidsai maintain 的測試：每日維護（V4）。

git 用真的（暫存資料夾裡的 bare repo 當 origin），範圍防護才是在真實的 git 狀態上驗證；
claude、gh、launchctl、osascript、模擬器一律是假的，不連網、不碰 launchd。
執行：python3 -m unittest discover .claude/skills/verify-kidsai/tests
"""

import contextlib
import datetime
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

CLI = Path(__file__).resolve().parents[1] / "control-kidsai"
_loader = importlib.machinery.SourceFileLoader("control_kidsai_maintain", str(CLI))
_spec = importlib.util.spec_from_loader("control_kidsai_maintain", _loader)
ck = importlib.util.module_from_spec(_spec)
_loader.exec_module(ck)

NOW = datetime.datetime(2026, 9, 30, 3, 17, 0, tzinfo=ck.TZ)
SKILL = ".claude/skills/verify-kidsai"
GIT_ID = ["-c", "user.name=test", "-c", "user.email=test@example.invalid"]


def git(cwd, *args):
    return subprocess.run(["git", *GIT_ID, *args], cwd=cwd, capture_output=True, text=True, check=True).stdout


class HybridRunner(ck.Runner):
    """git 走真的 subprocess；其他外部命令只記錄，回傳預先寫好的結果。"""

    def __init__(self):
        self.calls = []
        self.agent = None           # 假的 claude：拿到 clone 路徑後改檔、commit、寫 run notes
        self.agent_code = 0         # claude 的結束碼；None＝逾時
        self.open_prs = []          # gh pr list 回傳的 headRefName
        self.gh_list_fails = False
        self.pr_create_fails = False

    def run(self, cmd, cwd=None, input=None, env=None, timeout=None):
        if cmd[0] == "git":
            return super().run(cmd, cwd=cwd, input=input, env=env)
        self.calls.append(list(cmd))
        if cmd[:3] == ["/fake/gh", "pr", "list"]:
            if self.gh_list_fails:
                return ck.Result(1, "", "network down")
            return ck.Result(0, json.dumps([{"headRefName": h} for h in self.open_prs]), "")
        if cmd[:3] == ["/fake/gh", "pr", "create"]:
            if self.pr_create_fails:
                return ck.Result(1, "", "GraphQL error")
            return ck.Result(0, "https://github.com/godmosword/project-kid-ai/pull/99\n", "")
        return ck.Result(0, "", "")

    def run_logged(self, cmd, log_path, cwd=None, env=None, timeout=None):
        self.calls.append(list(cmd))
        Path(log_path).write_text("fake claude log\n")
        if self.agent:
            self.agent(Path(cwd))
        return self.agent_code

    def ran(self, *words):
        return [c for c in self.calls if all(w in c for w in words)]


class MaintainBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.home.mkdir()
        seed = self.checkout = root / "seed"  # 當作 Michael 平常工作的 checkout（install 從這裡跑）
        (seed / SKILL / "references").mkdir(parents=True)
        (seed / SKILL / "SKILL.md").write_text("# verify\n")
        (seed / SKILL / "maintain").mkdir()
        (seed / SKILL / "maintain" / "run-daily.sh").write_text("#!/bin/bash\n")
        (seed / SKILL / "maintain" / "maintain-settings.json").write_text("{}\n")
        (seed / "app").mkdir()
        (seed / "app" / "A.swift").write_text("let a = 1\n")
        (seed / ".gitignore").write_text(".verify/\n")
        git(seed, "init", "-q", "-b", "main")
        git(seed, "add", "-A")
        git(seed, "commit", "-q", "-m", "seed")
        self.origin = root / "origin.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(seed), str(self.origin)], check=True)
        self.clone = self.home / "kidsai-maintain" / "project-kid-ai"
        subprocess.run(["git", "clone", "-q", str(self.origin), str(self.clone)], check=True)
        self.runner = HybridRunner()
        self.ctx = ck.Context(repo=self.clone, home=self.home, runner=self.runner, now=lambda: NOW,
                              kill=lambda pid, sig: None, sleep=lambda s: None, which=lambda name: f"/fake/{name}")
        ck.write_json(self.home / "kidsai-maintain" / "config.json",
                      {"claude": "/fake/claude", "gh": "/fake/gh", "python": "/fake/python3"})
        # 維護模組自己查 claude 在不在：換成「/fake/ 開頭的都在」
        self.claude_exists = mock.patch.object(sys.modules["kidsai_maintain"], "tool_exists", lambda path: str(path).startswith("/fake/"))
        self.claude_exists.start()

    def tearDown(self):
        self.claude_exists.stop()
        self.tmp.cleanup()

    def fresh(self):
        """subTest 之間換一個全新的 origin／clone。"""
        self.tearDown()
        self.setUp()

    def call(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = ck.main(list(argv), self.ctx)
        return code, json.loads(out.getvalue())

    # 假 agent 的動作
    @staticmethod
    def notes(clone, outcome):
        (clone / ".verify").mkdir(exist_ok=True)
        (clone / ".verify" / "maintain-notes.md").write_text(f"outcome: {outcome}\n- 涵蓋：map\n")

    @staticmethod
    def commit(clone, rel, text="改了\n", message="docs: fix"):
        path = clone / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text) if isinstance(text, bytes) else path.write_text(text)
        git(clone, "add", "-A", "--", rel)
        git(clone, "commit", "-q", "-m", message)

    def remote_branches(self):
        return git(self.origin, "branch", "--list", "maintain/*").split()


class InstallTests(MaintainBase):
    def setUp(self):
        super().setUp()
        self.ctx.repo = self.checkout

    def test_install_dry_run_prints_plist_and_writes_nothing(self):
        code, out = self.call("maintain", "install", "--dry-run")
        self.assertEqual(code, 0, out)
        self.assertIn("<integer>3</integer>", out["plist"])
        self.assertIn("<integer>17</integer>", out["plist"])
        self.assertTrue(out["plist_path"].endswith("LaunchAgents/com.godmosword.kidsai.maintain-verify.plist"))
        self.assertFalse((self.home / "Library/LaunchAgents").exists())
        self.assertFalse(self.runner.ran("launchctl"))

    def test_install_then_uninstall(self):
        code, out = self.call("maintain", "install")
        self.assertEqual(code, 0, out)
        plist = self.home / "Library/LaunchAgents/com.godmosword.kidsai.maintain-verify.plist"
        bootstrap = self.home / "kidsai-maintain/bin/run-daily.sh"
        self.assertTrue(plist.exists() and bootstrap.exists())
        self.assertTrue(os.access(bootstrap, os.X_OK))
        config = json.loads((self.home / "kidsai-maintain/config.json").read_text())
        self.assertIn("git_email", config)
        self.assertTrue(self.runner.ran("launchctl", "bootstrap"))
        code, out = self.call("maintain", "uninstall")
        self.assertEqual(code, 0, out)
        self.assertFalse(plist.exists() or bootstrap.exists())
        self.assertTrue(self.runner.ran("launchctl", "bootout"))
        self.assertTrue(self.clone.exists(), "uninstall 不刪專用 clone")

    def test_install_refuses_without_claude(self):
        self.ctx.which = lambda name: None
        code, _ = self.call("maintain", "install", "--dry-run")
        self.assertEqual(code, ck.EXIT_ENV)


class RunOutcomeTests(MaintainBase):
    def test_clean(self):
        self.runner.agent = lambda c: self.notes(c, "clean")
        code, out = self.call("maintain", "run")
        self.assertEqual(out["outcome"], "clean", out)
        self.assertEqual(code, 0)
        self.assertFalse(self.runner.ran("/fake/gh", "pr", "create"))
        self.assertEqual(self.remote_branches(), [])
        self.assertTrue((self.home / "Library/Logs/kidsai-maintain/2026-09-30.log").exists())
        self.assertTrue(self.runner.ran("sim", "shutdown"), "一律關掉 KidsAI-Maintain")

    def test_changed_pushes_branch_and_opens_draft_pr(self):
        def agent(c):
            self.commit(c, f"{SKILL}/references/map.md")
            self.notes(c, "changed")
        self.runner.agent = agent
        code, out = self.call("maintain", "run")
        self.assertEqual(out["outcome"], "changed", out)
        self.assertEqual(out["pr"], "https://github.com/godmosword/project-kid-ai/pull/99")
        self.assertEqual(self.remote_branches(), ["maintain/verify-kidsai-2026-09-30"])
        create = self.runner.ran("/fake/gh", "pr", "create")[0]
        self.assertIn("--draft", create)
        self.assertFalse(self.runner.ran("evidence", "publish"), "每日維護不發布證據")

    def test_agent_runs_on_maintain_simulator_with_publish_disabled(self):
        seen = {}
        original = self.runner.run_logged

        def spy(cmd, log_path, cwd=None, env=None, timeout=None):
            seen.update(env or {})
            seen["timeout"] = timeout
            return original(cmd, log_path, cwd=cwd, env=env, timeout=timeout)
        self.runner.run_logged = spy
        self.runner.agent = lambda c: self.notes(c, "clean")
        self.call("maintain", "run")
        self.assertEqual(seen["KIDSAI_SIM"], "KidsAI-Maintain")
        self.assertEqual(seen["KIDSAI_MAINTAIN_AGENT"], "1")
        self.assertEqual(seen["timeout"], 90 * 60)

    def test_no_push_keeps_changes_local(self):
        def agent(c):
            self.commit(c, f"{SKILL}/SKILL.md")
            self.notes(c, "changed")
        self.runner.agent = agent
        _, out = self.call("maintain", "run", "--no-push")
        self.assertEqual(out["outcome"], "changed")
        self.assertIsNone(out["pr"])
        self.assertEqual(self.remote_branches(), [])

    def test_existing_maintain_pr_or_failed_query_means_no_new_pr(self):
        for name, attr, value in (("open-pr", "open_prs", ["maintain/verify-kidsai-2026-09-29"]),
                                  ("query-fails", "gh_list_fails", True)):
            with self.subTest(case=name):
                self.fresh()
                setattr(self.runner, attr, value)

                def agent(c):
                    self.commit(c, f"{SKILL}/SKILL.md")
                    self.notes(c, "changed")
                self.runner.agent = agent
                _, out = self.call("maintain", "run")
                self.assertEqual(out["outcome"], "changed", out)
                self.assertIsNone(out["pr"])
                self.assertEqual(self.remote_branches(), [])


class GuardTests(MaintainBase):
    def assert_blocked(self, agent, why):
        self.runner.agent = agent
        code, out = self.call("maintain", "run")
        self.assertEqual(out["outcome"], "blocked", out)
        self.assertIn(why, out["reason"])
        self.assertNotEqual(code, 0)
        self.assertEqual(self.remote_branches(), [], "blocked 一律不 push")
        self.assertFalse(self.runner.ran("/fake/gh", "pr", "create"))
        self.assertNotIn("maintain/verify-kidsai-2026-09-30", git(self.clone, "branch", "--list"), "blocked 要刪掉本機分支")

    def test_scope_violations(self):
        def outside_commit(c):
            self.commit(c, "app/A.swift", "let a = 2\n")
            self.notes(c, "changed")

        def untracked_outside(c):
            (c / "app" / "New.swift").write_text("x\n")
            self.notes(c, "clean")

        def staged_uncommitted(c):
            (c / SKILL / "SKILL.md").write_text("staged\n")
            git(c, "add", f"{SKILL}/SKILL.md")
            self.notes(c, "clean")

        def dirty_inside(c):
            self.commit(c, f"{SKILL}/SKILL.md")
            (c / SKILL / "SKILL.md").write_text("not committed\n")
            self.notes(c, "changed")

        def rename_out(c):
            git(c, "mv", f"{SKILL}/SKILL.md", "SKILL.md")
            git(c, "commit", "-q", "-m", "mv")
            self.notes(c, "changed")

        def delete_outside(c):
            git(c, "rm", "-q", "app/A.swift")
            git(c, "commit", "-q", "-m", "rm")
            self.notes(c, "changed")

        def symlink_inside(c):
            os.symlink("/etc/hosts", c / SKILL / "hosts")
            git(c, "add", f"{SKILL}/hosts")
            git(c, "commit", "-q", "-m", "link")
            self.notes(c, "changed")

        for agent in (outside_commit, untracked_outside, staged_uncommitted, dirty_inside, rename_out, delete_outside, symlink_inside):
            with self.subTest(agent=agent.__name__):
                self.fresh()
                self.assert_blocked(agent, "scope")

    def test_harness_files_are_off_limits(self):
        """每日 agent 只改文件；改到 harness（含防護本身）一律 blocked。"""
        for rel in ("control-kidsai", "lib/kidsai_core.py", "lib/kidsai_maintain.py", "maintain/maintain-settings.json",
                    "tests/test_maintain.py"):
            with self.subTest(rel=rel):
                self.fresh()

                def agent(c, rel=rel):
                    self.commit(c, f"{SKILL}/{rel}", "# weakened\n")
                    self.notes(c, "changed")
                self.assert_blocked(agent, "scope")

    def test_binary_file_blocks(self):
        def agent(c):
            self.commit(c, f"{SKILL}/references/pic.png", b"\x89PNG\x00\x01secret")
            self.notes(c, "changed")
        self.assert_blocked(agent, "binary")

    def test_pr_create_failure_is_blocked(self):
        self.runner.pr_create_fails = True

        def agent(c):
            self.commit(c, f"{SKILL}/SKILL.md")
            self.notes(c, "changed")
        self.runner.agent = agent
        code, out = self.call("maintain", "run")
        self.assertEqual(out["outcome"], "blocked", out)
        self.assertIn("PR", out["reason"])
        self.assertEqual(out["consecutive_blocked"], 1)

    def test_leak_in_diff_blocks(self):
        for text in ("見 /Users/someone/project\n", "token ghp_" + "a" * 36 + "\n", "-----BEGIN OPENSSH PRIVATE KEY-----\n"):
            with self.subTest(text=text[:12]):
                self.fresh()

                def agent(c, text=text):
                    self.commit(c, f"{SKILL}/SKILL.md", text)
                    self.notes(c, "changed")
                self.assert_blocked(agent, "leak")

    def test_leak_in_commit_message_blocks(self):
        def agent(c):
            self.commit(c, f"{SKILL}/SKILL.md", message="docs: 見 /Users/someone/.ssh/id_ed25519")
            self.notes(c, "changed")
        self.assert_blocked(agent, "leak")

    def test_notes_must_match_git_state(self):
        cases = {
            "missing": lambda c: None,
            "clean-but-committed": lambda c: (self.commit(c, f"{SKILL}/SKILL.md"), self.notes(c, "clean")),
            "changed-but-nothing": lambda c: self.notes(c, "changed"),
        }
        for name, agent in cases.items():
            with self.subTest(case=name):
                self.fresh()
                self.assert_blocked(agent, "notes")

    def test_agent_failure_timeout_and_missing_claude(self):
        for name, prepare, why in (
                ("exit", lambda: setattr(self.runner, "agent_code", 1), "claude"),
                ("timeout", lambda: setattr(self.runner, "agent_code", None), "timeout"),
                ("missing", lambda: ck.write_json(self.home / "kidsai-maintain/config.json", {"claude": "/gone/claude", "gh": "/fake/gh"}),
                 "claude")):
            with self.subTest(case=name):
                self.fresh()
                prepare()
                self.assert_blocked(lambda c: self.notes(c, "clean"), why)

    def test_agent_blocked_notes(self):
        self.assert_blocked(lambda c: self.notes(c, "blocked: doctor 失敗"), "doctor")


class LockAndStateTests(MaintainBase):
    def test_busy_lock_skips(self):
        lock = self.home / "kidsai-maintain/.lock"
        lock.mkdir()
        ck.write_json(lock / "owner.json", {"pid": os.getpid(), "started": NOW.isoformat()})
        code, out = self.call("maintain", "run")
        self.assertEqual((code, out["outcome"]), (0, "skip"))
        self.assertFalse(self.runner.ran("/fake/claude"))

    def test_stale_lock_is_reclaimed_and_released(self):
        lock = self.home / "kidsai-maintain/.lock"
        lock.mkdir()
        ck.write_json(lock / "owner.json", {"pid": 999999, "started": (NOW - datetime.timedelta(hours=5)).isoformat()})
        self.runner.agent = lambda c: self.notes(c, "clean")
        _, out = self.call("maintain", "run")
        self.assertEqual(out["outcome"], "clean", out)
        self.assertFalse(lock.exists(), "結束後釋放鎖")

    def test_corrupted_lock_is_reclaimed(self):
        for content in ("not json", json.dumps({"pid": "x", "started": "yesterday"})):
            with self.subTest(content=content[:8]):
                self.fresh()
                lock = self.home / "kidsai-maintain/.lock"
                lock.mkdir()
                (lock / "owner.json").write_text(content)
                self.runner.agent = lambda c: self.notes(c, "clean")
                _, out = self.call("maintain", "run")
                self.assertEqual(out["outcome"], "clean", out)

    def test_consecutive_blocked_is_counted_and_flagged(self):
        self.runner.agent_code = 1
        for day in range(3):
            _, out = self.call("maintain", "run")
        self.assertEqual(out["consecutive_blocked"], 3)
        notify = self.runner.ran("osascript")[-1]
        self.assertIn("連續 3 天", " ".join(notify))
        self.runner.agent_code = 0
        self.runner.agent = lambda c: self.notes(c, "clean")
        _, out = self.call("maintain", "run")
        self.assertEqual(out["consecutive_blocked"], 0)

    def test_status_reports_history(self):
        self.runner.agent = lambda c: self.notes(c, "clean")
        self.call("maintain", "run")
        self.ctx.repo = self.checkout
        code, out = self.call("maintain", "status")
        self.assertEqual(code, 0)
        self.assertFalse(out["installed"])
        self.assertEqual(out["recent"][-1]["outcome"], "clean")


class CloneGuardTests(MaintainBase):
    """從專用 clone 執行的 control-kidsai，不看環境變數也一律受限（agent 改不掉位置）。"""

    def test_clone_refuses_dangerous_commands_without_env(self):
        for argv in (["evidence", "publish", "--pr", "1", "--run", "20260930-031700-abcdef0", "--dry-run"],
                     ["maintain", "install", "--dry-run"], ["maintain", "uninstall", "--dry-run"], ["maintain", "status"],
                     ["doctor"], ["--sim", "KidsAI-Verify", "doctor"]):
            with self.subTest(argv=" ".join(argv)):
                with mock.patch.dict(os.environ):
                    os.environ.pop("KIDSAI_MAINTAIN_AGENT", None)
                    os.environ.pop("KIDSAI_SIM", None)
                    code, out = self.call(*argv)
                self.assertEqual(code, ck.EXIT_REFUSED, out)

    def test_clone_allows_maintain_run_and_maintain_sim(self):
        self.runner.agent = lambda c: self.notes(c, "clean")
        code, out = self.call("maintain", "run")
        self.assertEqual((code, out["outcome"]), (0, "clean"))
        code, out = self.call("--sim", "KidsAI-Maintain", "run", "new", "--feature", "map", "--entry", "app-launch")
        self.assertNotEqual(code, ck.EXIT_REFUSED, out)


class SettingsTests(unittest.TestCase):
    """無頭 agent 的權限：git 只給 status／add（skill 文件）／commit -m；control-kidsai 只給需要的子命令。"""

    def setUp(self):
        self.rules = json.loads((CLI.parent / "maintain" / "maintain-settings.json").read_text())["permissions"]

    def test_no_git_command_that_can_read_outside_files(self):
        git_rules = [r for r in self.rules["allow"] if r.startswith("Bash(git")]
        self.assertEqual(sorted(git_rules), sorted([
            "Bash(git status:*)", "Bash(git add .claude/skills/verify-kidsai/SKILL.md:*)",
            "Bash(git add .claude/skills/verify-kidsai/references/:*)", "Bash(git commit -m:*)"]))

    def test_cli_is_allowed_per_subcommand_only(self):
        cli_rules = [r for r in self.rules["allow"] if "control-kidsai" in r]
        self.assertNotIn("Bash(.claude/skills/verify-kidsai/control-kidsai:*)", cli_rules)
        for rule in cli_rules:
            self.assertNotRegex(rule, r"control-kidsai (maintain|evidence publish|--sim)")
        self.assertIn("Bash(.claude/skills/verify-kidsai/control-kidsai doctor:*)", cli_rules)

    def test_edit_only_docs(self):
        edits = [r for r in self.rules["allow"] if r.startswith(("Edit(", "Write("))]
        for rule in edits:
            self.assertRegex(rule, r"^(Edit|Write)\(\./(\.claude/skills/verify-kidsai/(SKILL\.md|references/\*\*)|\.verify/\*\*)\)$")


class AgentModeTests(MaintainBase):
    """agent 的環境（KIDSAI_MAINTAIN_AGENT=1）裡，CLI 自己擋下危險命令，不只靠權限規則。"""

    def test_agent_mode_refuses_dangerous_commands(self):
        env = {"KIDSAI_MAINTAIN_AGENT": "1", "KIDSAI_SIM": "KidsAI-Maintain"}
        for argv in (["evidence", "publish", "--pr", "1", "--run", "20260930-031700-abcdef0"],
                     ["evidence", "publish", "--pr", "1", "--run", "20260930-031700-abcdef0", "--dry-run"],
                     ["maintain", "status"], ["maintain", "install", "--dry-run"],
                     ["--sim", "KidsAI-Verify", "doctor"]):
            with self.subTest(argv=" ".join(argv)):
                with mock.patch.dict(os.environ, env):
                    code, out = self.call(*argv)
                self.assertEqual(code, ck.EXIT_REFUSED, out)


if __name__ == "__main__":
    unittest.main()
