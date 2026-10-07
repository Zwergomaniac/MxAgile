# Graph Report - tests\fixtures\graphify-pilot  (2026-10-07)

## Corpus Check
- 5 files · ~2,505 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 31 nodes · 36 edges · 6 communities (5 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7c7221a8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- auth.py
- session.py
- Authentication Design Notes
- validators.py
- check_account_lockout

## God Nodes (most connected - your core abstractions)
1. `authenticate()` - 5 edges
2. `_create_jwt_token()` - 5 edges
3. `Authentication Design Notes` - 5 edges
4. `validate_session()` - 4 edges
5. `refresh_session()` - 4 edges
6. `check_password_rules()` - 4 edges
7. `sanitize_input()` - 4 edges
8. `invalidate_session()` - 3 edges
9. `check_account_lockout()` - 2 edges
10. `validate_username()` - 2 edges

## Surprising Connections (you probably didn't know these)
- `authenticate()` --calls--> `check_password_rules()`  [EXTRACTED]
  tests/fixtures/graphify-pilot/src/auth.py → tests/fixtures/graphify-pilot/src/validators.py
- `refresh_session()` --calls--> `_create_jwt_token()`  [EXTRACTED]
  tests/fixtures/graphify-pilot/src/session.py → tests/fixtures/graphify-pilot/src/auth.py
- `authenticate()` --calls--> `sanitize_input()`  [EXTRACTED]
  tests/fixtures/graphify-pilot/src/auth.py → tests/fixtures/graphify-pilot/src/validators.py

## Import Cycles
- None detected.

## Communities (6 total, 1 thin omitted)

### Community 0 - "auth.py"
Cohesion: 0.32
Nodes (7): authenticate(), _create_jwt_token(), Authentication module.  Implements user authentication as specified in REQ-001., Authenticate a user with the given credentials.      Implements: REQ-001 (User A, Create a JWT token for the authenticated user.      Implements: DEC-001 (Use JWT, Sanitize user input to prevent injection attacks.      Security utility used by, sanitize_input()

### Community 1 - "session.py"
Cohesion: 0.32
Nodes (7): invalidate_session(), Session management module.  Implements session lifecycle per REQ-003 (Session Ti, Validate an existing session token.      Implements: REQ-003 (Session Timeout), Extend session timeout on user activity.      Implements: REQ-003 (timer resets, Invalidate a session (logout).      Part of REQ-001 auth lifecycle.     In a rea, refresh_session(), validate_session()

### Community 2 - "Authentication Design Notes"
Cohesion: 0.33
Nodes (5): Authentication Design Notes, Overview, Password Rules, Security Notes, Session Management

### Community 3 - "validators.py"
Cohesion: 0.33
Nodes (5): check_password_rules(), Input validation utilities.  Implements password validation rules from REQ-002., Validate password against all complexity rules.      Implements: REQ-002 (Passwo, Validate username format.      Part of REQ-001 (authentication prerequisite)., validate_username()

## Knowledge Gaps
- **4 isolated node(s):** `Overview`, `Password Rules`, `Session Management`, `Security Notes`
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_create_jwt_token()` connect `auth.py` to `session.py`?**
  _High betweenness centrality (0.308) - this node is a cross-community bridge._
- **Why does `authenticate()` connect `auth.py` to `validators.py`?**
  _High betweenness centrality (0.100) - this node is a cross-community bridge._
- **Why does `refresh_session()` connect `session.py` to `auth.py`?**
  _High betweenness centrality (0.087) - this node is a cross-community bridge._
- **What connects `Overview`, `Password Rules`, `Session Management` to the rest of the system?**
  _4 weakly-connected nodes found - possible documentation gaps or missing edges._