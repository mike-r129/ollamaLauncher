# Code Audit - Post-Restructure (June 2026)

Audit of the `restructure-modules` branch covering technical debt, dead code, and
potential defects introduced or left behind by the module restructure
(see `RESTRUCTURE_PLAN.md`). Each finding has an ID, severity, and a resolution
status. "Fix now" items are executed on this branch; "Deferred" items are
recorded debt that belongs to a later restructure phase or needs a product
decision.

## Summary

| ID  | Severity | Area | Finding | Resolution |
|-----|----------|------|---------|------------|
| A1  | High | Cache.psm1 / fetch_models.ps1 | `Write-AtomicTextFile` writes a UTF-8 BOM; batch `for /f` parsers consume these files raw, so the first line of `repos_list.txt`, model caches, tag caches, and `hardware.txt` is corrupted (first repo metadata never matches, model #1 / repo #1 selection breaks pull validation) | Fixed |
| A2  | High | Cache.psm1 / fetch_models.ps1 | `Write-AtomicTextFile -Lines` is Mandatory and rejects null/empty: `-ListSortFields` for a repo without sortFields (Ollama) and zero-result fetches crash with a parameter binding error instead of writing an empty file | Fixed |
| A3  | High | LegacyLauncher.bat | `:handle_repository` uses illegal nested delayed expansion `!repo_prefix[!repo_count!]!`, so the `(none)` pull-prefix sentinel is never cleared; after switching to a repo with an empty prefix via the [E] menu every pull target becomes `(none)<model>` and fails safety validation until relaunch | Fixed |
| A4  | Medium | fetch_models.ps1 | Repo-config errors emitted via `Write-Error` are wrapped to console width when stderr is redirected, which breaks callers (and the existing Pester test) matching on the message | Fixed |
| A5  | Medium | LegacyLauncher.bat | `count` is only initialized by the legacy local prompt; in the normal (selector) flow `if !count! equ 0` expands to a malformed `if` and the Cancel path in the model browser misbehaves | Fixed |
| A6  | Medium | LegacyLauncher.bat | `:wait_ollama` and `:wait_ollama_ready_context` poll `http://localhost:11434` forever; if `ollama serve` fails to start the launcher hangs | Fixed (bounded to 60 attempts) |
| A7  | Medium | ModelSelector.ps1 / LegacyLauncher.bat | The selector emits `CMD|U` ([U] Run model) but the batch CMD dispatcher has no `U` mapping, so the key silently does nothing in the arrow-key UI (legacy prompt parity loss) | Fixed |
| A8  | Low | LegacyLauncher.bat | Dead code: `:invalid` block jumps to nonexistent `:prompt` label (would crash if ever reached); write-only config vars `MODELS_PER_FETCH`, `OLLAMA_RUN_TIMEOUT_SECONDS`; vestigial `reached_end` reset; redundant `set "items_per_page=50"` shadowing `ITEMS_PER_PAGE` | Fixed (removed) |
| A9  | Low | RepositoryParse.psm1 | `Expand-RepoTemplate` uses regex `-replace` with unescaped replacement text; field values containing `$` (e.g. `$1`) trigger regex substitution artifacts in descriptions | Fixed (literal string replace) |
| A10 | Low | ollama_wrapper.ps1 | `$Command` parameter is declared and pinned by a contract test but never used by the script or any caller | Fixed (removed from script and test contract) |
| A11 | Low | README.md | Says model list is cached "for 1 hour"; actual `CACHE_EXPIRY_HOURS` is 24 | Fixed |
| A12 | Low | tests | No regression coverage for A1/A2 (BOM-free cache writes, empty-input handling, empty sort-field contract) | Fixed (tests added) |

## Deferred technical debt

Items originally deferred here were triaged again in a follow-up bug-fix
session (`BUGFIX_PLAN.md`). Resolved there:

- **ollama_wrapper.ps1 hides live output / dead tok/s overlay** - wrapper
  rewritten to stream ollama natively and delegate to `OllamaCli` (B1).
- **Cache-expiry logic duplicated** - the batch now calls
  `Cache.psm1\Test-CacheExpired` (B4).
- **Two repos.json materialization paths** - the entrypoint now uses
  `RepositoryConfig\Initialize-RepoConfig` (B3).
- **`pagination.param` not validated** - `Test-RepositoryConfig` now rejects
  page/offset pagination without a `param` name (B2).
- **Missing LICENSE file** - MIT `LICENSE` added (B5).

Still deferred (reasons in `BUGFIX_PLAN.md`):

- **Ui.psm1 is dead at runtime.** `Limit-Text` / `Write-PaddedLine` are duplicated
  privately inside both selectors. Phase 5 (UI consolidation) should make the
  selectors import `Ui.psm1` or fold the helpers in - blocked today because the
  batch copies selectors to `%APPDATA%\ollamaLauncher` as standalone legacy
  fallbacks where a relative module import would break.
- **OllamaCli.psm1 server-lifecycle functions unused.** `Invoke-OllamaPull` /
  `Invoke-OllamaRun` now have a caller (the wrapper), but `Test-OllamaCommand`,
  `Start-OllamaServer`, `Stop-OllamaProcess`, and `Remove-OllamaModel` remain
  the Phase 4 target API; the batch still shells `ollama`/`taskkill` directly.
- **Trust/repo-state fallback duplication.** The batch keeps full fallback
  implementations (`:check_repo_trust`, `:save_repo_state`, context fallbacks)
  beside the `TrustHost.ps1`/`StateValue.ps1`/`ContextValue.ps1` bridges. This is
  intentional transition scaffolding; remove the fallbacks once the bridges are
  the only path.
- **Stray files.** `test_agent.py` (LangChain experiment) and `.venv/` are
  unrelated to the launcher; both are untracked/ignored. `TEST_COVERAGE_PLAN.md`
  is intentionally local per its own commit policy.
- **Stale BOM'd caches.** Files written before the A1 fix still carry a BOM in
  `%LOCALAPPDATA%\ollamaLauncher\Cache`; they self-heal on the next refresh
  (24h expiry or `[R]`), or the user can delete the Cache folder.

## Execution plan

1. `Cache.psm1`: write UTF-8 **without BOM** in `Write-AtomicTextFile`; allow
   null/empty `Lines` (write an empty file). Guard `Write-CacheLines` in
   `fetch_models.ps1` the same way. (A1, A2)
2. `fetch_models.ps1`: emit the repo-config failure on stderr via
   `[Console]::Error.WriteLine` (consistent with `-ValidatePull`). (A4)
3. `LegacyLauncher.bat`: fix the `(none)` sentinel clear in `:handle_repository`;
   initialize `count`; bound both Ollama wait loops; map `CMD|U` to
   `:handle_run_model`; delete the dead `:invalid` block, dead config vars,
   `reached_end`, and the redundant `items_per_page` reassignment. (A3, A5-A8)
4. `RepositoryParse.psm1`: literal-string template expansion. (A9)
5. `ollama_wrapper.ps1` + `tests/static_contracts.Tests.ps1`: drop the unused
   `-Command` parameter and its contract entry. (A10)
6. `README.md`: correct cache-expiry wording. (A11)
7. Tests: add BOM/empty-line regression tests for `Write-AtomicTextFile`; add a
   `-ListSortFields -Repo Ollama` contract test (exit 0, empty file). (A12)
8. Run `scripts\Invoke-Tests.ps1` and `scripts\SmokeTest.ps1`; all tests must
   pass (baseline had 1 pre-existing failure, covered by A4).
