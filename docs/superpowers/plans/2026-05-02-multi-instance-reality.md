# Multi-Instance Reality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork the stable single-instance script into `sbox-deploy-tool` and add an isolated multi-instance Reality subsystem without breaking the legacy install flows.

**Architecture:** Preserve the copied single-instance menus and configuration model, then add a dedicated `19.多实例Reality` management entry that writes separate instance-suffixed config fragments for the currently installed core. Use current-core-only management to avoid the higher-risk dual-core refactor.

**Tech Stack:** Bash, jq, Xray-core, sing-box, systemd/OpenRC service restart flow

---

### Task 1: Replace repo contents with the stable baseline

**Files:**
- Modify: `/Users/dodo258/sbox-deploy-tool/README.md`
- Modify: `/Users/dodo258/sbox-deploy-tool/install.sh`
- Modify: `/Users/dodo258/sbox-deploy-tool/shell/install_en.sh`

- [x] Copy the stable `dodo258-v2ray-agent` workspace into `sbox-deploy-tool` while preserving the target repo `.git`.
- [x] Update project URLs and self-update targets to `dodo258/sbox-deploy-tool`.
- [x] Bump version strings for the new repo branch.

### Task 2: Add a dedicated multi-instance Reality subsystem

**Files:**
- Modify: `/Users/dodo258/sbox-deploy-tool/install.sh`

- [x] Add multi-instance file discovery and node selection helpers.
- [x] Add current-core-only deploy/list/show-account/add-user/remove-user/delete-node actions.
- [x] Generate separate instance-suffixed config files for Xray and sing-box Reality nodes.

### Task 3: Wire the feature into the existing UX

**Files:**
- Modify: `/Users/dodo258/sbox-deploy-tool/install.sh`
- Modify: `/Users/dodo258/sbox-deploy-tool/README.md`
- Create: `/Users/dodo258/sbox-deploy-tool/documents/multi_instance_reality.md`

- [x] Add menu entry `19.多实例Reality`.
- [x] Clarify that `12.添加新端口` is only an extra entry port, not a new node.
- [x] Document the multi-instance scope and usage.

### Task 4: Validate and prepare for publish

**Files:**
- Modify: `/Users/dodo258/sbox-deploy-tool/install.sh`
- Modify: `/Users/dodo258/sbox-deploy-tool/README.md`
- Modify: `/Users/dodo258/sbox-deploy-tool/shell/install_en.sh`

- [ ] Run shell syntax checks.
- [ ] Run diff hygiene checks.
- [ ] Review repo status, commit, and push.
