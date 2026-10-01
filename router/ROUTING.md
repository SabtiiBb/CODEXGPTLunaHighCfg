<!-- CODEX_AUTOROUTER_V4_START -->
# Codex model routing V4.1

Keep the session's selected model and effort. Respect explicit user preferences and
host restrictions. Instructions cannot switch the primary model mid-session.
Choose a suitable available specialist only when delegation adds value.

- Keep trivial and already-understood work in the primary; do not delegate to save
  tokens when spawning and repeating context would cost more than finishing locally.
- Prefer efficient_worker (GPT-6 Luna / high when available) for bounded implementation
  and efficient_max_worker (Luna / max) for precise work needing deeper reasoning.
- Use advanced_medium or advanced_high (latest Sol, including GPT-6.1 Sol) for
  integration and judgment beyond Luna. Use deep_architect / deep_max_architect for
  ambiguous root causes, concurrency, architecture, or substantial regression risk.
- Use frontier_architect (Astra / high), frontier_xhigh or frontier_max_architect only
  when substantial uncertainty or stakes justify it. Ultra is exceptional and only
  valid when advertised by this host. Do not follow a mandatory escalation ladder.
- Terra remains available as balanced_* when the host offers it. Do not assume a
  legacy model is cheaper or preferable merely from catalog order or version.

The efficient_*, advanced_*, balanced_* and frontier_* roles expose each supported
reasoning effort. For an exact version use model_<normalized_slug>_<effort>, e.g.
model_gpt_6_luna_high, model_gpt_6_luna_max, model_gpt_6_1_sol_high.
Only use roles actually offered by the host. Do not invent IDs or effort levels.
Use none/minimal/low only for simple bounded tasks when supported; medium/high for
normal analysis; xhigh/max for justified depth. More reasoning is not always better.

Use one specialist by default, at most two independent child workstreams. Give each
ownership, acceptance criteria and a compact handoff of evidence already gathered.
Do not copy full conversation history when a short task description suffices.
Reuse agents for follow-up work. Preserve others' edits. Do not delegate recursively.
If blocked, report the concrete missing evidence; do not retry the same approach or
upgrade models repeatedly without a new reason. The primary verifies the final result.
Build and run relevant checks for executable changes; avoid redundant broad tests.

This is a delegation policy, not a billing optimizer or an external per-message router.
It cannot guarantee token savings. Current fallback suggestion: {{PRIMARY}}.
The updater preserves existing primary preferences. Full mappings are maintained in
$CODEX_HOME/autorouter/MODELOS.md and agents/*.toml; consult only relevant entries.
<!-- CODEX_AUTOROUTER_V4_END -->