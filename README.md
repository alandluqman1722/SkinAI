# SkinAI

SkinAI is a Flutter app with a FastAPI backend. Skin-condition screening uses
the official Ivy AI API documented at <https://www.ivyai.hk/docs>. The backend
reads `IVYAI_API_KEY`; the key is never sent to or embedded in Flutter.

This is a screening tool, not a medical diagnosis. Please consult a healthcare
professional.

## Architecture

- Flutter uploads a selected image to `POST /analyze` with the signed-in
  Firebase user's bearer token.
- FastAPI verifies Firebase authentication, validates and converts the image to
  JPEG, and forwards it to
  `https://scanskinai.aihealthpred.com/api/detect/` using multipart field
  `input_image` and header `X-API-KEY`.
- The server accepts JPG, PNG, WebP, BMP, GIF, and TIFF uploads up to 10 MB;
  the provider receives a JPEG resized to at most 2000 pixels on its longest
  side.
- Optional location, duration, symptoms, and change-over-time fields are
  forwarded only when selected in the structured scanner controls.
- Successful responses are saved as generated IDs and timestamps in the local
  `scan_log.jsonl` file. Images and symptom fields are not written to that log.
- `GET /health` reports service status. `MOCK_API=1` returns an explicitly
  labeled test response without making an Ivy AI call; Firebase authentication
  still applies, and test responses cannot be saved as medical records.
- The Flutter app supports English, Sorani Kurdish, Badini Kurdish, and Arabic,
  including RTL support, and renders provider summaries as Markdown without
  loading remote images or opening links.
- SkinChat AI stores conversations under the authenticated Firebase user's
  Firestore account and images in a private local directory managed by
  FastAPI. Its endpoints reuse the existing Firebase token, email-verification,
  and blocked-account checks. Images are served only through authenticated,
  owner-scoped API endpoints. Image access is currently owner-only; the app has
  no doctor-to-patient image permission workflow, so doctor accounts cannot
  read another user's files.
- SkinChat conversation history, image storage, and localized safety responses
  remain available in English, Sorani Kurdish, Badini Kurdish, and Arabic.
  General generated skincare answers are unavailable until a supported text
  provider is integrated.
- SkinChat images remain in private backend file storage for the user's own
  conversation history. Image bytes are not sent to an AI provider, and
  requests to diagnose or interpret uploaded photos are refused.
- The backend blocks unrelated questions and provides localized medical-safety
  and urgent-care guidance. Daily limits default to 10
  messages for free users and 100 for paid users; paid limits require verified
  Firebase custom claims `skinchat_plan=paid` and
  `skinchat_subscription_status=active`. Missing or inactive claims get the
  free allowance.
- Dermatologist discovery uses real Firestore profiles from `doctors`; no
  sample doctors, clinics, coordinates, reviews, or ratings are seeded.
  Directory reads expose only published profiles, and a verified badge is
  shown only after an administrator approves the profile's verification.
- Doctor favorites are scoped to `users/{uid}`. Appointment requests, slot
  locks, reviews, and reports are server-validated and stored in
  `doctor_appointments`, `doctor_appointment_slots`, `doctor_reviews`, and
  `doctor_review_reports`. Verification documents are stored separately from
  public profiles and require the administrator claim to access.

The old model implementations, datasets, model binaries, and training scripts
are preserved under [`_to_delete/`](_to_delete/); they are not imported by the
active app.

## Backend setup (Windows PowerShell)

1. Activate the existing backend virtual environment and install dependencies:

   ```powershell
   .\backend\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```

2. If `.env` does not already exist, copy `.env.example` to `.env`. Set
   `FIREBASE_PROJECT_ID` to the project used by the app and set
   `GOOGLE_APPLICATION_CREDENTIALS` (or `FIREBASE_SERVICE_ACCOUNT_PATH`) to a
   Firebase service-account JSON file stored outside this repository. Do not
   overwrite an existing `.env`. Set `EMAIL_BLOCK_HMAC_KEY` to the exact same
   secret configured for the Firebase Functions secret of that name. The API
   requires it on authenticated requests to check the blocked-email list. Do not
   generate a different local value: it would not match the existing Firestore
   blocklist IDs. Keep this secret out of source control and chat.

3. Keep `MOCK_API=1` while developing without consuming provider calls. For
   real screening, configure a newly issued `IVYAI_API_KEY` only in the backend
   process or its untracked `.env` file, then set `MOCK_API=0`. Never reuse a
   credential exposed in logs, source, or chat; revoke exposed keys.

4. Configure the medical assessment in the backend's untracked `.env` file:

   ```dotenv
   IVYAI_API_KEY=your_new_rotated_ivy_key
   MEDICAL_ASSESSMENT_ENABLED=true
   SKINCHAT_FREE_DAILY_LIMIT=10
   SKINCHAT_PAID_DAILY_LIMIT=100
   SKINAI_MEDICAL_ENCRYPTION_KEY=<base64url-encoded-32-byte-key>
   SKINAI_MEDICAL_STORAGE_DIR=backend/uploads/medical
   OPENFDA_API_KEY=<optional-openfda-api-key>
   SKINAI_IMAGE_STORAGE_DIR=backend/uploads/skin_images
   ```

   Generate the encryption key outside source control and keep a secure backup:

   ```powershell
   python -c "import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"
   ```

   The assessment endpoint is `POST /medical/assessments`. It requires a Firebase
   bearer token and explicit `external_processing_consent=true`. It combines
   Ivy AI screens only the submitted skin image. The report is assembled from
   deterministic templates and validated user-entered questionnaire,
   medication, and examination details. Medication package OCR and medical
   report interpretation are unavailable; attached files are not interpreted.
   Manual medication names may be checked against FDA/DailyMed references, but
   the app does not recommend medication or assess its suitability. No patient
   history or report is sent to Ivy AI.

   The endpoint accepts multipart fields `patient_data` (JSON), `skin_image`,
   optional `medication_image`, and up to three repeated `medical_reports`
   attachments. The response is schema-validated and includes a deterministic
   `safety` object with `concern_level`, `referral_required`, and
   `medication_recommendations_allowed`. High-risk labels such as melanoma,
   basal/squamous cell carcinoma, and actinic keratosis require in-person
   dermatologist assessment. Unclear images receive an insufficient result.
   Medication action recommendations are not generated by this workflow.

   Authenticated history and ownership-scoped file routes are
   `GET /medical/assessments`, `GET /medical/assessments/{assessment_id}`,
   `GET /medical/assessments/{assessment_id}/files/{file_id}`, and
   `DELETE /medical/assessments/{assessment_id}`. These routes require Firebase
   authentication and only read records in the signed-in user's account.

   If `storage_consent=true`, the full assessment and original medication/report
   files are encrypted with AES-GCM and stored under the private
   `SKINAI_MEDICAL_STORAGE_DIR` directory. Firestore stores only the encrypted
   assessment payload and file references under
   `users/{uid}/medical_assessments/{assessmentId}` plus an owner audit event
   under `users/{uid}/medical_audit`. The skin image is not served as an
   assessment attachment. Original medication/report downloads use
   owner-scoped authenticated routes and return `no-store` responses.

   Use a persistent private volume in production, restrict OS permissions to
   the backend account, and back up the encryption key separately from the
   uploaded files. Rotating or losing the key makes previously encrypted
   assessments unreadable. There is no mock medical-assessment success mode:
   real provider configuration is required. The workflow never returns a
   medication dose or prescription and is educational, not diagnostic.

   Image screening only remains available through `POST /analyze`. The response
   includes deterministic concern/referral classification; Flutter displays
   the screening disclaimer without collecting the guided assessment fields.

5. Start the API from the repository root after setting up Firebase as above:

   ```powershell
   $env:MOCK_API = "1"
   $env:IVYAI_API_KEY = "..."
   .\backend\.venv\Scripts\python.exe app.py
   ```

   The API listens on `http://127.0.0.1:8000`. Open
   `http://127.0.0.1:8000/health` to check availability. Startup requires valid
   Firebase Admin credentials even in mock mode.

   SkinChat endpoints are under `/api/skinchat/conversations`. General
   AI-generated skincare answers are currently unavailable; localized safety
   responses, saved conversation history, and private image storage remain.
   Conversation
   messages, image metadata, and atomic daily usage counters are persisted in
   Firestore; image bytes are stored locally under
   `backend/uploads/skin_images` by default and are never exposed as static
   files or public URLs. Upload, download, and deletion use Firebase-authenticated
   owner-scoped API routes. In addition to daily quotas, the backend applies an
   in-process per-user burst limit; deployments with multiple workers should
   enforce a shared burst limit at the gateway.

   Local filesystem storage is suitable for development. For production,
   configure `SKINAI_IMAGE_STORAGE_DIR` to a mounted persistent volume and
   ensure it is backed up and restricted to the backend service. Files stored
   only in a container's writable layer may be lost on redeployment or instance
   replacement; no persistence across deployment is assumed.

6. Configure a persistent, private location for doctor photos and verification
   documents when deploying outside a local development environment:

   ```dotenv
   SKINAI_DOCTOR_STORAGE_DIR=backend/uploads/doctors
   ```

   This is the default for local development. In production, point it to a
   mounted persistent volume restricted to the API service. Doctor images and
   verification files are not public static files; the API serves doctor
   profile photos through the directory endpoint and verification documents
   only through administrator-authenticated endpoints.

7. Grant administrator access only to a trusted Firebase account. With the
   backend Firebase Admin credentials configured, run this from the repository
   root:

   ```powershell
   .\backend\.venv\Scripts\python.exe -m backend.manage_doctor_admin FIREBASE_UID
   ```

   Replace `FIREBASE_UID` with the intended administrator's Firebase UID. The
   user must refresh their ID token (signing out and back in is sufficient)
   before the app will use the claim. Revoke the claim with:

   ```powershell
   .\backend\.venv\Scripts\python.exe -m backend.manage_doctor_admin --revoke FIREBASE_UID
   ```

   Do not grant the claim from client-controlled code. The admin screen can
   create or edit doctor and clinic records, upload real profile photos and
   verification documents, approve or reject verification, manage availability
   and appointment status, and moderate reviews and reports. Publishing
   requires a real profile photo. Add only information verified by your
   administrators. There are no seeded doctors; the app displays an empty
   directory until real records are added. Clinic directions use coordinates
   only when an administrator has entered them; otherwise the verified address
   is shown without a map pin.

## Flutter app

With the backend running, use the repository's Firebase client configuration
file and point the app to the backend:

```powershell
flutter pub get
flutter run --dart-define-from-file=firebase.config.json --dart-define=AI_API_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's route to the host machine. For desktop use
`http://127.0.0.1:8000`; for a physical device use the host's reachable LAN
address. Keep `firebase.config.json` out of version control. To run in Chrome,
configure a Google OAuth Web client ID as
`GOOGLE_SIGN_IN_WEB_CLIENT_ID` in `firebase.config.json` (or pass the same
`--dart-define`) and authorize the local web origin in Google Cloud. Without
that client ID, the app still starts, but Google sign-in is unavailable on web.

## Validation

Backend unit tests use mocked provider calls and do not contact Ivy AI:

```powershell
.\backend\.venv\Scripts\python.exe -m pytest tests\test_doctor_directory.py tests\test_localization_audit.py -q
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_skinchat.py"
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_medical_records.py"
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_ivy_ai_provider.py"
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_patient_assessments.py"
```

The live Ivy AI test is skipped unless both `IVYAI_API_KEY` and
`RUN_REAL_IVYAI_TESTS=1` are set. It sends a generated synthetic image to Ivy
AI. Do not enable it with an exposed or unrotated credential.

Run Flutter checks with:

```powershell
flutter analyze
flutter test
```
