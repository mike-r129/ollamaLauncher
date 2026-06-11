# Bug Fix Session Plan - Deferred Audit Findings (June 2026)

Follow-up session to `CODE_AUDIT.md`. Items A1-A12 were fixed in the audit
session. This session resolves the deferred findings that are fixable without
pulling forward the remaining restructure phases. Each item lists the intended
change and acceptance criteria; statuses are updated as work lands.

## Fix items

### B1. ollama_wrapper.ps1 hides live output; tok/s overlay never functioned - [x] Done

**Problem.** Both pull and run mode redirect ollama's stdout to a cache file and
only replay it after the process exits. Interactive `ollama run` chat is
unusable (the user sees nothing while typing), and `ollama pull` shows no live
progress. The tokens/sec overlay the redirection exists for never triggers:
`ollama pull` reports MB/s (never matches `tokens/sec`), and interactive
`ollama run` only prints rate stats with `/set verbose`, in the format
`eval rate: NN.NN tokens/s`, which the regex also does not match. The feature is
dead weight that breaks the primary flow.

**Fix.** Rewrite the wrapper to stream ollama natively: delegate to
`OllamaCli\Invoke-OllamaPull` / `OllamaCli\Invoke-OllamaRun` (direct `ollama`
fallback when the module is missing so legacy AppData copies keep working),
keep the `-ModelName` / `-ContextLength` / `-Pull` / `-Run` contract and the
`OLLAMA_CONTEXT_LENGTH` handling, propagate ollama's exit code, and print a tip
that `/set verbose` shows token rates inside the session. Remove the dead
monitoring/parse/redirect machinery and the now-orphaned
`Start-OllamaCommandProcess` from `OllamaCli.psm1`. Update the wrapper
integration tests to the new contract.

**Accept when:** wrapper parses, contract tests pass, `-Pull`/`-Run` without a
model name exits 1 with usage text, no `Start-Process`/redirection remains.
This also advances Phase 4: the wrapper now exercises the OllamaCli module.

### B2. `pagination.param` not validated - [x] Done

**Problem.** A repos.json entry with pagination type `page`/`offset` but no
`param` crashes `Invoke-RepoFetch` with a null-key hashtable error instead of a
clear config message.

**Fix.** Validate in `RepositoryConfig\Test-RepositoryConfig`: page/offset
pagination must declare a non-empty `param`. Add a module test.

### B3. Two repos.json materialization paths - [x] Done

**Problem.** `src/OllamaLauncher.ps1` copies `repos.default.json` verbatim while
`RepositoryConfig\Initialize-RepoConfig` materializes it via a JSON round-trip;
two code paths can drift.

**Fix.** Make the entrypoint import `RepositoryConfig.psm1` and call
`Initialize-RepoConfig`. The entrypoint test (repos.json materialized on
`-InitializeOnly`) must keep passing.

### B4. Cache-expiry logic duplicated in the batch - [x] Done

**Problem.** `LegacyLauncher.bat :fetch_list` re-implements the cache age check
as inline PowerShell beside `Cache.psm1\Test-CacheExpired`.

**Fix.** Replace the inline check with an `Import-Module Cache.psm1;
Test-CacheExpired` one-liner so the module is the single source of truth
(degrades to "treat as expired" if the module cannot load). Pin with a batch
contract test.

### B5. README claims MIT license but no LICENSE file exists - [x] Done

**Fix.** Add a standard MIT `LICENSE` file (copyright Mike). Adjust the name in
the copyright line if it should read differently.

## Still deferred (with reasons)

- **Ui.psm1 duplication in selectors.** The batch copies selector scripts to
  `%APPDATA%\ollamaLauncher` as standalone legacy fallbacks; a relative
  `Import-Module ..\Ui.psm1` would break those copies. Consolidate in Phase 5
  when the copy mechanism / file-based handoff is retired.
- **Batch trust/state/context fallback duplication.** Intentional transition
  scaffolding for the same legacy-copy reason; remove when the PowerShell
  bridges become the only path.
- **OllamaCli server-lifecycle functions** (`Start-OllamaServer`,
  `Stop-OllamaProcess`, `Test-OllamaCommand`) remain uncalled - the batch still
  owns serve/restart flows (Phase 4 proper). Partially advanced by B1.
- **`test_agent.py` / `.venv`.** Untracked personal experiment; removal is the
  owner's call.
- **Stale BOM'd caches** from before the A1 fix self-heal on refresh (24h or
  `[R]`), or delete `%LOCALAPPDATA%\ollamaLauncher\Cache` once.

## Execution order & verification

1. B1 (wrapper rewrite + OllamaCli cleanup + test updates)
2. B2 (validation + test), B3 (entrypoint), B4 (batch + test), B5 (LICENSE)
3. Full verification: `scripts\Invoke-Tests.ps1` green, `scripts\SmokeTest.ps1`
   green, wrapper usage-error path checked manually.
