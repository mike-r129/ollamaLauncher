# ollamaLauncher Restructure Plan

## Purpose

The original project goal was a very small `.bat` plus `.ps1` helper combo. The launcher now has enough responsibilities that the current shape is becoming hard to maintain:

- first-run setup and file copying
- Ollama install detection and download flow
- installed model listing, running, pulling, and removing
- online repository fetching and parsing
- repository config and trust handling
- tag/variant fetching
- hardware detection and model-fit filtering
- context-length persistence and Ollama restart flow
- interactive selector UIs
- cache and state file management

The restructure should keep the launcher lightweight for users while making the codebase easier to change, test, and package.

## Recommendation: Install Location and AppData

Do not keep expanding the current pattern of moving executable project files into `%APPDATA%\ollamaLauncher` on first run.

Use AppData for user data, not application code:

- `%APPDATA%\ollamaLauncher` for roaming user settings such as `repos.json`, `state.txt`, `trusted_hosts.txt`, and `context.txt`.
- `%LOCALAPPDATA%\ollamaLauncher\Cache` for model-list caches, hardware cache, selector temp output, and other generated files that do not need to roam.
- `%LOCALAPPDATA%\Programs\ollamaLauncher` as the default per-user install directory for application files when we add an installer.
- `%ProgramFiles%\ollamaLauncher` only as an optional all-users install target, because it requires admin rights and complicates updates.

For now, keep a portable mode where users can run the launcher from any folder. The launcher should resolve helper scripts relative to its own install/root directory and should not delete source files after copying them.

Short version:

- App files: repo folder in portable mode, `%LOCALAPPDATA%\Programs\ollamaLauncher` in installed mode.
- User config/state: `%APPDATA%\ollamaLauncher`.
- Cache/temp output: `%LOCALAPPDATA%\ollamaLauncher\Cache` or `%TEMP%` for truly disposable files.

This preserves the simple-user story without treating `%APPDATA%` as a hidden install directory.

## Proposed Target Layout

```text
ollamaLauncher.bat
src/
  OllamaLauncher.ps1
  OllamaLauncher/
    Paths.psm1
    Config.psm1
    OllamaCli.psm1
    RepositoryConfig.psm1
    RepositoryFetch.psm1
    RepositoryParse.psm1
    ModelCatalog.psm1
    Hardware.psm1
    Context.psm1
    Trust.psm1
    Cache.psm1
    Ui.psm1
    Selectors/
      ModelSelector.ps1
      LocalSelector.ps1
      ContextSelector.ps1
config/
  repos.default.json
scripts/
  Install.ps1
  Uninstall.ps1
  SmokeTest.ps1
tests/
README.md
RESTRUCTURE_PLAN.md
```

The `.bat` file should eventually become a tiny compatibility shim:

```bat
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\OllamaLauncher.ps1" %*
```

PowerShell should become the main implementation language for the launcher. Batch can remain only for double-click convenience and compatibility.

## Module Boundaries

### Paths.psm1

Own all path decisions:

- app root detection
- portable vs installed mode
- config directory
- cache directory
- temp/result files
- migration from old `%APPDATA%\ollamaLauncher` script copies

No other module should hard-code `%APPDATA%`, `%TEMP%`, or `%LOCALAPPDATA%`.

### Config.psm1

Load, validate, and save launcher settings:

- context length
- selected repository
- trusted hosts
- user preferences

This module should hide the current loose `state.txt`, `context.txt`, and similar file details behind functions.

### RepositoryConfig.psm1

Own `repos.json`:

- materialize defaults from `config/repos.default.json`
- validate schema
- list repositories
- expose sort fields and repo metadata
- migrate older repo config versions

### RepositoryFetch.psm1

Own network requests and pagination:

- HTML and JSON fetches
- cursor/page/offset pagination
- request limits and safety caps
- cache refresh decisions

### RepositoryParse.psm1

Own extracting model data from repository responses:

- regex helpers
- JSON path helpers
- template expansion
- tag and variant expansion
- size and parameter extraction

### ModelCatalog.psm1

Own local model and catalog operations:

- list installed Ollama models
- merge installed status into remote lists
- sort/filter/search model rows
- prepare selector input rows
- validate pull targets

### OllamaCli.psm1

Own process-level interaction with Ollama:

- detect `ollama` on PATH
- launch Ollama app/server
- run model
- pull model
- remove model
- restart Ollama after context changes

### Hardware.psm1

Own hardware detection and compatibility scoring:

- VRAM
- RAM
- available model disk path space
- model-fit color/tier
- hardware cache refresh

### Context.psm1

Own context length behavior:

- load/save selected context length
- validate context input
- calculate memory impact
- coordinate Ollama restart needs

### Trust.psm1

Own repository trust:

- trusted host file
- host prompts
- validation before pulling from non-default repositories

### Cache.psm1

Own cache file naming, expiration, and safe writes:

- atomic cache refresh
- per-repo cache keys
- tag cache keys
- hardware-filtered cache variants

### Ui.psm1 and Selectors

Own console rendering and interaction:

- main menu
- repository browser
- local model selector
- remote model selector
- context selector
- tag selector

The existing `model_selector.ps1`, `local_selector.ps1`, and `context_selector.ps1` can move into `src/OllamaLauncher/Selectors/` first, then be converted into shared UI helpers later.

## Migration Strategy

### Phase 0: Baseline and Safety

- Create this restructure branch.
- Keep current behavior unchanged while planning.
- Document current entry points and AppData files.
- Add smoke-test commands for the current launcher helpers where possible.
- Decide whether Pester tests are worth adding now or after the first module split.

### Phase 1: Path Centralization

- Add a small `Paths.psm1`.
- Replace hard-coded `%APPDATA%`, `%TEMP%`, and script-copy paths with calls into the path layer.
- Stop deleting local helper scripts after copying.
- Keep compatibility with existing `%APPDATA%\ollamaLauncher` files.
- Move generated caches away from `%TEMP%` where persistence is intended.

Exit criteria:

- Existing launcher still runs from the repo folder.
- Existing user config in `%APPDATA%\ollamaLauncher` is still read.
- No source/helper scripts are deleted on first run.

### Phase 2: PowerShell Entrypoint

- Add `src/OllamaLauncher.ps1` as the real application entry point.
- Reduce `ollamaLauncher.bat` to a thin shim once the PowerShell entry point can cover the normal launch path.
- Move first-run setup into PowerShell.
- Keep all existing menu commands working before moving more logic.

Exit criteria:

- Double-clicking `ollamaLauncher.bat` still works.
- Running `powershell -File src\OllamaLauncher.ps1` works.
- The batch file no longer contains core application logic.

### Phase 3: Split Fetch and Repository Logic

- Move config bootstrap and repo schema handling into `RepositoryConfig.psm1`.
- Move network and pagination logic into `RepositoryFetch.psm1`.
- Move HTML/JSON extraction helpers into `RepositoryParse.psm1`.
- Keep `fetch_models.ps1` temporarily as a compatibility wrapper around the new modules.

Exit criteria:

- `fetch_models.ps1` command-line switches still work.
- Repository list, model fetch, tag fetch, sort fields, hardware detection, and pull validation still produce the same output shape.

### Phase 4: Split Ollama, Hardware, Context, and Catalog Logic

- Move Ollama process operations into `OllamaCli.psm1`.
- Move hardware detection/scoring into `Hardware.psm1`.
- Move context length persistence and validation into `Context.psm1`.
- Move installed/remote model list operations into `ModelCatalog.psm1`.
- Remove duplicated inline PowerShell sorting/filtering snippets from the batch flow.

Exit criteria:

- Pull, run, remove, context update, and hardware filter still work.
- Sorting/search/filtering can be exercised without going through the interactive menu.

### Phase 5: UI Consolidation

- Move selector scripts under `src/OllamaLauncher/Selectors/`.
- Extract shared rendering helpers into `Ui.psm1`.
- Keep selector input/output contracts stable until the rest of the code is migrated.
- Later, consider replacing file-based selector result handoff with returned objects inside the PowerShell process.

Exit criteria:

- Model selector, tag selector, local selector, and context selector work at existing feature parity.
- Shared console layout code is not duplicated across selector scripts.

### Phase 6: Installer and Packaging

- Add `scripts/Install.ps1`.
- Default install target: `%LOCALAPPDATA%\Programs\ollamaLauncher`.
- Optional all-users target: `%ProgramFiles%\ollamaLauncher`, only when running elevated.
- Add `scripts/Uninstall.ps1`.
- Keep portable mode documented and supported.
- Add a migration/cleanup command that can remove obsolete copied scripts from `%APPDATA%\ollamaLauncher` after user confirmation.

Exit criteria:

- Installed mode and portable mode both work.
- App files are no longer stored under `%APPDATA%`.
- User config and cache survive app updates.

### Phase 7: Tests and Release Hygiene

- Add focused tests around parsing, repo config validation, path resolution, pull-target validation, and hardware-fit scoring.
- Add a smoke test script for non-interactive flows.
- Update README installation docs.
- Replace static README checksums with release-generated checksums or remove them.
- Add a simple release checklist.

## Compatibility Notes

- Preserve `%APPDATA%\ollamaLauncher\repos.json` to avoid breaking customized repositories.
- Preserve `%APPDATA%\ollamaLauncher\trusted_hosts.txt` unless replaced by a migrated settings file.
- Preserve `%APPDATA%\ollamaLauncher\context.txt` or migrate it with a fallback read.
- Do not silently delete old AppData scripts. Offer cleanup after the new install layout is proven.
- Keep `fetch_models.ps1` callable during the transition because the batch launcher currently depends on its switches.

## First Concrete Refactor Candidates

1. Add `Paths.psm1` and make all runtime paths flow through it.
2. Stop `:create_fetch_script` from deleting `fetch_models.ps1` after copying.
3. Move `repos.json` defaults out of `fetch_models.ps1` into `config/repos.default.json`.
4. Create `src/OllamaLauncher.ps1` and have the batch file call it.
5. Convert `fetch_models.ps1` into a thin wrapper around repository modules.

These steps give immediate maintainability gains while keeping the user-facing experience stable.
