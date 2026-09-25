#!/usr/bin/env python3
"""產生 validate_content.py 的正反例。

一份合法的基準單元（valid/base），其餘每個反例只放一個缺陷，
expected.json 列出應該觸發、而且只觸發的規則代號。改 schema 後重跑本檔：
  python3 pipeline/fixtures/make_fixtures.py
內容全是虛構的測試文字，不含任何兒童資料。
"""

from __future__ import annotations

import copy
import json
import shutil
import sys
from pathlib import Path
from typing import Callable

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from content_rules import approval_hash  # noqa: E402
UNIT_ID = "unit_9_fixture"


def child(text_id: str, zh: str) -> dict:
    return {"id": text_id, "audience": "child", "text": {"zh-Hant": zh}, "vo": "vo/" + text_id.replace(".", "/"), "vo_status": "tts_placeholder"}


def option(option_id: str, zh: str, image: bool = False) -> dict:
    result = {"id": option_id, "label": child(f"fx.opt.{option_id}", zh)}
    if image:
        result |= {"image": f"img/{option_id}", "a11y_label": {"zh-Hant": zh}}
    return result


def graded_feedback(prefix: str) -> dict:
    return {
        "success": child(f"{prefix}.ok", "你找到了"),
        "not_yet": child(f"{prefix}.again", "再聽一次看看"),
        "reveal": child(f"{prefix}.reveal", "我們一起看答案"),
    }


def base_unit() -> dict:
    return {
        "kind": "unit",
        "schema_version": "1.0.0",
        "unit_id": UNIT_ID,
        "meta": {"title": child("fx.title", "測試單元"), "golden_line": child("fx.golden", "AI 會猜。"), "max_seconds": 600},
        "narrator": {"id": "diandian", "is_ai": False},
        "ai_persona": {"id": "guess_hat", "is_ai": True},
        "beats": [
            {"id": "b_intro", "type": "intro", "est_seconds": 30, "lines": [child("fx.intro", "今天來玩猜一猜")]},
            {
                "id": "b_choice", "type": "choice", "est_seconds": 60,
                "prompt": child("fx.choice.prompt", "哪一個會猜？"),
                "options": [option("opt_a", "猜猜帽", image=True), option("opt_b", "時鐘", image=True), option("opt_c", "書本")],
                "scoring": "graded", "correct_option_ids": ["opt_a"],
                "feedback": graded_feedback("fx.choice"), "max_attempts": 2, "after_max": "reveal_and_continue",
            },
            {
                "id": "b_asr", "type": "asr_repeat", "est_seconds": 60,
                "prompt": child("fx.asr.prompt", "跟我說一次"),
                "target_line": child("fx.asr.line", "AI 會猜"),
                "accept": {"zh-Hant": ["會猜", "AI 會猜"]},
                "match": "keyword_or_voice",
                "feedback": {"success": child("fx.asr.ok", "說得真好")},
                "on_mic_denied": {"mode": "say_together", "lines": [child("fx.asr.denied", "我們一起說")]},
                "on_device_unavailable": {"mode": "say_together", "lines": [child("fx.asr.unavailable", "跟著我一起說")]},
                "on_no_match": {"mode": "tap_to_read", "after_attempts": 2, "lines": [child("fx.asr.tap", "按一下聽聽看")]},
            },
            {"id": "b_ritual", "type": "sandbox_ritual", "est_seconds": 15, "lines": [child("fx.ritual", "戴上猜猜帽")], "skippable": False},
            {
                "id": "b_sandbox", "type": "sandbox", "est_seconds": 90,
                "sandbox_ref": "box_1",
                "prompt": child("fx.sandbox.prompt", "選一張圖"),
                "reaction_prompt": child("fx.sandbox.react", "AI 猜得怎樣？"),
                "reactions": [option("r_right", "好像對"), option("r_unsure", "不知道")],
                "scoring": "open",
                "closing_line": child("fx.sandbox.close", "AI 會猜。"),
                "feedback": {"reveal": child("fx.sandbox.reveal", "我們來看看")},
                "max_attempts": 1, "after_max": "reveal_and_continue",
            },
            {"id": "b_story", "type": "story", "est_seconds": 120, "story_ref": "story_1"},
            {
                "id": "b_review", "type": "review", "est_seconds": 60,
                "questions": [
                    {
                        "id": f"q{n}", "prompt": child(f"fx.q{n}.prompt", "AI 會不會猜？"),
                        "options": [option(f"q{n}_yes", "會"), option(f"q{n}_no", "不會")],
                        "correct_option_ids": [f"q{n}_yes"],
                        "feedback": graded_feedback(f"fx.q{n}"), "max_attempts": 2, "after_max": "reveal_and_continue",
                    }
                    for n in (1, 2)
                ],
            },
            {
                "id": "b_sticker", "type": "sticker", "est_seconds": 20,
                "sticker": {"id": "st_guess", "label": child("fx.sticker", "會猜貼紙"), "image": "stickers/guess", "a11y_label": {"zh-Hant": "會猜貼紙"}},
                "award": "on_reach",
            },
        ],
        "stories": [
            {
                "id": "story_1", "start": "n1",
                "nodes": [
                    {
                        "id": "n1", "speaker": "narrator", "lines": [child("fx.n1", "襪子不見了")],
                        "choices": [
                            {"id": "c_bed", "label": child("fx.c_bed", "床下"), "next": "n2"},
                            {"id": "c_bag", "label": child("fx.c_bag", "書包"), "next": "n3"},
                        ],
                    },
                    {"id": "n2", "speaker": "narrator", "lines": [child("fx.n2", "我們看看床下")], "next": "n4"},
                    {"id": "n3", "speaker": "narrator", "lines": [child("fx.n3", "我們看看書包")], "next": "n4"},
                    {"id": "n4", "speaker": "narrator", "lines": [child("fx.n4", "找到襪子了")], "end": True},
                ],
            }
        ],
        "sandboxes": [
            {
                "id": "box_1", "mode": "pregenerated", "required_uncertainty": "unsure",
                "slots": [
                    {
                        "id": "weather", "label": child("fx.slot.weather", "天氣"),
                        "image": "sandbox/weather", "a11y_label": {"zh-Hant": "天氣圖卡"},
                        "choices": [option("sun", "太陽", image=True)],
                    }
                ],
            }
        ],
        "parent_card": {"id": "fx.parent", "audience": "parent", "text": {"zh-Hant": "問孩子：今天 AI 猜對了幾次？"}},
    }


def approved(guess: dict) -> dict:
    return {**guess, "approved_hash": approval_hash(guess)}


def base_bank() -> dict:
    guess = {
        "id": "g_sun", "slot_id": "weather", "choice_id": "sun",
        "guess_text": child("fx.guess.sun", "我猜今天會出太陽"),
        "uncertainty_mark": "unsure", "safe": True,
    }
    return {
        "kind": "guess_bank",
        "schema_version": "1.0.0",
        "unit_id": UNIT_ID,
        "sandbox_id": "box_1",
        "guesses": [approved(guess)],
    }


def rich_unit() -> dict:
    """合法的變化版：拖曳分組、年齡覆寫、共玩提示、轉場提示。"""
    unit = base_unit()
    drag = {
        "id": "b_drag", "type": "drag", "est_seconds": 60,
        "prompt": child("fx.drag.prompt", "把怪怪的丟掉"), "mode": "group",
        "items": [option("i_fish", "魚會游"), option("i_moon", "方月亮"), option("i_ice", "冰是冷"), option("i_sun", "太陽熱")],
        "groups": [option("g_keep", "留下"), option("g_trash", "垃圾桶", image=True)],
        "assignments": {"i_fish": "g_keep", "i_moon": "g_trash", "i_ice": "g_keep", "i_sun": "g_keep"},
        "feedback": graded_feedback("fx.drag"), "max_attempts": 2, "after_max": "reveal_and_continue",
        "transition_hint": "gentle",
        "coplay_prompt": {"id": "fx.drag.coplay", "audience": "parent", "text": {"zh-Hant": "陪孩子一起念每張卡片"}},
    }
    unit["beats"].insert(2, drag)
    _beat(unit, "b_choice")["stage"] = {"image": "img/box_peek", "a11y_label": {"zh-Hant": "只露出一角的箱子"}}
    unit["age_overrides"] = {"5-6": {"b_choice": {"option_ids": ["opt_a", "opt_b"], "hint": child("fx.choice.hint", "聽聽看誰在猜")}}}
    return unit


def _beat(unit: dict, beat_id: str) -> dict:
    return next(beat for beat in unit["beats"] if beat["id"] == beat_id)


def _node(unit: dict, node_id: str) -> dict:
    return next(node for node in unit["stories"][0]["nodes"] if node["id"] == node_id)


# 反例：(名稱, 預期規則代號, 修改單元, 修改猜測庫)
Mutation = Callable[[dict], None]


def NOOP(doc: dict) -> None:  # noqa: N802 — 在表格中當作常數使用
    """不修改。"""

INVALID_CASES: list[tuple[str, list[str], Mutation, Mutation]] = [
    ("nested_unknown_field", ["R-CLOSED"], lambda u: _beat(u, "b_choice").update(transcript="孩子說的話"), NOOP),
    ("asr_cloud_mode", ["R-CLOSED"], lambda u: _beat(u, "b_asr").update(recognition="cloud"), NOOP),
    ("emit_not_allowed", ["R-CLOSED"], lambda u: _beat(u, "b_asr").update(emit=["asr.done"]), NOOP),
    ("open_sandbox_with_truth", ["R-CLOSED"], lambda u: _beat(u, "b_sandbox").update(reaction_for_truth={"right": "r_right", "wrong": "r_unsure"}), NOOP),
    ("data_uri_in_text", ["R-STRING-LEAK"], lambda u: _beat(u, "b_intro")["lines"][0]["text"].update({"zh-Hant": "data:audio/x"}), NOOP),
    ("parent_card_url", ["R-STRING-LEAK"], lambda u: u["parent_card"]["text"].update({"zh-Hant": "請看 https://x.io"}), NOOP),
    ("guess_too_long", ["R-LEN"], NOOP, lambda b: b["guesses"][0]["guess_text"]["text"].update({"zh-Hant": "我" * 25})),
    ("missing_zh_hant", ["R-REQUIRED"], lambda u: _beat(u, "b_choice")["options"][2]["label"].update(text={"en": "Book"}), NOOP),
    ("image_without_a11y", ["R-REQUIRED"], lambda u: _beat(u, "b_choice")["options"][2].update(image="img/book"), NOOP),
    ("unsafe_guess", ["R-UNSAFE"], NOOP, lambda b: b["guesses"][0].update(safe=False)),
    ("unreviewed_guess", ["R-UNREVIEWED"], NOOP, lambda b: b["guesses"][0].pop("approved_hash")),
    ("approval_hash_mismatch", ["R-UNREVIEWED"], NOOP, lambda b: b["guesses"][0]["guess_text"]["text"].update({"zh-Hant": "我猜會下雨"})),
    ("broken_unit_still_checks_approval", ["R-CLOSED", "R-UNREVIEWED"], lambda u: _beat(u, "b_choice").update(transcript="x"), lambda b: b["guesses"][0].pop("approved_hash")),
    ("second_locale", ["R-CLOSED"], lambda u: _beat(u, "b_intro")["lines"][0]["text"].update({"zh-Hant-TW": "看這裡"}), NOOP),
    ("url_glued_to_chinese", ["R-STRING-LEAK"], lambda u: _beat(u, "b_intro")["lines"][0]["text"].update({"zh-Hant": "看www.ab.io"}), NOOP),
    ("javascript_scheme", ["R-STRING-LEAK"], lambda u: _beat(u, "b_intro")["lines"][0]["text"].update({"zh-Hant": "點javascript:x"}), NOOP),
    ("bare_domain", ["R-STRING-LEAK"], lambda u: _beat(u, "b_intro")["lines"][0]["text"].update({"zh-Hant": "看 evil.com 喔"}), NOOP),
    ("phone_with_dots", ["R-STRING-LEAK"], lambda u: _beat(u, "b_intro")["lines"][0]["text"].update({"zh-Hant": "請打0912.345.678"}), NOOP),
    ("asset_key_traversal", ["R-PATTERN"], lambda u: _beat(u, "b_choice")["options"][0].update(image="img/../secret"), NOOP),
    ("asset_key_hostname", ["R-PATTERN"], lambda u: _beat(u, "b_choice")["options"][0].update(image="img.evil.com/pixel"), NOOP),
    ("sound_without_script", ["R-REQUIRED"], lambda u: _beat(u, "b_choice")["options"][0].update(sound="sfx/voice"), NOOP),
    ("duplicate_option_id", ["R-DUP-ID"], lambda u: _beat(u, "b_choice")["options"][1].update(id="opt_a"), NOOP),
    ("override_drops_answer", ["R-REF"], lambda u: u.update(age_overrides={"5-6": {"b_choice": {"option_ids": ["opt_b", "opt_c"]}}}), NOOP),
    ("open_multiple_attempts", ["R-ENUM"], lambda u: _beat(u, "b_sandbox").update(max_attempts=2), NOOP),
    ("open_guess_with_truth", ["R-SANDBOX-TRUTH"], NOOP, lambda b: b["guesses"][0].update(truth="wrong")),
    ("same_role_ids", ["R-ROLE"], lambda u: u["ai_persona"].update(id="diandian"), NOOP),
    ("banned_word_zero_width", ["R-BANNED-WORD"], lambda u: _beat(u, "b_choice")["feedback"]["not_yet"]["text"].update({"zh-Hant": "錯\u200b了再試"}), NOOP),
    ("banned_word_simplified", ["R-BANNED-WORD"], lambda u: _beat(u, "b_choice")["feedback"]["not_yet"]["text"].update({"zh-Hant": "错了再试"}), NOOP),
    ("wrong_uncertainty", ["R-UNCERTAINTY"], NOOP, lambda b: b["guesses"][0].update(uncertainty_mark="sure")),
    ("slot_choice_without_guess", ["R-SANDBOX-COVERAGE"], lambda u: u["sandboxes"][0]["slots"][0]["choices"].append(option("rain", "下雨")), NOOP),
    ("guess_choice_not_in_slot", ["R-SANDBOX-CHOICE"], NOOP, lambda b: b["guesses"].append(approved({**copy.deepcopy(b["guesses"][0]), "id": "g_moon", "choice_id": "moon", "guess_text": child("fx.guess.moon", "我猜是月亮")}))),
    ("story_cycle", ["R-STORY-CYCLE"], lambda u: _node(u, "n2").update(next="n1"), NOOP),
    ("story_dangling_next", ["R-REF"], lambda u: _node(u, "n3").update(next="n9"), NOOP),
    ("story_both_next_and_end", ["R-SHAPE"], lambda u: _node(u, "n4").update(next="n1"), NOOP),
    ("banned_word", ["R-BANNED-WORD"], lambda u: _beat(u, "b_choice")["feedback"]["not_yet"]["text"].update({"zh-Hant": "錯了再試"}), NOOP),
    ("four_options", ["R-COUNT"], lambda u: _beat(u, "b_choice")["options"].append(option("opt_d", "杯子")), NOOP),
    ("sticker_needs_score", ["R-ENUM"], lambda u: _beat(u, "b_sticker").update(award="on_all_correct"), NOOP),
    ("sandbox_without_ritual", ["R-FLOW"], lambda u: u["beats"].remove(_beat(u, "b_ritual")), NOOP),
    ("too_long_unit", ["R-DURATION"], lambda u: u["meta"].update(max_seconds=300), NOOP),
    ("duplicate_text_id", ["R-DUP-ID"], lambda u: _node(u, "n3")["lines"][0].update(id="fx.n2"), NOOP),
]


def write(case_dir: Path, unit: dict, bank: dict, codes: list[str] | None = None) -> None:
    case_dir.mkdir(parents=True)
    for name, doc in (("unit.json", unit), ("guesses.json", bank)):
        (case_dir / name).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if codes is not None:
        (case_dir / "expected.json").write_text(json.dumps({"codes": codes}) + "\n", encoding="utf-8")


def main() -> None:
    for sub in ("valid", "invalid"):
        shutil.rmtree(HERE / sub, ignore_errors=True)
    write(HERE / "valid" / "base", base_unit(), base_bank())
    write(HERE / "valid" / "rich", rich_unit(), base_bank())
    for name, codes, mutate_unit, mutate_bank in INVALID_CASES:
        unit, bank = base_unit(), base_bank()
        mutate_unit(unit)
        mutate_bank(bank)
        write(HERE / "invalid" / name, unit, bank, codes)
    requests = {
        "valid": [{"sandbox_id": "box_1", "slot_id": "weather", "structured_choice": "sun"}],
        "invalid": [
            {"sandbox_id": "box_1", "slot_id": "weather", "structured_choice": "sun", "nickname": "x"},
            {"sandbox_id": "box_1", "slot_id": "weather", "structured_choice": None},
            {"sandbox_id": "box_1", "slot_id": "weather", "structured_choice": "我想要太陽"},
            {"sandbox_id": "box_1", "slot_id": "weather"},
        ],
    }
    (HERE / "requests.json").write_text(json.dumps(requests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # 重複鍵無法用 dict 表達，直接寫原始文字
    dup_dir = HERE / "invalid" / "duplicate_key"
    write(dup_dir, base_unit(), base_bank(), ["R-DUP-KEY"])
    (dup_dir / "extra.json").write_text('{"kind": "guess_bank", "kind": "unit"}\n', encoding="utf-8")


if __name__ == "__main__":
    main()
