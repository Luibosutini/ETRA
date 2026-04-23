import sys
import pytest

sys.path.insert(0, "lambda/cognito_pre_signup")


def _event(email: str) -> dict:
    return {"request": {"userAttributes": {"email": email}}}


# ── ドメインチェックのみ（ALLOWED_EMAILS 未設定）──────────────────

def test_allowed_domain(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "")
    import cognito_pre_signup
    event = _event("student@university.ac.jp")
    assert cognito_pre_signup.handler(event, None) == event


def test_multiple_allowed_domains(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "lab.university.ac.jp,university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "")
    import cognito_pre_signup
    assert cognito_pre_signup.handler(_event("prof@university.ac.jp"), None)


def test_rejected_domain(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "")
    import cognito_pre_signup
    with pytest.raises(Exception, match="not allowed"):
        cognito_pre_signup.handler(_event("user@gmail.com"), None)


def test_no_at_sign(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "")
    import cognito_pre_signup
    with pytest.raises(Exception, match="Invalid email"):
        cognito_pre_signup.handler(_event("notanemail"), None)


def test_unconfigured_domains(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "")
    monkeypatch.setenv("ALLOWED_EMAILS", "")
    import cognito_pre_signup
    with pytest.raises(Exception, match="not configured"):
        cognito_pre_signup.handler(_event("student@university.ac.jp"), None)


# ── ホワイトリストチェック（ALLOWED_EMAILS 設定あり）─────────────

def test_allowlist_permitted(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "alice@university.ac.jp,bob@university.ac.jp")
    import cognito_pre_signup
    assert cognito_pre_signup.handler(_event("alice@university.ac.jp"), None)


def test_allowlist_rejected(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "alice@university.ac.jp,bob@university.ac.jp")
    import cognito_pre_signup
    with pytest.raises(Exception, match="not in the allowlist"):
        cognito_pre_signup.handler(_event("other@university.ac.jp"), None)


def test_allowlist_case_insensitive(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "university.ac.jp")
    monkeypatch.setenv("ALLOWED_EMAILS", "Alice@university.ac.jp")
    import cognito_pre_signup
    assert cognito_pre_signup.handler(_event("alice@university.ac.jp"), None)
