from __future__ import annotations

import os
from pathlib import Path
from uuid import UUID, uuid4

from .firebase_app import PROJECT_ROOT


def _storage_root() -> Path:
    configured = os.getenv("SKINAI_IMAGE_STORAGE_DIR", "").strip()
    root = Path(configured).expanduser() if configured else (
        Path(__file__).resolve().parent / "uploads" / "skin_images"
    )
    if not root.is_absolute():
        root = PROJECT_ROOT / root
    return root.resolve()


def _image_path(file_path: str) -> Path:
    try:
        image_id = str(UUID(file_path))
    except (ValueError, AttributeError) as error:
        raise ValueError("Invalid private image identifier.") from error
    root = _storage_root()
    path = root / image_id
    if path.parent != root:
        raise ValueError("Invalid private image path.")
    return path


def store_image(content: bytes) -> tuple[str, str]:
    root = _storage_root()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    image_id = str(uuid4())
    path = root / image_id
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as image_file:
            image_file.write(content)
            image_file.flush()
            os.fsync(image_file.fileno())
    except OSError:
        path.unlink(missing_ok=True)
        raise
    return image_id, image_id


def read_image(file_path: str) -> bytes:
    root = _storage_root()
    path = _image_path(file_path)
    resolved = path.resolve(strict=True)
    if resolved.parent != root:
        raise ValueError("Invalid private image path.")
    return resolved.read_bytes()


def image_exists(file_path: str) -> bool:
    root = _storage_root()
    try:
        resolved = _image_path(file_path).resolve(strict=True)
    except (FileNotFoundError, OSError, ValueError):
        return False
    return resolved.parent == root and resolved.is_file()


def delete_image(file_path: str) -> None:
    path = _image_path(file_path)
    path.unlink(missing_ok=True)
