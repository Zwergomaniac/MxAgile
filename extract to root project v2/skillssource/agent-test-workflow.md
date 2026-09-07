# Agent Test Workflow

## Browser smoke test

The isolated Docker runner creates exactly one temporary `Administrator` account per
run. Its username and password are random, written only to
`.concord/scratch/docker-test-credentials.json`, and never printed or committed.

The browser test uses that account only for the initial login. After login, it must
exercise the application's existing demo-user switcher/sidepanel and verify that the
expected demo users can be selected there. Do not add one temporary account per demo
role; that bypasses the product flow being tested.

## Isolated runtime

Always pass the exact absolute MPR path with `-p <project.mpr>` to every `mxcli`
model or Docker command. Do not rely on the current working directory. Before
opening Studio Pro, use `scripts/open-studio-pro.ps1`; it refuses to open a second
instance of the same project. An MCP port alone does not identify the project.

Use `scripts/run-docker-isolated.ps1` for Docker and Playwright checks. It creates a
fresh copy under `.concord/scratch`, skips the MPR-v2-materializing pre-check, builds
the PAD, and starts a uniquely named Compose project. The healthcheck probes `/xas/`
and accepts `200` or `401`; a root-page `404` is not used as a liveness signal.

Before and after the run, record the MPR size and `.mxunit` count. A materialized copy
or missing `mprcontents/` invalidates the run, but must not be repaired by copying
runtime output into the canonical project.

## Credentials and cleanup

Credentials are runtime-only test data. Never place them in `.env.mendix.example`,
MDL committed to the project, screenshots, logs, or reports. Stop the uniquely named
Compose project after the test and remove only its disposable volumes.
