import sys
import pytest

sys.path.insert(0, "lambda/cognito_pre_signup")


def _event(email: str) -> dict:
    return {"request": {"userAttributes": {"email": email}}}


def test_allowed_domain(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "lab.university.ac.jp,university.ac.jp")
    import cognito_pre_signup
    event = _event("student@lab.university.ac.jp")
    assert cognito_pre_signup.handler(event, None) == event


def test_multiple_allowed_domains(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "lab.university.ac.jp,university.ac.jp")
    import cognito_pre_signup
    assert cognito_pre_signup.handler(_event("prof@university.ac.jp"), None)


def test_rejected_domain(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "lab.university.ac.jp")
    import cognito_pre_signup
    with pytest.raises(Exception, match="not allowed"):
        cognito_pre_signup.handler(_event("user@gmail.com"), None)


def test_no_at_sign(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "lab.university.ac.jp")
    import cognito_pre_signup
    with pytest.raises(Exception, match="Invalid email"):
        cognito_pre_signup.handler(_event("notanemail"), None)


def test_unconfigured_domains(monkeypatch):
    monkeypatch.setenv("ALLOWED_EMAIL_DOMAINS", "")
    import cognito_pre_signup
    with pytest.raises(Exception, match="not configured"):
        cognito_pre_signup.handler(_event("student@lab.university.ac.jp"), None)
