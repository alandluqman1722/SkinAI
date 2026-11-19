from __future__ import annotations

import base64
import os
from pathlib import Path
from uuid import UUID, uuid4

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from ..firebase_app import PROJECT_ROOT

_MAGIC = b"SKM1"
_NONCE_LENGTH = 12


def _key() -> bytes:
    encoded = os.getenv("SKINAI_MEDICAL_ENCRYPTION_KEY", "").strip()
    if not encoded:
        raise RuntimeError("Medical data encryption is not configured.")
    try:
        value = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    except (ValueError, base64.binascii.Error) as error:
        raise RuntimeError("Medical data encryption key is invalid.") from error
    if len(value) != 32:
        raise RuntimeError("Medical data encryption key must be 32 bytes.")
    return value


def encrypt(value: bytes, *, associated_data: bytes) -> bytes:
    nonce = os.urandom(_NONCE_LENGTH)
    ciphertext = AESGCM(_key()).encrypt(nonce, value, associated_data)
    return _MAGIC + nonce + ciphertext


def decrypt(value: bytes, *, associated_data: bytes) -> bytes:
    if len(value) < len(_MAGIC) + _NONCE_LENGTH + 16 or not value.startswith(_MAGIC):
        raise ValueError("Encrypted medical data is invalid.")
    nonce_start = len(_MAGIC)
    nonce_end = nonce_start + _NONCE_LENGTH
    return AESGCM(_key()).decrypt(
        value[nonce_start:nonce_end],
        value[nonce_end:],
        associated_data,
    )


def _storage_root() -> Path:
    configured = os.getenv("SKINAI_MEDICAL_STORAGE_DIR", "").strip()
    root = Path(configured).expanduser() if configured else (
        Path(__file__).resolve().parent.parent / "uploads" / "medical"
    )
    if not root.is_absolute():
        root = PROJECT_ROOT / root
    return root.resolve()


def store_file(
    content: bytes,
    *,
    uid: str,
    assessment_id: str,
    file_id: str,
) -> str:
    storage_id = str(uuid4())
    root = _storage_root()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    path = root / f"{storage_id}.enc"
    payload = encrypt(
        content,
        associated_data=f"{uid}:{assessment_id}:{file_id}".encode(),
    )
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as target:
            target.write(payload)
            target.flush()
            os.fsync(target.fileno())
    except OSError:
        path.unlink(missing_ok=True)
        raise
    return storage_id


def read_file(
    storage_id: str,
    *,
    uid: str,
    assessment_id: str,
    file_id: str,
) -> bytes:
    try:
        normalized = str(UUID(storage_id))
    except (ValueError, AttributeError) as error:
        raise ValueError("Invalid encrypted medical file identifier.") from error
    root = _storage_root()
    path = root / f"{normalized}.enc"
    resolved = path.resolve(strict=True)
    if resolved.parent != root:
        raise ValueError("Invalid encrypted medical file path.")
    return decrypt(
        resolved.read_bytes(),
        associated_data=f"{uid}:{assessment_id}:{file_id}".encode(),
    )


def delete_file(storage_id: str) -> None:
    try:
        normalized = str(UUID(storage_id))
    except (ValueError, AttributeError) as error:
        raise ValueError("Invalid encrypted medical file identifier.") from error
    path = _storage_root() / f"{normalized}.enc"
    if path.resolve(strict=False).parent != _storage_root():
        raise ValueError("Invalid encrypted medical file path.")
    path.unlink(missing_ok=True)
