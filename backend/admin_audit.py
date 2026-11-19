from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def create_audit_entry(
    database: Any,
    *,
    admin_uid: str,
    action: str,
    target_type: str,
    target_id: str,
    before: dict[str, bool | int | str] | None = None,
    after: dict[str, bool | int | str] | None = None,
    transaction: Any | None = None,
) -> str:
    reference = database.collection("admin_audit_logs").document()
    entry = {
        "admin_uid": admin_uid,
        "action": action,
        "target_type": target_type,
        "target_id": target_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "before": before or {},
        "after": after or {},
    }
    if transaction is None:
        reference.create(entry)
    else:
        transaction.create(reference, entry)
    return reference.id
