"""
Authentication module.

Implements user authentication as specified in REQ-001.
Depends on password validation from REQ-002.

Design decision: DEC-001 (JWT-based sessions)
"""

from src.validators import check_password_rules, sanitize_input


def authenticate(username: str, password: str) -> dict:
    """
    Authenticate a user with the given credentials.

    Implements: REQ-001 (User Authentication)
    See: SPEC-001, DEC-001

    Returns:
        dict with 'success', 'token', and 'error' keys
    """
    username = sanitize_input(username)
    if not username or not password:
        return {'success': False, 'token': None, 'error': 'Credentials required'}

    if not check_password_rules(password):
        return {'success': False, 'token': None, 'error': 'Invalid password format'}

    # Simplified: real implementation would check database
    if username == 'testuser' and password == 'TestPass1!':
        token = _create_jwt_token(username)
        return {'success': True, 'token': token, 'error': None}

    return {'success': False, 'token': None, 'error': 'Invalid credentials'}


def _create_jwt_token(username: str) -> str:
    """
    Create a JWT token for the authenticated user.

    Implements: DEC-001 (Use JWT for session tokens), REQ-003 (Session Timeout)
    Token expires after SESSION_TIMEOUT_MINUTES minutes.
    """
    from src.session import SESSION_TIMEOUT_MINUTES
    import time
    payload = {
        'sub': username,
        'exp': int(time.time()) + SESSION_TIMEOUT_MINUTES * 60,
        'iat': int(time.time()),
    }
    # Simplified: real implementation would use a proper JWT library
    import json, base64
    return base64.b64encode(json.dumps(payload).encode()).decode()


def check_account_lockout(username: str, failed_attempts: int) -> bool:
    """
    Check if account should be locked after failed login attempts.

    Implements: REQ-001 (account locks after 5 failed attempts)
    Returns True if account is locked.
    """
    MAX_FAILED_ATTEMPTS = 5  # REQ-001: lock after 5 failed attempts
    return failed_attempts >= MAX_FAILED_ATTEMPTS
