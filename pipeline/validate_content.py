#!/usr/bin/env python3
"""驗證 content/ 的單元檔與猜測庫。

用法：
  validate_content.py                     驗證 content/ 下所有內容檔（schema/ 除外）
  validate_content.py --fixtures          跑 pipeline/fixtures/ 的正反例
  validate_content.py --allow-unreviewed  草稿階段暫時放行未核准的猜測（CI 不得使用）

每個錯誤都有規則代號，說明見 content/README.md。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from content_rules import Issue, check_approvals, check_banks_exist, check_guess_bank, check_strings, check_unit

ROOT = Path(__file__).resolve().parent.parent
CONTENT_DIR = ROOT / "content"
SCHEMA_DIR = CONTENT_DIR / "schema"
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

SCHEMA_FILES = {"unit": "unit.schema.json", "guess_bank": "sandbox.schema.json"}

# jsonschema 的 keyword → 規則代號
KEYWORD_CODES = {
    None: "R-CLOSED",  # false schema：此欄位不得出現
    "unevaluatedProperties": "R-CLOSED",
    "additionalProperties": "R-CLOSED",
    "required": "R-REQUIRED",
    "dependentRequired": "R-REQUIRED",
    "maxLength": "R-LEN",
    "minLength": "R-LEN",
    "minItems": "R-COUNT",
    "maxItems": "R-COUNT",
    "minProperties": "R-COUNT",
    "const": "R-ENUM",
    "enum": "R-ENUM",
    "pattern": "R-PATTERN",
    "propertyNames": "R-PATTERN",
    "type": "R-TYPE",
    "minimum": "R-RANGE",
    "maximum": "R-RANGE",
}


class DuplicateKeyError(ValueError):
    pass


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    keys = [key for key, _ in pairs]
    dups = sorted({key for key in keys if keys.count(key) > 1})
    if dups:
        raise DuplicateKeyError(f"重複的鍵：{'、'.join(dups)}")
    return dict(pairs)


def load_json(path: Path) -> tuple[object | None, list[Issue]]:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicate_keys), []
    except DuplicateKeyError as error:
        return None, [Issue("R-DUP-KEY", "$", str(error))]
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        return None, [Issue("R-JSON", "$", str(error))]


REQUEST_REF = "https://kidsai.invalid/schema/sandbox.schema.json#/$defs/request"


def build_validators() -> dict[str, Draft202012Validator]:
    schemas = {}
    for path in sorted(SCHEMA_DIR.glob("*.schema.json")):
        schema = json.loads(path.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        schemas[path.name] = schema
    registry = Registry().with_resources(
        (schema["$id"], Resource.from_contents(schema)) for schema in schemas.values()
    )
    validators = {
        kind: Draft202012Validator(schemas[name], registry=registry)
        for kind, name in SCHEMA_FILES.items()
    }
    validators["request"] = Draft202012Validator({"$ref": REQUEST_REF}, registry=registry)
    return validators


def _is_within(path: str, ancestor: str) -> bool:
    return path == ancestor or path.startswith(ancestor + ".") or path.startswith(ancestor + "[")


def schema_issues(validator: Draft202012Validator, doc: object) -> list[Issue]:
    issues = []
    for error in validator.iter_errors(doc):
        path = error.json_path
        code = KEYWORD_CODES.get(error.validator, "R-SHAPE")
        if error.validator == "const" and path.endswith(".safe"):
            code = "R-UNSAFE"
        issues.append((error.validator, Issue(code, path, error.message)))
    # 分支驗證失敗時，2020-12 會丟掉該分支的標註，上層的 unevaluatedProperties 因此連帶報錯。
    # 同一路徑或更深處已有其他錯誤時，略過這種連帶的 R-CLOSED。
    specific = [issue.path for keyword, issue in issues if keyword != "unevaluatedProperties"]
    return [
        issue
        for keyword, issue in issues
        if keyword != "unevaluatedProperties" or not any(_is_within(other, issue.path) for other in specific)
    ]


def validate_set(files: list[Path], validators: dict, allow_unreviewed: bool) -> dict[Path, list[Issue]]:
    """驗證一組檔案（單元檔與猜測庫會互相參照）。"""
    results: dict[Path, list[Issue]] = {}
    units: dict[str, dict] = {}
    unit_paths: dict[str, Path] = {}
    banks: list[tuple[Path, dict]] = []
    bank_keys: list[dict] = []  # 含格式不合的猜測庫，避免連帶誤報「沒有猜測庫」
    broken_units: set[str] = set()  # 格式不合的單元：跳過其猜測庫的交叉檢查
    for path in files:
        doc, issues = load_json(path)
        if doc is not None:
            issues += check_strings(doc)
            kind = doc.get("kind") if isinstance(doc, dict) else None
            if kind == "guess_bank":
                bank_keys.append({"unit_id": doc.get("unit_id"), "sandbox_id": doc.get("sandbox_id")})
            if kind not in SCHEMA_FILES:
                issues.append(Issue("R-KIND", "$.kind", f"未知的 kind：{kind}"))
            else:
                shape = schema_issues(validators[kind], doc)
                issues += shape
                if not shape and kind == "unit":
                    issues += check_unit(doc)
                    units[doc["unit_id"]] = doc
                    unit_paths[doc["unit_id"]] = path
                elif not shape and kind == "guess_bank":
                    banks.append((path, doc))
                    if not allow_unreviewed:
                        issues += check_approvals(doc)
                elif kind == "unit":
                    broken_units.add(doc.get("unit_id"))
        results[path] = issues
    for path, bank in banks:
        if bank["unit_id"] not in broken_units:
            results[path] += check_guess_bank(bank, units)
    for issue in check_banks_exist(units, bank_keys):
        results[unit_paths[issue.path]].append(issue)
    return results


def content_files() -> list[Path]:
    return sorted(path for path in CONTENT_DIR.rglob("*.json") if SCHEMA_DIR not in path.parents)


def run_content(validators: dict, allow_unreviewed: bool) -> int:
    files = content_files()
    if not files:
        print("content/ 沒有內容檔")
        return 0
    failed = False
    for path, issues in validate_set(files, validators, allow_unreviewed).items():
        name = path.relative_to(ROOT)
        if issues:
            failed = True
            for issue in issues:
                print(f"{name}: {issue.code} {issue.path}: {issue.message}")
        else:
            print(f"{name}: OK")
    return 1 if failed else 0


def run_request_fixtures(validators: dict) -> bool:
    """沙盒請求格式（S2 白名單）：valid 全部要通過、invalid 全部要被擋。"""
    samples = json.loads((FIXTURES_DIR / "requests.json").read_text(encoding="utf-8"))
    ok = True
    for expect_valid in (True, False):
        for sample in samples["valid" if expect_valid else "invalid"]:
            passed = validators["request"].is_valid(sample)
            ok &= passed == expect_valid
            print(f"{'PASS' if passed == expect_valid else 'FAIL'} request {'valid' if expect_valid else 'invalid'}: {sample}")
    return ok


def run_fixtures(validators: dict) -> int:
    failed = not run_request_fixtures(validators)
    for case in sorted(p for p in FIXTURES_DIR.glob("*/*") if p.is_dir()):
        files = sorted(p for p in case.glob("*.json") if p.name != "expected.json")
        found = sorted({issue.code for issues in validate_set(files, validators, False).values() for issue in issues})
        expected_file = case / "expected.json"
        expected = sorted(json.loads(expected_file.read_text(encoding="utf-8"))["codes"]) if expected_file.exists() else []
        ok = found == expected
        failed |= not ok
        label = case.relative_to(FIXTURES_DIR)
        print(f"{'PASS' if ok else 'FAIL'} {label}: 預期 {expected or '無錯誤'}，實際 {found or '無錯誤'}")
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fixtures", action="store_true", help="跑 pipeline/fixtures/ 的正反例")
    parser.add_argument("--allow-unreviewed", action="store_true", help="暫時放行未核准的猜測（草稿用，CI 不得使用）")
    args = parser.parse_args()
    validators = build_validators()
    if args.fixtures:
        return run_fixtures(validators)
    return run_content(validators, args.allow_unreviewed)


if __name__ == "__main__":
    sys.exit(main())
