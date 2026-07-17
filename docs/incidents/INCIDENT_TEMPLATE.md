# Incident: [Brief Descriptive Title]

**Date:** YYYY-MM-DD
**Severity:** 🟢 Low / 🟡 Medium / 🟠 High / 🔴 Critical
**Status:** 📋 Open / 🔍 Investigating / 🛠️ Resolving / ✅ Resolved / 📦 Archived
**Author:** [Your name]
**Reviewer:** [Peer reviewer name, if applicable]

---

## Executive Summary

**One-liner:** [Single sentence describing what happened and impact]

**Impact:** [Who/what was affected? Users, services, data?]
**Duration:** [Start time] → [End time] ([Total downtime/duration])
**Root Cause:** [Brief statement of the underlying cause]

---

## Timeline

| Time | Event | Details |
|------|-------|---------|
| YYYY-MM-DD HH:MM | 🚨 **Incident Detected** | [How was it discovered? Monitoring, user report, etc.] |
| YYYY-MM-DD HH:MM | 🔍 **Investigation Started** | [Initial diagnosis steps] |
| YYYY-MM-DD HH:MM | 🛠️ **Fix Applied** | [What was done to resolve] |
| YYYY-MM-DD HH:MM | ✅ **Verified Resolved** | [How was resolution verified] |
| YYYY-MM-DD HH:MM | 📦 **Incident Closed** | [Post-incident review completed] |

---

## Impact Analysis

### Affected Services
- [ ] **Service 1** - [Impact description]
- [ ] **Service 2** - [Impact description]
- [ ] **Service 3** - [Impact description]

### Affected Users
- **Internal:** [Which internal teams/users were affected?]
- **External:** [Were external users/customers affected? If so, how many?]
- **User Experience:** [What did users see? Error messages, timeouts, etc.]

### Data Loss/Corruption
- [ ] **No data loss**
- [ ] **Data loss detected** - [Describe extent and recovery status]

### Financial Impact
- **Estimated Cost:** [If applicable - compute resources, SLA credits, etc.]
- **Business Impact:** [Revenue impact, reputation damage, etc.]

---

## Root Cause Analysis

### What Happened?
[Detailed description of the incident sequence]

### Why Did It Happen?
[Technical root cause - be specific]

**Category:**
- [ ] **Human Error** - Configuration mistake, typo, procedural error
- [ ] **System Bug** - Software defect, race condition, edge case
- [ ] **Hardware Failure** - Disk, network, power, etc.
- [ ] **External Dependency** - Third-party service outage, API changes
- [ ] **Capacity Issue** - Ran out of resources (CPU, memory, disk, network)
- [ ] **Security Incident** - Attack, breach, unauthorized access
- [ ] **Other** - [Explain]

### Five Whys Analysis
1. **Why did the incident occur?**
   [Answer]

2. **Why did [that] happen?**
   [Answer]

3. **Why did [that] happen?**
   [Answer]

4. **Why did [that] happen?**
   [Answer]

5. **Why did [that] happen?**
   [Answer - this should reveal the systemic root cause]

---

## Resolution

### Immediate Actions Taken
1. **[Action 1]** - [Time taken] - [Result]
2. **[Action 2]** - [Time taken] - [Result]
3. **[Action 3]** - [Time taken] - [Result]

### Permanent Fix Applied
- [ ] **Code Change** - [PR/commit link]
- [ ] **Configuration Update** - [What was changed]
- [ ] **Process Improvement** - [New procedure]
- [ ] **Infrastructure Change** - [What was modified]
- [ ] **Other** - [Describe]

### Rollback Plan (if applicable)
[Was there a rollback? What was the procedure?]

---

## Prevention Measures

### Short-Term Actions (1-2 weeks)
- [ ] **[Action 1]** - Owner: [Name] - Due: [Date]
- [ ] **[Action 2]** - Owner: [Name] - Due: [Date]

### Long-Term Actions (1-3 months)
- [ ] **[Action 1]** - Owner: [Name] - Due: [Date]
- [ ] **[Action 2]** - Owner: [Name] - Due: [Date]

### Process Changes
- [ ] **Monitoring Enhancement** - [What alerts/checks to add]
- [ ] **Documentation Update** - [What docs need updating]
- [ ] **Training Needs** - [What training would prevent recurrence]
- [ ] **Testing Procedures** - [What tests to add]

### Systemic Improvements
[What broader system changes would prevent this class of incident?]

---

## Lessons Learned

### What Went Well
- ✅ **[Positive outcome 1]** - [Why it worked]
- ✅ **[Positive outcome 2]** - [Why it worked]

### What Could Be Improved
- ❌ **[Issue 1]** - [How to improve next time]
- ❌ **[Issue 2]** - [How to improve next time]

### Knowledge Gaps Identified
- [ ] **[Gap 1]** - [What to learn/document]
- [ ] **[Gap 2]** - [What to learn/document]

---

## Artifacts

### Logs
- **Location:** [Log file paths/links]
- **Relevant Time Range:** [Start] - [End]

### Metrics/Dashboards
- **Grafana:** [Dashboard links]
- **Prometheus:** [Query links]

### Screenshots/Attachments
- [ ] [Attachment 1 description]
- [ ] [Attachment 2 description]

### Related Documents
- [ ] [Document 1 link]
- [ ] [Document 2 link]

---

## Follow-Up Actions

| Action | Owner | Priority | Due Date | Status |
|--------|-------|----------|----------|--------|
| [Action 1] | [Name] | P0/P1/P2/P3 | YYYY-MM-DD | 📋/🔄/✅ |
| [Action 2] | [Name] | P0/P1/P2/P3 | YYYY-MM-DD | 📋/🔄/✅ |
| [Action 3] | [Name] | P0/P1/P2/P3 | YYYY-MM-DD | 📋/🔄/✅ |

---

## Sign-Off

**Incident Commander:** [Name] - **Date:** YYYY-MM-DD
**Technical Lead:** [Name] - **Date:** YYYY-MM-DD
**Communication Lead:** [Name] - **Date:** YYYY-MM-DD (if applicable)

**Post-Incident Review Completed:** ✅ / ⏳
**Review Date:** YYYY-MM-DD
**Attendees:** [List of participants]

---

**Incident Status:** 📦 Archived
**Archive Date:** YYYY-MM-DD
**Next Review Date:** [Date for follow-up check, if applicable]

---

## Template Usage Guide

### How to Use This Template

1. **Copy this template** to a new file in `docs/incidents/YYYY-MM-DD/`
2. **Name the file** descriptively (e.g., `searxng-http-403-errors.md`)
3. **Fill in all sections** as the incident progresses
4. **Update the file** as new information emerges
5. **Archive to incidents/** when resolved

### Filling Guidelines

- **Be specific:** Use exact times, error messages, metrics
- **Be honest:** Document human errors without blame
- **Be thorough:** Include all relevant context for future reference
- **Be timely:** Update the document as the incident evolves
- **Be collaborative:** Get peer review before closing

### Severity Levels

- **🟢 Low:** Minimal impact, workaround available, no user-visible degradation
- **🟡 Medium:** Service degraded for some users, core functionality still works
- **🟠 High:** Major service outage, significant user impact, no workaround
- **🔴 Critical:** Complete service failure, data loss, security breach

### Status Definitions

- **📋 Open:** Incident detected, not yet investigated
- **🔍 Investigating:** Active diagnosis, root cause unknown
- **🛠️ Resolving:** Fix being implemented or rolled back
- **✅ Resolved:** Fix applied, service restored, monitoring normal
- **📦 Archived:** Incident closed, post-mortem complete, no further action

---

**Template Version:** 1.0
**Created:** 2026-03-21
**Last Updated:** 2026-03-21
**Maintained By:** NixOS Cluster Operations Team
