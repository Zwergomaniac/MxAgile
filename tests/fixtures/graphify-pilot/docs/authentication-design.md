# Authentication Design Notes

## Overview

This document captures design notes for the authentication system.
The implementation follows REQ-001 (User Authentication) and REQ-002 (Password Validation Rules).

## Password Rules

Per REQ-002, passwords must meet the following complexity requirements:
- Minimum 8 characters
- At least one uppercase letter
- At least one digit
- At least one special character

The validation logic is in `src/validators.py`.

## Session Management

Sessions are managed per REQ-003 (Session Timeout). The decision to use JWT
(DEC-001) means sessions are stateless and validated by token expiry.

The 30-minute timeout is configured in `src/session.py`.

## Security Notes

Account lockout after 5 failed attempts is part of REQ-001.
The `check_account_lockout()` function in `src/auth.py` implements this.
