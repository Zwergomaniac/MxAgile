"""
Session management module.

Implements session lifecycle per REQ-003 (Session Timeout).
Uses JWT tokens as decided in DEC-001.
"""

SESSION_TIMEOUT_MINUTES = 30  # REQ-003: 30-minute inactivity timeout


def validate_session(token: str) -> dict:
    """
    Validate an existing session token.

    Implements: REQ-003 (Session Timeout)
    Returns dict with 'valid', 'username', 'expires_in_seconds'.
    """
    import time
    import json
    import base64

    try:
        payload = json.loads(base64.b64decode(token.encode()).decode())
    except Exception:
        return {'valid': False, 'username': None, 'expires_in_seconds': 0}

    now = int(time.time())
    if payload.get('exp', 0) < now:
        return {'valid': False, 'username': None, 'expires_in_seconds': 0}

    return {
        'valid': True,
        'username': payload.get('sub'),
        'expires_in_seconds': payload['exp'] - now,
    }


def refresh_session(token: str) -> str:
    """
    Extend session timeout on user activity.

    Implements: REQ-003 (timer resets on activity)
    Returns a new token with extended expiry, or empty string if invalid.
    """
    result = validate_session(token)
    if not result['valid']:
        return ''
    # Re-authenticate to get a fresh token
    from src.auth import _create_jwt_token
    return _create_jwt_token(result['username'])


def invalidate_session(token: str) -> bool:
    """
    Invalidate a session (logout).

    Part of REQ-001 auth lifecycle.
    In a real system, token would be added to blocklist.
    Returns True if session was valid and is now invalidated.
    """
    result = validate_session(token)
    return result['valid']  # simplified: real system would blacklist the token
