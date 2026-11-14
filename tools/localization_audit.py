#!/usr/bin/env python3
"""Audit SkinAI translation tables and common hardcoded UI-string patterns."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


LANGUAGES = ("en", "ku", "bad", "ar")
DOMAINS = ("app", "settings", "notifications", "routines", "widgets")
UNCHANGED_TEXT_ALLOWLIST = {"emailHint"}
DOMAIN_PATTERN = re.compile(r"(?m)^\s{2}'([^']+)':(?:<[^>]+>)?\s*\{")
KEY_PATTERN = re.compile(r"(?m)^\s{4}'([^']+)':\s*(.*)$")
STRING_PATTERN = re.compile(r"""(['"])((?:\\.|(?!\1).)*?)\1""", re.DOTALL)
VISIBLE_LITERAL_PATTERNS = (
    re.compile(r'''\bText\(\s*(['"])([^'"\n]+)\1'''),
    re.compile(
        r'''\b(?:hintText|labelText|tooltip|semanticLabel)\s*:\s*(['"])([^'"\n]+)\1'''
    ),
    re.compile(
        r'''\b(?:label|group|title|body|message)\s*:\s*(['"])([^'"\n]+)\1'''
    ),
)


def _literal_value(expression: str) -> str:
    return "".join(match.group(2) for match in STRING_PATTERN.finditer(expression))


def load_translation_file(
    path: Path,
) -> tuple[dict[str, dict[str, str]], list[str], list[str]]:
    source = path.read_text(encoding="utf-8")
    domains: dict[str, dict[str, str]] = {}
    duplicates: list[str] = []
    empty_values: list[str] = []
    domain_matches = list(DOMAIN_PATTERN.finditer(source))

    for domain_index, match in enumerate(domain_matches):
        domain = match.group(1)
        stop = (
            domain_matches[domain_index + 1].start()
            if domain_index + 1 < len(domain_matches)
            else len(source)
        )
        body = source[match.end() : stop]
        key_matches = list(KEY_PATTERN.finditer(body))
        entries: dict[str, str] = {}
        for key_index, key_match in enumerate(key_matches):
            key = key_match.group(1)
            if key in entries:
                duplicates.append(f"{domain}.{key}")
            expression_end = (
                key_matches[key_index + 1].start()
                if key_index + 1 < len(key_matches)
                else len(body)
            )
            expression = key_match.group(2) + body[key_match.end() : expression_end]
            value = _literal_value(expression)
            entries[key] = value
            if not value.strip():
                empty_values.append(f"{domain}.{key}")
        domains[domain] = entries
    return domains, duplicates, empty_values


def _localization_references(root: Path) -> list[str]:
    sources = {
        "app": root / "lib" / "main.dart",
        "routines": root / "lib" / "routines" / "routine_screens.dart",
        "notifications": root / "lib" / "notifications" / "notification_screens.dart",
    }
    errors: list[str] = []
    english, _, _ = load_translation_file(
        root / "lib" / "localization" / "translations" / "en.dart"
    )

    for relative, path in sources.items():
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(
            r"\b(?:controller|a)\.(t|settingsText|routineText)\('([^']+)'\)",
            source,
        ):
            method, key = match.groups()
            if "$" in key or "{" in key:
                continue
            allowed = {
                "t": ("app",),
                "settingsText": ("settings", "app"),
                "routineText": ("routines", "widgets"),
            }[method]
            if not any(key in english.get(domain, {}) for domain in allowed):
                errors.append(f"{relative}:{key}")

        if relative.endswith("routine_screens.dart"):
            routine_end = source.find("class RoutineTaskEditor")
            widget_start = source.find("class WidgetGalleryScreen")
            for match in re.finditer(r"_t\('([^']+)'\)", source):
                key = match.group(1)
                if "$" in key or "{" in key:
                    continue
                if match.start() < routine_end:
                    allowed = ("routines", "widgets")
                elif match.start() > widget_start:
                    allowed = ("widgets",)
                else:
                    continue
                if not any(key in english.get(domain, {}) for domain in allowed):
                    errors.append(f"{relative}:{key}")
        elif relative.endswith("notification_screens.dart"):
            for match in re.finditer(r"_t\('([^']+)'\)", source):
                key = match.group(1)
                if "$" not in key and key not in (
                    english.get("notifications", {}).keys()
                    | english.get("app", {}).keys()
                ):
                    errors.append(f"{relative}:{key}")
    return errors


def _hardcoded_visible_candidates(root: Path) -> list[str]:
    candidates: list[str] = []
    localization_dir = root / "lib" / "localization"
    for path in (root / "lib").rglob("*.dart"):
        if localization_dir in path.parents:
            continue
        source = path.read_text(encoding="utf-8")
        for pattern in VISIBLE_LITERAL_PATTERNS:
            for match in pattern.finditer(source):
                value = match.group(2).strip()
                if (
                    value
                    and "$" not in value
                    and value not in {"SkinAI", "Skin AI", "SKIN AI"}
                    and re.search(r"[A-Za-z]{2}", value)
                ):
                    line = source.count("\n", 0, match.start()) + 1
                    candidates.append(
                        f"{path.relative_to(root).as_posix()}:{line}: {value}"
                    )
    return candidates


def audit(root: Path) -> dict[str, object]:
    locale_domains: dict[str, dict[str, dict[str, str]]] = {}
    duplicates: list[str] = []
    empty_values: list[str] = []
    for language in LANGUAGES:
        path = root / "lib" / "localization" / "translations" / f"{language}.dart"
        locale_domains[language], file_duplicates, file_empty = (
            load_translation_file(path)
        )
        duplicates.extend(f"{language}.{entry}" for entry in file_duplicates)
        empty_values.extend(f"{language}.{entry}" for entry in file_empty)

    english_domains = locale_domains["en"]
    missing: dict[str, dict[str, list[str]]] = {}
    extra: dict[str, dict[str, list[str]]] = {}
    untranslated: list[str] = []
    badini_sorani_matches: list[str] = []
    coverage: dict[str, dict[str, tuple[int, int]]] = {}

    for language in LANGUAGES:
        coverage[language] = {}
        missing[language] = {}
        extra[language] = {}
        for domain in DOMAINS:
            baseline = english_domains.get(domain, {})
            translated = locale_domains[language].get(domain, {})
            missing_keys = sorted(set(baseline) - set(translated))
            extra_keys = sorted(set(translated) - set(baseline))
            missing[language][domain] = missing_keys
            extra[language][domain] = extra_keys
            coverage[language][domain] = (
                len(set(baseline) & set(translated)),
                len(baseline),
            )
            if language != "en":
                for key, value in translated.items():
                    if (
                        key not in UNCHANGED_TEXT_ALLOWLIST
                        and key in baseline
                        and value
                        and value == baseline[key]
                    ):
                        untranslated.append(f"{language}.{domain}.{key}")

    for domain, sorani_entries in locale_domains["ku"].items():
        badini_entries = locale_domains["bad"].get(domain, {})
        badini_sorani_matches.extend(
            f"{domain}.{key}"
            for key, value in sorani_entries.items()
            if badini_entries.get(key) == value
        )

    references = _localization_references(root)
    hardcoded = _hardcoded_visible_candidates(root)
    return {
        "coverage": coverage,
        "missing": missing,
        "extra": extra,
        "duplicates": duplicates,
        "empty_values": empty_values,
        "untranslated": sorted(set(untranslated)),
        "badini_sorani_matches": sorted(set(badini_sorani_matches)),
        "invalid_references": sorted(set(references)),
        "hardcoded_visible_candidates": hardcoded,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="SkinAI project root (defaults to the parent of tools/).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Also fail on untranslated entries and hardcoded visible candidates.",
    )
    args = parser.parse_args()
    report = audit(args.root.resolve())

    print("Translation key coverage:")
    for language in LANGUAGES:
        total = covered = 0
        for count, size in report["coverage"][language].values():
            covered += count
            total += size
        percentage = 100.0 if total == 0 else covered / total * 100
        print(f"  {language}: {covered}/{total} ({percentage:.1f}%)")
        for domain, keys in report["missing"][language].items():
            if keys:
                print(f"    missing {domain}: {len(keys)}")
    if any(report["missing"]["bad"][domain] for domain in DOMAINS):
        print("  Badini: blocked pending native-reviewed translations.")

    for key in (
        "duplicates",
        "empty_values",
        "untranslated",
        "badini_sorani_matches",
        "invalid_references",
        "hardcoded_visible_candidates",
    ):
        values = report[key]
        if key == "badini_sorani_matches":
            print(
                "Badini entries identical to Sorani: "
                f"{len(values)}/"
                f"{sum(size for _, size in report['coverage']['ku'].values())}"
            )
        else:
            print(f"{key.replace('_', ' ')}: {len(values)}")
        for value in values[:12]:
            print(f"  {value}")
        if len(values) > 12:
            print(f"  ... {len(values) - 12} more")

    incomplete = any(
        report["missing"][language][domain]
        for language in LANGUAGES
        for domain in DOMAINS
    )
    has_findings = (
        incomplete
        or report["duplicates"]
        or report["empty_values"]
        or report["untranslated"]
        or report["badini_sorani_matches"]
        or report["invalid_references"]
        or (
            args.strict
            and (
                report["untranslated"]
                or report["hardcoded_visible_candidates"]
            )
        )
    )
    return 1 if has_findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
