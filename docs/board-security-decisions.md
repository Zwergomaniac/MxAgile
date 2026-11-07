# Board security decisions

Decision records for the read-only local MxAgile Dev Board (loopback only).

## BRD-F-68 - references may be framed by the Board itself (accepted 2026-11-07)

**Context.** The Page Hub shows a scaled, read-only preview of a Page's reference (mockup). References are served by
`GET /reference/...`. Until CS-6 they were served with `frame-ancestors 'none'`, so even the Board could not embed them.

**Decision.** References are served with `frame-ancestors 'self'`. Only documents of the Board's own origin
(`127.0.0.1:<port>`) may embed a reference. The Design Preview already used the same value.

**Preserved protections.**

- Foreign origins can still not embed references, previews or any Board asset: there is no wildcard, no scheme or host
  source and no `*` in `frame-ancestors`.
- Every other Board response (application shell, JSON APIs, sources, captures) keeps `frame-ancestors 'none'`.
- The embedding frame is sandboxed (`allow-scripts allow-same-origin`) and loaded lazily on request.
- Reference content keeps `default-src 'self' data: blob:`, `object-src 'none'` and `base-uri 'none'`.

**Regression guard.** `tests/test_board_http.py::test_reference_csp_allows_only_the_board_itself_to_frame` asserts the exact
`frame-ancestors` directive of every response class and rejects wildcard or foreign sources. Do not broaden this policy
without a new decision record.

## Embedded project artifacts are not Board code

Previews embed project artifacts (reference mockups, HTML sources). Script errors raised inside those frames belong to the
artifact. The Board smoke classifies errors whose stack or location points to `/reference/`, `/design-preview/`,
`/design-preview-source/` or `/page-artifact/` as `ARTIFACT_SCRIPT_ERROR` warnings and never as Board failures; the Page Hub
states the same next to its previews.
