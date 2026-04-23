"""Cognito Pre-signup トリガー。

チェック順序:
1. ALLOWED_EMAIL_DOMAINS でドメインを検証
2. ALLOWED_EMAILS が設定されている場合はメールアドレスも検証（ホワイトリスト）

環境変数:
    ALLOWED_EMAIL_DOMAINS: カンマ区切りの許可ドメインリスト
                           例: "university.ac.jp"
    ALLOWED_EMAILS:        カンマ区切りの許可メールアドレスリスト（省略可）
                           設定した場合はドメイン一致に加えてアドレスも照合する
                           例: "alice@university.ac.jp,bob@university.ac.jp"
"""
import logging
import os

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def _allowed_domains() -> list[str]:
    raw = os.environ.get("ALLOWED_EMAIL_DOMAINS", "")
    return [d.strip().lower() for d in raw.split(",") if d.strip()]


def _allowed_emails() -> list[str]:
    raw = os.environ.get("ALLOWED_EMAILS", "")
    return [e.strip().lower() for e in raw.split(",") if e.strip()]


def handler(event: dict, context: object) -> dict:
    """Cognito が自動でイベントを渡し、そのまま返すと登録を許可する。
    例外を送出すると登録を拒否する。
    """
    email: str = event.get("request", {}).get("userAttributes", {}).get("email", "")
    logger.info("Pre-signup check: %s", email.split("@")[-1] if "@" in email else "(none)")

    allowed_domains = _allowed_domains()
    if not allowed_domains:
        raise Exception("ALLOWED_EMAIL_DOMAINS is not configured")

    if "@" not in email:
        raise Exception(f"Invalid email address: {email}")

    domain = email.split("@")[-1].lower()
    email_lower = email.lower()

    # ドメインチェック
    if domain not in allowed_domains:
        raise Exception(
            f"Email domain '{domain}' is not allowed. "
            f"Allowed domains: {', '.join(allowed_domains)}"
        )

    # ホワイトリストチェック（ALLOWED_EMAILS が設定されている場合のみ）
    allowed_emails = _allowed_emails()
    if allowed_emails and email_lower not in allowed_emails:
        raise Exception(f"Email address '{email}' is not in the allowlist")

    logger.info("Allowed: %s", email)
    return event
