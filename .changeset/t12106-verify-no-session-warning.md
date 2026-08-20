---
id: t12106-verify-no-session-warning
tasks: [T12106]
kind: fix
summary: "cleo verify without an active session now warns via the envelope diagnostics channel, and complete's session error names the remedy and confirms gates are preserved"
---

gh#1194: verify intentionally accepts evidence session-free (crash-recovery re-attestation), but nothing signalled that complete would then refuse with E_CLEO_SESSION_REQUIRED — agents re-checked gate state thinking the evidence was at fault. Verify now emits a W_NO_ACTIVE_SESSION warning through the canonical meta.warnings[] channel (stdout JSON stays pure), and complete's session error names `cleo session start` and states recorded gates do not need re-verification.
