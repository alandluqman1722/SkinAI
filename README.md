# SkinAI

SkinAI is a Flutter app with a FastAPI backend. **Skin-image analysis uses only
the external ScanSkinAI API**; no local model, training code, or dataset is part
of the active application. The ScanSkinAI secret is read only by the backend
from `SCANSKIN_API_KEY`.

This is a screening tool, not a medical diagnosis. Please consult a healthcare
professional.

## Architecture

- Flutter uploads a selected image to `POST /analyze` with the signed-in
  Firebase user's bearer token.
- FastAPI verifies Firebase authentication, validates and converts the image to
  JPEG, and forwards it to
  `https://scanskinai.aihealthpred.com/api/detect/`.
- The server accepts JPG, PNG, WebP, BMP, GIF, and TIFF uploads up to 10 MB;
  the provider receives a JPEG resized to at most 2000 pixels on its longest
  side.
- Optional location and symptom fields are forwarded only when provided.
- Successful responses are saved as generated IDs and timestamps in the local
  `scan_log.jsonl` file. Images and symptom fields are not written to that log.
- `GET /health` reports service status. `MOCK_API=1` returns a fake analysis
  without using a ScanSkinAI call; Firebase authentication still applies.
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
- SkinChat is a skincare-education assistant (not a general chatbot) powered by
  Google's Gemini `generateContent` API. It supports English, Sorani Kurdish,
  Badini Kurdish, and Arabic, using the language selected in the app.
- SkinChat images remain in private backend file storage for the user's own
  conversation history. The backend never sends image bytes or image references
  to Gemini and refuses requests to diagnose or interpret uploaded photos.
- The backend blocks unrelated questions before contacting Gemini and provides
  localized medical-safety and urgent-care guidance. Daily limits default to 10
  messages for free users and 100 for paid users; paid limits require verified
  Firebase custom claims `skinchat_plan=paid` and
  `skinchat_subscription_status=active`. Missing or inactive claims get the
  free allowance.

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

3. Keep `MOCK_API=1` while developing without consuming provider calls. Set
   `SCANSKIN_API_KEY` only in the backend process or its untracked `.env` file.
   To intentionally enable real provider calls, set `MOCK_API=0`.

4. Configure SkinChat only in the backend's untracked `.env` file:

   ```dotenv
   SKINCHAT_AI_ENABLED=true
   SKINCHAT_AI_API_KEY=your_rotated_gemini_api_key
   SKINCHAT_AI_MODEL=gemini-2.5-flash
   SKINCHAT_FREE_DAILY_LIMIT=10
   SKINCHAT_PAID_DAILY_LIMIT=100
   SKINAI_IMAGE_STORAGE_DIR=backend/uploads/skin_images
   ```

   `SKINCHAT_AI_API_KEY` is sent in the API header and must never be placed in
   Flutter configuration or source control. Use a valid Gemini model available
   to your Google AI project. The server calls Google's official
   `generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
   endpoint. The app allows general skincare education, routines, skin types,
   cosmetic ingredients, sunscreen, hydration, acne care, and general
   educational information about common skin conditions. It does not interpret
   images, diagnose, prescribe, or replace a dermatologist.
   Provider calls have a 20-second per-attempt deadline and at most one retry
   for transient failures; the Flutter client allows 60 seconds for the
   response. If the client times out, retrying uses the same message ID so a
   reply that was already saved can be recovered without duplicating history.

   Paid quotas apply only when Firebase ID-token custom claims are set by a
   trusted server to `skinchat_plan=paid` and
   `skinchat_subscription_status=active`. This project does not implement
   billing or subscription verification; absent, invalid, or inactive claims
   remain on the configured free limit. Do not grant these claims based on
   client-controlled data.

5. Start the API from the repository root after setting up Firebase as above:

   ```powershell
   $env:MOCK_API = "1"
   $env:SCANSKIN_API_KEY = "..."
   .\backend\.venv\Scripts\python.exe app.py
   ```

   The API listens on `http://127.0.0.1:8000`. Open
   `http://127.0.0.1:8000/health` to check availability. Startup requires valid
   Firebase Admin credentials even in mock mode.

   SkinChat endpoints are under `/api/skinchat/conversations`. Conversation
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

Backend tests use mocked provider calls and do not contact ScanSkinAI:

```powershell
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_skinchat.py"
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_medical_records.py"
.\backend\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_scanskin_api.py"
```

Run Flutter checks with:

```powershell
flutter analyze
flutter test
```
