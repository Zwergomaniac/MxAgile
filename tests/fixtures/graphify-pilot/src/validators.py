"""
Input validation utilities.

Implements password validation rules from REQ-002.
Used by: auth.py (authenticate, check_password_rules)
"""

import re


# REQ-002: minimum password length
MIN_PASSWORD_LENGTH = 8

# REQ-002: password complexity pattern
# Must contain uppercase, digit, and special character
PASSWORD_COMPLEXITY_PATTERN = re.compile(
    r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*]).{8,}$'
)


def check_password_rules(password: str) -> bool:
    """
    Validate password against all complexity rules.

    Implements: REQ-002 (Password Validation Rules)
    Rules:
    - Minimum 8 characters (REQ-002)
    - At least one uppercase letter (REQ-002)
    - At least one digit (REQ-002)
    - At least one special character (REQ-002)
    """
    if not password or len(password) < MIN_PASSWORD_LENGTH:
        return False
    return bool(PASSWORD_COMPLEXITY_PATTERN.match(password))


def sanitize_input(value: str) -> str:
    """
    Sanitize user input to prevent injection attacks.

    Security utility used by auth.py.
    Strips leading/trailing whitespace and removes null bytes.
    """
    if not isinstance(value, str):
        return ''
    return value.strip().replace('\x00', '')


def validate_username(username: str) -> bool:
    """
    Validate username format.

    Part of REQ-001 (authentication prerequisite).
    Username must be 3-50 alphanumeric chars with underscores/hyphens.
    """
    if not username:
        return False
    return bool(re.match(r'^[a-zA-Z0-9_-]{3,50}$', username))
