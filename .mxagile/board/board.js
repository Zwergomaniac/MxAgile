"use strict";

const $ = (selector) => document.querySelector(selector);
const root = $("#view");
const tabs = ["overview", "waves", "requirements", "verification", "gallery", "ui-pages", "findings", "decisions"];
let status = null;

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
  const normalized = String(value || "UNKNOWN");
  let tone = "unknown";
  if (["done", "VERIFIED", "CONFIRMED", "passed", "available", "ACTIVE_TARGET", "consistent"].includes(normalized)) tone = "good";
  else if (["blocked", "failed", "FAIL", "STALE", "DECISION_REQUIRED", "CRITICAL", "ambiguous", "mismatch", "INVALID", "AMBIGUOUS", "BLOCKED"].includes(normalized)) tone = "bad";
  else if (["PROPOSED", "PARTIAL", "partial", "unknown", "UNKNOWN", "REASSESS_REQUIRED", "SUPERSEDED", "RETIRED", "FRAMEWORK_FOLLOWUP", "REFERENCE_RECONCILIATION_REQUIRED", "DIRTY_REFERENCE_UNRECONCILED"].includes(normalized)) tone = "warn";
  const badge = node("span", `state ${tone}`, normalized.replaceAll("_", " "));
  if (kind) badge.dataset.kind = kind;
  return badge;
}

function countText(value, suffix = "") {
  return value === null || value === undefined ? "UNKNOWN" : `${value}${suffix}`;
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
  const raw = decodeURIComponent(location.hash.slice(1) || "portfolio");
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
  $("#active-wave").textContent = project.lifecycle.active_wave_id || "—";
  $("#active-phase").textContent = project.lifecycle.phase || "UNKNOWN";
  const phase = project.lifecycle.phase || "UNKNOWN";
  const phasePill = $("#lifecycle-pill");
  phasePill.textContent = phase.toUpperCase();
  phasePill.className = `pill ${phase === "done" ? "" : phase === "UNKNOWN" ? "warn" : ""}`;
  const mission = status.mission;
  $("#mission-line").textContent = mission.availability === "unavailable"
    ? "Mission state unavailable"
    : `${mission.id || "Mission"} · ${mission.status || "UNKNOWN"}`;

  const targets = status.project.active_targets.items;
  const targetList = $("#target-list");
  clear(targetList);
  $("#target-state").textContent = targets.length ? "ACTIVE TARGET AUTHORITY" : "REFERENCE UNKNOWN";
  if (!targets.length) targetList.append(node("div", "target-unknown", "REFERENCE UNKNOWN · No canonical ACTIVE_TARGET reference available"));
  else for (const target of targets) targetList.append(targetCard(target));
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
    stateLabel.textContent = "RECONCILIATION UNKNOWN";
    facts.append(empty("Project reconciliation state unavailable"));
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
    ["BLOCKERS", status.mission.blocker_count],
    ["BLOCKING FINDINGS", status.findings.blocking],
    ["BLOCKED BY DECISION", status.decisions.blocked_by_decision.count],
    ["PENDING DECISIONS", status.decisions.status_counts.PROPOSED],
    ["STALE EVIDENCE", status.verification.evidence.current_counts.stale],
    ["MODEL FRESHNESS", status.verification.evidence.model_freshness.toUpperCase()],
  ];
  if (status.reconciliation?.model_semantic_review?.status === "SEMANTIC_REVIEW_REQUIRED") {
    values.push(["MENDIX MODEL REVIEW", status.reconciliation.model_semantic_review.reason || "SEMANTIC_REVIEW_REQUIRED"]);
  }
  for (const [label, value] of values) {
    const chip = node("span", "attention-chip");
    chip.append(node("b", "", countText(value)));
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
    ["WAVES COMPLETE", countText(waves.done)],
    ["ACTIVE MISSION", status.mission.status || "UNKNOWN"],
    ["OPEN FINDINGS", countText(status.findings.open)],
    ["MODEL FRESHNESS", status.verification.evidence.model_freshness.toUpperCase()],
  ];
  for (const [label, value] of values) {
    const box = node("div", "metric");
    box.append(node("div", "metric-label", label));
    box.append(node("div", "metric-value", value));
    container.append(box);
  }
}

function renderOverview() {
  root.append(sectionTitle("Delivery at a glance", "Objective counts · no weighted progress"));
  const grid = node("div", "two-column");
  const wavesSection = node("section", "plain-section");
  wavesSection.append(node("h3", "", "Waves"));
  const wavesList = node("div", "plain-list");
  for (const wave of status.delivery.waves.items) {
    const row = node("div", "plain-item");
    const main = node("div", "item-main");
    main.append(internalLink(wave.wave_id, `wave/${encodeURIComponent(wave.wave_id)}`));
    main.append(node("small", "", `${wave.task_progress.total ?? "UNKNOWN"} tasks · ${wave.checklist_progress.availability === "available" ? `${wave.checklist_progress.done}/${wave.checklist_progress.total} checklist` : "checklist UNKNOWN"}`));
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
    ["Model freshness", evidence.model_freshness],
    ["Target stale", evidence.current_counts.stale],
    ["Unverified", evidence.current_counts.unverified],
    ["Failed", evidence.current_counts.failed],
  ]) {
    const row = node("div", "plain-item");
    row.append(node("div", "item-main", label), stateBadge(value === null ? "UNKNOWN" : value));
    evidenceList.append(row);
  }
  rightSection.append(evidenceList);
  grid.append(wavesSection, rightSection);
  root.append(grid);

  root.append(sectionTitle("Requirements", `${status.requirements.total ?? "UNKNOWN"} total`));
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
    ["VERIFICATION ATTENTION", `STALE ${countText(verification.stale)} · FAILED ${countText(verification.failed)} · MODEL ${status.verification.evidence.model_freshness.toUpperCase()}`],
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
  for (const label of ["Requirement", "Status", "Wave / Workpackage", "Source"]) header.append(node("th", "", label));
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
    const assignCell = node("td", "count-pair", assignments.length ? assignments.join(", ") : "UNMAPPED");
    const sourceCell = document.createElement("td");
    sourceCell.append(sourceLink("requirement", req.id));
    row.append(idCell, statusCell, assignCell, sourceCell);
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
  banner.append(node("div", "attention-items", evidence.model_freshness.toUpperCase()));
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
      ["IMPLEMENTATION", page.implementation_mode],
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
      actions.append(node("span", "state warn", "HTML source unavailable"));
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
    root.append(node("h3", "plain-section", "Evidence freshness"), stateBadge(status.verification.evidence.model_freshness.toUpperCase()));
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
    root.append(sourceLink("requirement", requirement.id));
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
  clear(root);
  renderCompatibility();
  const parts = routeParts();
  const view = parts[0] || "overview";
  const isPortfolio = view === "portfolio";
  $("#project-context").hidden = isPortfolio;
  $("#tabs").hidden = isPortfolio;
  for (const button of document.querySelectorAll("[data-route]")) {
    const buttonRoute = button.dataset.route;
    button.classList.toggle("active", buttonRoute === view || (view === "requirement" && buttonRoute === "requirements") || (["wave", "workpackage"].includes(view) && buttonRoute === "waves") || (view === "finding" && buttonRoute === "findings") || (view === "decision" && buttonRoute === "decisions"));
  }
  if (isPortfolio) renderPortfolio();
  else if (view === "overview") renderOverview();
  else if (view === "waves") renderWaves();
  else if (view === "requirements") renderRequirements();
  else if (view === "verification") renderVerification();
  else if (view === "gallery") renderGallery();
  else if (view === "ui-pages") renderUiPages();
  else if (view === "page") renderGallery(parts[1]);
  else if (view === "findings") renderFindings();
  else if (view === "decisions") renderDecisions();
  else renderDetail(parts);
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

async function load() {
  const button = $("#refresh");
  button.disabled = true;
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error("Status unavailable");
    status = await response.json();
    renderHeader();
    renderAttention();
    renderMetrics();
    $("#load-state").hidden = true;
    $("#board").hidden = false;
    renderView();
    $("#updated-label").textContent = `READ ${new Date().toLocaleTimeString()}`;
    void loadReconciliation();
  } catch {
    $("#load-state").textContent = "Project status unavailable. The board did not infer missing state.";
  } finally {
    button.disabled = false;
  }
}

document.addEventListener("click", (event) => {
  const routeButton = event.target.closest("[data-route]");
  if (routeButton) navigate(routeButton.dataset.route);
});
window.addEventListener("hashchange", () => { if (status) renderView(); });
$("#refresh").addEventListener("click", load);
load();