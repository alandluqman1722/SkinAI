import asyncio
import os
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import AsyncMock, patch

import httpx
from fastapi import HTTPException
from PIL import Image

import app as skinai_api
import backend.skinchat_service as skinchat
import backend.skinchat_ai as skinchat_ai
from backend.firebase_auth import require_firebase_user
from backend.skinchat_ai import detect_language


def png_image():
    buffer = BytesIO()
    Image.new("RGB", (16, 16), color=(40, 100, 160)).save(buffer, format="PNG")
    return buffer.getvalue()


class _Snapshot:
    def __init__(self, record_id, data, reference=None):
        self.id = record_id
        self._data = data
        self.reference = reference
        self.exists = data is not None

    def to_dict(self):
        return dict(self._data or {})


class _Document:
    def __init__(
        self,
        database,
        uid,
        collection,
        document_id,
        conversation_id=None,
    ):
        self.database = database
        self.uid = uid
        self.collection_name = collection
        self.id = document_id
        self.conversation_id = conversation_id

    def collection(self, name):
        return _Collection(self.database, self.uid, name, self.id)

    def _key(self):
        if self.collection_name == "skinchat_conversations":
            return self.uid, self.id
        return self.uid, self.conversation_id, self.id

    def get(self):
        if self.collection_name == "skinchat_conversations":
            data = self.database.conversations.get(self._key())
        else:
            data = self.database.messages.get(self._key())
        return _Snapshot(self.id, data, self)

    def set(self, data):
        if self.collection_name == "skinchat_conversations":
            self.database.conversations[self._key()] = dict(data)
        else:
            self.database.messages[self._key()] = dict(data)

    def update(self, data):
        self.get()
        if self.collection_name == "skinchat_conversations":
            self.database.conversations[self._key()].update(data)
        else:
            self.database.messages[self._key()].update(data)

    def delete(self):
        if self.collection_name == "skinchat_conversations":
            self.database.conversations.pop(self._key(), None)
        else:
            self.database.messages.pop(self._key(), None)


class _Query:
    def __init__(self, collection):
        self.collection = collection
        self.maximum = None
        self.before = None
        self.descending = False

    def order_by(self, _field, direction="ASCENDING"):
        self.descending = direction == "DESCENDING"
        return self

    def where(self, _field, operator, value):
        if operator == "<":
            self.before = value
        return self

    def limit(self, maximum):
        self.maximum = maximum
        return self

    def stream(self):
        entries = self.collection.stream()
        entries.sort(key=lambda item: item.to_dict().get("created_at", ""))
        if self.before is not None:
            entries = [
                item
                for item in entries
                if item.to_dict().get("created_at", "") < self.before
            ]
        if self.descending:
            entries.reverse()
        return entries[: self.maximum] if self.maximum is not None else entries


class _Collection:
    def __init__(self, database, uid, name, conversation_id=None):
        self.database = database
        self.uid = uid
        self.name = name
        self.conversation_id = conversation_id

    def document(self, document_id=None):
        if self.name == "users":
            return _Document(self.database, document_id, "users", document_id)
        if self.name == "skinchat_conversations":
            return _Document(
                self.database,
                self.uid,
                self.name,
                document_id,
            )
        document = _Document(
            self.database,
            self.uid,
            "messages",
            document_id,
            self.conversation_id,
        )
        return document

    def stream(self):
        if self.name == "skinchat_conversations":
            return [
                _Snapshot(conversation_id, data)
                for (uid, conversation_id), data in self.database.conversations.items()
                if uid == self.uid
            ]
        return [
            _Snapshot(message_id, data, self.document(message_id))
            for (uid, conversation_id, message_id), data in self.database.messages.items()
            if uid == self.uid and conversation_id == self.conversation_id
        ]

    def order_by(self, field, direction="ASCENDING"):
        return _Query(self).order_by(field, direction)


class _Database:
    def __init__(self):
        self.conversations = {}
        self.messages = {}

    def collection(self, name):
        return _Collection(self, None, name)


class _UsageSnapshot:
    def __init__(self, data):
        self.exists = data is not None
        self._data = data

    def to_dict(self):
        return dict(self._data or {})


class _UsageReference:
    def __init__(self, database, path):
        self.database = database
        self.path = path

    def collection(self, name):
        return _UsageCollection(self.database, f"{self.path}/{name}")

    def document(self, document_id):
        return _UsageReference(self.database, f"{self.path}/{document_id}")

    def get(self, *, transaction=None):
        return _UsageSnapshot(self.database.documents.get(self.path))


class _UsageCollection:
    def __init__(self, database, path):
        self.database = database
        self.path = path

    def document(self, document_id):
        return _UsageReference(self.database, f"{self.path}/{document_id}")


class _UsageTransaction:
    def __init__(self):
        self.writes = []

    def set(self, reference, data, merge=False):
        self.writes.append((reference, data, merge))

    def commit(self):
        for reference, data, merge in self.writes:
            current = self._database.documents.get(reference.path, {})
            self._database.documents[reference.path] = (
                {**current, **data} if merge else dict(data)
            )

    def bind(self, database):
        self._database = database


class _UsageDatabase:
    def __init__(self):
        self.documents = {}

    def collection(self, name):
        return _UsageCollection(self, name)

    def transaction(self, *, max_attempts):
        transaction = _UsageTransaction()
        transaction.bind(self)
        return transaction


def _direct_transactional(function):
    def wrapped(transaction):
        result = function(transaction)
        transaction.commit()
        return result

    return wrapped


class _ProviderResponse:
    is_error = False

    @staticmethod
    def json():
        return {
            "candidates": [
                {"content": {"parts": [{"text": "A cautious answer."}]}}
            ]
        }

    def __init__(self, status_code=200):
        self.status_code = status_code
        self.is_error = status_code >= 400


class _ProviderClient:
    def __init__(self, response=None):
        self.request = None
        self.response = response or _ProviderResponse()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return None

    async def post(self, url, *, headers, json):
        self.request = {"url": url, "headers": headers, "json": json}
        return self.response


class SkinChatApiTests(unittest.TestCase):
    def setUp(self):
        self.database = _Database()
        self.image_directory = tempfile.TemporaryDirectory()
        self.image_directory_patch = patch.dict(
            os.environ,
            {"SKINAI_IMAGE_STORAGE_DIR": self.image_directory.name},
        )
        self.image_directory_patch.start()
        skinai_service = skinchat
        self.database_patch = patch.object(
            skinai_service,
            "_database",
            return_value=self.database,
        )
        self.database_patch.start()
        skinchat._rate_requests.clear()
        self.usage = {}
        self.usage_requests = set()
        self.usage_patch = patch.object(
            skinchat,
            "_reserve_daily_message",
            side_effect=self._reserve_usage,
        )
        self.gemini_enabled_patch = patch.object(
            skinchat,
            "gemini_enabled",
            return_value=True,
        )
        self.usage_patch.start()
        self.gemini_enabled_patch.start()
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: {"uid": "user-a"}
        )

    def _reserve_usage(self, uid, claims, request_id):
        if (uid, request_id) in self.usage_requests:
            return
        limit = skinchat.daily_message_limit(claims)
        if self.usage.get(uid, 0) >= limit:
            raise HTTPException(
                status_code=429,
                detail="Your daily SkinChat message limit has been reached.",
            )
        self.usage[uid] = self.usage.get(uid, 0) + 1
        self.usage_requests.add((uid, request_id))

    def tearDown(self):
        self.database_patch.stop()
        self.image_directory_patch.stop()
        self.image_directory.cleanup()
        self.usage_patch.stop()
        self.gemini_enabled_patch.stop()
        skinai_api.app.dependency_overrides.clear()

    def _request(
        self,
        method,
        path,
        *,
        user_id="user-a",
        claims=None,
        json=None,
        **kwargs,
    ):
        async def send():
            skinai_api.app.dependency_overrides[require_firebase_user] = (
                lambda: {"uid": user_id, **(claims or {})}
            )
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.request(method, path, json=json, **kwargs)

        return asyncio.run(send())

    def _create(self, user_id="user-a"):
        response = self._request(
            "POST",
            "/api/skinchat/conversations",
            user_id=user_id,
        )
        self.assertEqual(response.status_code, 201)
        return response.json()["conversation_id"]

    def _upload(self, conversation_id, *, user_id="user-a", content_type="image/png"):
        return self._request(
            "POST",
            f"/api/skinchat/conversations/{conversation_id}/image",
            user_id=user_id,
            files={"file": ("skin.png", png_image(), content_type)},
            data={"language": "ku"},
        )

    def test_language_detection_supports_all_four_languages(self):
        self.assertEqual(detect_language("The skin is itchy."), "en")
        self.assertEqual(detect_language("ئەم پێستە سورە."), "ku")
        self.assertEqual(detect_language("Ez dikarim alîkarî bikim?"), "bad")
        self.assertEqual(detect_language("هل هذه البقعة مثيرة للقلق؟"), "ar")
        self.assertEqual(
            skinchat_ai.selected_language("How can I moisturize my skin?", "ku"),
            "ku",
        )

    def test_gemini_request_is_text_only_uses_official_endpoint_and_selected_language(self):
        provider = _ProviderClient()
        with (
            patch.dict(
                "os.environ",
                {
                    "SKINCHAT_AI_ENABLED": "true",
                    "SKINCHAT_AI_API_KEY": "test-key",
                    "SKINCHAT_AI_MODEL": "gemini-2.5-flash",
                },
            ),
            patch.object(skinchat_ai.httpx, "AsyncClient", return_value=provider),
        ):
            answer = asyncio.run(
                skinchat_ai.generate_response(
                    question="How do I care for oily skin?",
                    history=[
                        {"role": "user", "content": "I have oily skin."},
                        {"role": "assistant", "content": "Use a gentle cleanser."},
                    ],
                    language="ku",
                    scan_context={
                        "scan_id": "scan-123",
                        "detected_condition": "screening-result",
                        "confidence": 72.5,
                        "scan_date": "2026-11-16T10:00:00Z",
                        "summary": "Screening summary.",
                        "body_location": "left arm",
                        "has_original_image": False,
                    },
                )
            )

        self.assertEqual(answer, "A cautious answer.")
        self.assertEqual(
            provider.request["url"],
            "https://generativelanguage.googleapis.com/v1beta/models/"
            "gemini-2.5-flash:generateContent",
        )
        self.assertEqual(provider.request["headers"]["x-goog-api-key"], "test-key")
        payload = provider.request["json"]
        self.assertIn("Sorani Kurdish", payload["systemInstruction"]["parts"][0]["text"])
        self.assertIn(
            '"detected_condition": "screening-result"',
            payload["systemInstruction"]["parts"][0]["text"],
        )
        self.assertEqual(
            [message["role"] for message in payload["contents"]],
            ["user", "model", "user"],
        )
        self.assertTrue(
            all(
                "inlineData" not in str(message)
                and "image" not in str(message).lower()
                for message in payload["contents"]
            )
        )
        self.assertNotIn("test-key", provider.request["url"])

    def test_gemini_invalid_key_and_quota_errors_are_safe(self):
        async def call(response):
            provider = _ProviderClient(response)
            with (
                patch.dict(
                    "os.environ",
                    {
                        "SKINCHAT_AI_ENABLED": "true",
                        "SKINCHAT_AI_API_KEY": "test-key",
                        "SKINCHAT_AI_MODEL": "gemini-2.5-flash",
                    },
                ),
                patch.object(skinchat_ai.httpx, "AsyncClient", return_value=provider),
            ):
                return await skinchat_ai.generate_response(
                    question="How do I care for oily skin?",
                    history=[],
                    language="en",
                )

        with self.assertRaises(HTTPException) as invalid_key:
            asyncio.run(call(_ProviderResponse(status_code=403)))
        self.assertEqual(invalid_key.exception.status_code, 503)
        self.assertNotIn("test-key", invalid_key.exception.detail)
        with self.assertRaises(HTTPException) as quota:
            asyncio.run(call(_ProviderResponse(status_code=429)))
        self.assertEqual(quota.exception.status_code, 429)

    def test_gemini_must_be_enabled_and_network_failures_are_safe(self):
        async def unconfigured():
            with patch.dict(
                "os.environ",
                {
                    "SKINCHAT_AI_ENABLED": "false",
                    "SKINCHAT_AI_API_KEY": "test-key",
                    "SKINCHAT_AI_MODEL": "gemini-2.5-flash",
                },
            ):
                return await skinchat_ai.generate_response(
                    question="How do I care for oily skin?",
                    history=[],
                    language="en",
                )

        with self.assertRaises(HTTPException) as disabled:
            asyncio.run(unconfigured())
        self.assertEqual(disabled.exception.status_code, 503)

        async def provider_unreachable():
            provider = _ProviderClient()
            provider.post = AsyncMock(
                side_effect=httpx.ConnectError("provider unavailable")
            )
            with (
                patch.dict(
                    "os.environ",
                    {
                        "SKINCHAT_AI_ENABLED": "true",
                        "SKINCHAT_AI_API_KEY": "test-key",
                        "SKINCHAT_AI_MODEL": "gemini-2.5-flash",
                    },
                ),
                patch.object(
                    skinchat_ai.httpx,
                    "AsyncClient",
                    return_value=provider,
                ),
            ):
                return await skinchat_ai.generate_response(
                    question="How do I care for oily skin?",
                    history=[],
                    language="en",
                )

        with self.assertRaises(HTTPException) as unreachable:
            asyncio.run(provider_unreachable())
        self.assertEqual(unreachable.exception.status_code, 502)

    def test_gemini_retries_a_timeout_once_within_client_deadline(self):
        provider = _ProviderClient()
        provider.post = AsyncMock(
            side_effect=[
                httpx.ReadTimeout("provider response timed out"),
                _ProviderResponse(),
            ]
        )
        with (
            patch.dict(
                "os.environ",
                {
                    "SKINCHAT_AI_ENABLED": "true",
                    "SKINCHAT_AI_API_KEY": "test-key",
                    "SKINCHAT_AI_MODEL": "gemini-2.5-flash",
                },
            ),
            patch.object(skinchat_ai.httpx, "AsyncClient", return_value=provider),
            patch.object(skinchat_ai.asyncio, "sleep", new=AsyncMock()),
        ):
            answer = asyncio.run(
                skinchat_ai.generate_response(
                    question="How can I care for dry skin?",
                    history=[],
                    language="en",
                )
            )

        self.assertEqual(answer, "A cautious answer.")
        self.assertEqual(provider.post.await_count, 2)

    def test_gemini_does_not_return_a_truncated_max_tokens_answer(self):
        response = _ProviderResponse()
        response.json = lambda: {
            "candidates": [
                {
                    "finishReason": "MAX_TOKENS",
                    "content": {
                        "parts": [{"text": "The answer stopped in the"}],
                    },
                }
            ]
        }
        provider = _ProviderClient(response)
        with (
            patch.dict(
                "os.environ",
                {
                    "SKINCHAT_AI_ENABLED": "true",
                    "SKINCHAT_AI_API_KEY": "test-key",
                    "SKINCHAT_AI_MODEL": "gemini-2.5-flash",
                },
            ),
            patch.object(skinchat_ai.httpx, "AsyncClient", return_value=provider),
        ):
            with self.assertRaises(HTTPException) as incomplete:
                asyncio.run(
                    skinchat_ai.generate_response(
                        question="How do I choose a sunscreen?",
                        history=[],
                        language="en",
                    )
                )

        self.assertEqual(incomplete.exception.status_code, 502)
        self.assertIn("could not finish", incomplete.exception.detail)

    def test_question_filter_blocks_unrelated_diagnosis_and_urgent_queries(self):
        self.assertEqual(
            skinchat_ai.classify_question("Write a Python program.", []),
            "out_of_scope",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "Write a Python program about oily skin.",
                ["How do I care for oily skin?"],
            ),
            "out_of_scope",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "Can you tell if this spot is cancer from my photo?",
                [],
            ),
            "diagnosis",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "ما علاج حب الشباب؟",
                [],
            ),
            "skincare",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "What about sunscreen?",
                ["How do I care for oily skin?"],
            ),
            "skincare",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "ما أفضل واقي شمس للبشرة الحساسة؟",
                [],
            ),
            "skincare",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "I have difficulty breathing and severe allergic swelling.",
                [],
            ),
            "urgent",
        )

    def test_scan_context_allows_screening_follow_ups_but_not_diagnosis(self):
        self.assertEqual(
            skinchat_ai.classify_question(
                "Is it dangerous?",
                [],
                has_scan_context=True,
            ),
            "skincare",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "Do I have cancer?",
                [],
                has_scan_context=True,
            ),
            "diagnosis",
        )
        self.assertEqual(
            skinchat_ai.classify_question(
                "I have difficulty breathing.",
                [],
                has_scan_context=True,
            ),
            "urgent",
        )

    def test_daily_limits_default_to_free_and_use_only_verified_active_paid_claims(self):
        with patch.dict(
            "os.environ",
            {
                "SKINCHAT_FREE_DAILY_LIMIT": "4",
                "SKINCHAT_PAID_DAILY_LIMIT": "25",
            },
        ):
            self.assertEqual(skinchat.daily_message_limit({"uid": "user-a"}), 4)
            self.assertEqual(
                skinchat.daily_message_limit(
                    {"skinchat_plan": "paid", "skinchat_subscription_status": "active"}
                ),
                25,
            )
            self.assertEqual(
                skinchat.daily_message_limit(
                    {"skinchat_plan": "paid", "skinchat_subscription_status": "expired"}
                ),
                4,
            )

    def test_firestore_daily_counter_is_atomic_fail_closed_and_retry_idempotent(self):
        database = _UsageDatabase()
        self.usage_patch.stop()
        with (
            patch.object(skinchat, "_database", return_value=database),
            patch(
                "google.cloud.firestore_v1.transactional",
                _direct_transactional,
            ),
            patch.dict("os.environ", {"SKINCHAT_FREE_DAILY_LIMIT": "1"}),
        ):
            skinchat._reserve_daily_message("user-a", {"uid": "user-a"}, "same-id")
            skinchat._reserve_daily_message("user-a", {"uid": "user-a"}, "same-id")
            counter_paths = [
                path
                for path in database.documents
                if path.startswith("users/user-a/skinchat_usage/")
                and "/requests/" not in path
            ]
            self.assertEqual(len(counter_paths), 1, database.documents)
            self.assertEqual(database.documents[counter_paths[0]]["count"], 1)
            with self.assertRaises(HTTPException) as limited:
                skinchat._reserve_daily_message(
                    "user-a",
                    {"uid": "user-a"},
                    "another-id",
                )
            self.assertEqual(limited.exception.status_code, 429)

    def test_skinchat_endpoints_require_firebase_authentication(self):
        async def request():
            skinai_api.app.dependency_overrides.clear()
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.get("/api/skinchat/conversations")

        response = asyncio.run(request())
        self.assertEqual(response.status_code, 401)

    def test_conversations_are_private_and_storage_references_are_not_exposed(self):
        conversation_id = self._create()
        upload = self._upload(conversation_id)
        self.assertEqual(upload.status_code, 201)
        owner = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}",
        )
        other_user = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}",
            user_id="user-b",
        )
        self.assertEqual(owner.status_code, 200)
        self.assertNotIn("image_object", owner.json())
        self.assertNotIn("image_file_path", owner.json())
        stored = self.database.conversations[("user-a", conversation_id)]
        image_path = Path(self.image_directory.name) / stored["image_file_path"]
        self.assertTrue(image_path.is_file())
        self.assertEqual(stored["image_owner_uid"], "user-a")
        self.assertEqual(stored["image_file_size"], len(png_image()))
        self.assertEqual(
            stored["uploaded_image_id"],
            stored["image_file_path"],
        )
        self.assertTrue(stored["image_upload_timestamp"])
        self.assertEqual(other_user.status_code, 404)

    def test_scan_context_is_stored_only_in_the_owning_conversation(self):
        context = {
            "scan_id": "scan-123",
            "detected_condition": "screening-result",
            "confidence": 72.5,
            "scan_date": "2026-11-16T10:00:00Z",
            "summary": "Screening summary.",
            "body_location": "left arm",
            "has_original_image": False,
        }
        created = self._request(
            "POST",
            "/api/skinchat/conversations",
            json={"scan_context": context},
        )
        self.assertEqual(created.status_code, 201)
        conversation_id = created.json()["conversation_id"]
        self.assertEqual(created.json()["scan_context"]["scan_id"], "scan-123")

        owner_read = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}",
        )
        other_user_read = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}",
            user_id="user-b",
        )
        self.assertEqual(owner_read.json()["scan_context"], context)
        self.assertEqual(other_user_read.status_code, 404)

    def test_scan_follow_up_passes_attached_result_to_provider_without_image(self):
        context = {
            "scan_id": "scan-follow-up",
            "detected_condition": "screening-result",
            "confidence": 81.0,
            "scan_date": "2026-11-16T10:00:00Z",
            "summary": "The screening model returned a result.",
            "body_location": "left arm",
            "has_original_image": False,
        }
        created = self._request(
            "POST",
            "/api/skinchat/conversations",
            json={"scan_context": context},
        )
        conversation_id = created.json()["conversation_id"]
        provider = AsyncMock(
            side_effect=[
                "This is a screening prediction, not a diagnosis.",
                "A dermatologist can assess personal risk.",
            ]
        )
        with patch.object(skinchat, "generate_response", new=provider):
            first_response = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "What does this result mean?",
                    "client_message_id": "scan-result-meaning",
                    "language": "en",
                },
            )
            second_response = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "Is it dangerous?",
                    "client_message_id": "scan-danger-follow-up",
                    "language": "en",
                },
            )

        self.assertEqual(first_response.status_code, 200)
        self.assertEqual(second_response.status_code, 200)
        self.assertEqual(
            first_response.json()["reply"]["content"],
            "This is a screening prediction, not a diagnosis.",
        )
        self.assertEqual(provider.await_count, 2)
        self.assertEqual(
            provider.await_args_list[0].kwargs["scan_context"]["scan_id"],
            "scan-follow-up",
        )
        self.assertEqual(
            provider.await_args_list[1].kwargs["scan_context"]["scan_id"],
            "scan-follow-up",
        )
        self.assertIn(
            "What does this result mean?",
            str(provider.await_args_list[1].kwargs["history"]),
        )

    def test_general_question_works_without_an_uploaded_image(self):
        conversation_id = self._create()
        provider = AsyncMock(return_value="A gentle cleanser may help.")
        with patch.object(skinchat, "generate_response", new=provider):
            response = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "Why does my skin become dry?",
                    "client_message_id": "general-no-image",
                    "language": "en",
                },
            )

        self.assertEqual(response.status_code, 200)
        provider.assert_awaited_once()
        self.assertNotIn("scan_context", provider.await_args.kwargs)

    def test_image_upload_validates_content_type_and_prevents_replacement(self):
        conversation_id = self._create()
        invalid_conversation_id = self._create()
        invalid = self._upload(invalid_conversation_id, content_type="text/plain")
        self.assertEqual(invalid.status_code, 415)
        mismatched = self._upload(conversation_id, content_type="image/jpeg")
        self.assertEqual(mismatched.status_code, 415)
        invalid_bytes_conversation = self._create()
        invalid_bytes = self._request(
            "POST",
            f"/api/skinchat/conversations/{invalid_bytes_conversation}/image",
            files={"file": ("skin.png", b"not an image", "image/png")},
        )
        self.assertEqual(invalid_bytes.status_code, 400)
        conversation_id = self._create()
        with patch.object(skinchat, "generate_response", new=AsyncMock()) as provider:
            valid = self._upload(conversation_id)
        provider.assert_not_awaited()
        self.assertEqual(valid.status_code, 201)
        self.assertEqual(valid.json()["detected_language"], "ku")
        self.assertIn("بۆ Gemini نانێردرێت", valid.json()["initial_analysis"])
        duplicate = self._upload(conversation_id)
        self.assertEqual(duplicate.status_code, 409)

    def test_image_download_and_deletion_require_the_owner(self):
        conversation_id = self._create()
        self.assertEqual(self._upload(conversation_id).status_code, 201)
        stored = self.database.conversations[("user-a", conversation_id)]
        image_path = Path(self.image_directory.name) / stored["image_file_path"]
        owner_read = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}/image",
        )
        other_read = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}/image",
            user_id="user-b",
        )
        denied_delete = self._request(
            "DELETE",
            f"/api/skinchat/conversations/{conversation_id}",
            user_id="user-b",
        )
        self.assertEqual(owner_read.status_code, 200)
        self.assertEqual(owner_read.content, png_image())
        self.assertEqual(owner_read.headers["cache-control"], "no-store")
        self.assertEqual(other_read.status_code, 404)
        self.assertEqual(denied_delete.status_code, 404)
        self.assertTrue(image_path.exists())
        deleted = self._request(
            "DELETE",
            f"/api/skinchat/conversations/{conversation_id}",
        )
        self.assertEqual(deleted.status_code, 204)
        self.assertFalse(image_path.exists())

    def test_missing_local_image_can_be_replaced_without_old_storage_access(self):
        conversation_id = self._create()
        first_upload = self._upload(conversation_id)
        first_image_id = first_upload.json()["uploaded_image_id"]
        stored = self.database.conversations[("user-a", conversation_id)]
        (Path(self.image_directory.name) / stored["image_file_path"]).unlink()

        replacement = self._upload(conversation_id)

        self.assertEqual(replacement.status_code, 201)
        self.assertNotEqual(
            replacement.json()["uploaded_image_id"],
            first_image_id,
        )
        self.assertEqual(
            self._request(
                "GET",
                f"/api/skinchat/conversations/{conversation_id}/image",
            ).status_code,
            200,
        )

    def test_out_of_scope_and_image_diagnosis_questions_never_call_gemini(self):
        conversation_id = self._create()
        provider = AsyncMock()
        with patch.object(skinchat, "generate_response", new=provider):
            unrelated = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "What is the capital of Japan?",
                    "client_message_id": "unrelated",
                    "language": "en",
                },
            )
            diagnosis = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "Can you tell if this spot is cancer from my photo?",
                    "client_message_id": "diagnosis",
                    "language": "en",
                },
            )
        self.assertEqual(unrelated.status_code, 200)
        self.assertIn("specialized in skincare", unrelated.json()["reply"]["content"])
        self.assertEqual(diagnosis.status_code, 200)
        self.assertIn("can’t diagnose", diagnosis.json()["reply"]["content"])
        provider.assert_not_awaited()

    def test_daily_message_allowance_is_enforced_by_backend(self):
        conversation_id = self._create()
        provider = AsyncMock(return_value="Use a gentle cleanser.")
        with (
            patch.dict("os.environ", {"SKINCHAT_FREE_DAILY_LIMIT": "1"}),
            patch.object(skinchat, "daily_message_limit", return_value=1),
            patch.object(skinchat, "generate_response", new=provider),
        ):
            first = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "How do I care for oily skin?",
                    "client_message_id": "within-limit",
                    "language": "en",
                },
            )
            second = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "What sunscreen suits oily skin?",
                    "client_message_id": "over-limit",
                    "language": "en",
                },
            )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 429)
        self.assertEqual(provider.await_count, 1)

    def test_follow_up_questions_reuse_image_and_persist_latest_language(self):
        conversation_id = self._create()
        self.assertEqual(self._upload(conversation_id).status_code, 201)
        provider = AsyncMock(side_effect=["First answer.", "Second answer."])
        with patch.object(skinchat, "generate_response", new=provider):
            first = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "How do I care for oily skin?",
                    "client_message_id": "first",
                    "language": "en",
                },
            )
            second = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "چۆن چاودێری پێستی چەور بکەم؟",
                    "client_message_id": "second",
                    "language": "ku",
                },
            )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.json()["reply"]["language"], "ku")
        self.assertIn("oily skin", str(provider.await_args_list[1].kwargs["history"]))
        self.assertNotIn("image", provider.await_args_list[1].kwargs)
        page = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}/messages",
        )
        self.assertEqual(len(page.json()["messages"]), 4)

    def test_message_history_supports_before_cursor_pagination(self):
        conversation_id = self._create()
        for index in range(5):
            self.database.messages[
                ("user-a", conversation_id, f"message-{index}")
            ] = {
                "role": "user",
                "content": f"Message {index}",
                "language": "en",
                "created_at": f"2026-11-13T10:00:0{index}+00:00",
            }
        first_page = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}/messages",
            params={"limit": 2},
        )
        second_page = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}/messages",
            params={
                "limit": 2,
                "before": first_page.json()["next_before"],
            },
        )
        self.assertEqual(
            [item["content"] for item in first_page.json()["messages"]],
            ["Message 3", "Message 4"],
        )
        self.assertEqual(
            [item["content"] for item in second_page.json()["messages"]],
            ["Message 1", "Message 2"],
        )

    def test_provider_failure_does_not_fabricate_an_answer(self):
        conversation_id = self._create()
        provider = AsyncMock(
            side_effect=HTTPException(status_code=503, detail="Provider unavailable.")
        )
        with patch.object(skinchat, "generate_response", new=provider):
            response = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "How do I care for oily skin?",
                    "client_message_id": "failed",
                },
            )
        self.assertEqual(response.status_code, 503)
        self.assertFalse(
            any(
                message_id == "assistant-failed"
                for _, _, message_id in self.database.messages
            )
        )

    def test_retry_reuses_client_id_without_duplicating_the_user_message(self):
        conversation_id = self._create()
        provider = AsyncMock(
            side_effect=[
                HTTPException(status_code=503, detail="Provider unavailable."),
                "The provider recovered.",
            ]
        )
        with patch.object(skinchat, "generate_response", new=provider):
            payload = {
                "content": "Please explain sunscreen for oily skin.",
                "client_message_id": "retry-same-message",
            }
            failed = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json=payload,
            )
            retried = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json=payload,
            )
        self.assertEqual(failed.status_code, 503)
        self.assertEqual(retried.status_code, 200)
        user_messages = [
            data
            for (uid, conv_id, message_id), data in self.database.messages.items()
            if uid == "user-a"
            and conv_id == conversation_id
            and message_id.startswith("user-")
        ]
        self.assertEqual(len(user_messages), 1)

    def test_deleting_a_user_message_also_removes_its_paired_reply(self):
        conversation_id = self._create()
        provider = AsyncMock(return_value="Reply to remove.")
        with patch.object(skinchat, "generate_response", new=provider):
            sent = self._request(
                "POST",
                f"/api/skinchat/conversations/{conversation_id}/messages",
                json={
                    "content": "How do I choose sunscreen for oily skin?",
                    "client_message_id": "delete-me",
                },
            )
        self.assertEqual(sent.status_code, 200)
        deleted = self._request(
            "DELETE",
            f"/api/skinchat/conversations/{conversation_id}/messages/user-delete-me",
        )
        page = self._request(
            "GET",
            f"/api/skinchat/conversations/{conversation_id}/messages",
        )
        self.assertEqual(deleted.status_code, 204)
        self.assertEqual(page.json()["messages"], [])

    def test_delete_removes_only_the_owner_conversation_and_image(self):
        first = self._create()
        second = self._create()
        self._upload(first)
        denied = self._request(
            "DELETE",
            f"/api/skinchat/conversations/{first}",
            user_id="user-b",
        )
        self.assertEqual(denied.status_code, 404)
        deleted = self._request("DELETE", f"/api/skinchat/conversations/{first}")
        retained = self._request(
            "GET",
            f"/api/skinchat/conversations/{second}",
        )
        self.assertEqual(deleted.status_code, 204)
        self.assertEqual(retained.status_code, 200)


if __name__ == "__main__":
    unittest.main()
