# SkinAI Localization Audit Report

Date: 2026-11-13

## Status

**Localization is not complete.** The translation tables have full structural key
coverage, but Badini is a copy of Sorani, multiple user-visible strings bypass
the translation tables, and some requested runtime behavior has not been
verified in the running UI.

This report distinguishes key coverage from translation quality. A present,
non-empty value does not establish that it is natural or medically accurate.

## Translation coverage

The app's current custom catalog contains 514 English keys across five domains:
`app`, `settings`, `notifications`, `routines`, and `widgets`.

| Language | Catalog keys present | Missing keys | Content / review status |
| --- | ---: | ---: | --- |
| English | 514/514 (100%) | 0 | Source catalog; no remaining key gaps |
| Kurdish Sorani | 514/514 (100%) | 0 | Structurally complete; linguistic review not independently established |
| Kurdish Badini | 514/514 (100%) | 0 | **0/514 values differ from Sorani; not a Badini translation** |
| Arabic | 514/514 (100%) | 0 | Structurally complete; linguistic review not independently established |

The Badini locale code is accepted by the app, but its catalog duplicates all
514 Sorani values. The home-widget label map also groups `badini` with `ku`,
returning the same Sorani labels. The existing key-coverage tests pass because
they check key presence and non-empty values, not dialect identity or quality.

## Hardcoded-string scan

The expanded `tools/localization_audit.py` scan reports **159 hardcoded visible
string candidates**. Candidates need triage; some are exception messages that
may not be displayed directly. Confirmed user-visible gaps include:

- The body-region selector has 88 literal region-label entries (65 distinct
  labels). These feed chips, selected-area summaries, map tooltips, and
  semantic labels; category headings and group classifications are also
  hardcoded in English.
- The interactive body map has literal front/back instructions and selection
  semantics; the region count uses hardcoded English singular/plural forms.
- Routine defaults and reminder flows include English task names, notification
  titles, and message bodies outside the translation tables.
- The scan flow has English fallback strings such as “Concern not selected” and
  “Body area not selected.”

The current audit script checks catalog key references and common literal
patterns; its result is not proof that every screen, dialog, tooltip, native
notification, or dynamic string has been manually reviewed.

## Runtime behavior checks

- **RTL/LTR:** `LocaleHelper` configures RTL for Sorani, Badini, and Arabic, and
  LTR for English. This was verified by unit tests, not by visual inspection of
  every screen.
- **Immediate switching:** the `AppController` test verifies that translated
  values update when its language changes. A full UI test covering all routes
  was not run.
- **Persistence:** tests verify that preferences restore after constructing a
  new controller, including legacy Badini preference values.
- **Preserving screen and input:** there is no integration test demonstrating
  that switching languages preserves the current route and every in-progress
  form value.
- **Fonts:** no locale-specific `fontFamily` or font assets are configured in
  the Flutter theme. Platform font fallback may render scripts, but language-
  dependent font changes were not verified and are not implemented explicitly.

## Medical and medication terminology

The English catalog includes screening/disclaimer wording and medical labels
such as actinic keratosis, vascular lesion, and acne. The app also contains
sunscreen reminders and skincare routine actions. A source scan found no
prescription drug names or dosage instructions in the catalog.

Badini cannot pass medical-term review while it duplicates Sorani. The medical
and medication-related wording in Sorani and Arabic has not been independently
reviewed by qualified native speakers with relevant terminology expertise.
Therefore no claim of clinically accurate translation is made.

## Commands and tests

| Check | Result |
| --- | --- |
| `flutter gen-l10n` | **Not applicable to the current custom catalog; command exits 1** because `flutter: generate: true` and ARB inputs are not configured. No localization architecture change was made. |
| `flutter analyze` | Passed: no issues found |
| `flutter test test/localization_test.dart` | Passed: 8 tests |
| `python -m py_compile tools/localization_audit.py` | Passed |
| `python tools/localization_audit.py` | Exits 1 after reporting 514/514 Badini/Sorani value matches and 159 hardcoded-string candidates |

## Conclusion and required follow-up

The catalogs have complete key counts, and the controller-level direction,
language-change, and preference checks pass. The application is **not fully
localized**: Badini requires native translation, confirmed hardcoded UI strings
must be moved into the catalogs, and UI preservation/font behavior needs
runtime verification. A qualified review is also needed for medical wording.
