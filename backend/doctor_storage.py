from __future__ import annotations

import os
from pathlib import Path
from uuid import UUID, uuid4

from .firebase_app import PROJECT_ROOT


def _storage_root() -> Path:
    configured = os.getenv("SKINAI_DOCTOR_STORAGE_DIR", "").strip()
    root = Path(configured).expanduser() if configured else (
        Path(__file__).resolve().parent / "uploads" / "doctors"
    )
    if not root.is_absolute():
        root = PROJECT_ROOT / root
    return root.resolve()


def _file_path(folder: str, file_id: str, extension: str) -> Path:
    if folder not in {"profiles", "verification"}:
        raise ValueError("Invalid doctor file category.")
    if extension not in {"jpg", "png", "webp", "pdf"}:
        raise ValueError("Invalid doctor file extension.")
    safe_id = str(UUID(file_id))
    root = _storage_root()
    directory = (root / folder).resolve()
    path = directory / f"{safe_id}.{extension}"
    if path.parent != directory:
        raise ValueError("Invalid doctor file path.")
    return path


def store_file(folder: str, extension: str, content: bytes) -> str:
    file_id = str(uuid4())
    path = _file_path(folder, file_id, extension)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
    except OSError:
        path.unlink(missing_ok=True)
        raise
    return file_id


def read_file(folder: str, file_id: str, extension: str) -> bytes:
    root = _storage_root()
    path = _file_path(folder, file_id, extension)
    resolved = path.resolve(strict=True)
    if resolved.parent != (root / folder).resolve():
        raise ValueError("Invalid doctor file path.")
    return resolved.read_bytes()


def file_exists(folder: str, file_id: str, extension: str) -> bool:
    try:
        path = _file_path(folder, file_id, extension).resolve(strict=True)
    except (FileNotFoundError, OSError, ValueError):
        return False
    return path.parent == (_storage_root() / folder).resolve() and path.is_file()


def delete_file(folder: str, file_id: str, extension: str) -> None:
    _file_path(folder, file_id, extension).unlink(missing_ok=True)
