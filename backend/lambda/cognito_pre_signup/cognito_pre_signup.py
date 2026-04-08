"""Cognito Pre-signup トリガー。

許可ドメイン以外のメールアドレスで登録しようとした場合に拒否する。

環境変数:
    ALLOWED_EMAIL_DOMAINS: カンマ区切りの許可ドメインリスト
                           例: "lab.university.ac.jp,university.ac.jp"
"""
import logging
import os

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def _allowed_domains() -> list[str]:
    raw = os.environ.get("ALLOWED_EMAIL_DOMAINS", "")
    return [d.strip().lower() for d in raw.split(",") if d.strip()]


def handler(event: dict, context: object) -> dict:
    """Cognito が自動でイベントを渡し、そのまま返すと登録を許可する。
    例外を送出すると登録を拒否する。
    """
    email: str = event.get("request", {}).get("userAttributes", {}).get("email", "")
    logger.info("Pre-signup check for email domain: %s", email.split("@")[-1] if "@" in email else "(none)")

    allowed = _allowed_domains()
    if not allowed:
        # 許可ドメイン未設定の場合は管理者ミスとして拒否
        raise Exception("ALLOWED_EMAIL_DOMAINS is not configured")

    if "@" not in email:
        raise Exception(f"Invalid email address: {email}")

    domain = email.split("@")[-1].lower()
    if domain not in allowed:
        raise Exception(
            f"Email domain '{domain}' is not allowed. "
            f"Allowed domains: {', '.join(allowed)}"
        )

    logger.info("Allowed: %s", email)
    return event
