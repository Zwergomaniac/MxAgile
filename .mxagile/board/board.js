"use strict";

const $ = (selector) => document.querySelector(selector);
const root = $("#view");
const tabs = ["overview", "waves", "requirements", "verification", "findings", "decisions"];
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
  else if (["blocked", "failed", "FAIL", "STALE", "DECISION_REQUIRED", "CRITICAL", "ambiguous", "mismatch"].includes(normalized)) tone = "bad";
  else if (["PROPOSED", "PARTIAL", "partial", "unknown", "UNKNOWN"].includes(normalized)) tone = "warn";
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
  const title = target.mockup_name || target.revision_id || "Reference";
  meta.append(node("strong", "", title));
  meta.append(node("div", "target-file", `${target.revision_id || "NO REVISION"} · ${pathLabel(target.canonical_path)}`));
  const fingerprint = target.bundle_hash || target.content_hash || target.source_fingerprint;
  meta.append(node("div", "target-fingerprint", fingerprint ? `FINGERPRINT  ${fingerprint.slice(0, 19)}…` : "FINGERPRINT  UNKNOWN"));
  const authority = node("div", "target-fingerprint", `AUTHORITY  ${target.authoritative_state || "UNKNOWN"} · ${target.availability.toUpperCase()}`);
  meta.append(authority);
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

function renderFindings() {
  root.append(sectionTitle("Findings", `${countText(status.findings.open)} open · ${countText(status.findings.blocking)} blocking`));
  if (!status.findings.items.length) {
    root.append(empty(status.findings.availability === "unavailable" ? "Canonical Finding records unavailable" : "No Findings"));
    return;
  }
  const list = node("div", "plain-list");
  for (const finding of status.findings.items) {
    const row = node("article", `plain-item ${finding.blocking ? "blocking" : ""}`);
    const main = node("div", "item-main");
    main.append(internalLink(`${finding.id} · ${finding.title}`, `finding/${encodeURIComponent(finding.id)}`));
    main.append(node("small", "", `${finding.gap_type || "UNKNOWN TYPE"} · ${finding.wave_id || "NO WAVE"} · ${finding.workpackage_id || "NO WORKPACKAGE"}`));
    row.append(main, stateBadge(finding.lifecycle_status || "UNKNOWN"));
    list.append(row);
  }
  root.append(list);
}

function renderDecisions() {
  root.append(sectionTitle("Decisions", `${status.decisions.status_counts.PROPOSED ?? "UNKNOWN"} proposed · ${status.decisions.blocked_by_decision.count ?? "UNKNOWN"} blocking`));
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
    facts.append(countItem("MISSION BLOCKERS", status.mission.status === "blocked" ? status.mission.blocker_count : 0, status.mission.availability));
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
    const finding = status.findings.items.find((item) => item.id === id);
    if (!finding) return root.append(empty("Finding unavailable"));
    root.append(sectionTitle(`${finding.id} · ${finding.title}`, finding.lifecycle_status || "UNKNOWN"));
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
  else if (view === "findings") renderFindings();
  else if (view === "decisions") renderDecisions();
  else renderDetail(parts);
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