"""JSON Schema 表達不了的內容規則：參照、流程、故事圖、沙盒覆蓋、字串掃描。

每個檢查回傳 Issue 清單；規則代號說明見 content/README.md。
"""

from __future__ import annotations

import hashlib
import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Iterator

# 單元節奏：intro → 小關 → story → review → sticker
GATE_TYPES = frozenset({"choice", "drag", "asr_repeat", "sandbox"})
MIN_GATES = 3
MAX_GATES = 5
MAX_STORY_BRANCH_DEPTH = 3

# 繁簡都擋；比對前先去掉零寬等看不見的字元（Unicode Cf 類）
BANNED_WORDS = ("錯了", "错了", "不對", "不对", "答錯", "答错", "失敗", "失败", "不正確", "不正确", "笨")

# 任何字串都不得出現（不用 \b：中文字與英文字母之間沒有字界）
LEAK_PATTERNS = (
    re.compile(r"(?i)data:[a-z]+/"),
    re.compile(r"(?i)://|javascript:|file:|www\."),
    re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"),
    re.compile(r"\+?\(?\d[\d\s().-]{7,}\d"),
)

# 只套用在給人看的文字上（id 允許用 . 分層，不適用）
PROSE_LEAK_PATTERNS = (
    re.compile(r"(?i)[a-z0-9-]+\.(?:com|net|org|io|tw|app|dev|xyz|info|ai|co|me|cc|ly|gg)(?![a-z])"),
    re.compile(r"[:@]"),
)
PROSE_KEYS = frozenset({"zh-Hant"})


@dataclass(frozen=True)
class Issue:
    code: str
    path: str
    message: str


def walk_strings(node: Any, path: str = "$") -> Iterator[tuple[str, str]]:
    """列出所有字串值（不含 key）與其路徑。"""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from walk_strings(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_strings(value, f"{path}[{index}]")
    elif isinstance(node, str):
        yield path, node


def _is_prose(path: str) -> bool:
    return path.rsplit(".", 1)[-1].split("[", 1)[0] in PROSE_KEYS


def _visible(value: str) -> str:
    return "".join(char for char in value if unicodedata.category(char) != "Cf")


def check_strings(doc: Any) -> list[Issue]:
    issues = []
    for path, value in walk_strings(doc):
        if unicodedata.normalize("NFC", value) != value:
            issues.append(Issue("R-NFC", path, "字串不是 NFC 正規化"))
        visible = _visible(value)
        patterns = LEAK_PATTERNS + (PROSE_LEAK_PATTERNS if _is_prose(path) else ())
        if any(pattern.search(visible) for pattern in patterns):
            issues.append(Issue("R-STRING-LEAK", path, "字串含網址、網域、data URI、email、電話或半形 : @"))
        found = [word for word in BANNED_WORDS if word in visible]
        if found:
            issues.append(Issue("R-BANNED-WORD", path, f"含禁用詞：{'、'.join(found)}"))
    return issues


def _ids(items: list[dict]) -> list[str]:
    return [item["id"] for item in items]


def _duplicates(values: list[str]) -> set[str]:
    seen, dups = set(), set()
    for value in values:
        (dups if value in seen else seen).add(value)
    return dups


def _text_ids(node: Any) -> Iterator[str]:
    if isinstance(node, dict):
        if "audience" in node and isinstance(node.get("id"), str):
            yield node["id"]
        for value in node.values():
            yield from _text_ids(value)
    elif isinstance(node, list):
        for value in node:
            yield from _text_ids(value)


def check_unique_ids(unit: dict) -> list[Issue]:
    groups = {
        "beats": _ids(unit["beats"]),
        "stories": _ids(unit["stories"]),
        "sandboxes": _ids(unit["sandboxes"]),
        "text ids": list(_text_ids(unit)),
    }
    for story in unit["stories"]:
        groups[f"story {story['id']} nodes"] = _ids(story["nodes"])
        for node in story["nodes"]:
            groups[f"story node {node['id']} choices"] = _ids(node.get("choices", []))
    for beat in unit["beats"]:
        for key in ("options", "items", "targets", "groups", "reactions", "questions"):
            groups[f"beat {beat['id']} {key}"] = _ids(beat.get(key, []))
        for question in beat.get("questions", []):
            groups[f"question {question['id']} options"] = _ids(question["options"])
    for box in unit["sandboxes"]:
        groups[f"sandbox {box['id']} slots"] = _ids(box["slots"])
        for slot in box["slots"]:
            groups[f"slot {slot['id']} choices"] = _ids(slot["choices"])
    for age, per_beat in unit.get("age_overrides", {}).items():
        for beat_id, fields in per_beat.items():
            groups[f"age_overrides {age} {beat_id} option_ids"] = fields.get("option_ids", [])
    issues = []
    for name, values in groups.items():
        for dup in sorted(_duplicates(values)):
            issues.append(Issue("R-DUP-ID", name, f"id 重複：{dup}"))
    return issues


def _check_subset(ids: list[str], allowed: set[str], path: str) -> list[Issue]:
    return [Issue("R-REF", path, f"引用不存在的 id：{value}") for value in ids if value not in allowed]


def _check_drag(beat: dict, path: str) -> list[Issue]:
    items = set(_ids(beat["items"]))
    mode = beat["mode"]
    if mode == "match":
        issues = _check_subset(list(beat["pairs"]), items, path + ".pairs")
        issues += _check_subset(list(beat["pairs"].values()), set(_ids(beat["targets"])), path + ".pairs")
        if set(beat["pairs"]) != items:
            issues.append(Issue("R-REF", path + ".pairs", "每個 item 都要配對"))
        return issues
    if mode == "order":
        orders = [beat["correct_order"], *beat.get("alt_orders", [])]
        issues = [
            Issue("R-REF", path + ".correct_order", "順序必須剛好包含所有 item 各一次")
            for order in orders
            if sorted(order) != sorted(items)
        ]
        if len({tuple(order) for order in orders}) != len(orders):
            issues.append(Issue("R-DUP-ID", path + ".alt_orders", "alt_orders 重複列出同一個順序"))
        return issues
    issues = _check_subset(list(beat["assignments"].values()), set(_ids(beat["groups"])), path + ".assignments")
    if set(beat["assignments"]) != items:
        issues.append(Issue("R-REF", path + ".assignments", "每個 item 都要分組"))
    return issues


def _options_of(beat: dict) -> list[str]:
    if beat["type"] in ("choice", "sandbox"):
        return _ids(beat.get("options") or beat.get("reactions", []))
    if beat["type"] == "drag":
        return _ids(beat["items"])
    return []


def check_references(unit: dict) -> list[Issue]:
    beats = unit["beats"]
    beat_by_id = {beat["id"]: beat for beat in beats}
    sandbox_ids = set(_ids(unit["sandboxes"]))
    story_ids = set(_ids(unit["stories"]))
    issues: list[Issue] = []
    for index, beat in enumerate(beats):
        path = f"$.beats[{index}]"
        kind = beat["type"]
        if kind == "choice" and beat["scoring"] == "graded":
            issues += _check_subset(beat["correct_option_ids"], set(_ids(beat["options"])), path)
        elif kind == "drag":
            issues += _check_drag(beat, path)
        elif kind == "sandbox":
            issues += _check_subset([beat["sandbox_ref"]], sandbox_ids, path + ".sandbox_ref")
            if "reaction_for_truth" in beat:
                issues += _check_subset(list(beat["reaction_for_truth"].values()), set(_ids(beat["reactions"])), path)
        elif kind == "story":
            issues += _check_subset([beat["story_ref"]], story_ids, path + ".story_ref")
        elif kind == "review":
            for question in beat["questions"]:
                issues += _check_subset(question["correct_option_ids"], set(_ids(question["options"])), path)
        elif kind == "asr_repeat" and "target_lines_by_option" in beat:
            issues += _check_asr_source(beat["target_lines_by_option"], beats[:index], path)
    issues += _check_age_overrides(unit.get("age_overrides", {}), beat_by_id)
    return issues


def _check_asr_source(spec: dict, earlier: list[dict], path: str) -> list[Issue]:
    source = next((beat for beat in earlier if beat["id"] == spec["from_beat"]), None)
    if source is None:
        return [Issue("R-REF", path, f"from_beat 必須是前面的 beat：{spec['from_beat']}")]
    options = set(_options_of(source))
    if set(spec["lines"]) != options:
        return [Issue("R-REF", path, "每個選項都要有對應的跟讀句")]
    return []


def _check_age_overrides(overrides: dict, beat_by_id: dict) -> list[Issue]:
    issues = []
    for age, per_beat in overrides.items():
        for beat_id, fields in per_beat.items():
            path = f"$.age_overrides.{age}.{beat_id}"
            beat = beat_by_id.get(beat_id)
            if beat is None:
                issues.append(Issue("R-REF", path, f"不存在的 beat：{beat_id}"))
                continue
            # hint 可以加在任何有題幹的 beat 上
            requires = {"prompt": "prompt", "hint": "prompt", "max_attempts": "max_attempts"}
            for field, needed in requires.items():
                if field in fields and needed not in beat:
                    issues.append(Issue("R-REF", path, f"此 beat 沒有可覆寫的 {field}"))
            if "option_ids" in fields:
                issues += _check_subset(fields["option_ids"], set(_options_of(beat)), path)
                correct = set(beat.get("correct_option_ids", []))
                if correct and not correct & set(fields["option_ids"]):
                    issues.append(Issue("R-REF", path, "覆寫後的選項必須包含正確答案"))
    return issues


def check_flow(unit: dict) -> list[Issue]:
    types = [beat["type"] for beat in unit["beats"]]
    issues = []

    def fail(message: str) -> None:
        issues.append(Issue("R-FLOW", "$.beats", message))

    if types[0] != "intro":
        fail("第一個 beat 必須是 intro")
    for kind in ("story", "review", "sticker"):
        if types.count(kind) != 1:
            fail(f"{kind} 必須剛好一個")
    if issues:
        return issues
    story_at, review_at, sticker_at = (types.index(kind) for kind in ("story", "review", "sticker"))
    if not (story_at < review_at < sticker_at == len(types) - 1):
        fail("順序必須是 story → review → sticker，且 sticker 在最後")
    if review_at != story_at + 1:
        fail("story 之後必須直接接 review")
    gates = [kind for kind in types[1:story_at] if kind in GATE_TYPES]
    if not MIN_GATES <= len(gates) <= MAX_GATES:
        fail(f"小關數量必須是 {MIN_GATES}–{MAX_GATES} 個，目前 {len(gates)} 個")
    if "intro" in types[1:]:
        fail("intro 只能在開頭")
    for index, kind in enumerate(types):
        if kind == "sandbox" and (index == 0 or types[index - 1] != "sandbox_ritual"):
            fail("每個 sandbox 前面都要緊接 sandbox_ritual")
        if kind == "sandbox_ritual" and (index + 1 >= len(types) or types[index + 1] != "sandbox"):
            fail("sandbox_ritual 後面必須緊接 sandbox")
    return issues


def check_duration(unit: dict) -> list[Issue]:
    total = sum(beat["est_seconds"] for beat in unit["beats"])
    limit = unit["meta"]["max_seconds"]
    if total > limit:
        return [Issue("R-DURATION", "$.beats", f"est_seconds 合計 {total} 秒，超過 max_seconds {limit}")]
    return []


def _story_edges(node: dict) -> list[str]:
    if "choices" in node:
        return [choice["next"] for choice in node["choices"]]
    if "next" in node:
        return [node["next"]]
    return []


def check_story(story: dict, index: int) -> list[Issue]:
    path = f"$.stories[{index}]"
    nodes = {node["id"]: node for node in story["nodes"]}
    issues = [
        Issue("R-REF", path, f"指向不存在的節點：{target}")
        for node in story["nodes"]
        for target in [story["start"], *_story_edges(node)]
        if target not in nodes
    ]
    if issues:
        return issues
    state: dict[str, str] = {}
    depth: dict[str, int] = {}

    def visit(node_id: str) -> bool:
        if state.get(node_id) == "active":
            return False
        if state.get(node_id) == "done":
            return True
        state[node_id] = "active"
        node = nodes[node_id]
        children_ok = all(visit(child) for child in _story_edges(node))
        child_depth = max((depth[child] for child in _story_edges(node) if child in depth), default=0)
        depth[node_id] = child_depth + (1 if "choices" in node else 0)
        state[node_id] = "done"
        return children_ok

    if not visit(story["start"]):
        return [Issue("R-STORY-CYCLE", path, "故事路徑繞回原處")]
    unreachable = sorted(set(nodes) - set(state))
    if unreachable:
        issues.append(Issue("R-STORY-UNREACHABLE", path, f"走不到的節點：{'、'.join(unreachable)}"))
    if depth[story["start"]] > MAX_STORY_BRANCH_DEPTH:
        issues.append(Issue("R-STORY-DEPTH", path, f"一條路徑最多 {MAX_STORY_BRANCH_DEPTH} 個分歧"))
    return issues


def check_roles(unit: dict) -> list[Issue]:
    if unit["narrator"]["id"] == unit["ai_persona"]["id"]:
        return [Issue("R-ROLE", "$.ai_persona.id", "旁白（不是 AI）與 AI 角色的 id 不得相同")]
    return []


def check_unit(unit: dict) -> list[Issue]:
    issues = check_unique_ids(unit) + check_references(unit) + check_flow(unit) + check_duration(unit) + check_roles(unit)
    for index, story in enumerate(unit["stories"]):
        issues += check_story(story, index)
    return issues


def approval_hash(guess: dict) -> str:
    text = unicodedata.normalize("NFC", guess["guess_text"]["text"]["zh-Hant"])
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def check_approvals(bank: dict) -> list[Issue]:
    """核准綁定文字：approved_hash 缺少或與目前文字不符，都算未核准。"""
    return [
        Issue("R-UNREVIEWED", f"$.guesses[{index}]", f"Michael 尚未核准這段文字（核准碼應為 {approval_hash(guess)}）")
        for index, guess in enumerate(bank["guesses"])
        if guess.get("approved_hash") != approval_hash(guess)
    ]


def check_guess_bank(bank: dict, units: dict[str, dict]) -> list[Issue]:
    unit = units.get(bank["unit_id"])
    sandbox = next((box for box in (unit or {}).get("sandboxes", []) if box["id"] == bank["sandbox_id"]), None)
    if sandbox is None:
        return [Issue("R-BANK-ORPHAN", "$", f"找不到 {bank['unit_id']} 的沙盒 {bank['sandbox_id']}")]
    choices = {slot["id"]: set(_ids(slot["choices"])) for slot in sandbox["slots"]}
    graded = any(
        beat["type"] == "sandbox" and beat["sandbox_ref"] == sandbox["id"] and beat["scoring"] == "graded"
        for beat in unit["beats"]
    )
    limit = sandbox.get("max_guess_chars", 24)
    issues = [Issue("R-DUP-ID", "$.guesses", f"id 重複：{dup}") for dup in sorted(_duplicates(_ids(bank["guesses"])))]
    covered = set()
    for index, guess in enumerate(bank["guesses"]):
        path = f"$.guesses[{index}]"
        if guess["choice_id"] not in choices.get(guess["slot_id"], set()):
            issues.append(Issue("R-SANDBOX-CHOICE", path, f"{guess['slot_id']}／{guess['choice_id']} 不是沙盒裡的選項"))
        covered.add((guess["slot_id"], guess["choice_id"]))
        if "required_uncertainty" in sandbox and guess["uncertainty_mark"] != sandbox["required_uncertainty"]:
            issues.append(Issue("R-UNCERTAINTY", path, f"uncertainty_mark 必須是 {sandbox['required_uncertainty']}"))
        if len(guess["guess_text"]["text"]["zh-Hant"]) > limit:
            issues.append(Issue("R-GUESS-LEN", path, f"猜測超過 {limit} 字"))
        if graded != ("truth" in guess):
            issues.append(Issue("R-SANDBOX-TRUTH", path, "graded 沙盒的猜測必須有 truth；open 沙盒不得有"))
    missing = sorted(f"{slot}／{choice}" for slot, ids in choices.items() for choice in ids if (slot, choice) not in covered)
    if missing:
        issues.append(Issue("R-SANDBOX-COVERAGE", "$.guesses", f"沒有猜測的選項：{'、'.join(missing)}"))
    return issues


def check_banks_exist(units: dict[str, dict], banks: list[dict]) -> list[Issue]:
    have = {(bank["unit_id"], bank["sandbox_id"]) for bank in banks}
    return [
        Issue("R-SANDBOX-COVERAGE", f"{unit_id}", f"沙盒 {box['id']} 沒有猜測庫")
        for unit_id, unit in units.items()
        for box in unit["sandboxes"]
        if (unit_id, box["id"]) not in have
    ]
