"use strict";

const $ = (selector) => document.querySelector(selector);
const root = $("#view");
const tabs = ["overview", "timeline", "waves", "requirements", "tasks", "verification", "pages", "findings", "decisions", "health"];
let status = null;
let loadInFlight = false;
let revisionCheckInFlight = false;
let runEventRevision = null;
const REVISION_POLL_INTERVAL_MS = 2000;

function node(tag, className = "", text = "") {
  const result = document.createElement(tag);
  if (className) result.className = className;
  if (text !== null && text !== undefined) result.textContent = String(text);
  return result;
}

function clear(element) {
  while (element.firstChild) element.removeChild(element.firstChild);
}

function safePathUrl(prefix, path) {
  return `${prefix}/${String(path).split("/").map(encodeURIComponent).join("/")}`;
}

function externalLink(label, href, className = "source-link") {
  const link = node("a", className, label);
  link.href = href;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  return link;
}

function sourceLink(sourceType, artifactId, label = "Quelle öffnen ↗") {
  const reference = status.source_references.items.find((item) =>
    item.source_type === sourceType && item.artifact_id === artifactId && item.availability === "available"
  );
  if (!reference) return node("span", "state unknown", "Quelle unavailable");
  return externalLink(label, safePathUrl("/source", reference.canonical_path));
}

function sourceLinkPath(path, label = "Quelle öffnen ↗") {
  const reference = status.source_references.items.find((item) => item.canonical_path === path && item.availability === "available");
  if (!reference) return node("span", "state unknown", "Quelle unavailable");
  return externalLink(label, safePathUrl("/source", reference.canonical_path));
}

function internalLink(label, route) {
  const link = node("a", "internal-link", label);
  link.href = `#${route}`;
  return link;
}

function stateBadge(value, kind = "") {
  const normalized = value === null || value === undefined || value === "" ? "UNKNOWN" : String(value);
  let tone = "unknown";
  if (["done", "VERIFIED", "CONFIRMED", "passed", "available", "ACTIVE_TARGET", "consistent", "AVAILABLE", "OK"].includes(normalized)) tone = "good";
  else if (["blocked", "failed", "FAIL", "STALE", "DECISION_REQUIRED", "CRITICAL", "ambiguous", "mismatch", "INVALID", "AMBIGUOUS", "BLOCKED", "PROJECTION_ERROR"].includes(normalized)) tone = "bad";
  else if (["PROPOSED", "PARTIAL", "partial", "unknown", "UNKNOWN", "RESULT_UNKNOWN", "INTERRUPTED", "NEEDS_RECONCILIATION", "REASSESS_REQUIRED", "SUPERSEDED", "RETIRED", "FRAMEWORK_FOLLOWUP", "REFERENCE_RECONCILIATION_REQUIRED", "DIRTY_REFERENCE_UNRECONCILED", "NOT_RECORDED", "UNSUPPORTED", "DEGRADED"].includes(normalized)) tone = "warn";
  const badge = node("span", `state ${tone}`, normalized.replaceAll("_", " "));
  if (kind) badge.dataset.kind = kind;
  return badge;
}

function countText(value, suffix = "") {
  return value === null || value === undefined ? "UNKNOWN" : `${value}${suffix}`;
}

const OBS_TEXT = {
  AVAILABLE: ["", "Wert bekannt, Quelle valide."],
  EMPTY: ["EMPTY", "Quelle ist vorhanden und lesbar, enthält aber keine Einträge."],
  NOT_RECORDED: ["NOT RECORDED", "Das Projekt hat diese Quelle nicht angelegt. Das ist keine Aussage über den Inhalt."],
  NOT_LOADED: ["NOT LOADED", "Noch nicht geladen. Fehlende Daten bedeuten hier nicht, dass nichts existiert."],
  LOADING: ["LOADING", "Wird gerade geladen."],
  STALE: ["STALE", "Wert ist an einen älteren Stand gebunden."],
  INVALID: ["INVALID", "Quelle existiert, ist aber nicht lesbar oder schemakonform."],
  UNSUPPORTED: ["UNSUPPORTED", "Quelle in Legacy- oder Fremdform ohne Projektionsregel."],
  NOT_OBSERVABLE: ["NOT OBSERVABLE", "Mit dem heutigen Framework strukturell nicht ermittelbar. Kein Projektdefekt."],
  NOT_APPLICABLE: ["NOT APPLICABLE", "Konzept trifft hier nicht zu."],
  AMBIGUOUS: ["AMBIGUOUS", "Widersprüchliche Quellen, keine eindeutige Aussage möglich."],
  PROJECTION_ERROR: ["PROJECTION ERROR", "Projektion konnte nicht aufgebaut werden."],
};
const GROUP_TEXT = {
  project_attention: ["Project attention", "Kann Aktion von Projekteigner oder Entwickler erfordern."],
  projection_health: ["Projection / data health", "Qualität und Lesbarkeit der projizierten Quellen."],
  framework_compat: ["Framework diagnostics", "Implementierungs-, Kompatibilitäts- und Historieninformation. Für sich keine aktive Projektblockade."],
  optional_metadata: ["Optional metadata", "Optionale Felder, die das Projekt nicht gesetzt hat."],
};

function obsOf(area) {
  return area && typeof area.observation_state === "string" ? area.observation_state : null;
}

function obsLabel(area, fallback = "UNKNOWN") {
  const state = obsOf(area);
  return state && OBS_TEXT[state] && OBS_TEXT[state][0] ? OBS_TEXT[state][0] : fallback;
}

// A missing value is shown as its precise observation state, never as 0 or as a generic UNKNOWN (v2 snapshots fall back).
function valueText(value, area, suffix = "") {
  if (value !== null && value !== undefined) return `${value}${suffix}`;
  return obsLabel(area, "UNKNOWN");
}

function obsBadge(state) {
  const info = OBS_TEXT[state] || [String(state), ""];
  const badge = stateBadge(state);
  badge.textContent = info[0] || "AVAILABLE";
  if (info[1]) badge.title = info[1];
  return badge;
}


function sectionTitle(title, detail = "") {
  const wrapper = node("div", "view-title");
  wrapper.append(node("h2", "", title));
  if (detail) wrapper.append(node("small", "", detail));
  return wrapper;
}

function empty(message) {
  return node("div", "empty", message);
}

function pathLabel(path) {
  if (!path) return "REFERENCE UNKNOWN";
  return path.split("/").pop();
}

function routeParts() {
  const full = location.hash.slice(1) || "portfolio";
  const query = full.indexOf("?");
  const raw = decodeURIComponent(query >= 0 ? full.slice(0, query) : full);
  return raw.split("/").filter(Boolean);
}

function navigate(route) {
  location.hash = route;
}

function targetCard(target) {
  const card = node("article", "target-card");
  const meta = node("div", "target-meta");
  const title = target.mockup_name || target.revision_id || pathLabel(target.canonical_path) || "Reference";
  meta.append(node("strong", "", title));
  const referenceType = target.reference_type === "spa_bundle_entrypoint" ? "SPA BUNDLE" : target.reference_type === "single_file_mockup" ? "SINGLE-FILE TARGET" : "REFERENCE TYPE UNKNOWN";
  meta.append(node("div", "target-file", `${referenceType} · ${target.revision_id || "NO REVISION"} · ${pathLabel(target.canonical_path)}`));
  meta.append(node("div", "target-fingerprint", `REFERENCE ID  ${target.reference_id || "UNKNOWN"}`));
  const fingerprint = target.bundle_hash || target.content_hash || target.source_fingerprint;
  meta.append(node("div", "target-fingerprint", fingerprint ? `FINGERPRINT  ${fingerprint.slice(0, 19)}…` : "FINGERPRINT  UNKNOWN"));
  const authority = node("div", "target-fingerprint", `AUTHORITY  ${target.authoritative_state || "UNKNOWN"} · ${target.availability.toUpperCase()}`);
  meta.append(authority);
  const authoritySources = (target.authority_sources || []).map((source) => `${source.source_type} · ${pathLabel(source.canonical_path)}`);
  meta.append(node("div", "target-fingerprint", `AUTHORITY SOURCE  ${authoritySources.join(" · ") || "UNKNOWN"}`));
  for (const binding of target.page_bindings || []) {
    meta.append(node("div", "target-file", `${binding.page_id} · Mendix: ${binding.mendix_page_name || "UNBOUND"}`));
  }
  const drift = target.inventory_drift?.state || "unknown";
  meta.append(stateBadge(drift === "not_applicable" ? "CONSISTENT" : drift.toUpperCase(), "reference-drift"));
  card.append(meta);
  if (target.availability === "available" && target.canonical_path) {
    card.append(externalLink("Mockup öffnen ↗", safePathUrl("/reference", target.canonical_path), "target-open"));
  } else {
    card.append(node("span", "state warn", "REFERENCE UNKNOWN"));
  }
  return card;
}

function renderHeader() {
  const project = status.project;
  $("#project-name").textContent = project.name || "MxAgile Project";
  $("#rail-project-name").textContent = project.name || "Project";
  $("#core-version").textContent = project.core_version || "unknown";
  $("#fingerprint-short").textContent = status.source_fingerprint ? status.source_fingerprint.slice(0, 15) : "";
  $("#source-fingerprint").textContent = status.source_fingerprint || "SOURCE FINGERPRINT UNKNOWN";
  const idle = status.current_work && status.current_work.state === "NONE";
  $("#active-wave").textContent = project.lifecycle.active_wave_id || "—";
  $("#active-phase").textContent = idle ? "keine aktive Wave" : (project.lifecycle.phase || obsLabel(project.lifecycle));
  const phase = project.lifecycle.phase || obsLabel(project.lifecycle).replaceAll(" ", "_");
  const phasePill = $("#lifecycle-pill");
  phasePill.textContent = phase.toUpperCase().replaceAll("_", " ");
  phasePill.className = `pill ${phase === "done" ? "" : phase === phase.toUpperCase() ? "warn" : ""}`;
  const mission = status.mission;
  $("#mission-line").textContent = mission.availability === "unavailable"
    ? `Mission state · ${obsLabel(mission, "unavailable")}`
    : `${mission.id || "Mission"} · ${mission.status || obsLabel(mission)}`;

  const targets = status.project.active_targets.items;
  const targetList = $("#target-list");
  clear(targetList);
  $("#target-state").textContent = targets.length ? "ACTIVE TARGET AUTHORITY" : obsLabel(status.project.active_targets, "REFERENCE UNKNOWN");
  if (!targets.length) targetList.append(node("div", "target-unknown", `${obsLabel(status.project.active_targets, "REFERENCE UNKNOWN")} · No canonical ACTIVE_TARGET reference available`));
  else for (const target of targets) targetList.append(compactTargetCard(target));
  for (const candidate of status.reconciliation?.external_reference_candidates || []) {
    const card = node("article", "target-card reference-candidate");
    const meta = node("div", "target-meta");
    meta.append(node("strong", "", "NEW EXTERNAL REFERENCE CANDIDATE"));
    meta.append(node("div", "target-file", candidate.path));
    meta.append(node("div", "target-fingerprint", "NOT ACTIVE · RECONCILIATION REQUIRED"));
    card.append(meta, stateBadge(candidate.status));
    targetList.append(card);
  }
  renderProjectDrift();
}

function renderProjectDrift() {
  const reconciliation = status.reconciliation;
  const stateLabel = $("#drift-state");
  const facts = $("#drift-facts");
  clear(facts);
  if (!reconciliation) {
    stateLabel.textContent = "NOT LOADED";
    facts.append(empty("Reconciliation not loaded. This does not mean that no reconciliation exists."));
    return;
  }
  const range = reconciliation.commit_range || {};
  const head = range.to_commit ? range.to_commit.slice(0, 12) : "NICHT ERMITTELT";
  const branch = range.branch_ref ? range.branch_ref.replace(/^refs\/heads\//, "") : "NICHT ERMITTELT";
  // Not loaded / loading is a transient projection state, never a project fact (BRD-F-01).
  if (reconciliation.availability === "not_loaded") {
    stateLabel.textContent = status.reconciliation_loading ? "LÄDT …" : "NICHT GELADEN";
    for (const [label, value] of [
      ["CURRENT HEAD", head],
      ["BRANCH", branch],
      ["LAST RECONCILED", "lädt …"],
      ["UNRECONCILED COMMITS", "lädt …"],
    ]) facts.append(countItem(label, value, ""));
    return;
  }
  if (reconciliation.availability === "unavailable") {
    stateLabel.textContent = "RECONCILIATION NICHT VERFÜGBAR";
    for (const [label, value] of [
      ["CURRENT HEAD", head],
      ["BRANCH", branch],
      ["GRUND", "Reconciliation-Bericht konnte nicht erstellt werden"],
    ]) facts.append(countItem(label, value, ""));
    return;
  }
  const watermark = range.from_commit || (range.status === "BASELINE_REQUIRED" ? "BASELINE REQUIRED" : "NICHT ERMITTELT");
  const commits = Array.isArray(range.commits) ? range.commits : [];
  const externalCommitCount = commits.filter((commit) => ["EXTERNAL_CHANGE", "MIXED", "AMBIGUOUS"].includes(commit.classification)).length;
  const externalPathCount = commits.reduce((total, commit) => total + (commit.paths || []).filter((path) => ["EXTERNAL_CHANGE", "AMBIGUOUS"].includes(path.classification)).length, 0);
  stateLabel.textContent = String(range.status || reconciliation.status || "UNKNOWN").replaceAll("_", " ");
  facts.append(countItem("BRANCH", branch, ""));
  for (const [label, value] of [
    ["LAST RECONCILED", watermark],
    ["CURRENT HEAD", head],
    ["UNRECONCILED COMMITS", countText(commits.length)],
    ["EXTERNAL / AMBIGUOUS", `${externalCommitCount} commits · ${externalPathCount} paths`],
    ["WATERMARK GATE", (reconciliation.watermark_gate?.blockers || []).join(", ") || "EXPLICIT ADVANCE REQUIRED"],
  ]) facts.append(countItem(label, value, ""));
}

function renderAttention() {
  const container = $("#attention-items");
  clear(container);
  const values = [
    ["BLOCKERS", valueText(status.mission.blocker_count, status.mission)],
    ["BLOCKING FINDINGS", valueText(status.findings.blocking, status.findings)],
    ["BLOCKED BY DECISION", valueText(status.decisions.blocked_by_decision.count, status.mission)],
    ["PENDING DECISIONS", valueText(status.decisions.status_counts.PROPOSED, status.decisions)],
    ["STALE EVIDENCE", valueText(status.verification.evidence.current_counts.stale, status.verification.evidence)],
  ];
  const health = status.health;
  if (health) {
    values.push(["PROJECT ATTENTION ITEMS", health.diagnostics_by_group.project_attention.total]);
    // Blocking diagnostics stay visible on the first screen whatever their group.
    if (health.blocking_diagnostics > 0) values.push(["BLOCKING DIAGNOSTICS", health.blocking_diagnostics]);
  }
  if (status.reconciliation?.model_semantic_review?.status === "SEMANTIC_REVIEW_REQUIRED") {
    values.push(["MENDIX MODEL REVIEW", status.reconciliation.model_semantic_review.reason || "SEMANTIC_REVIEW_REQUIRED"]);
  }
  for (const [label, value] of values) {
    const chip = node("span", "attention-chip");
    chip.append(node("b", "", String(value)));
    chip.append(node("span", "", label));
    container.append(chip);
  }
}

function renderMetrics() {
  const container = $("#metrics");
  clear(container);
  const waves = status.delivery.waves.phase_counts;
  const proposed = status.decisions.status_counts.PROPOSED;
  const evidence = status.verification.evidence.current_counts;
  const values = [
    ["WAVES COMPLETE", valueText(waves.done, status.delivery.waves)],
    ["ACTIVE MISSION", status.mission.status || obsLabel(status.mission)],
    ["OPEN FINDINGS", valueText(status.findings.open, status.findings)],
  ];
  for (const [label, value] of values) {
    const box = node("div", "metric");
    box.append(node("div", "metric-label", label));
    box.append(node("div", "metric-value", value));
    container.append(box);
  }
}

function renderOverview() {
  renderHealthSummary(root);
  root.append(sectionTitle("Delivery at a glance", "Objective counts · no weighted progress"));
  const grid = node("div", "two-column");
  const wavesSection = node("section", "plain-section");
  wavesSection.append(node("h3", "", "Waves"));
  const wavesList = node("div", "plain-list");
  for (const wave of status.delivery.waves.items) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(internalLink(wave.wave_id, `wave/${encodeURIComponent(wave.wave_id)}`));
    main.append(node("small", "", `${valueText(wave.task_progress.total, status.delivery.tasks)} tasks · ${wave.checklist_progress.availability === "available" ? `${wave.checklist_progress.done}/${wave.checklist_progress.total} checklist` : "no checklist recorded"}`));
    row.append(main, stateBadge(wave.phase || "UNKNOWN"));
    wavesList.append(row);
  }
  wavesSection.append(wavesList.childElementCount ? wavesList : empty("Wave state unavailable"));

  const rightSection = node("section", "plain-section");
  rightSection.append(node("h3", "", "Verification"));
  const evidence = status.verification.evidence;
  const evidenceList = node("div", "plain-list");
  for (const [label, value] of [
    ["Target freshness", evidence.target_freshness],
    ["Target stale", evidence.current_counts.stale],
    ["Unverified", evidence.current_counts.unverified],
    ["Failed", evidence.current_counts.failed],
  ]) {
    const row = node("div", "plain-item");
    row.append(node("div", "item-main", label), stateBadge(value === null ? obsLabel(evidence).replaceAll(" ", "_") : value));
    evidenceList.append(row);
  }
  rightSection.append(evidenceList);
  grid.append(wavesSection, rightSection);
  root.append(grid);

  renderTrustInDone(root);
  renderRevisionLedger(root);
  root.append(sectionTitle("Requirements", `${valueText(status.requirements.total, status.requirements)} total`));
  renderRequirementTable(root, status.requirements.items.slice(0, 6));
}

function renderPortfolio() {
  root.append(sectionTitle("Portfolio", "Dieses lokale Board ist an genau ein ausgewähltes Projekt gebunden"));
  const card = node("article", "portfolio-card");
  const heading = node("div", "portfolio-project-heading");
  const identity = node("div", "item-main");
  identity.append(node("div", "eyebrow", `PROJECT · CORE ${status.project.core_version || "UNKNOWN"}`));
  identity.append(node("h2", "", status.project.name || "MxAgile Project"));
  heading.append(identity, stateBadge(status.project.lifecycle.phase || "UNKNOWN"));
  card.append(heading);
  const facts = node("div", "portfolio-facts");
  const activeWave = status.project.lifecycle.active_wave_id || "UNKNOWN";
  const verification = status.verification.evidence.current_counts;
  for (const [label, value] of [
    ["LIFECYCLE", status.project.lifecycle.phase || "UNKNOWN"],
    ["ACTIVE WAVE / MISSION", `${activeWave} · ${status.mission.status || "UNKNOWN"}`],
    ["BLOCKERS", countText(status.mission.blocker_count)],
    ["PENDING DECISIONS", countText(status.decisions.status_counts.PROPOSED)],
    ["VERIFICATION ATTENTION", `STALE ${countText(verification.stale)} · FAILED ${countText(verification.failed)}`],
  ]) facts.append(countItem(label, value, ""));
  card.append(facts);
  card.append(internalLink("Project Overview →", "overview"));
  root.append(card);
}

function renderRequirementTable(container, requirements) {
  if (!requirements.length) {
    container.append(empty(status.requirements.availability === "unavailable" ? "Requirements unavailable" : "No Requirements"));
    return;
  }
  const scroll = node("div", "table-scroll");
  const table = node("table", "data-table");
  const head = document.createElement("thead");
  const header = document.createElement("tr");
  for (const label of ["Requirement", "Status", "Superseded by", "Assessment (abgeleitet)", "Wave / Workpackage", "Source"]) header.append(node("th", "", label));
  head.append(header);
  const body = document.createElement("tbody");
  for (const req of requirements) {
    const related = status.delivery.tasks.items.filter((task) => task.requirement_ids.includes(req.id));
    const assignments = [...new Set(related.map((task) => [task.wave_id, task.workpackage_id].filter(Boolean).join(" / ")).filter(Boolean))];
    const row = document.createElement("tr");
    const idCell = document.createElement("td");
    idCell.append(internalLink(`${req.id} · ${req.title || "Untitled"}`, `requirement/${encodeURIComponent(req.id)}`));
    const statusCell = document.createElement("td");
    statusCell.append(stateBadge(req.status || "UNKNOWN"));
    const successorCell = document.createElement("td");
    if (req.superseded_by) successorCell.append(internalLink(req.superseded_by, `requirement/${encodeURIComponent(req.superseded_by)}`));
    else successorCell.textContent = req.status === "superseded" ? "SUCCESSOR UNKNOWN" : "—";
    const assignCell = node("td", "count-pair", assignments.length ? assignments.join(", ") : "UNMAPPED");
    const assessmentCell = document.createElement("td");
    if (req.delivery_assessment) assessmentCell.append(stateBadge(req.delivery_assessment.label));
    const sourceCell = document.createElement("td");
    sourceCell.append(sourceLink("requirement", req.id));
    row.append(idCell, statusCell, successorCell, assessmentCell, assignCell, sourceCell);
    body.append(row);
  }
  table.append(head, body);
  scroll.append(table);
  container.append(scroll);
}

function renderWaves() {
  root.append(sectionTitle("Waves & Workpackages", "Wave assignments come from canonical process state and explicit task fields"));
  if (!status.delivery.waves.items.length) root.append(empty("Wave state unavailable"));
  for (const wave of status.delivery.waves.items) {
    const panel = node("article", "plain-section");
    const title = node("div", "view-title");
    title.append(internalLink(wave.wave_id, `wave/${encodeURIComponent(wave.wave_id)}`));
    title.append(stateBadge(wave.phase || "UNKNOWN"));
    panel.append(title);
    const details = node("div", "row-panel");
    details.append(countItem("TASKS", wave.task_progress.total, `${wave.task_progress.status_counts.done ?? "UNKNOWN"} done`));
    details.append(countItem("CHECKLIST", wave.checklist_progress.total, wave.checklist_progress.availability === "available" ? `${wave.checklist_progress.done} done` : "UNKNOWN"));
    details.append(countItem("GATE READY", wave.gates.gate_to_ready, ""));
    details.append(countItem("REQUIREMENTS", wave.requirement_ids.length, wave.requirement_ids.join(", ") || "UNMAPPED"));
    panel.append(details);
    root.append(panel);
  }
  root.append(sectionTitle("Workpackages", `${status.delivery.workpackages.unmapped_task_count ?? "UNKNOWN"} tasks without explicit workpackage`));
  if (!status.delivery.workpackages.items.length) {
    root.append(empty("Workpackages unavailable until canonical tasks carry workpackage_id"));
  } else {
    for (const workpackage of status.delivery.workpackages.items) {
      const row = node("div", "plain-item");
      row.append(internalLink(workpackage.workpackage_id, `workpackage/${encodeURIComponent(workpackage.wave_id || "")}/${encodeURIComponent(workpackage.workpackage_id)}`));
      row.append(node("span", "count-pair", `${workpackage.task_progress.status_counts.done ?? "UNKNOWN"}/${workpackage.task_progress.total ?? "UNKNOWN"} done`));
      root.append(row);
    }
  }
  const knownWaves = new Set(status.delivery.waves.items.map((wave) => wave.wave_id));
  const unassigned = status.delivery.tasks.items.filter((task) => !knownWaves.has(task.wave_id));
  root.append(sectionTitle("Tasks", `${status.delivery.tasks.items.length} recognized · ${unassigned.length} UNASSIGNED`));
  renderTaskList(unassigned);
}

function countItem(label, value, detail) {
  const item = node("div", "count-pair");
  item.append(node("span", "metric-label", label));
  item.append(node("div", "", countText(value)));
  if (detail) item.append(node("small", "muted", detail));
  return item;
}

function renderRequirements() {
  root.append(sectionTitle("Requirements", "Canonical status and explicit delivery links"));
  renderRequirementTable(root, status.requirements.items);
}

function renderVerification() {
  root.append(sectionTitle("Verification & Evidence", "Recorded result is distinct from freshness"));
  const evidence = status.verification.evidence;
  const banner = node("div", "attention-strip");
  banner.append(node("div", "attention-title", "Model freshness"));
  banner.append(node("div", "attention-items", obsLabel({ observation_state: evidence.model_freshness_observation_state }, evidence.model_freshness.toUpperCase())), internalLink("Erklärung in Health & Diagnostics →", "health"));
  root.append(banner);
  const grid = node("div", "metrics");
  for (const [label, count] of [
    ["RECORDED PASS", evidence.recorded_counts.PASS],
    ["UNVERIFIED", evidence.current_counts.unverified],
    ["STALE", evidence.current_counts.stale],
    ["FAILED", evidence.current_counts.failed],
  ]) {
    const card = node("div", "metric");
    card.append(node("div", "metric-label", label), node("div", "metric-value", countText(count)));
    grid.append(card);
  }
  root.append(grid);
  root.append(node("p", "muted", "Recorded PASS is not promoted to VERIFIED while current Mendix model freshness is unknown."));
  const evidenceEntries = Array.isArray(evidence.entries) ? evidence.entries : [];
  root.append(sectionTitle("Evidence entries", `${evidenceEntries.length} recorded`));
  if (evidenceEntries.length) {
    const list = node("div", "plain-list");
    for (const entry of evidenceEntries) {
      const row = node("article", "plain-item");
      const main = node("div", "item-main");
      main.append(node("strong", "", `${entry.entry_id} · ${entry.screen_id}`));
      main.append(node("small", "", `${entry.scenario_id} · ${entry.requirement_ids.join(", ") || "No Requirement link"} · ${entry.target_revision || "TARGET UNKNOWN"}`));
      row.append(main, stateBadge(entry.parity_result || "UNKNOWN"), sourceLinkPath(entry.canonical_path, "Manifest ↗"));
      list.append(row);
    }
    root.append(list);
  } else {
    root.append(empty("Evidence manifests unavailable"));
  }
  renderParityReports();
  renderReferenceList(root, ["test_contract", "verification_plan", "evidence_manifest", "evidence_artifact", "parity_report"]);
}

function renderGallery(screenId = null) {
  root.append(sectionTitle(screenId || "Parity Evidence", "Mock / Runtime"));
  const runs = screenId ? status.page_galleries?.[screenId] : status.all_gallery;
  if (!runs) {
    const cacheKey = screenId || "*";
    const unavailable = status.gallery_errors?.[cacheKey];
    root.append(empty(unavailable ? "PARITY EVIDENCE UNAVAILABLE" : (status.gallery_loading?.[cacheKey] ? "LOADING PARITY EVIDENCE" : "PARITY EVIDENCE NOT LOADED")));
    if (!unavailable) void loadGallery(screenId);
    return;
  }
  if (!runs.length) {
    root.append(empty("VISUAL PARITY NOT VERIFIED"));
    return;
  }
  function renderRun(run, container) {
    const heading = node("div", "gallery-heading");
    heading.append(internalLink(run.screen_id, `page/${encodeURIComponent(run.screen_id)}`));
    heading.append(node("strong", "", run.revision), stateBadge(run.historical ? "HISTORICAL" : "ACTIVE_TARGET"));
    heading.append(stateBadge(run.parity_result));
    heading.append(externalLink("Mockup öffnen ↗", safePathUrl("/reference", run.reference_path)));
    container.append(heading);
    container.append(node("p", "gallery-provenance", `REFERENCE ${run.reference_fingerprint}`));
    container.append(node("p", "gallery-provenance", `${run.manifest_path} · ${run.entry_id} · ${run.run_id}`));
    const resolution = run.parity_resolution || {};
    const resolutionDetails = node("details", "gallery-resolution");
    resolutionDetails.append(node("summary", "", "Aggregate resolution"));
    resolutionDetails.append(node("p", "gallery-provenance", `CLASS ${resolution.evidence_class || "NOT_OBSERVABLE"} · STATUS ${resolution.status || "NOT_OBSERVABLE"}`));
    resolutionDetails.append(node("p", "gallery-provenance", `REPORTED ${run.reported_parity_result || "NOT_OBSERVABLE"} · COMPUTED ${resolution.computed_overall_result || "NOT_VERIFIED"}`));
    resolutionDetails.append(node("p", "gallery-provenance", `IDENTITY ${resolution.comparison_identity_status || "NOT_OBSERVABLE"} · FRESHNESS ${resolution.target_freshness || "NOT_OBSERVABLE"}`));
    for (const blocker of resolution.blockers || []) {
      resolutionDetails.append(node("p", "gallery-provenance", `${blocker.code}: ${blocker.reason}`));
    }
    container.append(resolutionDetails);
    const dimensions = node("dl", "gallery-dimensions");
    for (const [key, label] of [
      ["contract_parity", "CONTRACT"], ["model_parity", "MODEL"], ["structural_dom_parity", "STRUCTURAL_DOM"],
      ["behavioral_parity", "BEHAVIORAL"], ["role_parity", "ROLE"], ["visual_whole_screen_parity", "VISUAL_WHOLE_SCREEN"],
    ]) {
      const dimension = node("div");
      dimension.append(node("dt", "", label));
      const value = node("dd");
      value.append(stateBadge(run.dimensions[key] || "NOT_VERIFIED"));
      dimension.append(value);
      dimensions.append(dimension);
    }
    container.append(dimensions);
    const captures = node("div", "gallery-captures");
    for (const capture of run.captures) {
      const figure = node("figure", "gallery-capture");
      const link = externalLink("", safePathUrl("/capture", capture.screenshot_path), "gallery-image-link");
      link.title = `${capture.capture_id} öffnen`;
      const image = node("img");
      image.alt = `${capture.side === "mockup" ? "Mock" : "Runtime"} · ${capture.role} · ${run.screen_id}`;
      image.loading = "lazy";
      image.src = link.href;
      link.append(image);
      const caption = node("figcaption");
      caption.append(node("strong", "", `${capture.side === "mockup" ? "Soll / Mock" : "Runtime / Ist"} · ${capture.role}`));
      caption.append(node("small", "", `${capture.run_id} · ${capture.capture_id}`));
      caption.append(node("small", "", capture.captured_at));
      caption.append(node("small", "", `${capture.cleanliness_state} · ${capture.freshness} · ${capture.evidence_status}`));
      if (capture.runtime_url) caption.append(externalLink(capture.runtime_url, capture.runtime_url));
      figure.append(link, caption);
      captures.append(figure);
    }
    container.append(captures);
    if (!run.captures.some((capture) => capture.side === "mockup") || !run.captures.some((capture) => capture.side === "application")) {
      container.append(empty("VISUAL PARITY NOT VERIFIED"));
    }
  }
  for (const run of runs.filter((item) => !item.historical)) {
    const section = node("section", "gallery-run");
    renderRun(run, section);
    root.append(section);
  }
  for (const run of runs.filter((item) => item.historical)) {
    const details = node("details", "gallery-run gallery-history");
    details.append(node("summary", "", `${run.screen_id} · ${run.revision} · HISTORICAL · ${run.run_id}`));
    details.addEventListener("toggle", () => {
      if (details.open && !details.dataset.loaded) {
        renderRun(run, details);
        details.dataset.loaded = "true";
      }
    });
    root.append(details);
  }
}

function renderUiPages() {
  root.append(sectionTitle("UI & Pages", "Project settings · page implementation · design and runtime evidence"));
  const resolved = status.ui_settings || {};
  const settingLabels = [
    ["html_first", "UI IMPLEMENTATION"],
    ["mockup_driven", "MOCKUP VERIFICATION"],
    ["leave_running_after_visual_verification", "RUNTIME AFTER VISUAL VERIFICATION"],
  ];
  const settings = node("section", "ui-settings");
  settings.append(node("h3", "eyebrow", "PROJECT DEFAULTS"));
  if (resolved.availability !== "available") {
    settings.append(empty("PROJECT SETTINGS INVALID OR UNAVAILABLE"));
  } else {
    const settingGrid = node("div", "ui-setting-grid");
    for (const [key, label] of settingLabels) {
      const value = resolved.settings?.[key];
      if (!value) continue;
      const row = node("div", "ui-setting-row");
      row.append(node("span", "metric-label", label));
      row.append(node("strong", "ui-setting-value", String(value.effective).toUpperCase()));
      row.append(node("small", "muted", `REQUESTED ${String(value.requested).toUpperCase()} · SOURCE ${String(value.source).toUpperCase()} · SCOPE ${value.scope || "project"}`));
      if (value.override) row.append(node("small", "muted", `OVERRIDE ${value.override.page_id} = ${String(value.override.value).toUpperCase()}`));
      settingGrid.append(row);
    }
    settings.append(settingGrid);
  }
  root.append(settings);

  const projection = status.page_previews;
  if (!projection) {
    root.append(empty(status.page_previews_loading ? "LOADING PAGE PREVIEW METADATA" : "PAGE PREVIEW METADATA NOT LOADED"));
    void loadPagePreviews();
    return;
  }
  const builder = projection.builder_kit || {};
  const builderSection = node("section", "ui-settings");
  builderSection.append(node("h3", "eyebrow", "BUILDER KIT CAPABILITY"));
  const builderGrid = node("div", "ui-setting-grid");
  for (const [label, value] of [
    ["KIT INSTALLED", builder.availability === "available" ? String(builder.installed).toUpperCase() : "UNKNOWN"],
    ["KIT VERSION", builder.version || "UNKNOWN"],
    ["AGENT AVAILABLE FOR HARNESS", builder.agent_available_for_harness === null || builder.agent_available_for_harness === undefined ? "UNKNOWN" : String(builder.agent_available_for_harness).toUpperCase()],
    ["AGENT DELEGABLE THIS SESSION", builder.agent_delegable === null || builder.agent_delegable === undefined ? "UNKNOWN" : String(builder.agent_delegable).toUpperCase()],
  ]) {
    const row = node("div", "ui-setting-row");
    row.append(node("span", "metric-label", label));
    row.append(node("strong", "ui-setting-value", value));
    builderGrid.append(row);
  }
  builderSection.append(builderGrid);
  root.append(builderSection);

  if (projection.availability !== "available") {
    root.append(empty("PAGE INVENTORY UNAVAILABLE"));
    return;
  }
  if (!projection.items.length) {
    root.append(empty("NO CANONICAL PAGES IN UI INVENTORY"));
    return;
  }
  const pageGrid = node("div", "page-preview-grid");
  for (const page of projection.items) {
    const card = node("article", "page-preview-card");
    const heading = node("div", "page-preview-heading");
    heading.append(node("div", "page-preview-name", page.page_name));
    heading.append(node("code", "page-preview-id", page.page_id));
    card.append(heading);

    const facts = node("dl", "page-preview-facts");
    // Parity is only shown once evidence data is loaded; until then no value is implied (BRD-F-06).
    const parityLabel = page.parity_status === "NOT_LOADED"
      ? (status.gallery_errors?.["*"] ? "NICHT VERFÜGBAR" : (status.gallery_loading?.["*"] ? "LÄDT …" : "NICHT GELADEN"))
      : (page.parity_status || "NOT_VERIFIED");
    for (const [label, value] of [
      ["IMPLEMENTATION (ABSICHT)", page.implementation_mode],
      ...(page.implementation && page.implementation.mismatch ? [["ABSICHT ≠ FAKT", page.implementation.mismatch_reason]] : []),
      ["MOCKUP MODE", page.mockup_driven?.effective || "UNKNOWN"],
      ["PARITY", parityLabel],
      ["RUNTIME (RECORDED)", page.runtime_status?.state || "NOT_RECORDED"],
    ]) {
      const pair = node("div");
      pair.append(node("dt", "metric-label", label));
      pair.append(node("dd", "", value));
      facts.append(pair);
    }
    const conflicts = page.authority_conflicts?.items || [];
    const conflictPair = node("div");
    conflictPair.append(node("dt", "metric-label", "AUTHORITY CONFLICTS"));
    conflictPair.append(node("dd", "", page.authority_conflicts?.availability === "available" ? String(conflicts.length) : "UNKNOWN"));
    facts.append(conflictPair);
    card.append(facts);

    const actions = node("div", "page-preview-actions");
    if (page.reference?.availability === "available" && page.reference.path) {
      actions.append(externalLink("Reference / Mockup", safePathUrl("/reference", page.reference.path), "preview-type preview-reference"));
    } else actions.append(node("span", "state unknown", "Reference unknown"));
    if (page.html_source?.availability === "available") {
      actions.append(externalLink("DESIGN PREVIEW", page.html_source.preview_url, "preview-type preview-design"));
      actions.append(externalLink("HTML Source", page.html_source.source_url, "preview-type preview-source"));
    } else if (page.implementation_mode === "HTML_FIRST") {
      actions.append(node("span", "state warn", "HTML source not registered or unavailable"));
    }
    const evidenceLink = internalLink("Verification Evidence", `page/${encodeURIComponent(page.page_id)}`);
    evidenceLink.className = "preview-type preview-evidence";
    actions.append(evidenceLink);
    if (page.last_verification_evidence?.runtime_url) {
      actions.append(externalLink("Mendix Runtime", page.last_verification_evidence.runtime_url, "preview-type preview-runtime"));
    }
    card.append(actions);
    const evidence = page.last_verification_evidence;
    card.append(node("small", "gallery-provenance", evidence
      ? evidence.status === "NOT_LOADED"
        ? "LAST VERIFICATION EVIDENCE · NOT LOADED"
        : `${evidence.entry_id || "EVIDENCE"} · ${evidence.run_id || "RUN UNKNOWN"} · ${evidence.captured_at || "TIME UNKNOWN"}${evidence.historical ? " · HISTORICAL" : ""}`
      : "LAST VERIFICATION EVIDENCE · NOT RECORDED"));
    if (conflicts.length) {
      const conflictList = node("div", "page-authority-conflicts");
      for (const conflict of conflicts) conflictList.append(stateBadge(`${conflict.id || "FINDING"} · AUTHORITY CONFLICT`, "authority-conflict"));
      card.append(conflictList);
    }
    pageGrid.append(card);
  }
  root.append(pageGrid);
  if (!status.all_gallery && !status.gallery_errors?.["*"]) void loadGallery();
}

async function loadPagePreviews() {
  if (status.page_previews_loading || status.page_previews) return;
  status.page_previews_loading = true;
  try {
    const response = await fetch("/api/page-previews", { cache: "no-store" });
    if (!response.ok) throw new Error("Page preview metadata unavailable");
    status.page_previews = await response.json();
    if (status.all_gallery) {
      for (const page of status.page_previews.items || []) {
        updatePageEvidence(page.page_id, status.all_gallery, status.all_gallery_latest || {});
      }
    }
  } catch {
    status.page_previews = { availability: "unavailable", items: [] };
  } finally {
    status.page_previews_loading = false;
    if (routeParts()[0] === "ui-pages") renderView();
  }
}

async function loadGallery(screenId = null) {
  const cacheKey = screenId || "*";
  status.gallery_loading ||= {};
  status.gallery_errors ||= {};
  status.page_galleries ||= {};
  if (status.gallery_loading[cacheKey]) return;
  if (screenId ? status.page_galleries[screenId] : status.all_gallery) return;
  status.gallery_loading[cacheKey] = true;
  try {
    const query = screenId ? `?screen_id=${encodeURIComponent(screenId)}` : "";
    const response = await fetch(`/api/gallery${query}`, { cache: "no-store" });
    if (!response.ok) throw new Error("Parity gallery unavailable");
    const result = await response.json();
    const latestRuns = result.latest_runs || {};
    if (screenId) {
      status.page_galleries[screenId] = result.items || [];
      updatePageEvidence(screenId, result.items || [], latestRuns);
    } else {
      status.all_gallery = result.items || [];
      status.all_gallery_latest = latestRuns;
      for (const page of status.page_previews?.items || []) {
        updatePageEvidence(page.page_id, result.items || [], latestRuns);
      }
    }
    delete status.gallery_errors[cacheKey];
  } catch {
    status.gallery_errors[cacheKey] = true;
  } finally {
    status.gallery_loading[cacheKey] = false;
    const parts = routeParts();
    if ((screenId && parts[0] === "page" && parts[1] === screenId) || (!screenId && ["gallery", "ui-pages"].includes(parts[0]))) {
      renderView();
    }
  }
}

function updatePageEvidence(pageId, runs, latestRuns) {
  const page = status.page_previews?.items?.find((item) => item.page_id === pageId);
  if (!page) return;
  // The latest-run decision is made once on the server; the client only looks it up (BRD-F-08).
  const key = latestRuns[pageId];
  const latestRun = key
    ? runs.find((run) => run.screen_id === pageId && run.entry_id === key.entry_id && run.run_id === key.run_id && run.manifest_path === key.manifest_path)
    : null;
  page.parity_status = !latestRun ? "NOT_VERIFIED" : (key.stale ? "STALE" : (latestRun.parity_result || "NOT_VERIFIED"));
  if (!latestRun) {
    page.last_verification_evidence = null;
    return;
  }
  const captures = latestRun.captures || [];
  page.last_verification_evidence = {
    entry_id: latestRun.entry_id,
    run_id: latestRun.run_id,
    parity_status: latestRun.parity_result || "NOT_VERIFIED",
    captured_at: captures.map((capture) => capture.captured_at || "").sort().at(-1) || null,
    capture_count: captures.length,
    historical: Boolean(latestRun.historical),
    runtime_url: captures.find((capture) => capture.runtime_url)?.runtime_url || null,
  };
}

async function loadReconciliation() {
  if (!status || status.reconciliation?.availability !== "not_loaded" || status.reconciliation_loading) return;
  status.reconciliation_loading = true;
  renderProjectDrift();
  // Observed HEAD/branch from the summary stay visible even if the report fails.
  const observedRange = { ...(status.reconciliation.commit_range || {}), status: "UNAVAILABLE", commits: [], spans: [] };
  try {
    const response = await fetch("/api/reconciliation", { cache: "no-store" });
    if (!response.ok) throw new Error("Project reconciliation unavailable");
    const result = await response.json();
    status.reconciliation = result.reconciliation || { status: "UNAVAILABLE", availability: "unavailable", commit_range: observedRange };
  } catch {
    status.reconciliation = { status: "UNAVAILABLE", availability: "unavailable", commit_range: observedRange };
  } finally {
    status.reconciliation_loading = false;
    renderProjectDrift();
    if (routeParts()[0] === "overview") renderView();
  }
}

function renderFindings() {
  root.append(sectionTitle("Findings", `${countText(status.findings.open)} open · ${countText(status.findings.blocking)} blocking · ${countText(status.findings.decision_required)} decision required · ${countText(status.findings.framework_followup)} framework followup · ${countText(status.findings.resolved)} resolved · ${countText(status.findings.superseded)} superseded`));
  if (!status.findings.items.length) {
    root.append(empty(status.findings.availability === "unavailable" ? "Canonical Finding records unavailable" : "No active Findings"));
  } else {
    const list = node("div", "plain-list");
    for (const finding of status.findings.items) {
      const row = node("article", `plain-item ${finding.blocking ? "blocking" : ""}`);
      const main = node("div", "item-main");
      main.append(internalLink(`${finding.id} · ${finding.title}`, `finding/${encodeURIComponent(finding.id)}`));
      main.append(node("small", "", `${finding.gap_type || "UNKNOWN TYPE"} · ${finding.wave_id || "NO WAVE"} · ${finding.workpackage_id || "NO WORKPACKAGE"}`));
      if (finding.origin === "FRAMEWORK_FOLLOWUP") main.append(stateBadge("FRAMEWORK_FOLLOWUP"));
      if (finding.reconciliation_outcome === "REASSESS_REQUIRED") main.append(stateBadge("REASSESS_REQUIRED"));
      row.append(main, stateBadge(finding.lifecycle_status || "UNKNOWN"));
      list.append(row);
    }
    root.append(list);
  }
  const history = status.findings.history || [];
  if (history.length) {
    const details = node("details", "finding-history");
    const summary = node("summary", "", `Terminal history · ${history.length} · ${countText(status.findings.resolved)} resolved · ${countText(status.findings.superseded)} superseded · ${countText(status.findings.retired)} retired`);
    details.append(summary);
    const list = node("div", "plain-list");
    for (const finding of history) {
      const row = node("article", "plain-item");
    const main = node("div", "item-main");
      main.append(internalLink(`${finding.id} · ${finding.title || "Historical finding"}`, `finding/${encodeURIComponent(finding.id)}`));
      main.append(node("small", "", `${finding.gap_type || "UNKNOWN TYPE"} · ${finding.wave_id || "NO WAVE"} · ${finding.workpackage_id || "NO WORKPACKAGE"}`));
      if (finding.superseded_by) main.append(node("small", "", `Replaced by ${finding.superseded_by}`));
      row.append(main, stateBadge(finding.lifecycle_status || "UNKNOWN"));
      list.append(row);
    }
    details.append(list);
    root.append(details);
  }
}

function renderDecisions() {
  root.append(sectionTitle("Decisions", `${status.decisions.status_counts.PROPOSED ?? "UNKNOWN"} proposed · ${status.decisions.blocked_by_decision.count ?? "UNKNOWN"} blocking`));
  for (const decision of status.decisions.historical || []) {
    const row = node("div", "plain-item");
    row.append(node("strong", "", decision.id), stateBadge("HISTORICAL"));
    row.append(externalLink(decision.source_path, safePathUrl("/diagnostic-source", decision.source_path)));
    root.append(row);
  }
  if (!status.decisions.items.length) {
    root.append(empty(status.decisions.availability === "unavailable" ? "Decision records unavailable" : "No Decisions"));
    return;
  }
  const list = node("div", "plain-list");
  for (const decision of status.decisions.items) {
    const row = node("article", "plain-item");
    const main = node("div", "item-main");
    main.append(internalLink(`${decision.id} · ${decision.title || "Untitled"}`, `decision/${encodeURIComponent(decision.id)}`));
    main.append(node("small", "", decision.affected_requirements.join(", ") || "No explicit Requirement links"));
    row.append(main, stateBadge(decision.status || "UNKNOWN"));
    list.append(row);
  }
  root.append(list);
}

function renderReferenceList(container, types) {
  const refs = status.source_references.items.filter((item) => types.includes(item.source_type));
  container.append(node("h3", "plain-section", "Canonical evidence and source artifacts"));
  if (!refs.length) {
    container.append(empty("No available source references"));
    return;
  }
  const list = node("div", "plain-list");
  for (const reference of refs) {
    const row = node("div", "plain-item");
    const label = `${reference.source_type} · ${reference.artifact_id || reference.canonical_path.split("/").pop()}`;
    row.append(node("span", "item-main", label), sourceLink(reference.source_type, reference.artifact_id));
    list.append(row);
  }
  container.append(list);
}

function renderDetail(parts) {
  const [kind, id, packageId] = parts;
  root.append(internalLink("← Project Overview", "overview"));
  if (kind === "wave") {
    const wave = status.delivery.waves.items.find((item) => item.wave_id === id);
    if (!wave) return root.append(empty("Wave unavailable"));
    root.append(sectionTitle(`${wave.wave_id} · ${wave.phase || "UNKNOWN"}`, "Wave detail"));
    const tasks = status.delivery.tasks.items.filter((task) => task.wave_id === wave.wave_id);
    root.append(node("div", "detail-fields"),);
    const facts = root.lastChild;
    facts.append(countItem("CHECKLIST", wave.checklist_progress.total, wave.checklist_progress.availability === "available" ? `${wave.checklist_progress.done} done` : "UNKNOWN"));
    facts.append(countItem("TASKS", wave.task_progress.total, `${wave.task_progress.status_counts.done ?? "UNKNOWN"} done`));
    // No count without a source: an absent mission state is "not recorded", never 0 (BRD-F-04).
    const missionRecorded = status.mission.availability !== "unavailable" && status.mission.blocker_count !== null && status.mission.blocker_count !== undefined;
    facts.append(countItem("MISSION BLOCKERS (MISSIONSWEIT)", missionRecorded ? status.mission.blocker_count : "NICHT ERFASST", missionRecorded ? "aus mission-state.yaml" : "keine Mission-State-Quelle"));
    renderWaveTrustBlock(wave.wave_id);
    renderEntityTimeline("wave", wave.wave_id);
    root.append(node("h3", "plain-section", "Requirements"));
    for (const reqId of wave.requirement_ids) root.append(internalLink(reqId, `requirement/${encodeURIComponent(reqId)}`));
    renderTaskList(tasks);
    root.append(node("h3", "plain-section", "Findings"));
    renderFindingCards(status.findings.items.filter((finding) => finding.wave_id === wave.wave_id));
    const requirementIds = new Set(wave.requirement_ids);
    root.append(node("h3", "plain-section", "Decisions"));
    renderDecisionCards(status.decisions.items.filter((decision) => decision.affected_requirements.some((reqId) => requirementIds.has(reqId))));
    root.append(node("h3", "plain-section", "Evidence"));
    renderEvidenceEntries((status.verification.evidence.entries || []).filter((entry) => entry.wave_id === wave.wave_id));
    return;
  }
  if (kind === "workpackage") {
    const workpackage = status.delivery.workpackages.items.find((item) => item.workpackage_id === packageId && (item.wave_id || "") === (id || ""));
    if (!workpackage) return root.append(empty("Workpackage unavailable"));
    root.append(sectionTitle(`${workpackage.workpackage_id} · ${workpackage.wave_id || "NO WAVE"}`, "Workpackage detail"));
    const tasks = status.delivery.tasks.items.filter((task) => task.workpackage_id === workpackage.workpackage_id && task.wave_id === workpackage.wave_id);
    root.append(node("div", "detail-fields"),);
    const facts = root.lastChild;
    facts.append(countItem("TASKS", workpackage.task_progress.total, `${workpackage.task_progress.status_counts.done ?? "UNKNOWN"} done`));
    facts.append(countItem("BLOCKING FINDINGS", status.findings.items.filter((finding) => finding.workpackage_id === workpackage.workpackage_id && finding.blocking).length, "Explicit package link"));
    facts.append(countItem("CHECKLIST", tasks.filter((task) => task.migrated_from).length, "Canonicalized task links"));
    root.append(node("h3", "plain-section", "Requirements"));
    for (const reqId of workpackage.requirement_ids) root.append(internalLink(reqId, `requirement/${encodeURIComponent(reqId)}`));
    renderTaskList(tasks);
    root.append(node("h3", "plain-section", "Findings"));
    renderFindingCards(status.findings.items.filter((finding) => finding.workpackage_id === workpackage.workpackage_id));
    root.append(node("h3", "plain-section", "Decisions"));
    renderDecisionCards(status.decisions.items.filter((decision) => decision.affected_requirements.some((reqId) => workpackage.requirement_ids.includes(reqId))));
    root.append(node("h3", "plain-section", "Evidence"));
    renderEvidenceEntries((status.verification.evidence.entries || []).filter((entry) => workpackage.requirement_ids.some((reqId) => entry.requirement_ids.includes(reqId))));
    return;
  }
  if (kind === "requirement") {
    const requirement = status.requirements.items.find((item) => item.id === id);
    if (!requirement) return root.append(empty("Requirement unavailable"));
    root.append(sectionTitle(`${requirement.id} · ${requirement.title || "Untitled"}`, requirement.status || "UNKNOWN"));
    root.append(stateBadge(requirement.status || "UNKNOWN"));
    if (requirement.status === "superseded") {
      root.append(requirement.superseded_by
        ? internalLink(`Superseded by ${requirement.superseded_by}`, `requirement/${encodeURIComponent(requirement.superseded_by)}`)
        : stateBadge("SUCCESSOR UNKNOWN"));
    }
    root.append(sourceLink("requirement", requirement.id));
    renderAssessmentBlock(requirement);
    renderEntityTimeline("requirement", requirement.id);
    const relatedTasks = status.delivery.tasks.items.filter((task) => task.requirement_ids.includes(id));
    renderTaskList(relatedTasks);
    root.append(node("h3", "plain-section", "Verification / Proof Points"));
    const contracts = status.verification.test_contracts.items.filter((contract) => contract.requirement_ids.includes(id));
    if (contracts.length) {
      for (const contract of contracts) {
        const row = node("div", "plain-item");
        row.append(node("div", "item-main", `${contract.id} · ${contract.title || "Test Contract"} · ${contract.proof_point_ids.join(", ") || "No Proof Points"}`), stateBadge(contract.status || "UNKNOWN"), sourceLink("test_contract", contract.id));
        root.append(row);
      }
    } else root.append(empty("Test Contract mapping unavailable"));
    root.append(node("h3", "plain-section", "Evidence"));
    renderEvidenceEntries((status.verification.evidence.entries || []).filter((entry) => entry.requirement_ids.includes(id)));
    root.append(node("h3", "plain-section", "Findings"));
    renderFindingCards(status.findings.items.filter((finding) => finding.requirement_ids.includes(id)));
    root.append(node("h3", "plain-section", "Related decisions"));
    for (const decision of status.decisions.items.filter((item) => item.affected_requirements.includes(id))) {
      root.append(internalLink(`${decision.id} · ${decision.title}`, `decision/${encodeURIComponent(decision.id)}`));
    }
    return;
  }
  if (kind === "decision") {
    const decision = status.decisions.items.find((item) => item.id === id);
    if (!decision) return root.append(empty("Decision unavailable"));
    root.append(sectionTitle(`${decision.id} · ${decision.title || "Untitled"}`, decision.status || "UNKNOWN"));
    root.append(stateBadge(decision.status || "UNKNOWN"), sourceLink("decision", decision.id));
    renderDecisionFacts(decision);
    renderEntityTimeline("decision", decision.id);
    for (const reqId of decision.affected_requirements) root.append(internalLink(reqId, `requirement/${encodeURIComponent(reqId)}`));
    root.append(node("h3", "plain-section", "Related Findings"));
    renderFindingCards(status.findings.items.filter((finding) => finding.decision_ids.includes(id)));
    return;
  }
  if (kind === "finding") {
    // Terminal findings live in history; their links must resolve as well (BRD-F-03).
    const finding = status.findings.items.find((item) => item.id === id)
      || (status.findings.history || []).find((item) => item.id === id);
    if (!finding) return root.append(empty("Finding unavailable"));
    root.append(sectionTitle(`${finding.id} · ${finding.title || "Historical finding"}`, finding.lifecycle_status || "UNKNOWN"));
    root.append(stateBadge(finding.lifecycle_status || "UNKNOWN"));
    root.append(sourceLink("finding", finding.id));
    root.append(node("div", "detail-fields"));
    const facts = root.lastChild;
    facts.append(countItem("TYPE", finding.gap_type, ""), countItem("SEVERITY", finding.severity, ""), countItem("WAVE / WORKPACKAGE", `${finding.wave_id || "UNKNOWN"} / ${finding.workpackage_id || "UNKNOWN"}`, ""));
    root.append(node("h3", "plain-section", "Related Requirements / Decisions"));
    for (const reqId of finding.requirement_ids) root.append(internalLink(reqId, `requirement/${encodeURIComponent(reqId)}`));
    for (const decisionId of finding.decision_ids) root.append(internalLink(decisionId, `decision/${encodeURIComponent(decisionId)}`));
    root.append(node("h3", "plain-section", "Evidence"));
    for (const evidenceRef of finding.evidence_refs) root.append(sourceLinkPath(evidenceRef));
  }
}

function renderFindingCards(findings) {
  if (!findings.length) {
    root.append(empty("No explicitly linked Findings"));
    return;
  }
  const list = node("div", "plain-list");
  for (const finding of findings) {
    const row = node("article", `plain-item ${finding.blocking ? "blocking" : ""}`);
    row.append(internalLink(`${finding.id} · ${finding.title}`, `finding/${encodeURIComponent(finding.id)}`), stateBadge(finding.severity || "UNKNOWN"), stateBadge(finding.lifecycle_status || "UNKNOWN"));
    list.append(row);
  }
  root.append(list);
}

function renderDecisionCards(decisions) {
  if (!decisions.length) {
    root.append(empty("No explicitly linked Decisions"));
    return;
  }
  const list = node("div", "plain-list");
  for (const decision of decisions) {
    const row = node("div", "plain-item");
    row.append(internalLink(`${decision.id} · ${decision.title || "Decision"}`, `decision/${encodeURIComponent(decision.id)}`), stateBadge(decision.status || "UNKNOWN"));
    list.append(row);
  }
  root.append(list);
}

function renderEvidenceEntries(entries) {
  if (!entries.length) {
    root.append(empty("No explicitly linked Evidence"));
    return;
  }
  const list = node("div", "plain-list");
  for (const entry of entries) {
    const row = node("article", "plain-item");
    row.append(node("div", "item-main", `${entry.entry_id} · ${entry.screen_id}`), stateBadge(entry.parity_result || "UNKNOWN"), sourceLinkPath(entry.canonical_path, "Manifest ↗"));
    list.append(row);
  }
  root.append(list);
}

function renderTaskList(tasks) {
  if (!tasks.length) {
    root.append(empty("No explicitly linked tasks"));
    return;
  }
  const list = node("div", "plain-list");
  for (const task of tasks) {
    const row = node("div", "plain-item");
    row.append(node("div", "item-main", `${task.id} · ${task.action || "Task"}`), stateBadge(task.status || "UNKNOWN"));
    row.append(sourceLink("task", task.id));
    list.append(row);
  }
  root.append(list);
}

function renderView() {
  const parts = routeParts();
  const view = parts[0] || "overview";
  const redirects = { gallery: "pages?view=parity", "ui-pages": "pages" };
  if (redirects[view]) { location.replace(`#${redirects[view]}`); return; }
  if (view === "page" && parts[1]) { location.replace(`#pages/${encodeURIComponent(parts[1])}`); return; }
  clear(root);
  const isPortfolio = view === "portfolio";
  // The project context block belongs to Overview and Health only (v2 snapshots keep it everywhere but Portfolio).
  $("#project-context").hidden = isPortfolio || (Boolean(status.health) && !["overview", "health"].includes(view));
  if (!status.health && view === "timeline") root.append(empty("Die Timeline benötigt eine Status-Projektion ab Schema v3."));
  if (!status.health) renderCompatibility();
  $("#tabs").hidden = isPortfolio;
  for (const button of document.querySelectorAll("[data-route]")) {
    const buttonRoute = button.dataset.route;
    button.classList.toggle("active", buttonRoute === view || (view === "requirement" && buttonRoute === "requirements") || (["wave", "workpackage"].includes(view) && buttonRoute === "waves") || (view === "finding" && buttonRoute === "findings") || (["page", "gallery", "ui-pages"].includes(view) && buttonRoute === "pages") || (view === "decision" && buttonRoute === "decisions"));
  }
  if (isPortfolio) renderPortfolio();
  else if (view === "overview") renderOverview();
  else if (view === "health") renderHealthView();
  else if (view === "timeline") renderTimeline();
  else if (view === "activity") renderRunActivity();
  else if (view === "waves") renderWaves();
  else if (view === "requirements") renderRequirements();
  else if (view === "verification") renderVerification();
  else if (view === "pages") { if (parts[1]) renderPageHub(parts[1]); else renderPages(); }
  else if (view === "tasks") renderTasks();
  else if (view === "legacy") {
    if (parts[1] === "gallery") renderGallery();
    else if (parts[1] === "ui-pages") renderUiPages();
    else if (parts[1] === "page" && parts[2]) renderGallery(parts[2]);
    else root.append(empty("Unbekannte Legacy-Route"));
  }
  else if (view === "findings") renderFindings();
  else if (view === "decisions") renderDecisions();
  else renderDetail(parts);
  updateHealthChip();
}

function renderCompatibility() {
  const report = status.compatibility;
  if (!report) return;
  const panel = node("details", "plain-section compatibility-diagnostics");
  const actionable = report.diagnostics.filter((item) => item.category !== "FRESHNESS_UNKNOWN");
  const summary = node("summary", "view-title");
  summary.append(node("strong", "", "Project compatibility"), stateBadge(report.compatibility));
  const blocking = report.diagnostics.filter((item) => item.blocking).length;
  const inspectMigrationCount = new Set(report.diagnostics
    .filter((item) => item.proposed_repair_type === "TASK_INSPECT_TYPED_TARGET_V1")
    .map((item) => item.source_path)).size;
  const inspectMigrationSummary = inspectMigrationCount
    ? `${inspectMigrationCount} tasks require task-inspect compatibility migration · ` : "";
  summary.append(node("small", "", `${inspectMigrationSummary}${blocking} blocking · ${actionable.length} diagnostics`));
  panel.append(summary);
  panel.open = false;
  for (const [type, counts] of Object.entries(report.coverage)) {
    panel.append(node("p", "muted", `${type}: ${counts.recognized} recognized · ${counts.invalid} invalid · ${counts.unassigned} unassigned`));
  }
  const list = node("div", "plain-list");
  const states = {
    SYNTAX_ERROR: "INVALID", SCHEMA_ERROR: "INVALID", ID_MISMATCH: "INVALID", DUPLICATE_ID: "AMBIGUOUS",
    REFERENCE_MISSING: "MISSING", REFERENCE_AMBIGUOUS: "AMBIGUOUS", AUTHORITY_CONFLICT: "AMBIGUOUS",
    WAVE_ASSIGNMENT_MISSING: "UNASSIGNED", UNSUPPORTED_VARIANT: "UNSUPPORTED", LEGACY_VARIANT: "LEGACY",
    FRESHNESS_UNKNOWN: "UNKNOWN", MISSING: "MISSING", UNASSIGNED: "UNASSIGNED", STALE: "STALE",
  };
  for (const item of report.diagnostics) {
    const row = node("div", "plain-item diagnostic-item");
    const description = node("div", "item-main");
    description.append(node("strong", "", item.affected_board_area), node("p", "", item.message));
    description.append(node("small", "muted", `${item.category} · ${item.repairability}`));
    if (item.source_path) {
      const location = `${item.source_path}${item.line ? `:${item.line}:${item.column}` : ""}`;
      description.append(externalLink(location, safePathUrl("/diagnostic-source", item.source_path)));
    }
    row.append(description, stateBadge(states[item.category] || "UNKNOWN"));
    list.append(row);
  }
  panel.append(list);
  root.append(panel);
}

function ago(epochSeconds) {
  if (typeof epochSeconds !== "number") return null;
  const seconds = Math.max(0, Date.now() / 1000 - epochSeconds);
  if (seconds < 3600) return `vor ${Math.max(1, Math.round(seconds / 60))} min`;
  if (seconds < 172800) return `vor ${Math.round(seconds / 3600)} h`;
  return `vor ${Math.round(seconds / 86400)} Tagen`;
}

const WORK_STATE_TEXT = {
  ACTIVE: "ACTIVE", BLOCKED: "BLOCKED", NOT_STARTED: "NOT STARTED", NONE: "KEINE AKTIVE ARBEIT", CONFLICT: "CONFLICT",
};
const ASSESSMENT_TEXT = {
  NOT_STARTED: "NOT STARTED", IN_PROGRESS: "IN PROGRESS", IMPLEMENTED: "IMPLEMENTED", VERIFIED: "VERIFIED", BLOCKED: "BLOCKED",
};
const LEVEL_TEXT = { implementation: "Implementation", verification: "Verification", freshness: "Freshness", blocker: "Blocker" };
const LEVEL_STATE_TEXT = { MET: "MET", PARTIAL: "PARTIAL", NOT_MET: "NOT MET", NOT_OBSERVABLE: "NOT OBSERVABLE" };

function derivedBadge() {
  const badge = node("span", "derived-badge", "ABGELEITET");
  badge.title = "Berechnet aus kanonischen Artefakten. Wird nie gespeichert oder zurückgeschrieben.";
  return badge;
}

function workHeadline(work) {
  if (work.state === "ACTIVE" || work.state === "BLOCKED") {
    const where = work.wave ? `Wave ${work.wave.wave_id} · Phase ${work.wave.phase || "?"}` : "Mission ohne benannte aktive Wave";
    return `${work.state === "BLOCKED" ? "Blockiert: " : "Aktiv: "}${where}`;
  }
  if (work.state === "NOT_STARTED") return `Nächste registrierte Wave: ${work.wave.wave_id} (Phase ${work.wave.phase}) – noch nicht begonnen`;
  if (work.state === "CONFLICT") {
    return work.reason === "MULTIPLE_ACTIVE_WAVES" ? "Widerspruch: mehrere Waves sind gleichzeitig aktiv"
      : work.reason === "ACTIVE_WAVE_IS_DONE" ? "Widerspruch: die Mission nennt eine bereits abgeschlossene Wave als aktiv"
      : "Widerspruch: die Mission nennt eine nicht registrierte Wave als aktiv";
  }
  return work.waves_registered ? "Keine aktive kanonische Arbeit" : "Keine aktive kanonische Arbeit – es sind keine Waves registriert";
}

function outsideLifecycleNote(work) {
  if (work.state !== "NONE") return null;
  const activity = work.unattributed_activity;
  if (activity.observation_state !== "AVAILABLE") return { tone: "muted", text: "Git-Aktivität nach dem letzten DONE-Übergang ist nicht beobachtbar (kein Git-Verlauf oder kein DONE-Übergang im Beobachtungsfenster)." };
  if (activity.observed) return {
    tone: "warn",
    text: `Arbeit außerhalb des kanonischen Lifecycles beobachtet: ${activity.commit_count} Commit(s) auf Projekt-/Modellpfaden seit dem letzten DONE-Übergang (${activity.since_commit}). Sie sind keiner Wave, Task oder Mission zugeordnet.`,
  };
  return { tone: "muted", text: `Seit dem letzten DONE-Übergang (${activity.since_commit}) wurden keine Commits auf Projekt-/Modellpfaden beobachtet.` };
}

function workRow(label, content) {
  const row = node("div", "cw-row");
  row.append(node("span", "cw-label", label));
  const value = node("div", "cw-value");
  if (content instanceof Node) value.append(content);
  else value.textContent = content;
  row.append(value);
  return row;
}

function assessmentSummary(requirementIds) {
  const labels = {};
  for (const id of requirementIds) {
    const item = status.requirements.items.find((entry) => entry.id === id);
    const label = item && item.delivery_assessment ? item.delivery_assessment.label : null;
    if (label) labels[label] = (labels[label] || 0) + 1;
  }
  return Object.entries(labels).map(([label, count]) => `${count} ${ASSESSMENT_TEXT[label] || label}`).join(" · ");
}

function renderCurrentWork() {
  const container = $("#current-work");
  if (!container) return;
  clear(container);
  const work = status.current_work;
  container.hidden = !work;
  if (!work) return;
  container.className = `current-work ${work.state.toLowerCase()}`;
  const head = node("div", "cw-head");
  head.append(node("span", "eyebrow", "CURRENT WORK"), stateBadge(WORK_STATE_TEXT[work.state] || work.state), derivedBadge());
  container.append(head, node("h2", "cw-headline", workHeadline(work)));
  const note = outsideLifecycleNote(work);
  if (note) container.append(node("p", `cw-note ${note.tone}`, note.text));

  const rows = node("div", "cw-rows");
  if (work.mission) {
    const mission = node("span", "", `${work.mission.id || "Mission"} · ${work.mission.status || ""}${work.mission.objective ? ` – ${work.mission.objective}` : ""}`);
    rows.append(workRow("Mission", mission));
  } else {
    rows.append(workRow("Mission", `nicht erfasst (${obsLabel(status.mission, "keine Mission")})`));
  }
  if (work.wave) {
    const link = internalLink(`${work.wave.wave_id} · ${work.wave.phase || "?"}`, `wave/${encodeURIComponent(work.wave.wave_id)}`);
    rows.append(workRow("Wave / Phase", link));
  }
  if (work.requirement_ids.length) {
    const wrapper = node("span", "");
    work.requirement_ids.slice(0, 6).forEach((id, index) => {
      if (index) wrapper.append(document.createTextNode(", "));
      wrapper.append(internalLink(id, `requirement/${encodeURIComponent(id)}`));
    });
    if (work.requirement_ids.length > 6) wrapper.append(document.createTextNode(` … (+${work.requirement_ids.length - 6})`));
    rows.append(workRow("Requirements", wrapper));
    const summary = assessmentSummary(work.requirement_ids);
    if (summary) rows.append(workRow("Verification-Stand", `${summary} (abgeleitet)`));
  }
  if (work.tasks_in_progress.length) rows.append(workRow("Tasks in Arbeit", work.tasks_in_progress.join(", ")));
  if (work.blockers.length) {
    const first = work.blockers[0];
    rows.append(workRow("Blocker", `${work.blockers.length} · ${first.type || "OTHER"}${first.description ? ` – ${first.description}` : ""}`));
  }
  if (work.last_completed && work.last_completed.wave_ids.length) {
    const wrapper = node("span", "");
    work.last_completed.wave_ids.forEach((id, index) => {
      if (index) wrapper.append(document.createTextNode(", "));
      wrapper.append(internalLink(id, `wave/${encodeURIComponent(id)}`));
    });
    const stamp = ago(work.last_completed.committed_at);
    const summary = assessmentSummary(work.last_completed.requirement_ids);
    wrapper.append(document.createTextNode(` (done${stamp ? `, ${stamp}` : ""}) · ${work.last_completed.tasks_done}/${work.last_completed.task_count} Tasks done${summary ? ` · Requirements: ${summary} (abgeleitet)` : ""}`));
    rows.append(workRow("Zuletzt abgeschlossen", wrapper));
  }
  if (work.latest_activity) {
    const stamp = ago(work.latest_activity.committed_at);
    rows.append(workRow("Letzte Git-Aktivität", `${work.latest_activity.commit}${stamp ? ` · ${stamp}` : ""} · ${work.latest_activity.subject} (nicht zugeordnet)`));
  }
  if (work.design_authority.length) {
    rows.append(workRow("Design Authority", `${work.design_authority.length} aktive Referenz(en), projektweit – keiner Wave zugeordnet`));
  }
  const step = work.next_step || {};
  if (work.next_action) {
    rows.append(workRow("Nächster Schritt", `${work.next_action.description}${work.next_action.safe_to_run === false ? " (nicht automatisch ausführbar)" : ""}`));
  } else if (step.kind === "LIFECYCLE_TRANSITION") {
    rows.append(workRow("Nächster Lifecycle-Schritt", `${step.from_phase} → ${step.to_phase}${step.requires ? ` · erfordert ${step.requires}` : ""}`));
  } else if (step.kind === "REGISTER_WAVE") {
    rows.append(workRow("Nächster Schritt", "Neue oder nachträgliche Arbeit braucht eine neu registrierte Wave (bei Autorisierung in process-state.yaml eintragen)"));
  }
  container.append(rows);
}

function trustCounts() {
  const trust = status.waves_trust || [];
  const done = trust.filter((item) => item.historical_state === "DONE");
  const count = (predicate) => done.filter(predicate).length;
  return {
    total: trust.length, done: done.length,
    recorded: count((item) => item.done_basis.state === "RECORDED"),
    legacy: count((item) => item.done_basis.state === "LEGACY"),
    missing: count((item) => item.done_basis.state === "NOT_RECORDED"),
    superseded: done.reduce((sum, item) => sum + item.open_tasks_superseded.length, 0),
    unexplained: done.reduce((sum, item) => sum + item.open_tasks_unexplained.length, 0),
    evidenced: count((item) => item.present_confidence.level === "EVIDENCED"),
    notEvidenced: count((item) => item.present_confidence.level === "NOT_EVIDENCED"),
  };
}

function trustWaveRows(items) {
  const list = node("div", "plain-list");
  for (const item of items) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(internalLink(item.wave_id, `wave/${encodeURIComponent(item.wave_id)}`));
    const parts = [`DONE-Grundlage: ${item.done_basis.state === "NOT_RECORDED" ? "nicht erfasst" : item.done_basis.state === "LEGACY" ? "Legacy" : "erfasst"}`];
    if (item.open_tasks_superseded.length) parts.push(`${item.open_tasks_superseded.length} offene Tasks durch Acceptance überholt`);
    if (item.open_tasks_unexplained.length) parts.push(`${item.open_tasks_unexplained.length} offene Tasks ohne Grundlage`);
    if (item.later_findings.length) parts.push(`${item.later_findings.length} Findings gegen diese Wave`);
    const after = item.changes_after_done;
    if (after && after.observation_state === "AVAILABLE") {
      parts.push(`nach DONE: ${after.commit_count} Commit(s) an verknüpften Artefakten · ${after.project_activity_commits} Projekt-Commits (nicht zugeordnet)`);
    } else if (after && after.observation_state === "NOT_RECORDED") {
      parts.push("DONE-Zeitpunkt nicht im Git-Verlauf");
    }
    main.append(node("small", "", parts.join(" · ")));
    const confidence = item.present_confidence.level === "EVIDENCED" ? "EVIDENCED" : item.present_confidence.level === "NOT_EVIDENCED" ? "NOT EVIDENCED" : "NOT OBSERVABLE";
    row.append(main, stateBadge(item.historical_state), stateBadge(confidence.replaceAll(" ", "_")));
    list.append(row);
  }
  return list;
}

function renderTrustInDone(container) {
  if (!status.waves_trust || !status.waves_trust.length) return;
  const counts = trustCounts();
  const section = node("section", "plain-section trust-card");
  const title = node("div", "cw-head");
  title.append(node("h3", "", "Vertrauen in DONE"), derivedBadge());
  section.append(title);
  section.append(node("p", "", `${counts.done} von ${counts.total} Waves sind abgeschlossen (done). DONE bleibt historisch gültig – es sagt nur, dass das Acceptance-Gate damals für den Scope der Wave bestanden wurde.`));
  const facts = node("div", "plain-list");
  for (const [label, value] of [
    ["DONE-Grundlage erfasst", counts.recorded],
    ["Legacy-DONE (ohne Gate-Protokoll)", counts.legacy],
    ["Historische DONE-Grundlage nicht erfasst", `${counts.missing} (Hinweis, keine aktive Blockade)`],
    ["Offene Tasks durch Acceptance überholt", counts.superseded],
    ["Offene Tasks ohne Grundlage", counts.unexplained],
    ["Waves mit belegter Verifikations-Evidenz", counts.evidenced],
    ["Waves ohne belegte Evidenz", counts.notEvidenced],
  ]) {
    const row = node("div", "plain-item");
    row.append(node("div", "item-main", label), node("span", "count-pair", String(value)));
    facts.append(row);
  }
  section.append(facts);
  section.append(node("p", "muted", "Aktualität der Evidenz gegenüber dem aktuellen Modell ist nicht beobachtbar (Details unter Health & Diagnostics)."));
  const details = node("details", "trust-waves");
  details.append(node("summary", "", `Pro Wave (${counts.total})`), trustWaveRows(status.waves_trust));
  section.append(details);
  container.append(section);
}

function renderAssessmentBlock(requirement) {
  const assessment = requirement.delivery_assessment;
  if (!assessment) return;
  const section = node("section", "plain-section assessment");
  const head = node("div", "cw-head");
  head.append(node("h3", "", "Delivery assessment"), stateBadge(assessment.label), derivedBadge(), node("small", "muted", assessment.rule_version));
  section.append(head);
  const met = assessment.levels.filter((level) => level.state === "MET").map((level) => LEVEL_TEXT[level.level]);
  const open = assessment.levels.filter((level) => level.state !== "MET").map((level) => LEVEL_TEXT[level.level]);
  section.append(node("p", "", `Warum gilt das als erreicht? ${met.length ? met.join(", ") + " erfüllt." : "Noch keine Stufe erfüllt."}`));
  section.append(node("p", "", `Warum ist Abschluss nicht belegt? ${open.length ? open.join(", ") + " nicht (vollständig) belegt." : "Alle Stufen sind belegt."}`));
  const list = node("div", "plain-list");
  for (const level of assessment.levels) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(node("strong", "", LEVEL_TEXT[level.level]));
    for (const reason of level.reasons) main.append(node("p", "muted", reason.text));
    if (level.evidence_refs.length) {
      const refs = node("small", "");
      level.evidence_refs.forEach((ref, index) => {
        if (index) refs.append(document.createTextNode(", "));
        if (ref.type === "decision") refs.append(internalLink(ref.id, `decision/${encodeURIComponent(ref.id)}`));
        else if (ref.type === "finding") refs.append(internalLink(ref.id, `finding/${encodeURIComponent(ref.id)}`));
        else refs.append(document.createTextNode(ref.id));
      });
      main.append(refs);
    }
    row.append(main, stateBadge((LEVEL_STATE_TEXT[level.state] || level.state).replaceAll(" ", "_")));
    list.append(row);
  }
  section.append(list);
  root.append(section);
}

function renderWaveTrustBlock(waveId) {
  const item = (status.waves_trust || []).find((entry) => entry.wave_id === waveId);
  if (!item) return;
  root.append(node("h3", "plain-section", "Vertrauen in DONE"));
  root.append(trustWaveRows([item]));
  const reasons = node("div", "plain-list");
  for (const reason of item.present_confidence.reasons) reasons.append(node("p", "muted", reason));
  root.append(reasons);
}

function renderRevisionLedger(container) {
  const ledger = status.project && status.project.revision_ledger;
  if (!ledger || ledger.observation_state === "NOT_RECORDED" || !ledger.items.length) return;
  const section = node("section", "plain-section");
  const head = node("div", "cw-head");
  head.append(node("h3", "", "Revision ledger"), node("small", "muted", "Design-Authority-Quelle · planning/revisions"));
  section.append(head);
  const list = node("div", "plain-list");
  for (const item of ledger.items) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(node("strong", "", item.revision_id));
    main.append(node("small", "muted", `${item.artifact_path || "kein Artefakt"} · ${item.screens.length} Screen(s)${item.acceptance_decisions.length ? ` · ${item.acceptance_decisions.join(", ")}` : ""}`));
    row.append(main, stateBadge(item.active_target ? "ACTIVE_TARGET" : (item.status || "NOT_ACTIVE")));
    list.append(row);
  }
  section.append(list);
  container.append(section);
}

function renderParityReports() {
  const reports = status.verification && status.verification.parity_reports;
  if (!reports || !reports.length) return;
  const labels = { COMPUTED: "COMPUTED", REPORTED_UNBOUND: "BERICHTET, NICHT BELEGT", STALE: "STALE", NOT_VERIFIED: "NOT VERIFIED" };
  root.append(sectionTitle("Parity reports", `${reports.length} Report(s) · ein berichtetes Ergebnis ohne gebundene Evidenz zählt nicht als Verifikation`));
  const list = node("div", "plain-list");
  for (const report of reports) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(node("strong", "", `${report.page_id || "—"} · ${report.scenario_id || report.report_path}`));
    main.append(node("small", "muted", `berichtet: ${report.reported_result || "—"} · berechnet: ${report.computed_result || "—"} · ${report.verified_at || "ohne Datum"}`));
    row.append(main, stateBadge(labels[report.state] || report.state), sourceLinkPath(report.report_path, "Report ↗"));
    list.append(row);
  }
  root.append(list);
}

function renderDecisionFacts(decision) {
  const facts = node("div", "detail-fields");
  facts.append(countItem("ERSTELLT", decision.created_at || "NICHT ERFASST", ""), countItem("BESTÄTIGT", decision.confirmed_at || (decision.status === "CONFIRMED" ? "NICHT ERFASST" : "noch nicht"), ""));
  root.append(facts);
  if (decision.rationale_excerpt) root.append(node("p", "", decision.rationale_excerpt));
  const lists = [["Screens", decision.affected_screens], ["Mockup-Revisionen", decision.affected_mockup_revisions]];
  for (const [label, values] of lists) if (values && values.length) root.append(node("p", "muted", `${label}: ${values.join(", ")}`));
}

// ---------------------------------------------------------------------------------------------- Timeline (CS-5)
function hashQuery() {
  const raw = location.hash.slice(1);
  const index = raw.indexOf("?");
  return new URLSearchParams(index >= 0 ? raw.slice(index + 1) : "");
}

const AUTHORITY_TEXT = {
  CANONICAL_RECORD: ["kanonisch", "Aus einem kanonischen Eintrag mit eigenem Zeitstempel."],
  GIT_DERIVED: ["aus Git belegt", "Aus einer Änderung an einem Projektartefakt im Git-Verlauf abgeleitet."],
  COMMIT_TRAILER: ["Change-Set-Beleg", "Durch Commit-Trailer und ein schema-gültiges Change-Set belegt."],
  GIT_MENTION: ["nur erwähnt", "Nur in der Commit-Nachricht erwähnt. Keine belegte Beziehung."],
};
const GROUP_LABELS = {
  "": "Alles", wave: "Waves & Mission", requirement: "Requirements", decision: "Decisions", finding: "Findings",
  verification: "Verification & Evidenz", authority: "Design Authority", page: "Pages", task: "Tasks",
  provenance: "Herkunft & Framework", code: "Modell, Code & Dokumente",
};
const ENTITY_LABELS = {
  wave: "Wave", requirement: "Requirement", decision: "Decision", finding: "Finding", page: "Page", task: "Task", revision: "Revision",
  change_set: "Change-Set", mission: "Mission", parity_report: "Parity-Report", test_contract: "Test Contract", evidence_manifest: "Evidenz",
  framework: "Framework", context_epoch: "Epoche", delegation: "Delegation",
};
const DIRECT_ROUTES = { wave: "wave", requirement: "requirement", decision: "decision", finding: "finding", page: "pages" };

const HEALTH_TEXT = {
  CHANGE_SET_SCHEMA_INVALID: ["Change-Set ungültig", "Das Change-Set verletzt sein Schema und hat deshalb keine Zuordnungswirkung."],
  COMMIT_TRAILER_UNVERIFIED: ["Trailer nicht verifiziert", "Die MxAgile-Trailer des Commits konnten nicht gegen ein gültiges Change-Set verifiziert werden. Keine Zuordnung."],
  COMMIT_TRAILER_UNVERIFIABLE: ["Trailer nicht prüfbar", "Die Trailer des Commits konnten nicht geprüft werden. Keine Zuordnung."],
};

function healthBadge(code) {
  const info = HEALTH_TEXT[code] || [code.replaceAll("_", " ").toLowerCase(), ""];
  const badge = node("span", "lane-badge", info[0]);
  badge.title = info[1];
  return badge;
}

function authorityBadge(event) {
  const info = AUTHORITY_TEXT[event.authority_class] || [event.authority_class, ""];
  const badge = node("span", `authority-badge ${event.authority_class === "GIT_MENTION" ? "weak" : event.authority_class === "GIT_DERIVED" ? "quiet" : ""}`, info[0]);
  badge.title = info[1];
  return badge;
}

function entityChip(entity) {
  const weak = entity.derivation === "message_mention";
  const label = `${weak ? "erwähnt: " : ""}${entity.id}`;
  const route = DIRECT_ROUTES[entity.type] && !weak ? `${DIRECT_ROUTES[entity.type]}/${encodeURIComponent(entity.id)}`
    : `timeline?entity=${encodeURIComponent(`${entity.type}:${entity.id}`)}${weak ? "&include_mentions=1" : ""}`;
  const chip = internalLink(label, route);
  chip.className = `entity-chip ${weak ? "weak" : ""}`;
  chip.title = `${ENTITY_LABELS[entity.type] || entity.type} · ${weak ? "nur in der Commit-Nachricht erwähnt" : entity.derivation.replaceAll("_", " ")}`;
  return chip;
}

function groupMoments(events) {
  const moments = [];
  const byKey = new Map();
  for (const event of events) {
    const key = event.commit ? event.commit.hash : event.event_id;
    let moment = byKey.get(key);
    if (!moment) {
      moment = { key, events: [], iso: event.occurred_at, epoch: event.occurred_epoch, commit: event.commit };
      byKey.set(key, moment);
      moments.push(moment);
    }
    moment.events.push(event);
  }
  // Headline = most significant event; at equal significance an event with evidence-backed entities beats a generic one.
  const evidenced = (event) => (event.entities.some((entity) => entity.derivation !== "message_mention") ? 1 : 0);
  for (const moment of moments) {
    moment.events = moment.events
      .map((event, order) => ({ event, order }))
      .sort((a, b) => (b.event.significance - a.event.significance) || (evidenced(b.event) - evidenced(a.event)) || (a.order - b.order))
      .map((item) => item.event);
  }
  return moments;
}

function timeOf(iso) {
  const match = /T(\d{2}:\d{2})/.exec(iso);
  return match ? match[1] : "";
}

function dayLabel(iso) {
  const [year, month, day] = iso.slice(0, 10).split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("de-DE", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}

function momentSummary(moment) {
  const counts = {};
  for (const event of moment.events.slice(1)) {
    const group = event.type.split(".")[0];
    const label = { task: "Tasks", requirement: "Requirements", decision: "Decisions", finding: "Findings", wave: "Wave-Änderungen", parity: "Parity", evidence: "Evidenz",
      page: "Pages", model: "Modell", project: "Projektdateien", document: "Dokumente", reference: "Referenz", authority: "Authority", verification: "Verification",
      framework: "Framework", commit: "Commit", changeset: "Change-Set", mission: "Mission", epoch: "Epoche", delegation: "Delegation" }[group] || group;
    counts[label] = (counts[label] || 0) + 1;
  }
  return Object.entries(counts).map(([label, count]) => `${count} ${label}`).join(" · ");
}


const MILESTONE_PREFIXES = ["wave.registered", "wave.phase_changed", "mission.", "decision.", "authority.", "finding.", "framework.updated"];
const EYEBROWS = [
  ["wave.", "WAVE"], ["mission.", "MISSION"], ["decision.", "DECISION"], ["authority.", "DESIGN AUTHORITY"], ["finding.", "FINDING"],
  ["requirement.", "REQUIREMENT"], ["task.", "TASK"], ["page.", "PAGE"], ["parity.", "VERIFIKATION"], ["evidence.", "VERIFIKATION"],
  ["verification.", "VERIFIKATION"], ["framework.", "FRAMEWORK"], ["changeset.", "CHANGE-SET"], ["delegation.", "DELEGATION"],
];

// Presentation tier only; it never changes events, evidence classes or assignments.
function tierOf(moment) {
  const head = moment.events[0];
  const evidenced = head.entities.some((entity) => entity.derivation !== "message_mention");
  if (evidenced && MILESTONE_PREFIXES.some((prefix) => head.type.startsWith(prefix))) return "milestone";
  if (evidenced && head.significance >= 2) return "standard";
  return "routine";
}

function eyebrowOf(type) {
  const found = EYEBROWS.find(([prefix]) => type.startsWith(prefix));
  return found ? found[1] : null;
}

function withTip(element, text) {
  element.classList.add("has-tip");
  element.dataset.tip = text;
  element.tabIndex = 0;
  return element;
}

function othersTip(moment) {
  const lines = moment.events.slice(1).map((event) => `• ${event.title}${event.lane === "unattributed" ? " (nicht zugeordnet)" : ""}`);
  return `Im selben Commit, aber nicht diesem Ereignis zugeordnet:\n${lines.slice(0, 12).join("\n")}${lines.length > 12 ? `\n… +${lines.length - 12} weitere` : ""}`;
}

function commitTip(moment) {
  if (!moment.commit) return moment.iso;
  return `Commit ${moment.commit.short}\n${moment.commit.author}\n${moment.iso}`;
}

function momentDetails(moment, unattributed) {
  const details = node("details", "moment-details");
  details.append(node("summary", "", "Details & Beleg"));
  details.append(node("p", "muted moment-note", "Alle Änderungen dieses Commits. Eine Zuordnung gilt nur dort, wo das Ereignis selbst Entitäten mit Beleg nennt."));
  const list = node("div", "moment-events");
  for (const event of moment.events) {
    const row = node("div", "moment-event");
    const text = node("div", "item-main");
    text.append(node("div", "", event.title));
    if (event.detail) text.append(node("small", "muted", event.detail));
    const trail = node("div", "moment-entities");
    for (const entity of event.entities.slice(0, 10)) trail.append(entityChip(entity));
    if (event.entities.length) text.append(trail);
    if (event.source && event.source.path) text.append(node("small", "muted mono", `${event.source.path}${event.source.field ? ` · ${event.source.field}` : ""}${event.source.before || event.source.after ? ` · ${event.source.before ?? "—"} → ${event.source.after ?? "—"}` : ""}`));
    const badge = authorityBadge(event);
    badge.classList.remove("quiet");
    row.append(text, badge);
    list.append(row);
  }
  details.append(list);
  const provenance = [];
  if (moment.commit) provenance.push(`Commit ${moment.commit.short} · ${moment.commit.author} · „${moment.commit.subject}"`);
  const changeSet = moment.events.find((event) => event.change_set_id);
  if (changeSet) provenance.push(`Change-Set ${changeSet.change_set_id}${changeSet.mission_label ? ` · Mission-Label: ${changeSet.mission_label}` : ""}`);
  if (unattributed) provenance.push("Zuordnung: keine – Zeitnähe, Dateinamen oder Commit-Text begründen keine Beziehung.");
  if (provenance.length) details.append(node("p", "muted mono provenance", provenance.join("  |  ")));
  return details;
}

function momentCard(moment, { compact = false } = {}) {
  const tier = tierOf(moment);
  const head = moment.events[0];
  const unattributed = moment.events.every((event) => event.lane === "unattributed");
  const card = node("article", `moment tier-${tier} ${unattributed ? "unattributed" : ""}`);
  card.append(withTip(node("div", "moment-time", timeOf(moment.iso) || "—"), commitTip(moment)));
  const body = node("div", "moment-body");
  const commitText = moment.commit ? moment.commit.subject : null;
  const rest = moment.events.length - 1;
  if (tier === "routine") {
    // Quiet one-liner: the human-written commit text, honest label, everything else on hover or in the details.
    const line = node("div", "moment-line");
    line.append(node("span", "moment-title", unattributed && commitText ? commitText : head.title));
    if (unattributed) line.append(withTip(node("span", "unassigned-tag", "nicht zugeordnet"), `${moment.events.map((event) => event.title).join("\n")}\n\nKeiner Wave, Task oder Page zugeordnet.`));
    for (const code of head.health) line.append(healthBadge(code));
    body.append(line);
  } else {
    const eyebrow = eyebrowOf(head.type);
    if (eyebrow) body.append(node("div", "moment-eyebrow", eyebrow));
    body.append(node("div", "moment-title", head.title));
    if (rest > 0) body.append(withTip(node("div", "moment-sub", `+${rest} weitere im selben Commit`), othersTip(moment)));
    const strong = head.entities.filter((entity) => entity.derivation !== "message_mention");
    const limit = compact ? 3 : 5;
    const chips = node("div", "moment-entities");
    strong.slice(0, limit).forEach((entity) => chips.append(entityChip(entity)));
    if (strong.length > limit) chips.append(withTip(node("span", "entity-more", `+${strong.length - limit}`), strong.slice(limit).map((entity) => `${entity.type}: ${entity.id}`).join("\n")));
    const flags = node("span", "moment-flags");
    flags.append(authorityBadge(head));
    for (const code of head.health) flags.append(healthBadge(code));
    chips.append(flags);
    body.append(chips);
  }
  if (!compact) body.append(momentDetails(moment, unattributed));
  card.append(body);
  return card;
}

function routineGroupSummary(run) {
  const unattributed = run.filter((moment) => moment.events.every((event) => event.lane === "unattributed")).length;
  const label = `${run.length} weitere Aktivitäten${unattributed ? ` (${unattributed} ohne Zuordnung)` : ""}`;
  const previews = run.slice(0, 2).map((moment) => `„${(moment.commit ? moment.commit.subject : moment.events[0].title).slice(0, 48)}"`).join(", ");
  return `${label} · ${timeOf(run[run.length - 1].iso)}–${timeOf(run[0].iso)} · ${previews}${run.length > 2 ? ` · +${run.length - 2}` : ""}`;
}


function renderMomentStream(container, moments, options = {}) {
  let currentDay = null;
  let section = null;
  const target = () => (options.compact ? container : section);
  let run = [];
  const flush = () => {
    if (!run.length) return;
    if (run.length === 1 || options.compact) {
      run.forEach((moment) => target().append(momentCard(moment, options)));
    } else {
      // Consecutive routine moments collapse into one honest summary row; nothing is hidden, the count and previews stay visible.
      const group = node("details", "routine-group");
      group.append(node("summary", "", routineGroupSummary(run)));
      run.forEach((moment) => group.append(momentCard(moment, options)));
      target().append(group);
    }
    run = [];
  };
  for (const moment of moments) {
    const day = moment.iso.slice(0, 10);
    if (!options.compact && day !== currentDay) {
      flush();
      currentDay = day;
      section = node("section", "day-group");
      section.append(node("h3", "day-heading", dayLabel(moment.iso)));
      container.append(section);
    }
    if (tierOf(moment) === "routine") {
      run.push(moment);
    } else {
      flush();
      target().append(momentCard(moment, options));
    }
  }
  flush();
}
async function fetchTimeline(params) {
  const query = new URLSearchParams(params);
  const response = await fetch(`/api/timeline?${query.toString()}`, { cache: "no-store" });
  if (!response.ok) throw new Error("timeline unavailable");
  return response.json();
}

async function fetchRunActivity(params = {}) {
  const query = new URLSearchParams(params);
  const response = await fetch(`/api/run-activity${query.toString() ? `?${query}` : ""}`, { cache: "no-store" });
  if (!response.ok) throw new Error("run activity unavailable");
  return response.json();
}

let runActivityToken = 0;
async function renderRunActivity() {
  const params = hashQuery();
  const category = params.get("category") || "all";
  root.append(sectionTitle("Run Activity", "Validierte operative Events · Kanonischer Projektstatus bleibt artefaktbasiert"));
  const filter = node("label", "filter run-activity-filter");
  filter.append(node("span", "", "Bereich"));
  const select = document.createElement("select");
  for (const [value, label] of [["all", "Alle"], ["delivery", "Delivery"], ["children", "Child Agents"],
    ["verification", "Verification"], ["gates", "Gates"], ["recovery", "Recovery"], ["updates", "Updates / Migration"], ["warnings", "Warnings / Blocks"]]) {
    const option = document.createElement("option"); option.value = value; option.textContent = label; option.selected = value === category; select.append(option);
  }
  select.addEventListener("change", () => { location.hash = `activity?category=${encodeURIComponent(select.value)}`; });
  filter.append(select); root.append(filter);
  const activeSection = node("section", "run-active-section");
  activeSection.append(node("h3", "", "Open / Unresolved Runs"));
  activeSection.append(node("p", "muted", "Ein Start ohne Abschluss ist RESULT UNKNOWN; aus Events allein ist keine Prozess-Liveness ableitbar."));
  const activeList = node("div", "run-active-list"); activeSection.append(activeList); root.append(activeSection);
  const timeline = node("div", "run-event-stream"); root.append(timeline);
  const footer = node("div", "timeline-footer"); root.append(footer);
  const token = ++runActivityToken;
  footer.textContent = "lädt …";
  try {
    const result = await fetchRunActivity({ category, limit: "500" });
    if (token !== runActivityToken || routeParts()[0] !== "activity") return;
    clear(activeList);
    if (!result.active_runs.length) activeList.append(empty("Keine laufenden oder verwaisten Runs."));
    for (const run of result.active_runs) {
      const row = node("div", `run-active-row${run.parent_run_id ? " child-run" : ""}`);
      row.append(node("code", "", run.run_id), stateBadge(run.reconciliation_state || run.status));
      row.append(node("span", "muted", [run.wave_id, run.capability, run.actor].filter(Boolean).join(" · ") || "Run"));
      if (run.parent_run_id) row.append(node("span", "muted", `parent ${run.parent_run_id}`));
      if (run.reconciliation_state) row.append(node("strong", "run-orphan", "RESULT UNKNOWN · NEEDS RECONCILIATION"));
      activeList.append(row);
    }
    clear(timeline);
    if (!result.events.length) timeline.append(empty("Keine Run-Events für diesen Filter."));
    for (const event of result.events) {
      const row = node("article", "run-event-row");
      const time = new Date(event.occurred_at);
      row.append(node("time", "run-event-time", Number.isNaN(time.valueOf()) ? event.occurred_at : time.toLocaleString()));
      const detail = node("div", "run-event-detail");
      detail.append(node("strong", "", event.event_type.replaceAll("_", " ")));
      detail.append(node("span", "muted", `${event.event_class} · ${event.run_id}${event.parent_run_id ? ` · parent ${event.parent_run_id}` : ""}${event.wave_id ? ` · ${event.wave_id}` : ""}`));
      const codes = event.payload?.reason_codes || [];
      if (codes.length) detail.append(node("span", "run-event-reasons", codes.join(" · ")));
      const links = [...(event.payload?.evidence_references || []), event.correlation?.verdict_reference, event.correlation?.handoff_reference, event.correlation?.result_reference].filter(Boolean);
      for (const path of [...new Set(links)]) {
        if (!/^(planning\/(evidence|verification-plans|ui-inventory)\/|\.concord\/(evidence|delegation-handoffs|delegated-results)\/|requirements\/|specs\/)/.test(path)) continue;
        detail.append(externalLink(path.split("/").pop(), `/run-artifact/${path.split("/").map(encodeURIComponent).join("/")}`, "run-artifact-link"));
      }
      row.append(detail); timeline.append(row);
    }
    footer.textContent = `${result.events.length} Events · ${result.total_valid} gültig · ${result.invalid_lines} ungültig übersprungen · Reihenfolge je Zeitstempel, keine globale Kausalordnung`;
  } catch {
    clear(activeList); clear(timeline);
    activeList.append(empty("Run-Status nicht verfügbar.")); timeline.append(empty("Run-Events nicht verfügbar."));
    footer.textContent = "Runtime-History nicht verfügbar; Current State bleibt unabhängig.";
  }
}

function timelineStateMessage(meta) {
  if (!meta) return null;
  if (meta.state === "BUILDING") return "Timeline wird aus der Git-Historie aufgebaut … (einmalig, danach sofort verfügbar)";
  if (meta.state === "NOT_OBSERVABLE") return "Kein Git-Verlauf beobachtbar. Die Timeline wird nicht erraten.";
  if (meta.state === "ERROR" || meta.state === "UNAVAILABLE") return `Timeline nicht verfügbar (${meta.reason || meta.state}).`;
  return null;
}

let timelineView = { token: 0, events: [], next: null, meta: null };

function timelineFilterBar(params) {
  const bar = node("form", "timeline-filters");
  bar.addEventListener("submit", (event) => event.preventDefault());
  const apply = () => {
    const next = new URLSearchParams();
    for (const [key, value] of new FormData(bar).entries()) if (String(value).trim()) next.set(key, String(value).trim());
    location.hash = `timeline${next.toString() ? `?${next.toString()}` : ""}`;
  };
  const primary = node("div", "filters-primary");
  const advanced = node("details", "filters-advanced");
  const select = (container, name, label, options, value) => {
    const wrapper = node("label", "filter");
    wrapper.append(node("span", "", label));
    const element = document.createElement("select");
    element.name = name;
    for (const [optionValue, optionLabel] of options) {
      const option = document.createElement("option");
      option.value = optionValue;
      option.textContent = optionLabel;
      option.selected = optionValue === (value || "");
      element.append(option);
    }
    element.addEventListener("change", apply);
    wrapper.append(element);
    container.append(wrapper);
  };
  const dayOffset = (days) => { const date = new Date(); date.setDate(date.getDate() - days); return date.toISOString().slice(0, 10); };
  select(primary, "from", "Zeitraum", [["", "Gesamter Verlauf"], [dayOffset(1), "Seit gestern"], [dayOffset(7), "Letzte 7 Tage"], [dayOffset(30), "Letzte 30 Tage"]], params.get("from"));
  select(primary, "group", "Bereich", Object.entries(GROUP_LABELS), params.get("group"));
  select(primary, "min_significance", "Umfang", [["", "Alles"], ["2", "Nur Wichtiges"]], params.get("min_significance"));
  select(advanced, "lane", "Zuordnung", [["", "Alle"], ["attributed", "Zugeordnet"], ["unattributed", "Nicht zugeordnet"]], params.get("lane"));
  select(advanced, "authority", "Beleg", [["", "Alle"], ["CANONICAL_RECORD", "Kanonisch"], ["GIT_DERIVED", "Aus Git belegt"], ["COMMIT_TRAILER", "Change-Set"], ["GIT_MENTION", "Nur erwähnt"]], params.get("authority"));
  const entity = node("label", "filter");
  entity.append(node("span", "", "Eintrag (z. B. wave:W13)"));
  const input = document.createElement("input");
  input.name = "entity";
  input.placeholder = "wave:W13 · requirement:REQ-093";
  input.value = params.get("entity") || "";
  input.addEventListener("change", apply);
  entity.append(input);
  advanced.append(entity);
  const active = ["lane", "authority", "entity"].filter((key) => params.get(key)).length;
  advanced.open = active > 0;
  const summary = node("summary", "", active ? `Weitere Filter (${active} aktiv)` : "Weitere Filter");
  advanced.prepend(summary);
  bar.append(primary, advanced);
  for (const hidden of ["include_mentions"]) if (params.get(hidden)) { const field = document.createElement("input"); field.type = "hidden"; field.name = hidden; field.value = params.get(hidden); bar.append(field); }
  return bar;
}
async function renderTimeline() {
  const params = hashQuery();
  root.append(sectionTitle("Project Timeline", "Was ist im Projekt passiert – rekonstruiert aus kanonischen Artefakten und Git (abgeleitet, nie gespeichert)"));
  root.append(timelineFilterBar(params));
  const explain = node("p", "muted timeline-note", "Chronologisch älter → neuer. Wichtiges hervorgehoben, Routine zusammengefasst. ");
  explain.append(withTip(node("span", "hint", "ⓘ Wie wird zugeordnet?"), "Beziehungen zu Waves, Requirements oder Pages erscheinen nur, wenn sie aus Artefakten oder Change-Sets belegt sind. „nur erwähnt“ und „nicht zugeordnet“ bleiben sichtbar schwach. Zeitnähe, Dateinamen und Commit-Texte ordnen nichts zu."));
  root.append(explain);
  const stream = node("div", "timeline-stream");
  const footer = node("div", "timeline-footer");
  root.append(stream, footer);
  const token = ++timelineView.token;
  const filters = Object.fromEntries([...params.entries()].filter(([key]) => key !== "cursor"));
  filters.limit = "80";
  const load = async (cursor) => {
    footer.textContent = "";
    footer.append(node("span", "muted", "lädt …"));
    let result;
    try {
      result = await fetchTimeline(cursor ? { ...filters, cursor } : filters);
    } catch {
      footer.textContent = "Timeline nicht erreichbar.";
      return;
    }
    if (token !== timelineView.token) return;
    const message = timelineStateMessage(result.index);
    if (message) {
      footer.textContent = message;
      if (result.index.state === "BUILDING") setTimeout(() => { if (token === timelineView.token && routeParts()[0] === "timeline") load(cursor); }, 1500);
      return;
    }
    const chronologicalPage = result.events.slice().sort((left, right) =>
      left.occurred_epoch - right.occurred_epoch || left.event_id.localeCompare(right.event_id));
    const previousHeight = cursor ? stream.scrollHeight : 0;
    const previousScrollY = cursor ? window.scrollY : 0;
    if (!cursor) timelineView.events = chronologicalPage;
    else timelineView.events.unshift(...chronologicalPage);
    clear(stream);
    if (!timelineView.events.length) stream.append(empty("Keine Ereignisse für diesen Filter."));
    renderMomentStream(stream, groupMoments(timelineView.events));
    if (cursor) requestAnimationFrame(() => window.scrollTo(0, previousScrollY + stream.scrollHeight - previousHeight));
    clear(footer);
    footer.append(node("span", "muted", `${timelineView.events.length} von ${result.total} Ereignissen · Index ${result.index.head || ""}${result.index.incremental ? " (inkrementell)" : ""} · ${result.index.rule_version || ""}`));
    if (result.next_cursor) {
      const more = node("button", "load-more", "Ältere Ereignisse laden");
      more.type = "button";
      more.addEventListener("click", () => load(result.next_cursor));
      footer.append(more);
    }
  };
  load(null);
}

async function renderRecentActivity() {
  const container = $("#recent-activity");
  if (!container) return;
  clear(container);
  container.hidden = !status.health;
  if (!status.health) return;
  const head = node("div", "cw-head");
  head.append(node("span", "eyebrow", "RECENT ACTIVITY"), derivedBadge());
  const all = internalLink("Gesamte Timeline →", "timeline");
  all.className = "internal-link all-activity";
  head.append(all);
  container.append(head);
  const body = node("div", "recent-body");
  container.append(body);
  body.append(node("p", "muted", "Aktivität wird geladen …"));
  const token = ++timelineView.token;
  const attempt = async () => {
    let result;
    try {
      result = await fetchTimeline({ limit: "150", min_significance: "2" });
    } catch {
      clear(body);
      body.append(node("p", "muted", "Timeline nicht erreichbar."));
      return;
    }
    if (token !== timelineView.token) return;
    const message = timelineStateMessage(result.index);
    clear(body);
    if (message) {
      body.append(node("p", "muted", message));
      if (result.index.state === "BUILDING") setTimeout(() => { if (token === timelineView.token) attempt(); }, 1500);
      return;
    }
    const moments = groupMoments(result.events);
    const story = moments.filter((moment) => tierOf(moment) !== "routine");
    if (!story.length && !moments.length) {
      body.append(node("p", "muted", "Keine wesentlichen Ereignisse im beobachteten Verlauf."));
      return;
    }
    // Orientation first: activity without evidence that is newer than the latest project milestone gets one honest line.
    const newest = story.length ? story[0].epoch : -1;
    const newer = moments.filter((moment) => tierOf(moment) === "routine" && moment.epoch > newest);
    if (newer.length) {
      const latest = newer[0];
      const note = node("div", "recent-unassigned");
      note.append(node("span", "unassigned-tag", "nicht zugeordnet"));
      const text = latest.commit ? latest.commit.subject : latest.events[0].title;
      note.append(withTip(node("span", "recent-unassigned-text", `${newer.length} Aktivität${newer.length > 1 ? "en" : ""} seit dem letzten Meilenstein – zuletzt: „${text.slice(0, 90)}"`),
        newer.slice(0, 8).map((moment) => `${timeOf(moment.iso)}  ${moment.commit ? moment.commit.subject : moment.events[0].title}`).join("\n") + "\n\nKeiner Wave, Task oder Page zugeordnet."));
      const more = internalLink("ansehen", "timeline?lane=unattributed");
      more.className = "internal-link all-activity";
      note.append(more);
      body.append(note);
    }
    let currentDay = null;
    for (const moment of story.slice(0, 6)) {
      const day = moment.iso.slice(0, 10);
      if (day !== currentDay) {
        currentDay = day;
        body.append(node("div", "recent-day", dayLabel(moment.iso)));
      }
      body.append(momentCard(moment, { compact: true }));
    }
  };
  attempt();
}
async function renderEntityTimeline(type, id) {
  const section = node("section", "plain-section entity-timeline");
  const head = node("div", "cw-head");
  head.append(node("h3", "", "Verlauf"), derivedBadge());
  const all = internalLink("Alle Ereignisse →", `timeline?entity=${encodeURIComponent(`${type}:${id}`)}`);
  all.className = "internal-link all-activity";
  head.append(all);
  section.append(head);
  const body = node("div", "recent-body");
  body.append(node("p", "muted", "Verlauf wird geladen …"));
  section.append(body);
  root.append(section);
  try {
    const result = await fetchTimeline({ entity: `${type}:${id}`, limit: "30" });
    clear(body);
    const message = timelineStateMessage(result.index);
    if (message) return body.append(node("p", "muted", message));
    const moments = groupMoments(result.events).slice(0, 8);
    if (!moments.length) return body.append(node("p", "muted", "Keine belegten Ereignisse zu diesem Eintrag im beobachteten Verlauf."));
    renderMomentStream(body, moments, { compact: true });
  } catch {
    clear(body);
    body.append(node("p", "muted", "Verlauf nicht erreichbar."));
  }
}

// ---------------------------------------------------------------------------------- Pages & Parity / Page Hub (CS-6)
async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) throw new Error(String(response.status));
  return response.json();
}

const PARITY_STATE_TEXT = { COMPUTED: "belegt (berechnet)", REPORTED_UNBOUND: "berichtet, nicht belegt", STALE: "veraltet", NOT_VERIFIED: "nicht verifiziert" };

function parityStateLabel(state) {
  return PARITY_STATE_TEXT[state] || state;
}

function germanDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value || "");
  return match ? `${match[3]}.${match[2]}.${match[1]}` : (value || "ohne Datum");
}

function pageReports(pageId) {
  const reports = ((status.verification && status.verification.parity_reports) || []).filter((report) => report.page_id === pageId);
  return reports.sort((a, b) => (b.verified_at || "").localeCompare(a.verified_at || ""));
}

function pageSignals(preview, reports) {
  // Scannability only: which Pages deserve a look. Signals are facts from the projection, never verdicts.
  const signals = [];
  let score = 0;
  const latest = reports[0];
  if (!reports.length) { signals.push(["warn", "kein Parity-Report"]); score += 2; }
  else {
    if (latest.reported_result === "FAIL") { signals.push(["bad", "Parity: FAIL"]); score += 3; }
    else if (latest.reported_result === "PARTIAL") { signals.push(["warn", "Parity: PARTIAL"]); score += 2; }
    if (latest.state === "REPORTED_UNBOUND") signals.push(["muted", "nicht belegt"]);
  }
  if (preview.implementation && preview.implementation.mismatch) { signals.push(["bad", "Absicht ≠ Fakt"]); score += 3; }
  if (preview.reference && preview.reference.availability !== "available") { signals.push(["bad", "Referenz fehlt"]); score += 3; }
  if (preview.html_source && preview.html_source.availability === "missing") { signals.push(["warn", "HTML-Quelle fehlt"]); score += 2; }
  return { signals, score };
}

function pageCard(preview) {
  const reports = pageReports(preview.page_id);
  const { signals, score } = pageSignals(preview, reports);
  const card = node("article", `page-card ${score >= 3 ? "attention" : score > 0 ? "notice" : ""}`);
  const head = node("div", "page-card-head");
  const link = internalLink(preview.title || preview.page_name || preview.page_id, `pages/${encodeURIComponent(preview.page_id)}`);
  link.className = "internal-link page-card-title";
  head.append(link);
  const sourceKind = preview.html_source && preview.html_source.availability === "available" ? "HTML-Quelle vorhanden" : preview.implementation_mode === "HTML_FIRST" ? "HTML-first" : "Mendix";
  head.append(node("span", "page-card-mode", sourceKind));
  card.append(head, node("div", "page-card-id mono", `${preview.page_id}${preview.title && preview.page_name && preview.title !== preview.page_name ? ` · Mendix: ${preview.page_name}` : ""}`));
  const latest = reports[0];
  card.append(node("p", "page-card-parity", latest
    ? `Zuletzt geprüft ${germanDate(latest.verified_at)}${reports.length > 1 ? ` · ${reports.length} Reports` : ""}`
    : "Parity: nicht erfasst"));
  const chips = node("div", "page-card-signals");
  for (const [tone, text] of signals) chips.append(node("span", `signal ${tone}`, text));
  card.append(chips);
  return { card, score, name: preview.title || preview.page_name || preview.page_id };
}

function renderParityOverview(container) {
  const reports = (status.verification && status.verification.parity_reports) || [];
  container.append(node("p", "muted", "Gesamtsicht über alle Parity-Reports des Projekts. Details je Page stehen im Page Hub. „berichtet, nicht belegt“ heißt: Der Report existiert, ist aber an keine Evidenz gebunden."));
  if (!reports.length) {
    container.append(empty("Keine Parity-Reports erfasst."));
    return;
  }
  const counts = {};
  for (const report of reports) counts[report.state] = (counts[report.state] || 0) + 1;
  container.append(node("p", "", Object.entries(counts).map(([state, count]) => `${count} ${parityStateLabel(state)}`).join(" · ")));
  const list = node("div", "plain-list");
  for (const report of [...reports].sort((a, b) => (b.verified_at || "").localeCompare(a.verified_at || ""))) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    const page = report.page_id ? internalLink(report.page_id, `pages/${encodeURIComponent(report.page_id)}`) : node("span", "", "ohne Page");
    main.append(page, node("small", "muted", `${report.scenario_id || report.report_path} · berichtet: ${report.reported_result || "—"} · berechnet: ${report.computed_result || "—"} · ${germanDate(report.verified_at)}`));
    row.append(main, stateBadge(parityStateLabel(report.state).toUpperCase().replaceAll(" ", "_").replaceAll(",", "")), sourceLinkPath(report.report_path, "Report ↗"));
    list.append(row);
  }
  container.append(list);
}

async function renderPages() {
  const params = hashQuery();
  const parity = params.get("view") === "parity";
  root.append(sectionTitle("Pages & Parity", "Page als Einstieg: Soll, Ist, Parity und Evidenz an einer Stelle · read-only"));
  const seg = node("div", "segmented");
  const pagesLink = internalLink("Pages", "pages");
  const parityLink = internalLink("Parity-Übersicht", "pages?view=parity");
  (parity ? parityLink : pagesLink).classList.add("active");
  seg.append(pagesLink, parityLink);
  root.append(seg);
  const container = node("div", "pages-body");
  root.append(container);
  if (parity) return renderParityOverview(container);
  container.append(node("p", "muted", "Pages werden geladen …"));
  let previews;
  try {
    previews = await fetchJson("/api/page-previews");
  } catch {
    clear(container);
    container.append(node("p", "muted", "Pages nicht erreichbar."));
    return;
  }
  if (routeParts()[0] !== "pages" || routeParts()[1]) return;
  clear(container);
  const items = previews.items || [];
  if (!items.length) return container.append(empty(previews.availability === "unavailable" ? "Kein UI-Inventar (planning/ui-inventory) vorhanden." : "Keine Pages im UI-Inventar."));
  const cards = items.map(pageCard).sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
  const attention = cards.filter((entry) => entry.score > 0);
  const calm = cards.filter((entry) => entry.score === 0);
  if (attention.length) {
    container.append(node("h3", "pages-group", `Zum Hinschauen (${attention.length})`));
    const grid = node("div", "page-grid");
    attention.forEach((entry) => grid.append(entry.card));
    container.append(grid);
  }
  if (calm.length) {
    const details = node("details", "pages-calm");
    details.open = !attention.length;
    details.append(node("summary", "", `Ohne auffällige Signale (${calm.length})`));
    const grid = node("div", "page-grid");
    calm.forEach((entry) => grid.append(entry.card));
    details.append(grid);
    container.append(details);
  }
  container.append(node("p", "muted", `${items.length} Pages · Signale sind Fakten aus der Projektion, keine Bewertung. Der Parity-Stand ist „berichtet“, solange keine Evidenz gebunden ist.`));
}

function lazyFrame(label, url) {
  // The artifact renders at a desktop viewport (1440 px) and is scaled to the tile, so the preview shows the whole screen.
  const details = node("details", "hub-preview");
  details.append(node("summary", "", label));
  details.addEventListener("toggle", () => {
    if (details.open && !details.querySelector("iframe")) {
      const wrap = node("div", "hub-frame-wrap");
      details.append(wrap);
      const scale = Math.min(1, (wrap.clientWidth || 330) / 1440);
      wrap.style.height = `${Math.round(900 * scale)}px`;
      const frame = document.createElement("iframe");
      frame.src = url;
      frame.loading = "lazy";
      frame.className = "hub-frame";
      frame.style.transform = `scale(${scale})`;
      frame.setAttribute("sandbox", "allow-scripts allow-same-origin");
      frame.title = label;
      wrap.append(frame);
      details.append(node("small", "muted", "Vorschau eines Projekt-Artefakts im Sandbox-Frame. Skriptfehler darin stammen aus dem Artefakt, nicht aus dem Board."));
    }
  });
  return details;
}

function hubTile(title, subtitle, stateText, tone) {
  const tile = node("section", "hub-tile");
  const head = node("div", "hub-tile-head");
  head.append(node("span", "eyebrow", title), node("span", `signal ${tone}`, stateText));
  tile.append(head);
  if (subtitle) tile.append(node("div", "hub-tile-sub", subtitle));
  return tile;
}

function thumbGroup(group) {
  const wrapper = node("div", "thumb-group");
  const head = node("div", "thumb-head");
  head.append(node("strong", "", group.label), node("small", "muted", `${group.total} Bild${group.total === 1 ? "" : "er"} · im Parity-Report erwähnt, nicht als Evidenz gebunden`));
  wrapper.append(head);
  const strip = node("div", "thumb-strip");
  for (const item of group.items.slice(0, 12)) {
    const link = externalLink("", item.url, "thumb");
    link.title = item.name;
    const image = document.createElement("img");
    image.loading = "lazy";
    image.src = item.url;
    image.alt = item.name;
    link.append(image);
    strip.append(link);
  }
  wrapper.append(strip);
  if (group.total > 12) wrapper.append(node("small", "muted", `+${group.total - 12} weitere im Ordner ${group.path}`));
  return wrapper;
}

function reportCard(report, open) {
  const details = node("details", "hub-report");
  details.open = open;
  const summary = node("summary", "");
  summary.append(node("strong", "", `${report.reported_result || "—"} · ${germanDate(report.verified_at)}`),
    node("span", "hub-report-state", ` ${parityStateLabel(report.state)}`), node("small", "muted", `  ${report.scenario_id || ""}`));
  details.append(summary);
  const facts = node("div", "hub-facts");
  const add = (label, value) => {
    if (!value) return;
    const item = node("div", "hub-fact");
    item.append(node("span", "cw-label", label), node("span", "", value));
    facts.append(item);
  };
  add("Geprüft gegen", report.target_mockup ? pathLabel(report.target_mockup) : null);
  add("Laufzeit-URL", report.app_url);
  add("Nachweisstufe", report.evidence_level ? `${report.evidence_level} (laut Report)` : null);
  add("Evidenz-Bindung", report.state === "COMPUTED" ? "gebunden" : "keine – der Report ist an kein Evidence-Manifest gebunden");
  add("Modell-/Commit-Stand der Prüfung", "nicht erfasst");
  if (report.recorded_in) add("Report erfasst in", `Commit ${report.recorded_in.commit} · „${report.recorded_in.subject}"`);
  details.append(facts);
  if (report.dimensions.length) {
    const dims = node("div", "dimension-grid");
    for (const dimension of report.dimensions) {
      const chip = node("span", `dimension ${dimension.result === "PASS" ? "good" : dimension.result === "PARTIAL" || dimension.result === "FAIL" ? "warn" : "muted"}`, `${dimension.dimension}: ${dimension.result || "—"}`);
      if (dimension.note) withTip(chip, dimension.note);
      dims.append(chip);
    }
    details.append(node("div", "cw-label", "Verglichene Dimensionen"), dims);
  }
  const links = node("div", "hub-links");
  links.append(externalLink("Report-Quelle ↗", report.source_url, "source-link"));
  details.append(links);
  return details;
}

function hubSection(title, hint) {
  const section = node("section", "hub-section");
  const head = node("div", "cw-head");
  head.append(node("h3", "", title));
  if (hint) head.append(node("small", "muted", hint));
  section.append(head);
  return section;
}

async function renderPageHub(pageId) {
  root.append(internalLink("← Pages & Parity", "pages"));
  const hub = node("div", "page-hub");
  root.append(hub);
  hub.append(node("p", "muted", "Page wird geladen …"));
  let data;
  try {
    data = await fetchJson(`/api/page/${encodeURIComponent(pageId)}`);
  } catch (error) {
    clear(hub);
    hub.append(empty(String(error.message) === "404" ? `Page ${pageId} ist im UI-Inventar nicht bekannt.` : "Page nicht erreichbar."));
    return;
  }
  if (routeParts()[0] !== "pages" || routeParts()[1] !== pageId) return;
  clear(hub);

  const header = node("header", "hub-header");
  header.append(node("div", "eyebrow", `PAGE · ${data.page_id}`), node("h2", "", data.title || data.page_name));
  const mode = data.implementation.mode === "HTML_FIRST" ? "HTML-first" : data.implementation.mode === "MENDIX_NATIVE" ? "Mendix-nativ" : "Modus unbekannt";
  const htmlState = data.visuals.design_preview.availability === "available" ? "HTML-Quelle registriert" : data.visuals.design_preview.availability === "missing" ? "registrierter HTML-Pfad fehlt" : "keine HTML-Quelle im UI-Inventar registriert";
  header.append(node("div", "hub-modeline", `Einstellung: ${mode} · ${htmlState} · Mendix-Seite: ${data.page_name}`));
  if (data.purpose) header.append(node("p", "hub-purpose muted", data.purpose.length > 260 ? `${data.purpose.slice(0, 260)} …` : data.purpose));
  hub.append(header);

  const strip = node("div", "hub-attention");
  if (data.attention.length) for (const item of data.attention) strip.append(node("span", "signal warn", item.text));
  else strip.append(node("span", "signal good", "Keine Hinweise aus der Projektion"));
  hub.append(strip);

  // Soll und Ist side by side: what it should look like, the implementation source, what was captured.
  const tiles = node("div", "hub-tiles");
  const reference = data.visuals.reference;
  const referenceTile = hubTile("SOLL · REFERENZ", reference.path ? pathLabel(reference.path) : null, reference.availability === "available" ? "vorhanden" : "nicht auffindbar", reference.availability === "available" ? "good" : "bad");
  if (reference.availability === "available") {
    referenceTile.append(externalLink("Mockup öffnen ↗", reference.url, "target-open"), lazyFrame("Vorschau einblenden", reference.url));
  }
  if (reference.active_revision) {
    referenceTile.append(node("small", "hub-tile-sub", `AKTIV ${reference.active_revision} · INVENTAR ${reference.inventory_revision || "UNKNOWN"}`));
  }
  const design = data.visuals.design_preview;
  const designLabel = design.fragment ? "RAW HTML FRAGMENT PREVIEW" : "HTML DOCUMENT SOURCE PREVIEW";
  const designTile = hubTile("UMSETZUNG · HTML-QUELLE", design.path ? pathLabel(design.path) : null,
    design.availability === "available" ? "vorhanden" : design.availability === "missing" ? "fehlt" : "nicht konfiguriert",
    design.availability === "available" ? "good" : design.availability === "missing" ? "bad" : "muted");
  if (design.availability === "available") {
    designTile.append(node("small", "preview-class", designLabel), externalLink("HTML source preview öffnen ↗", design.preview_url, "target-open"), externalLink("Quelle ↗", design.source_url, "source-link"), lazyFrame("Vorschau einblenden", design.preview_url));
    designTile.append(node("p", "muted", design.fragment
      ? "Fragmentvorschau ohne Mendix-Host-/Runtime-Kontext; Scripts sind deaktiviert. Nicht appgetreu, keine Parity-Evidenz."
      : "Quellvorschau ohne Script-Ausführung; nicht gleichbedeutend mit einer laufenden Mendix-Page."));
    for (const dependency of design.dependencies || []) {
      const row = node("div", "preview-dependency");
      const label = `${dependency.kind === "stylesheet" ? "CSS" : "JS"} · ${pathLabel(dependency.canonical_path || dependency.reference)}`;
      row.append(node("span", "muted", label), stateBadge(dependency.availability === "available" ? "available" : dependency.availability === "missing" ? "MISSING" : "NOT_LOADED"));
      if (dependency.kind === "javascript") row.append(node("small", "muted", "not executed in preview"));
      designTile.append(row);
    }
  } else if (design.availability === "not_configured") {
    designTile.append(node("p", "muted", "Keine HTML-Quelle im UI-Inventar registriert; daraus folgt nicht, dass im Projekt keine HTML-/JS-Artefakte existieren."));
  } else {
    designTile.append(node("p", "muted", "Der im Inventar genannte Pfad existiert im Projekt nicht."));
  }
  const captures = data.visuals.captures;
  const runtime = data.visuals.runtime;
  const captureCount = captures.reported.reduce((sum, group) => sum + group.total, 0);
  const runtimeTile = hubTile("IST · CAPTURES & LAUFZEIT", runtime.app_urls[0] || null,
    captures.bound_runs.length ? "Evidenz-gebunden" : captureCount ? `${captureCount} im Report erwähnt` : "nicht erfasst",
    captures.bound_runs.length ? "good" : captureCount ? "warn" : "muted");
  if (!captureCount && !captures.bound_runs.length) runtimeTile.append(node("p", "muted", "Keine Screenshots sind mit dieser Page verknüpft oder in einem Report erwähnt."));
  for (const group of captures.reported.slice(0, 2)) runtimeTile.append(thumbGroup(group));
  if (captures.reported.length > 2) runtimeTile.append(node("small", "muted", `+${captures.reported.length - 2} weitere Capture-Ordner in den technischen Quellen`));
  tiles.append(referenceTile, designTile, runtimeTile);
  hub.append(tiles);

  // Parity and evidence: what was compared, and whether the result is evidenced.
  const parity = hubSection("Parity & Evidenz", "Ein Screenshot oder Report allein belegt keine Parität.");
  const bindingText = data.parity.evidence_binding.state === "BOUND" ? `${data.parity.evidence_binding.entries} gebundene Evidenz-Einträge` : "keine gebundene Evidenz (kein Evidence-Manifest für diese Page)";
  parity.append(node("p", "", data.parity.reports.length
    ? `${data.parity.reports.length} Report${data.parity.reports.length > 1 ? "s" : ""} · zuletzt berichtet: ${data.parity.reports[0].reported_result || "—"} (${germanDate(data.parity.reports[0].verified_at)}) · ${bindingText}`
    : `Kein Parity-Report · ${bindingText}`));
  data.parity.reports.forEach((report, index) => parity.append(reportCard(report, index === 0)));
  hub.append(parity);

  // Context with explicit derivation; only canonical fields create relationships.
  const context = hubSection("Kontext", "nur belegte Beziehungen");
  const contextRows = node("div", "plain-list");
  const line = (label, content) => { const entry = node("div", "plain-item"); entry.append(node("div", "item-main", label)); entry.append(content); contextRows.append(entry); };
  const linkList = (items, route, text) => {
    const wrapper = node("span", "hub-linklist");
    items.forEach((item, index) => { if (index) wrapper.append(document.createTextNode(" · ")); wrapper.append(internalLink(text(item), `${route}/${encodeURIComponent(item.id)}`)); });
    return wrapper;
  };
  line("Decisions", data.context.decisions.length ? linkList(data.context.decisions, "decision", (item) => `${item.id}${item.status ? ` (${item.status})` : ""}`) : node("span", "muted", "keine Decision verweist auf diese Page (affected_screens)"));
  line("Requirements", data.context.requirements.length ? linkList(data.context.requirements, "requirement", (item) => `${item.id} (über ${item.via.join(", ")})`) : node("span", "muted", "keine – nur über Decisions ableitbar"));
  line("Findings", data.context.findings.length ? linkList(data.context.findings, "finding", (item) => item.id) : node("span", "muted", "keine verknüpft"));
  line("Tasks", node("span", "muted", data.context.tasks.note));
  const authority = data.authority.active_targets.map((target) => `${target.revision_id || target.mockup_name || pathLabel(target.canonical_path)}`).concat(data.authority.revision_ledger.map((item) => `${item.revision_id}${item.active_target ? " (aktiv)" : ""}`));
  line("Design Authority", node("span", authority.length ? "" : "muted", authority.length ? [...new Set(authority)].join(" · ") : "keine aktive Referenz an diese Page gebunden"));
  context.append(contextRows);
  hub.append(context);

  const sources = node("details", "hub-sources");
  sources.append(node("summary", "", "Technische Quellen"));
  const sourceList = node("div", "hub-links");
  sourceList.append(externalLink("UI-Inventar ↗", data.sources.inventory_url, "source-link"));
  data.parity.reports.forEach((report) => sourceList.append(externalLink(`${report.scenario_id || "Report"} ↗`, report.source_url, "source-link")));
  captures.documents.forEach((doc) => sourceList.append(externalLink(`${doc.name} ↗`, doc.url, "source-link")));
  captures.reported.forEach((group) => sourceList.append(node("small", "muted mono", `${group.path} (${group.total})`)));
  sources.append(sourceList);
  hub.append(sources);
  renderEntityTimeline("page", pageId);
}

function renderTasks() {
  const tasks = (status.delivery && status.delivery.tasks.items) || [];
  root.append(sectionTitle("Tasks", `${valueText(status.delivery.tasks.items.length, status.delivery.tasks)} Tasks · aus planning/tasks`));
  if (!tasks.length) return root.append(empty(obsLabel(status.delivery.tasks, "Keine Tasks")));
  const counts = {};
  for (const task of tasks) counts[task.status || "unknown"] = (counts[task.status || "unknown"] || 0) + 1;
  root.append(node("p", "", Object.entries(counts).map(([name, count]) => `${count} ${name}`).join(" · ")));
  const scroll = node("div", "table-scroll");
  const table = node("table", "data-table");
  const head = document.createElement("thead");
  const headerRow = document.createElement("tr");
  for (const label of ["Task", "Status", "Wave", "Requirements"]) headerRow.append(node("th", "", label));
  head.append(headerRow);
  const body = document.createElement("tbody");
  const order = { blocked: 0, in_progress: 1, pending: 2, deferred: 3, failed: 0, done: 4 };
  for (const task of [...tasks].sort((a, b) => (order[a.status] ?? 5) - (order[b.status] ?? 5) || a.id.localeCompare(b.id, undefined, { numeric: true }))) {
    const row = document.createElement("tr");
    const idCell = document.createElement("td");
    idCell.append(node("strong", "", task.id), node("div", "muted", task.action || ""));
    const statusCell = document.createElement("td");
    statusCell.append(stateBadge(task.status || "UNKNOWN"));
    const waveCell = document.createElement("td");
    if (task.wave_id) waveCell.append(internalLink(task.wave_id, `wave/${encodeURIComponent(task.wave_id)}`)); else waveCell.append(node("span", "muted", "keine"));
    const reqCell = document.createElement("td");
    task.requirement_ids.slice(0, 4).forEach((id, index) => { if (index) reqCell.append(document.createTextNode(", ")); reqCell.append(internalLink(id, `requirement/${encodeURIComponent(id)}`)); });
    if (task.requirement_ids.length > 4) reqCell.append(node("span", "muted", ` +${task.requirement_ids.length - 4}`));
    row.append(idCell, statusCell, waveCell, reqCell);
    body.append(row);
  }
  table.append(head, body);
  scroll.append(table);
  root.append(scroll);
}

function compactTargetCard(target) {
  const card = node("article", "target-compact");
  const title = target.mockup_name || target.revision_id || pathLabel(target.canonical_path) || "Reference";
  const main = node("div", "target-compact-main");
  main.append(node("strong", "", title));
  const pages = (target.screen_ids || []).length;
  main.append(node("span", "muted", `${target.revision_id || "ohne Revision"} · ${pages} Page${pages === 1 ? "" : "s"} gebunden`));
  // Fingerprints and authority-source lists are technical detail: on hover, not on the Overview.
  const fingerprint = target.bundle_hash || target.content_hash || target.source_fingerprint;
  withTip(main, `Referenz-ID: ${target.reference_id || "unbekannt"}\nFingerprint: ${fingerprint || "unbekannt"}\nAutorität: ${target.authoritative_state || "unbekannt"}\nQuellen: ${(target.authority_sources || []).map((source) => `${source.source_type} · ${pathLabel(source.canonical_path)}`).join(", ") || "unbekannt"}`);
  card.append(main);
  if (target.availability === "available" && target.canonical_path) card.append(externalLink("Mockup öffnen ↗", safePathUrl("/reference", target.canonical_path), "target-open"));
  else card.append(node("span", "signal warn", "Referenz nicht auffindbar"));
  const drift = target.inventory_drift && target.inventory_drift.state;
  if (drift && drift !== "not_applicable" && drift !== "consistent") card.append(node("span", "signal warn", `Inventar: ${drift}`));
  return card;
}

function healthChipInfo() {
  const health = status && status.health;
  if (!health) return null;
  const projection = status.projection_state;
  const projectionNote = projection && projection.state !== "FRESH" ? ` · PROJECTION ${projection.state}` : "";
  const label = health.level === "BLOCKED" ? `HEALTH · ${health.blocking_diagnostics} BLOCKING` : `HEALTH · ${health.level}`;
  return { level: health.level, text: label + projectionNote, stale: Boolean(projectionNote) };
}

function updateHealthChip() {
  const chip = document.querySelector("#health-chip");
  if (!chip) return;
  const info = healthChipInfo();
  chip.hidden = !info;
  if (!info) return;
  chip.textContent = info.text;
  chip.className = `health-chip ${info.level === "OK" && !info.stale ? "ok" : info.level === "BLOCKED" ? "bad" : "warn"}`;
  chip.title = "Projection / data health. Details in Health & Diagnostics.";
}

function groupCount(group) {
  const entry = status.health && status.health.diagnostics_by_group[group];
  return entry || { total: 0, blocking: 0 };
}

function renderHealthSummary(container) {
  const health = status.health;
  if (!health) return;
  const section = node("section", "health-summary");
  section.setAttribute("aria-label", "Attention, health and diagnostics");
  const cards = [
    ["project_attention", groupCount("project_attention").total ? "warn" : "ok", `${groupCount("project_attention").total} items`],
    ["projection_health", health.level === "OK" ? "ok" : health.level === "BLOCKED" ? "bad" : "warn", `${health.level}${groupCount("projection_health").total ? ` · ${groupCount("projection_health").total} diagnostics` : ""}`],
    ["framework_compat", groupCount("framework_compat").blocking + groupCount("optional_metadata").blocking ? "bad" : "calm",
      `${groupCount("framework_compat").total} compatibility notes · ${groupCount("optional_metadata").total} optional metadata${groupCount("framework_compat").blocking + groupCount("optional_metadata").blocking ? ` · ${groupCount("framework_compat").blocking + groupCount("optional_metadata").blocking} blocking` : ""}`],
  ];
  for (const [group, tone, value] of cards) {
    const card = node("a", `health-card ${tone}`);
    card.href = "#health";
    card.append(node("span", "eyebrow", GROUP_TEXT[group][0].toUpperCase()), node("strong", "", value), node("small", "muted", GROUP_TEXT[group][1]));
    section.append(card);
  }
  container.append(section);
}

function diagnosticRow(item) {
  const states = {
    SYNTAX_ERROR: "INVALID", SCHEMA_ERROR: "INVALID", ID_MISMATCH: "INVALID", DUPLICATE_ID: "AMBIGUOUS",
    REFERENCE_MISSING: "NOT_RECORDED", REFERENCE_AMBIGUOUS: "AMBIGUOUS", AUTHORITY_CONFLICT: "AMBIGUOUS",
    WAVE_ASSIGNMENT_MISSING: "NOT_RECORDED", UNSUPPORTED_VARIANT: "UNSUPPORTED", LEGACY_VARIANT: "UNSUPPORTED",
    FRESHNESS_UNKNOWN: "NOT_OBSERVABLE", MISSING: "NOT_RECORDED", UNASSIGNED: "NOT_APPLICABLE", STALE: "STALE",
    DONE_BASIS_NOT_RECORDED: "NOT_RECORDED", CHANGE_SET_SCHEMA_INVALID: "INVALID", ACTIVE_REVISION_UNBOUND: "AMBIGUOUS",
  };
  const row = node("div", "plain-item diagnostic-item");
  const description = node("div", "item-main");
  description.append(node("strong", "", item.affected_board_area), node("p", "", item.message));
  description.append(node("small", "muted", `${item.category} · ${item.repairability}${item.blocking ? " · BLOCKING" : ""}`));
  if (item.source_path) {
    const location = `${item.source_path}${item.line ? `:${item.line}:${item.column}` : ""}`;
    description.append(externalLink(location, safePathUrl("/diagnostic-source", item.source_path)));
  }
  row.append(description, obsBadge(states[item.category] || "NOT_OBSERVABLE"));
  return row;
}

function renderHealthView() {
  const health = status.health;
  root.append(sectionTitle("Health & Diagnostics", "Trennt Projekt-Attention, Projektions-/Datengesundheit und Framework-Diagnostik"));

  const projection = status.projection_state;
  const projectionSection = node("section", "plain-section");
  projectionSection.append(node("h3", "", "Projection"));
  const projectionRow = node("div", "plain-item");
  projectionRow.append(node("div", "item-main", projection ? `Server snapshot · age ${projection.age_seconds === null ? "?" : Math.round(projection.age_seconds)} s` : "Projection state not loaded"), stateBadge(projection ? projection.state : "NOT_LOADED"));
  projectionSection.append(projectionRow);
  root.append(projectionSection);

  const states = health.observation_states;
  const order = Object.keys(states).sort((a, b) => (states[a] === "AVAILABLE") - (states[b] === "AVAILABLE") || a.localeCompare(b));
  const observed = node("section", "plain-section");
  observed.append(node("h3", "", "Observation states"), node("p", "muted", "Jeder Bereich hat genau einen Zustand. Nichts wird ausgeblendet; fehlende Information ist kein Erfolg."));
  const list = node("div", "plain-list");
  for (const area of order) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(node("strong", "", area), node("small", "muted", OBS_TEXT[states[area]] ? OBS_TEXT[states[area]][1] : ""));
    row.append(main, obsBadge(states[area]));
    list.append(row);
  }
  observed.append(list);
  root.append(observed);

  const diagnostics = (status.compatibility && status.compatibility.diagnostics) || [];
  const inspectMigrationCount = new Set(diagnostics
    .filter((item) => item.proposed_repair_type === "TASK_INSPECT_TYPED_TARGET_V1")
    .map((item) => item.source_path)).size;
  for (const group of ["project_attention", "projection_health", "framework_compat", "optional_metadata"]) {
    const items = diagnostics.filter((item) => (item.diagnostic_group || "projection_health") === group);
    const counts = groupCount(group);
    const panel = node("details", "plain-section compatibility-diagnostics");
    panel.open = group === "project_attention" ? counts.total > 0 : counts.blocking > 0;
    const summary = node("summary", "view-title");
    summary.append(node("strong", "", GROUP_TEXT[group][0]));
    const extra = group === "framework_compat" && inspectMigrationCount ? ` · ${inspectMigrationCount} tasks use the legacy task-inspect form (lossless migration available)` : "";
    summary.append(node("small", "", `${counts.total} diagnostics · ${counts.blocking} blocking${extra}`));
    panel.append(summary, node("p", "muted", GROUP_TEXT[group][1]));
    const body = node("div", "plain-list");
    for (const item of items) body.append(diagnosticRow(item));
    panel.append(items.length ? body : empty("Keine Diagnosen in dieser Gruppe"));
    root.append(panel);
  }

  const framework = node("section", "plain-section");
  framework.append(node("h3", "", "Framework"));
  const frameworkRow = node("div", "plain-item");
  frameworkRow.append(node("div", "item-main", `Compatibility ${health.framework.compatibility || "UNKNOWN"} · repair ${health.framework.repair_status || "UNKNOWN"}`), stateBadge(health.framework.compatibility || "NOT_OBSERVABLE"));
  framework.append(frameworkRow);
  root.append(framework);
}

function renderProjectionState() {
  // A stale or rebuilding projection must never look current (CS-2).
  const projection = status.projection_state || null;
  const read = `READ ${new Date().toLocaleTimeString()}`;
  const connection = document.querySelector(".connection");
  if (connection && connection.lastChild && connection.dataset.base === undefined) connection.dataset.base = connection.lastChild.textContent;
  if (!projection) {
    $("#updated-label").textContent = read;
    return;
  }
  const seconds = (value) => (value === null || value === undefined ? "?" : `${Math.round(value)} s`);
  const reasons = { STARTUP_LAST_GOOD: "letzter gespeicherter Stand", SOURCES_CHURNING: "Quellen ändern sich gerade" };
  let label;
  if (projection.state === "FRESH") {
    label = `PROJEKTION AKTUELL · geprüft vor ${seconds(projection.validated_age_seconds)}`;
  } else if (projection.state === "STALE") {
    label = `PROJEKTION VERALTET · ${reasons[projection.reason] || projection.reason || "unbekannter Grund"} · Stand vor ${seconds(projection.age_seconds)}${projection.rebuilding ? " · wird neu aufgebaut" : ""}`;
  } else {
    label = `PROJEKTION ${projection.state}`;
  }
  $("#updated-label").textContent = `${read} · ${label}`;
  if (connection && connection.dataset.base !== undefined) {
    connection.lastChild.textContent = projection.state === "FRESH"
      ? connection.dataset.base
      : `${connection.dataset.base} · ${projection.state}`;
  }
}

async function load({ preserveUi = false, silent = false } = {}) {
  if (loadInFlight) return;
  loadInFlight = true;
  const button = $("#refresh");
  const scrollY = preserveUi ? window.scrollY : 0;
  const detailsState = preserveUi ? [...root.querySelectorAll("details")].map((item) => item.open) : [];
  button.disabled = true;
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error("Status unavailable");
    status = await response.json();
    renderHeader();
    renderCurrentWork();
    renderRecentActivity();
    renderAttention();
    renderMetrics();
    updateHealthChip();
    $("#load-state").hidden = true;
    $("#board").hidden = false;
    renderView();
    renderProjectionState();
    if (preserveUi) {
      [...root.querySelectorAll("details")].forEach((item, index) => {
        if (detailsState[index] !== undefined) item.open = detailsState[index];
      });
      requestAnimationFrame(() => window.scrollTo(0, scrollY));
    }
    void loadReconciliation();
  } catch {
    if (!silent && !status) $("#load-state").textContent = "Project status unavailable. The board did not infer missing state.";
  } finally {
    button.disabled = false;
    loadInFlight = false;
  }
}

async function checkForRevision() {
  if (!status || document.hidden || revisionCheckInFlight) return;
  revisionCheckInFlight = true;
  try {
    const response = await fetch("/api/revision", { cache: "no-store" });
    if (!response.ok) return;
    const revision = await response.json();
    if (revision.projection_state?.state !== "FRESH") return;
    if (runEventRevision === null) {
      runEventRevision = revision.run_event_revision;
      if (routeParts()[0] === "activity") renderView();
    }
    else if (revision.run_event_revision && revision.run_event_revision !== runEventRevision) {
      runEventRevision = revision.run_event_revision;
      if (routeParts()[0] === "activity") renderView();
    }
    if (revision.source_fingerprint && revision.source_fingerprint !== status.source_fingerprint) {
      await load({ preserveUi: true, silent: true });
    }
  } catch {
    // Transient file writes or a restarting local server are retried by the next poll.
  } finally {
    revisionCheckInFlight = false;
  }
}

document.addEventListener("click", (event) => {
  const routeButton = event.target.closest("[data-route]");
  if (routeButton) navigate(routeButton.dataset.route);
});
window.addEventListener("hashchange", () => { if (status) renderView(); });
$("#refresh").addEventListener("click", load);
window.setInterval(checkForRevision, REVISION_POLL_INTERVAL_MS);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) void checkForRevision();
});
load();