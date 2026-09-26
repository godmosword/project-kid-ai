"""control-kidsai 的單元測試：所有外部命令都換成假的，不需要 Xcode、模擬器或網路。

執行：python3 -m unittest discover .claude/skills/verify-kidsai/tests
"""

import contextlib
import datetime
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

CLI = Path(__file__).resolve().parents[1] / "control-kidsai"
_loader = importlib.machinery.SourceFileLoader("control_kidsai", str(CLI))
_spec = importlib.util.spec_from_loader("control_kidsai", _loader)
ck = importlib.util.module_from_spec(_spec)
_loader.exec_module(ck)

UDID = "11111111-2222-3333-4444-555555555555"
SHA = "62f3515abcdef0123456789abcdef0123456789a"
FIXED_NOW = datetime.datetime(2026, 9, 26, 21, 30, 5, tzinfo=ck.TZ)


def png_bytes(width, height):
    """最小的合法 PNG（只要 IHDR 對，尺寸檢查會讀它）。"""
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", len(ihdr)) + chunk + struct.pack(">I", zlib.crc32(chunk))


class FakeRunner:
    """記錄每一個外部命令；依命令內容回傳預先寫好的結果。"""

    def __init__(self, booted=True, sim_exists=True, statusbar=True, apps=None):
        self.calls = []
        self.booted = booted
        self.sim_exists = sim_exists
        self.statusbar = statusbar
        self.apps = apps if apps is not None else {"com.godmosword.kidsai": {"ApplicationType": "User"}}
        self.app_dir = None
        self.ps_line = None
        self.shutdown_fails = False
        self.popen_log = ""

    def run(self, cmd, cwd=None, input=None):
        self.calls.append(list(cmd))
        text = " ".join(cmd)
        if cmd[:4] == ["xcrun", "simctl", "list", "devices"]:
            devices = []
            if self.sim_exists:
                devices = [{"name": "KidsAI-Verify", "udid": UDID, "isAvailable": True,
                            "state": "Booted" if self.booted else "Shutdown",
                            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17e"}]
            return ck.Result(0, json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": devices}}), "")
        if cmd[:4] == ["xcrun", "simctl", "list", "runtimes"]:
            return ck.Result(0, json.dumps({"runtimes": [{
                "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "name": "iOS 27.0", "version": "27.0",
                "platform": "iOS", "isAvailable": True,
                "supportedDeviceTypes": [{"name": "iPhone 17e", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17e"}]}]}), "")
        if "status_bar" in cmd and "list" in cmd:
            return ck.Result(0, "Current Status Bar Overrides:\n Time: 9:41\n" if self.statusbar else "", "")
        if "listapps" in cmd:
            return ck.Result(0, "plist", "")
        if cmd[:1] == ["plutil"]:
            return ck.Result(0, json.dumps(self.apps), "")
        if "get_app_container" in cmd:
            if self.app_dir is None:
                return ck.Result(2, "", "not installed")
            return ck.Result(0, str(self.app_dir) + "\n", "")
        if "screenshot" in cmd:
            Path(cmd[-1]).write_bytes(png_bytes(1170, 2532))
            return ck.Result(0, "", "")
        if cmd[:2] == ["git", "rev-parse"] and "HEAD" in cmd:
            return ck.Result(0, SHA + "\n", "")
        if cmd[:2] == ["git", "diff"] or cmd[:2] == ["git", "ls-files"] or cmd[:2] == ["git", "status"]:
            return ck.Result(0, "", "")
        if cmd[:2] == ["ps", "-p"]:
            line = self.ps_line() if callable(self.ps_line) else self.ps_line
            return ck.Result(0 if line else 1, line or "", "")
        if "shutdown" in cmd and self.shutdown_fails:
            return ck.Result(1, "", "busy")
        return ck.Result(0, "", "")

    def popen(self, cmd, log_path):
        self.calls.append(list(cmd))
        Path(log_path).write_text(self.popen_log)
        return 4242

    def ran(self, *words):
        return [c for c in self.calls if all(w in c for w in words)]


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.home = root / "home"
        self.repo.mkdir()
        self.home.mkdir()
        self.runner = FakeRunner()
        self.killed = []
        self.ctx = ck.Context(repo=self.repo, home=self.home, runner=self.runner,
                              now=lambda: FIXED_NOW, kill=lambda pid, sig: self.killed.append((pid, sig)),
                              sleep=lambda s: None, which=lambda name: "/opt/homebrew/bin/" + name)

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = ck.main(list(argv), self.ctx)
        text = out.getvalue()
        return code, (json.loads(text) if text.strip().startswith("{") else text)

    def make_run(self, files=None, review=True):
        """建一個合格的 run：manifest 由 CLI 的函式寫，檔案內容可自訂。"""
        run_id = "20260926-213005-62f3515"
        run_dir = self.repo / ".verify" / run_id
        run_dir.mkdir(parents=True)
        entries = []
        for name, data in (files or {"map-islands.png": png_bytes(1170, 2532)}).items():
            (run_dir / name).write_bytes(data)
            entries.append({"name": name, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                            "kind": "screenshot"})
        manifest = {"sha": SHA, "dirty": False, "device": "iPhone 17e", "runtime": "iOS 27.0",
                    "simulator": "KidsAI-Verify", "feature": "map", "entry": "app-launch", "files": entries,
                    "captured_at": FIXED_NOW.isoformat(),
                    "visual_review": {"ok": True, "images_checked": len(entries), "videos": {},
                                      "items": [{"name": e["name"], "sha256": e["sha256"]} for e in entries],
                                      "reviewed_at": FIXED_NOW.isoformat()} if review else None}
        (run_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        return run_id, run_dir


class ExitCodeTests(Base):
    def test_exit_codes_are_fixed(self):
        self.assertEqual((ck.EXIT_OK, ck.EXIT_USAGE, ck.EXIT_ENV, ck.EXIT_REFUSED, ck.EXIT_EXTERNAL, ck.EXIT_EVIDENCE, ck.EXIT_STALE),
                         (0, 2, 3, 4, 5, 6, 7))

    def test_help_lists_every_command(self):
        code, text = self.call("--help")
        self.assertEqual(code, 0)
        for word in ["doctor", "sim", "build", "install", "launch", "terminate", "run", "screenshot", "record",
                     "cleanup", "evidence"]:
            self.assertIn(word, text)

    def test_names_cannot_escape_the_run_directory(self):
        for bad in ["../x", "a/b", "Map", ""]:
            code, _ = self.call("run", "new", "--feature", bad, "--entry", "app-launch")
            self.assertEqual(code, ck.EXIT_USAGE, bad)


class RunIdTests(Base):
    def test_run_id_uses_taipei_time_and_short_sha(self):
        self.assertEqual(ck.make_run_id(FIXED_NOW, "62f3515abcdef", set()), "20260926-213005-62f3515")

    def test_run_id_adds_suffix_on_same_second(self):
        taken = {"20260926-213005-62f3515"}
        self.assertEqual(ck.make_run_id(FIXED_NOW, "62f3515abcdef", taken), "20260926-213005-62f3515-2")

    def test_run_new_writes_manifest_without_local_paths(self):
        code, out = self.call("run", "new", "--feature", "map", "--entry", "app-launch")
        self.assertEqual(code, 0)
        text = (self.repo / ".verify" / out["run"] / "manifest.json").read_text()
        for leak in [str(self.home), str(self.repo), "/Users/", UDID]:
            self.assertNotIn(leak, text)


class SimulatorTests(Base):
    def test_erase_requires_yes(self):
        code, _ = self.call("sim", "erase")
        self.assertEqual(code, ck.EXIT_REFUSED)
        self.assertEqual(self.runner.ran("erase"), [])

    def test_erase_dry_run_does_not_erase(self):
        code, _ = self.call("sim", "erase", "--yes", "--dry-run")
        self.assertEqual(code, 0)
        self.assertEqual(self.runner.ran("erase"), [])

    def test_only_dedicated_simulators(self):
        code, _ = self.call("--sim", "iPhone 17", "sim", "boot")
        self.assertEqual(code, ck.EXIT_REFUSED)
        self.assertEqual(self.runner.ran("boot"), [])


class DoctorTests(Base):
    def test_missing_simulator_points_to_sim_ensure(self):
        self.runner.sim_exists = False
        code, out = self.call("doctor")
        self.assertEqual(code, ck.EXIT_ENV)
        self.assertIn("sim ensure", json.dumps(out, ensure_ascii=False))

    def test_shutdown_simulator_is_an_environment_error(self):
        self.runner.booted = False
        code, out = self.call("doctor")
        self.assertEqual(code, ck.EXIT_ENV)
        self.assertIn("sim boot", json.dumps(out, ensure_ascii=False))

    def test_stale_build_is_rejected(self):
        app = self.home / "Installed.app"
        app.mkdir()
        (app / "KidsAI").write_bytes(b"stub")
        (app / "KidsAI.debug.dylib").write_bytes(b"code -openUnit")
        self.runner.app_dir = app
        ck.write_json(self.repo / ".verify" / "build.json",
                      {"source_fingerprint": "old", "executable_sha256": "old", "configuration": "Debug"})
        code, out = self.call("doctor")
        self.assertEqual(code, ck.EXIT_STALE)
        self.assertIn("build", json.dumps(out, ensure_ascii=False))

    def installed_debug_app(self):
        """Xcode 的 Debug build：主執行檔只是小殼，程式在 KidsAI.debug.dylib。"""
        app = self.home / "Installed.app"
        app.mkdir()
        (app / "KidsAI").write_bytes(b"stub")
        (app / "KidsAI.debug.dylib").write_bytes(b"code -openUnit")
        self.runner.app_dir = app
        ck.write_json(self.repo / ".verify" / "build.json",
                      {"source_fingerprint": ck.source_fingerprint(self.ctx), "executable_sha256": ck.binary_fingerprint(app),
                       "configuration": "Debug"})
        return app

    def test_debug_code_in_dylib_passes(self):
        self.installed_debug_app()
        code, out = self.call("doctor")
        self.assertEqual(code, 0, out)

    def test_code_change_in_dylib_is_stale(self):
        app = self.installed_debug_app()
        (app / "KidsAI.debug.dylib").write_bytes(b"new code -openUnit")
        code, _ = self.call("doctor")
        self.assertEqual(code, ck.EXIT_STALE)

    def test_other_user_apps_fail_doctor(self):
        self.runner.apps = {"com.godmosword.kidsai": {"ApplicationType": "User"}, "com.example.chat": {"ApplicationType": "User"}}
        code, _ = self.call("doctor")
        self.assertEqual(code, ck.EXIT_ENV)


class DoctorDebugTests(Base):
    def test_string_without_debug_dylib_is_not_debug(self):
        app = self.home / "Installed.app"
        app.mkdir()
        (app / "KidsAI").write_bytes(b"binary -openUnit")
        self.runner.app_dir = app
        code, out = self.call("doctor")
        self.assertEqual(code, ck.EXIT_ENV)
        self.assertIn("debug-build", [c["check"] for c in out["checks"] if not c["ok"]])


class RecordTests(Base):
    def test_stop_refuses_to_signal_a_process_that_is_not_ours(self):
        run_id, _ = self.make_run()
        ck.write_json(ck.session_path(self.ctx, "KidsAI-Verify"), {"recordings": {f"{run_id}/map-launch": {
            "pid": 4242, "identity": "Sat Sep 26 21:30:05 2026 xcrun simctl io recordVideo", "path": "x.mp4",
            "watchdog": None}}})
        self.runner.ps_line = "Sat Sep 26 22:00:00 2026 /usr/bin/something-else"
        code, _ = self.call("record", "stop", "--run", run_id, "--name", "map-launch")
        self.assertEqual(code, ck.EXIT_EVIDENCE)
        self.assertEqual(self.killed, [])

    def test_stop_sends_sigint_to_our_process(self):
        states = iter(["Sat Sep 26 21:30:05 2026 xcrun simctl io recordVideo", None])
        self.runner.ps_line = lambda: next(states, None)
        stopped = ck.stop_process(self.ctx, {"pid": 4242, "identity": "Sat Sep 26 21:30:05 2026 xcrun simctl io recordVideo"})
        self.assertTrue(stopped)
        self.assertEqual(self.killed, [(4242, ck.signal.SIGINT)])

    def test_stop_times_out_then_sigterm_and_reports_failure(self):
        self.runner.ps_line = "Sat Sep 26 21:30:05 2026 xcrun simctl io recordVideo"
        stopped = ck.stop_process(self.ctx, {"pid": 4242, "identity": self.runner.ps_line})
        self.assertFalse(stopped)
        self.assertEqual([sig for _, sig in self.killed], [ck.signal.SIGINT, ck.signal.SIGTERM])

    def test_start_timeout_is_invalid_evidence_and_only_stops_recordvideo(self):
        run_id, _ = self.make_run()
        self.runner.ps_line = "Sat Sep 26 21:30:05 2026 /usr/bin/other"
        code, _ = self.call("record", "start", "--run", run_id, "--name", "map-launch")
        self.assertEqual(code, ck.EXIT_EVIDENCE)
        self.assertEqual(self.killed, [], "不是錄影程序就不停")


class CleanupTests(Base):
    def test_cleanup_keeps_evidence_and_only_stops_what_we_started(self):
        run_id, run_dir = self.make_run()
        ck.write_json(ck.session_path(self.ctx, "KidsAI-Verify"), {"booted_by_us": False, "launched": True, "recordings": {}})
        code, _ = self.call("cleanup")
        self.assertEqual(code, 0)
        self.assertTrue((run_dir / "manifest.json").exists())
        self.assertEqual(self.runner.ran("shutdown"), [], "不是本次開機的模擬器不關")
        self.assertTrue(self.runner.ran("terminate"), "本次啟動的 App 要關")

    def test_cleanup_failure_is_reported_and_kept(self):
        ck.write_json(ck.session_path(self.ctx, "KidsAI-Verify"), {"booted_by_us": True, "launched": False, "recordings": {}})
        self.runner.shutdown_fails = True
        code, _ = self.call("cleanup")
        self.assertEqual(code, ck.EXIT_EXTERNAL)
        self.assertTrue(json.loads(ck.session_path(self.ctx, "KidsAI-Verify").read_text())["booted_by_us"], "失敗要保留紀錄")

    def test_cleanup_dry_run_changes_nothing(self):
        ck.write_json(ck.session_path(self.ctx, "KidsAI-Verify"), {"booted_by_us": True, "launched": True, "recordings": {}})
        code, _ = self.call("cleanup", "--dry-run")
        self.assertEqual(code, 0)
        self.assertEqual(self.runner.calls, [])


class PublishTests(Base):
    def publish(self, run_id, *extra):
        return self.call("evidence", "publish", "--pr", "7", "--run", run_id, *extra)

    def test_dry_run_touches_nothing(self):
        run_id, run_dir = self.make_run()
        before = sorted((p.name, p.stat().st_mtime_ns) for p in run_dir.iterdir())
        code, out = self.publish(run_id, "--dry-run")
        self.assertEqual(code, 0, out)
        self.assertEqual([c for c in self.runner.calls if c[:1] == ["git"]], [], "dry-run 不得呼叫 git")
        self.assertFalse(ck.cache_dir(self.ctx).exists(), "dry-run 不得建立 cache")
        self.assertEqual(before, sorted((p.name, p.stat().st_mtime_ns) for p in run_dir.iterdir()))

    def assert_rejected(self, run_id):
        code, _ = self.publish(run_id, "--dry-run")
        self.assertEqual(code, ck.EXIT_EVIDENCE)

    def test_rejects_file_not_in_manifest(self):
        run_id, run_dir = self.make_run()
        (run_dir / "extra.png").write_bytes(png_bytes(1, 1))
        self.assert_rejected(run_id)

    def test_rejects_symlink_and_subdirectory(self):
        run_id, run_dir = self.make_run()
        (run_dir / "sub").mkdir()
        self.assert_rejected(run_id)
        (run_dir / "sub").rmdir()
        os.symlink(run_dir / "map-islands.png", run_dir / "link.png")
        self.assert_rejected(run_id)

    def test_rejects_disallowed_extension(self):
        run_id, _ = self.make_run(files={"notes.txt": b"hello"})
        self.assert_rejected(run_id)

    def test_rejects_file_over_10_mb(self):
        run_id, _ = self.make_run(files={"big.png": b"0" * (10 * 1024 * 1024 + 1)})
        self.assert_rejected(run_id)

    def test_rejects_local_path_in_manifest(self):
        run_id, run_dir = self.make_run()
        manifest = json.loads((run_dir / "manifest.json").read_text())
        manifest["entry"] = str(self.home)
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        self.assert_rejected(run_id)

    def test_rejects_unknown_manifest_field(self):
        run_id, run_dir = self.make_run()
        manifest = json.loads((run_dir / "manifest.json").read_text())
        manifest["note"] = "hi"
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        self.assert_rejected(run_id)

    def test_rejects_run_without_visual_review(self):
        run_id, _ = self.make_run(review=False)
        self.assert_rejected(run_id)

    def test_rejects_sha_mismatch(self):
        run_id, run_dir = self.make_run()
        (run_dir / "map-islands.png").write_bytes(png_bytes(2, 2))
        self.assert_rejected(run_id)

    def test_rejects_other_simulator(self):
        run_id, run_dir = self.make_run()
        manifest = json.loads((run_dir / "manifest.json").read_text())
        manifest["simulator"] = "iPhone 17"
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        self.assert_rejected(run_id)

    def test_rejects_path_traversal_in_manifest(self):
        run_id, run_dir = self.make_run()
        outside = self.repo / ".verify" / "secret.png"
        outside.write_bytes(png_bytes(3, 3))
        manifest = json.loads((run_dir / "manifest.json").read_text())
        data = outside.read_bytes()
        manifest["files"].append({"name": "../secret.png", "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                                  "kind": "screenshot"})
        manifest["visual_review"]["items"].append({"name": "../secret.png", "sha256": hashlib.sha256(data).hexdigest()})
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        self.assert_rejected(run_id)

    def test_rejects_file_swapped_after_review(self):
        run_id, run_dir = self.make_run()
        data = png_bytes(4, 4)
        (run_dir / "map-islands.png").write_bytes(data)
        manifest = json.loads((run_dir / "manifest.json").read_text())
        manifest["files"][0].update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        self.assert_rejected(run_id)

    def test_review_requires_frames_of_the_same_video(self):
        run_id, run_dir = self.make_run(files={"map-launch.mp4": b"video-bytes"}, review=False)
        manifest = json.loads((run_dir / "manifest.json").read_text())
        manifest["files"][0]["kind"] = "video"
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        code, _ = self.call("evidence", "review", "--run", run_id, "--ok")
        self.assertEqual(code, ck.EXIT_EVIDENCE, "沒抽格不能 review")
        frames = self.repo / ".verify" / "_frames" / run_id
        frames.mkdir(parents=True)
        ck.write_json(frames / "frames.json", {"map-launch.mp4": {"sha256": "old", "frames": ["map-launch-01.png"]}})
        code, _ = self.call("evidence", "review", "--run", run_id, "--ok")
        self.assertEqual(code, ck.EXIT_EVIDENCE, "抽格後影片換過不能 review")
        ck.write_json(frames / "frames.json", {"map-launch.mp4": {"sha256": hashlib.sha256(b"video-bytes").hexdigest(),
                                                                   "frames": ["map-launch-01.png"]}})
        code, _ = self.call("evidence", "review", "--run", run_id, "--ok")
        self.assertEqual(code, 0)
        code, _ = self.publish(run_id, "--dry-run")
        self.assertEqual(code, 0)

    def test_dry_run_refuses_existing_destination_in_local_copy(self):
        run_id, _ = self.make_run()
        (ck.cache_dir(self.ctx) / "pr-7" / run_id).mkdir(parents=True)
        self.assert_rejected(run_id)

    def test_publish_without_gh_is_refused(self):
        run_id, _ = self.make_run()
        self.ctx.which = lambda name: None
        code, _ = self.publish(run_id)
        self.assertEqual(code, ck.EXIT_ENV)
        self.assertEqual([c for c in self.runner.calls if c[:1] == ["git"]], [])

    def test_bad_manifest_types_give_fixed_exit_code(self):
        run_id, run_dir = self.make_run()
        manifest = json.loads((run_dir / "manifest.json").read_text())
        manifest["files"] = "not-a-list"
        (run_dir / "manifest.json").write_text(json.dumps(manifest))
        self.assert_rejected(run_id)

    def test_markdown_embeds_raw_links(self):
        run_id, _ = self.make_run()
        code, out = self.call("evidence", "md", "--pr", "7", "--run", run_id)
        self.assertEqual(code, 0)
        self.assertIn(f"](https://raw.githubusercontent.com/godmosword/project-kid-ai-evidence/main/pr-7/{run_id}/map-islands.png)",
                      out["markdown"])


if __name__ == "__main__":
    unittest.main()
