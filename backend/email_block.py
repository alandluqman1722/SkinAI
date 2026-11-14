
import hashlib
import hmac


def normalize_email(email: str) -> str:
    if not isinstance(email, str):
        raise ValueError("A valid email address is required.")

    normalized = email.strip().lower()

    if not normalized:
        raise ValueError("Email address cannot be empty.")

    return normalized


def email_document_id(email: str, key: str) -> str:
    if not isinstance(key, str) or not key:
        raise ValueError("EMAIL_BLOCK_HMAC_KEY is required.")

    normalized_email = normalize_email(email)

    return hmac.new(
        key.encode("utf-8"),
        normalized_email.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
