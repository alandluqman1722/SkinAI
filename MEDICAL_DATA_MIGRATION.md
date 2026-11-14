# Medical data integration notes

## Current implementation boundary

The authenticated FastAPI service now exposes owner-scoped record endpoints at
`/medical/records/{record_type}`. Records are stored under
`users/{firebaseUid}/medical_records/{recordId}`; change audit events are stored
under `users/{firebaseUid}/medical_audit/{eventId}`. The service derives the
Firebase UID from the verified bearer token. A UID supplied in a record is
rejected by strict schema validation.

User-writable record types are medications, medication history, treatment
plans, routines, routine completions, and health reports. Scan/comparison,
appointment, doctor-review, and medical-notification records are not writable
through generic client CRUD because they require trusted analysis or a verified
provider/alert workflow. Original scan image endpoints require an existing
owner-scoped scan and explicit `storage_consent=true`; image reads go through
the authenticated API and never return a public object URL.

`POST /analyze` retains its existing response contract and accepts two optional
multipart flags: `save_history` (default `false`) and
`image_storage_consent` (default `false`). Mock analyses cannot be saved as
medical records. The Flutter scanner now sends its Firebase ID token as a
bearer token and sets `save_history` only after account-history consent. The
image flag is intentionally not sent with analysis: after the server confirms
the analysis and record, a separate authenticated image upload sends
`storage_consent=true`. This keeps an image-storage failure from discarding a
completed analysis.

The scanner has separate controls for existing device history, account scan
records, and original-image storage. A confirmation dialog offers an
analysis-only choice before an opted-in account save. Original-image storage can only be selected after the authenticated
integration-status endpoint reports local storage available. The original is
sent only to the private backend endpoint; it is never uploaded to a public URL.

The history screen loads authenticated owner-scoped records and keeps
device-only records visible as a separate source. Existing `scans_{email}`
preferences are neither imported nor overwritten. Clearing device history
affects only device records. Account scans support authenticated details,
metadata edits (`PATCH /medical/scans/{id}` updates only body location and user
notes), authenticated private-image reads, and per-record deletion. A local
copy of an account record is removed only after the backend confirms deletion.
The analysis ID is the stable record ID used for deduplication.

## Required configuration

- Firebase Admin service-account configuration already required by the API.
- `SKINAI_IMAGE_STORAGE_DIR` optionally selects the private local image
  directory. The default is `backend/uploads/skin_images` under the repository.
- `MEDICINE_RECOGNITION_URL` and `MEDICINE_REFERENCE_URL` for verified medicine
  recognition and information.
- `VERIFIED_DOCTOR_DIRECTORY_URL` for verified provider search and appointment
  workflows.
- `SKIN_ASSISTANT_URL` for an assistant backed by authorized real records.

The medical integration status endpoint reports whether these URLs and local
image storage are configured. A configured URL alone does not certify the
external source; the API currently does not call these external systems.

## Migration and deployment

No existing local scan history or `scan_log.jsonl` data is migrated. The new
Firestore subcollections are created on first write; no existing collection is
renamed or modified. Deploy the backend before enabling client writes. Keep
Firestore rules deny-by-default: these records are accessed through the
authenticated backend's Admin SDK, not direct client Firestore access.

If a later, separately approved feature migrates local history, it should
preview each device-only record, require per-account consent, create a new
server record without replacing the local copy, and remove or relabel the
local copy only after the backend confirms the new owner-scoped record. Records
without a stable scan ID must not be deduplicated by result text or timestamp.

Images are stored as random UUID-named files in the private backend directory;
Firestore stores owner UID, image ID, opaque relative file path, MIME type,
upload time, and byte size only. The upload directory is not mounted as a
static route. Local storage is suitable for development. Production must mount
`SKINAI_IMAGE_STORAGE_DIR` to a persistent volume: files in an ephemeral
container filesystem can be lost when an instance is replaced or redeployed.

Existing Firebase Storage objects are not automatically copied or deleted by
this change. Legacy records without local-file metadata no longer return their
old cloud images; migrate or clean up those objects separately before
decommissioning any existing bucket.

The legacy `/analyze` endpoint still appends its existing metadata-only JSONL
log for compatibility. That file is not owner-scoped and is not the secure
medical-record store; do not expose it or treat it as user history.

The API writes each record mutation and its audit event in one Firestore batch.
Filesystem writes and Firestore writes cannot share a transaction; the API
cleans up files when metadata persistence fails, but deployments should monitor
for orphaned files. Account deletion must remove that user's `medical_records`,
`medical_audit`, SkinChat conversations, and associated UUID files; account-wide
deletion cleanup is not implemented yet.

## Scan-history implementation and verification

The Flutter-to-backend scanner and history wiring, consent controls, owner
scoping, metadata update, deletion, and private-image API boundary are
implemented. Existing local history remains separate and is not automatically
migrated. This is not a clinical diagnosis or medical functionality.

Verified in this repository:

- `flutter analyze` — passed with no issues.
- `flutter test test\\medical_scan_api_test.dart test\\localization_test.dart test\\body_scan_flow_test.dart`
  — 17 tests passed, including bearer authentication, consent flags, storage
  status, authenticated API operations, error handling, and all four language
  catalogs.
- `flutter test test\\widget_test.dart --plain-name "remote history stays separate and clearing does not migrate or erase it"`
  — passed; prior local records remain separate from account records.
- `python -m pytest -q tests\\test_medical_records.py tests\\test_scanskin_api.py tests\\test_firebase_app.py`
  — 29 tests passed, including end-to-end owner-only scan list/update,
  private-image consent/read, cross-owner denial, and confirmed deletion tests.

The tests use mocked Firebase/Firestore boundaries and FastAPI in-process
integration with a temporary local image directory; they do not verify a
production persistent volume. Do not declare the full Scan History workflow
operational until a signed-in client has verified save, image upload/read,
metadata edit, and deletion against the deployed API. Other medical modules,
local-history migration, and account-wide deletion remain outside this
integration.
