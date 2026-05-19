@echo off
REM ollamaLauncher.bat
REM Version: 1.2 
REM Date: 11/25/2025
REM Author: Mike
REM ============================================================================
REM ollamaLauncher - Interactive CLI for Managing and Running Ollama Models
REM ============================================================================
REM CLI Features:
REM   - List installed Ollama models
REM   - Launch selected models for usage
REM   - Install Ollama if not present
REM   - Install models if not present
REM   - Browse and download new models from the Ollama library
REM   - Navigate through paginated model listings
REM   - fetch_models.ps1 to fetch models from Ollama.com
REM   - ollama-models.txt to cache files for fetched models
REM Associated Files:
REM   - ollamaLauncher.bat : Main launcher batch file script, run this to use the program.
REM   - %APPDATA%\ollamaLauncher\fetch_models.ps1 : PowerShell script to fetch model list from Ollama.com, 
REM     -fetch_models.ps1 gets installed to %APPDATA%\ollamaLauncher\ on first run: 
REM         -if it is in same directory as ollamaLauncher.bat then copy to %APPDATA%\ollamaLauncher\, 
REM   - %TEMP%\ollama-models.txt : Cache file storing fetched model list
REM Requirements:
REM   - Windows OS (Built and tested on Windows 10/11)
REM   - PowerShell (for fetch_models.ps1 script)
REM   - Internet connection (for fetching model list)
REM   - Ollama installed and accessible via PATH, 
REM     - If Ollama is not installed CLI will download it using curl then the install file will need to be manually installed by the user.
REM     - Once Ollama is installed re-launch the script ollamaLauncher.bat
REM ============================================================================
setlocal enabledelayedexpansion
set "OLLAMA_STARTED=0"

REM Use APPDATA for storing fetch_models.ps1 script
set "APPDATA_OLLAMA=%APPDATA%\ollamaLauncher"
set "FETCH_MODELS_SCRIPT=%APPDATA_OLLAMA%\fetch_models.ps1"
set "SELECTOR_SCRIPT=%APPDATA_OLLAMA%\model_selector.ps1"
set "CONTEXT_SELECTOR_SCRIPT=%APPDATA_OLLAMA%\context_selector.ps1"
set "SELECTOR_RESULT=%TEMP%\ollama-selector-result.txt"
set "CONTEXT_SELECTOR_RESULT=%TEMP%\ollama-context-result.txt"
set "REPOS_CONFIG=%APPDATA_OLLAMA%\repos.json"
set "REPOS_LIST=%APPDATA_OLLAMA%\repos_list.txt"
set "REPO_STATE_FILE=%APPDATA_OLLAMA%\state.txt"
set "TRUSTED_HOSTS_FILE=%APPDATA_OLLAMA%\trusted_hosts.txt"
set "HW_CACHE_FILE=%APPDATA_OLLAMA%\hardware.txt"
set "CONTEXT_FILE=%APPDATA_OLLAMA%\context.txt"

REM Detected hardware (populated by :detect_hardware on first :start pass)
set "VRAM_GB=0"
set "RAM_GB=0"
set "DISK_GB=0"
set "OLLAMA_MODELS_PATH="
set "HW_FILTER=0"
set "HW_DETECTED="

REM Context length in tokens (default 4k, user adjustable)
set "CONTEXT_LENGTH=4096"

REM Active model repository (defaults to Ollama, persisted to state file)
set "CURRENT_REPO=Ollama"
set "CURRENT_REPO_TYPE=ollama"
set "CURRENT_REPO_PREFIX="
set "CURRENT_REPO_HOST="

REM Per-repo cache files derived from CURRENT_REPO (set in :load_repo_state)
set "MODELS_CACHE=%TEMP%\ollama-models-Ollama.txt"
set "MODELS_SORTED=%TEMP%\ollama-models-sorted-Ollama.txt"

REM Configurable pagination settings
set "ITEMS_PER_PAGE=50"
set "MODELS_PER_FETCH=100"
set "CACHE_EXPIRY_HOURS=24"
set "OLLAMA_RUN_TIMEOUT_SECONDS=3600"

REM Create APPDATA directory if it doesn't exist
if not exist "%APPDATA_OLLAMA%" mkdir "%APPDATA_OLLAMA%"

REM Create fetch_models.ps1 in APPDATA on first run
call :create_fetch_script
call :create_selector_script

REM Load saved active repo (if any) and ensure repos.json exists
call :load_repo_state

:start
call :load_context_length
set "OLLAMA_CONTEXT_LENGTH=!CONTEXT_LENGTH!"

echo              @@@            @@@              
echo            @@@ @@          @@ @@@            
echo            @@  @@@        @@@  @@            
echo            @@   @@@@@@@@@@@@   @@            
echo            @@   @@@      @@@   @@            
echo            @@@@@@          @@@@@@            
echo          @@@                    @@@          
echo         @@@                      @@@         
echo         @@                        @@         
echo        @@@   @@@  @@@@@@@@  @@@   @@@        
echo         @@    @  @        @  @    @@         
echo          @@     @@   @@   @@     @@          
echo         @@@     @@        @@     @@@     ____  ____                      __                           __             
echo         @@        @@@@@@@@        @@    / __ \/ / /___ _____ ___  ____ _/ /   ____ ___  ______  _____/ /_  ___  _____
echo         @@                        @@   / / / / / / __ `/ __ `__ \/ __ `/ /   / __ `/ / / / __ \/ ___/ __ \/ _ \/ ___/
echo         @@                        @@  / /_/ / / / /_/ / / / / / / /_/ / /___/ /_/ / /_/ / / / / /__/ / / /  __/ /    
echo         @@@                      @@@  \____/_/_/\__,_/_/ /_/ /_/\__,_/_____/\__,_/\__,_/_/ /_/\___/_/ /_/\___/_/ 
echo                                                                                               v1.2 by Mike 11/25/2025
REM Check if Ollama is installed and accessible
where ollama >nul 2>nul
if %errorlevel% neq 0 (
    REM Ollama not found - offer to download installer
    echo.
    echo Error: 'ollama' command not found.
    echo.
    set /p install_ollama="Would you like to download the latest version of Ollama? (Y/N): "
    if /i "!install_ollama!"=="Y" (
        echo.
        echo Downloading Ollama installer...
        echo.
        curl -L -o "%TEMP%\OllamaSetup.exe" "https://ollama.com/download/OllamaSetup.exe"
        if not exist "%TEMP%\OllamaSetup.exe" (
            echo.
            echo Error: Failed to download Ollama installer.
            echo Please check your internet connection and try again.
            echo You can manually download from: https://ollama.com/download
            echo.
            pause
            goto cleanup
        )
        echo.
        echo Download complete. Opening installer...
        echo.
        start "" "%TEMP%\OllamaSetup.exe"
        echo.
        echo Please complete the installation and then run this script again.
        echo.
        pause
        cls
        goto start
    ) else (
        echo Please ensure Ollama is installed and added to your PATH.
        pause
        goto cleanup
    )
)

REM Check if Ollama is running and start if needed
tasklist /FI "IMAGENAME eq ollama.exe" 2>nul | find /I "ollama.exe" >nul
if !errorlevel! neq 0 (
    echo.
    echo Starting Ollama server...
    start "" /B ollama serve >nul 2>&1
    set "OLLAMA_STARTED=1"
    
    echo Waiting for Ollama to be ready...
    :wait_ollama
    timeout /t 1 /nobreak >nul
    curl -s http://localhost:11434 >nul 2>&1
    if !errorlevel! neq 0 goto wait_ollama
    echo Ollama is ready.
)

REM Detect system hardware once per session for model-fit hints
if not defined HW_DETECTED (
    call :detect_hardware
    set "HW_DETECTED=1"
)

REM Query and store all installed Ollama models
echo Fetching available Ollama models...
echo   0. Update/Pull a new model
echo.
set "LOCAL_MODELS_LIST=%TEMP%\ollama-local-list.txt"REM Use PowerShell script to list, parse, and display local models with details
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -Local -CacheFile "%LOCAL_MODELS_LIST%"

if %errorlevel% neq 0 (
    echo.
    echo No local models found. You can browse and install models from the Ollama library.
    echo.
    set /p continue="Would you like to browse available models? (Y/N): "
    if /i "!continue!"=="Y" (
        goto fetch_list
    ) else if /i "!continue!"=="0" (
        goto fetch_list
    ) else (
        echo.
        echo Exiting. Run 'ollama pull model:tag' to install a model, then try again.
        pause
        goto cleanup
    )
)

REM Read the models into the batch array
set count=0
for /f "usebackq delims=" %%a in ("%LOCAL_MODELS_LIST%") do (
    set /a count+=1
    set "model[!count!]=%%a"
)

echo. 
echo [0/U] Update/Pull a new Model   [E] Repository (!CURRENT_REPO!)   [R] Remove a model   [L] Exit CLI ^& Start Ollama.exe   [X] Exit
echo.
:prompt
set "choice="
set /p choice="Enter the number or model name for the model you want to use (r to remove, or 0 / u to pull a new one): "

REM Strip trailing period if present
if "%choice:~-1%"=="." set "choice=%choice:~0,-1%"

if /i "%choice%"=="x" goto cleanup
if /i "%choice%"=="exit" goto cleanup
if /i "%choice%"=="R" goto remove_model
if /i "%choice%"=="L" goto launch_ollama
if /i "%choice%"=="u" goto fetch_list
if /i "%choice%"=="e" goto main_repository
if "%choice%"=="" goto invalid

REM Validate user input: check if numeric
set "is_numeric=true"
for /f "delims=0123456789" %%a in ("%choice%") do set "is_numeric=false"

if "%is_numeric%"=="true" (
    REM User entered a number
    if %choice% LSS 0 goto invalid
    if %choice% GTR %count% goto invalid
    
    REM Option 0: Browse/fetch new models
    if "%choice%"=="0" goto fetch_list
    
    REM Get the model name by index
    set "selected_model=!model[%choice%]!"
) else (
    REM User entered a model name directly - validate it exists
    set "model_found=false"
    for /L %%i in (1,1,!count!) do (
        if /i "!model[%%i]!"=="!choice!" (
            set "model_found=true"
            set "selected_model=!model[%%i]!"
        )
    )
    
    if "!model_found!"=="false" (
        echo.
        echo Error: Model '!choice!' not found in the installed models list.
        echo Please enter a valid model number or name from the list.
        echo.
        goto prompt
    )
)

REM Run selected model with Ollama
echo.
echo Launching !selected_model!...
echo.
REM Note: Timeout of %OLLAMA_RUN_TIMEOUT_SECONDS% seconds can be enforced via firewall rules or job object limits
REM Users can interrupt with Ctrl+C if needed
set "OLLAMA_CONTEXT_LENGTH=!CONTEXT_LENGTH!"
echo Context length: !CONTEXT_LENGTH! tokens
ollama run "!selected_model!"
if %errorlevel% neq 0 (
    echo.
    echo Error encountered launching model '!selected_model!'.
    
    if "!is_numeric!"=="true" (
        echo.
        set /p remove_broken="Would you like to remove this broken model? (Y/N): "
        if /i "!remove_broken!"=="Y" (
            echo Removing !selected_model!...
            ollama rm !selected_model!
            if !errorlevel! neq 0 (
                echo Failed to remove model.
            ) else (
                echo Model removed successfully.
            )
        )
    ) else (
        echo.
        echo The model '!selected_model!' could not be found or failed to run.
        echo Please check the name and try again.
    )
    
    echo Returning to menu...
    pause
    cls
    goto start
)
echo.
echo Session ended.
pause
cls
goto start

:launch_ollama
echo.
echo Launching Ollama...

if exist "%LOCALAPPDATA%\Programs\Ollama\Ollama app.exe" (
    REM If we started the internal server, stop it so the Tray App can take over
    if "!OLLAMA_STARTED!"=="1" (
        taskkill /F /IM ollama.exe >nul 2>&1
        set "OLLAMA_STARTED=0"
    )
    start "" "%LOCALAPPDATA%\Programs\Ollama\Ollama app.exe"
    
    echo Waiting for Ollama window to appear...
    timeout /t 2 /nobreak >nul
    
    REM Close the Ollama chat window but keep the tray icon running
    powershell -NoProfile -Command "$proc = Get-Process | Where-Object {$_.MainWindowTitle -eq 'Ollama'}; if($proc) { $proc.CloseMainWindow() }"
    
    echo Ollama is now running in the system tray.
    timeout /t 1 /nobreak >nul
) else (
    REM No Tray App found.
    if "!OLLAMA_STARTED!"=="1" (
        REM We are running a hidden server. Switch to minimized window.
        taskkill /F /IM ollama.exe >nul 2>&1
        start "" /MIN ollama serve
        set "OLLAMA_STARTED=0"
    ) else (
        REM Already running externally.
        echo Ollama is already running externally.
        timeout /t 2 /nobreak >nul
    )
)
goto cleanup

:remove_model
echo.
set /p remove_choice="Enter the number for the model to remove (or C to cancel): "

REM Strip trailing period if present
if "%remove_choice:~-1%"=="." set "remove_choice=%remove_choice:~0,-1%"

if /i "%remove_choice%"=="C" goto start

REM Validate input
set "is_numeric=true"
for /f "delims=0123456789" %%a in ("%remove_choice%") do set "is_numeric=false"

if "%is_numeric%"=="false" (
    echo Invalid selection. Please enter a number.
    goto remove_model
)

if %remove_choice% LSS 1 (
    echo Invalid selection.
    goto remove_model
)
if %remove_choice% GTR %count% (
    echo Invalid selection.
    goto remove_model
)

set "model_to_remove=!model[%remove_choice%]!"

echo.
set /p confirm="Are you sure you want to remove !model_to_remove!? (Y/N): "
if /i "!confirm!"=="Y" (
    echo.
    echo Removing !model_to_remove!...
    ollama rm "!model_to_remove!"
    if !errorlevel! neq 0 (
        echo.
        echo Error: Failed to remove model.
        echo Possible causes:
        echo   - Model does not exist
        echo   - Model is currently in use
        echo   - Permission denied
        pause
    ) else (
        echo.
        echo Model removed successfully.
        timeout /t 2 /nobreak >nul
    )
)
cls
goto start

:invalid
echo.
echo Invalid selection. Please enter a valid number or model name.
echo.
timeout /t 2 /nobreak >nul
goto prompt

:fetch_list
REM Fetch online models from Ollama library
REM Always fetch fresh models to ensure latest catalog (unless cache was just created)
REM In HW compat mode, expand each base into hardware-fitting tags (-ExpandTags).
set "FETCH_EXTRA_ARGS="
set "FETCH_LABEL=top 100 models"
if "!HW_COMPAT_MODE!"=="1" (
    set "FETCH_EXTRA_ARGS=-ExpandTags"
    set "FETCH_LABEL=hardware-compatible tag variants"
)
if not exist "%MODELS_CACHE%" (
    REM Fetch top 100 models from the active repository using PowerShell script
    echo.
    echo Fetching latest !FETCH_LABEL! from !CURRENT_REPO!...
    powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -CacheFile "%MODELS_CACHE%" -Repo "!CURRENT_REPO!" !FETCH_EXTRA_ARGS!
    
    if not exist "%MODELS_CACHE%" (
        echo.
        echo Error: Failed to fetch models. models.txt was not created.
        echo.
        pause
        goto start
    )
) else (
    REM Check if cache is older than CACHE_EXPIRY_HOURS
    powershell -NoProfile -Command "if ((Get-Date) - (Get-Item '%MODELS_CACHE%').LastWriteTime -gt (New-TimeSpan -Hours %CACHE_EXPIRY_HOURS%)) { exit 1 } else { exit 0 }"
    
    if !errorlevel! neq 0 (
        echo.
        echo Cache is older than %CACHE_EXPIRY_HOURS% hours. Refreshing !FETCH_LABEL! from !CURRENT_REPO!...
        REM Fetch to temporary file first to avoid losing old cache if fetch fails
        powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -CacheFile "%MODELS_CACHE%.tmp" -Repo "!CURRENT_REPO!" !FETCH_EXTRA_ARGS!
        
        if exist "%MODELS_CACHE%.tmp" (
            move /Y "%MODELS_CACHE%.tmp" "%MODELS_CACHE%" >nul
            echo Cache updated successfully.
        ) else (
            echo.
            echo Warning: Failed to fetch fresh models. Using existing cache.
            echo The cache file may be outdated. Check your internet connection.
            echo.
            timeout /t 2 /nobreak >nul
        )
    ) else (
        echo.
        echo Using cached model list, enter [R] to re-pull and refresh.
    )
)

REM Initialize sort settings if not set
if "%SORT_MODE%"=="" (
    set "SORT_MODE=DEFAULT"
    set "SORT_DESC=0"
    set "SEARCH_TERM="
)

REM Apply sort and load models
call :apply_sort

set "page=1"
set "items_per_page=50"
if not defined SEL_INDEX set "SEL_INDEX=1"

:show_models_page
call :load_context_length
set "OLLAMA_CONTEXT_LENGTH=!CONTEXT_LENGTH!"

REM Calculate total pages needed for pagination
set /a total_pages=(remote_count + items_per_page - 1) / items_per_page
if !total_pages! lss 1 set "total_pages=1"

set "hw_filter_label=OFF"
if "!HW_FILTER!"=="1" set "hw_filter_label=ON (showing compatible tags)"

set "sort_info=Default"
if "!SORT_MODE!"=="SIZE" (
    if "!SORT_DESC!"=="1" (set "sort_info=Size (Desc)") else (set "sort_info=Size (Asc)")
)
if "!SORT_MODE!"=="BEST" (
    set "sort_info=Best Fit"
)
if "!SORT_MODE!"=="FIELD" (
    if "!SORT_DESC!"=="1" (set "sort_info=!SORT_FIELD_NAME! (Desc)") else (set "sort_info=!SORT_FIELD_NAME! (Asc)")
)

REM Clamp SEL_INDEX into current page's range so the highlight stays valid
set /a _pg_start=(page-1)*items_per_page+1
set /a _pg_end=page*items_per_page
if !_pg_end! gtr !remote_count! set /a _pg_end=remote_count
if !SEL_INDEX! lss !_pg_start! set "SEL_INDEX=!_pg_start!"
if !SEL_INDEX! gtr !_pg_end!   set "SEL_INDEX=!_pg_end!"
if !remote_count! equ 0 set "SEL_INDEX=0"

if exist "%SELECTOR_RESULT%" del "%SELECTOR_RESULT%" >nul 2>&1

REM Keep the title in sync with the context passed to the selector.
title ollamaLauncher - Models (Context: !CONTEXT_LENGTH! tokens)

REM Pass context via env var to avoid PowerShell parameter binding issues
set "OLLAMA_LAUNCHER_CTX=!CONTEXT_LENGTH!"

set "ACTIVE_SELECTOR_SCRIPT=%SELECTOR_SCRIPT%"
if exist "%~dp0model_selector.ps1" set "ACTIVE_SELECTOR_SCRIPT=%~dp0model_selector.ps1"

REM Fallback to legacy prompt if the selector script is missing
if not exist "!ACTIVE_SELECTOR_SCRIPT!" goto legacy_prompt

powershell -NoProfile -ExecutionPolicy Bypass -File "!ACTIVE_SELECTOR_SCRIPT!" ^
    -SortedFile "%MODELS_SORTED%" -LocalFile "%LOCAL_MODELS_LIST%" ^
    -Page !page! -PerPage !items_per_page! -TotalPages !total_pages! ^
    -SelIndex !SEL_INDEX! -Repo "!CURRENT_REPO!" -SearchTerm "!SEARCH_TERM!" ^
    -SortInfo "!sort_info!" -HwFilterLabel "!hw_filter_label!" ^
    -VramGb "!VRAM_GB!" -RamGb "!RAM_GB!" -DiskGb "!DISK_GB!" ^
    -ContextLength "!CONTEXT_LENGTH!" ^
    -HasTags "!CURRENT_REPO_HASTAGS!" ^
    -ResultFile "%SELECTOR_RESULT%"

if not exist "%SELECTOR_RESULT%" goto show_models_page

set "sel_action="
set "sel_arg="
REM Result file: line 1 = ACTION[|ARG]; line 2 = SEL_INDEX=<n>; optional line 3 = PAGE=<n>
for /f "usebackq tokens=1,* delims=|" %%a in ("%SELECTOR_RESULT%") do (
    if not defined sel_action (
        set "sel_action=%%a"
        set "sel_arg=%%b"
    )
)
for /f "usebackq tokens=1,2 delims==" %%a in ("%SELECTOR_RESULT%") do (
    if /i "%%a"=="SEL_INDEX" set "SEL_INDEX=%%b"
    if /i "%%a"=="PAGE" set "page=%%b"
)
REM Guard: the SEL_INDEX=... line has no '|' so it could leak in as the action
REM if (somehow) it appeared first. Filter it out.
echo !sel_action! | findstr /b "SEL_INDEX=" >nul && (
    set "sel_action="
    set "sel_arg="
)

if /i "!sel_action!"=="NEXT" goto handle_next_page
if /i "!sel_action!"=="PREV" goto handle_prev_page
if /i "!sel_action!"=="SELECT" (
    set "model_input=!sel_arg!"
    goto handle_selection
)
if /i "!sel_action!"=="EXPAND" (
    set "tag_prefill=!sel_arg!"
    goto handle_show_tags
)
if /i "!sel_action!"=="INPUT" (
    set "model_input=!sel_arg!"
    goto dispatch_input
)
if /i "!sel_action!"=="CMD" (
    if /i "!sel_arg!"=="N" goto handle_next_page
    if /i "!sel_arg!"=="P" goto handle_prev_page
    if /i "!sel_arg!"=="R" goto handle_refresh
    if /i "!sel_arg!"=="E" goto handle_repository
    if /i "!sel_arg!"=="F" goto handle_search
    if /i "!sel_arg!"=="S" goto handle_sort_size
    if /i "!sel_arg!"=="B" goto handle_sort_best
    if /i "!sel_arg!"=="L" goto handle_context_length
    if /i "!sel_arg!"=="I" goto handle_sort_field
    if /i "!sel_arg!"=="D" goto handle_sort_default
    if /i "!sel_arg!"=="A" goto handle_expand_all
    if /i "!sel_arg!"=="H" goto handle_hardware
    if /i "!sel_arg!"=="V" goto handle_show_tags
    if /i "!sel_arg!"=="T" goto handle_expand_all
    if /i "!sel_arg!"=="X" goto cleanup
    if /i "!sel_arg!"=="C" (
        set "model_input=c"
        goto dispatch_input
    )
)
goto show_models_page

:legacy_prompt
echo Using cached model list, enter [R] to re-pull and refresh.
if !count! equ 0 (echo No models found locally. Please select a model to download.) else (echo Select a model to download from the Ollama library.)
echo.
echo Hardware: VRAM=!VRAM_GB!GB  RAM=!RAM_GB!GB  Disk=!DISK_GB!GB   Filter: !hw_filter_label!
echo Legend: [green]=fits VRAM  [yellow]=spills to RAM  [red]=will not fit
echo.
if not "!SEARCH_TERM!"=="" (
    echo Showing Models (Page !page!/!total_pages!^) - Search Results: !SEARCH_TERM!
) else (
    echo Showing Models (Page !page!/!total_pages!^) - Sorted by: !sort_info!
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=!page!; $l=!items_per_page!; $f='%MODELS_SORTED%'; $lf='%LOCAL_MODELS_LIST%'; $s=($p-1)*$l; $installed=@{}; if(Test-Path $lf){Get-Content $lf -Encoding UTF8 | ForEach-Object {$installed[$_]=$true}}; $vram=0.0;[double]::TryParse($env:HW_VRAM,[ref]$vram)|Out-Null; $ram=0.0;[double]::TryParse($env:HW_RAM,[ref]$ram)|Out-Null; $disk=0.0;[double]::TryParse($env:HW_DISK,[ref]$disk)|Out-Null; try{$w=$Host.UI.RawUI.WindowSize.Width}catch{$w=80}; if($w -lt 60){$w=60}; $dw=$w-66; if($dw -lt 5){$dw=5}; Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8} {4,-11}  {5}' -f 'Num','Model Name','Size (GB)','Params','# of Models','Description'); Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8} {4,-11}  {5}' -f ('-'*4),('-'*25),('-'*10),('-'*8),('-'*11),('-'*$dw)); $k=0; Import-Csv $f -Delimiter '|' -Header 'Name','Size','Params','TagCount','Description' -Encoding UTF8 | Select-Object -Skip $s -First $l | ForEach-Object { $k++; $i=$s+$k; $n=$_.Name; if($n.Length -gt 25){$n=$n.Substring(0,22)+'...'}; $d=$_.Description; if($installed.ContainsKey($_.Name)){$d='   [Installed]    '+$d}; if($d.Length -gt $dw){$d=$d.Substring(0,$dw-3)+'...'}; $sz=-1.0; if($_.Size -match '([\d\.]+)\s*GB'){$sz=[double]$matches[1]} elseif($_.Size -match '<\s*1'){$sz=0.5}; $color='Gray'; if($sz -ge 0){ $need=$sz; if($disk -gt 0 -and $sz -gt $disk){$color='Red'} elseif($vram -gt 0 -and $need -le $vram){$color='Green'} elseif($need -le ($vram+$ram)){$color='Yellow'} else {$color='Red'} }; $tc=$_.TagCount; Write-Host ('{0,3}. ' -f $i) -NoNewline; Write-Host ('{0,-25} {1,-10} {2,-8}' -f $n,$_.Size,$_.Params) -ForegroundColor $color -NoNewline; if([string]::IsNullOrEmpty($tc)){ Write-Host (' {0,-11}' -f '') -NoNewline } else { Write-Host (' {0,-11}' -f $tc) -ForegroundColor Cyan -NoNewline }; Write-Host ('  {0}' -f $d) }"

echo.
if not "!SEARCH_TERM!"=="" (
    echo (Page !page!/!total_pages!^) - Search Results: !SEARCH_TERM!  [Repo: !CURRENT_REPO!]
    echo.
    set "nav_line="
    if !page! gtr 1 set "nav_line=[P] Previous    "
    if !page! lss !total_pages! set "nav_line=!nav_line![N] Next Page   "
    set "nav_line=!nav_line![R] Refresh List   [E] Repository"
    echo !nav_line!
    echo [C] Cancel [X] Exit
) else (
    echo (Page !page!/!total_pages!^) - Sorted by: !sort_info!  [Repo: !CURRENT_REPO!]
    echo.
    set "nav_line="
    if !page! gtr 1 set "nav_line=[P] Previous    "
    if !page! lss !total_pages! set "nav_line=!nav_line![N] Next Page   "
    set "nav_line=!nav_line![R] Refresh List   [E] Repository"

    echo !nav_line!
    set "tags_opt="
    if "!CURRENT_REPO_HASTAGS!"=="1" set "tags_opt=[V] View Models  "
    echo [F] Find Model  !tags_opt![S] Sort Size   [B] Best Sort   [L] Context  [I] Sort Field  [D] Default Sort  [A] Expand All  [C] Cancel  [X] Exit
)
set /p model_input="Enter model number/name to pull, [U] Run model, or command: "

:dispatch_input
REM Handle pagination navigation commands
if /i "!model_input!"=="n" goto handle_next_page
if /i "!model_input!"=="p" goto handle_prev_page
if /i "!model_input!"=="r" goto handle_refresh
if /i "!model_input!"=="e" goto handle_repository
if /i "!model_input!"=="f" goto handle_search
if /i "!model_input!"=="u" goto handle_run_model
if /i "!model_input!"=="s" goto handle_sort_size
if /i "!model_input!"=="b" goto handle_sort_best
if /i "!model_input!"=="l" goto handle_context_length
if /i "!model_input!"=="i" goto handle_sort_field
if /i "!model_input!"=="d" goto handle_sort_default
if /i "!model_input!"=="h" goto handle_hardware
if /i "!model_input!"=="a" goto handle_expand_all
if /i "!model_input!"=="v" goto handle_show_tags
if /i "!model_input!"=="x" (
    goto cleanup
)
if /i "!model_input!"=="c" (
    if not "!SEARCH_TERM!"=="" (
        set "SEARCH_TERM="
        set "page=1"
        call :apply_sort
        goto show_models_page
    )
    cls
    if !count! equ 0 (
        goto cleanup
    ) else (
        goto start
    )
)

if "!model_input!"=="" (
    echo No model selected.
    timeout /t 1 /nobreak
    goto show_models_page
)

goto handle_selection

:handle_search
echo.
set "query="
set /p query="Enter search term: "
if "!query!"=="" goto show_models_page

set "SEARCH_TERM=!query!"
set "page=1"
set "SEL_INDEX=1"
call :apply_sort

if !remote_count! equ 0 (
    echo.
    echo No results found for "!query!".
    timeout /t 2 /nobreak >nul
    set "SEARCH_TERM="
    call :apply_sort
)
goto show_models_page

:handle_sort_size
if "!SORT_MODE!"=="SIZE" (
    if "!SORT_DESC!"=="1" ( set "SORT_DESC=0" ) else ( set "SORT_DESC=1" )
) else (
    set "SORT_MODE=SIZE"
    set "SORT_DESC=1"
)
set "page=1"
set "SEL_INDEX=1"
call :apply_sort
goto show_models_page

:handle_sort_default
set "SORT_MODE=DEFAULT"
set "SORT_DESC=0"
set "SORT_FIELD_NAME="
set "SORT_FIELD_REGEX="
set "SORT_FIELD_NUMERIC="
set "page=1"
set "SEL_INDEX=1"
call :apply_sort
goto show_models_page

:handle_sort_best
if "!SORT_MODE!"=="BEST" (
    set "SORT_MODE=DEFAULT"
) else (
    set "SORT_MODE=BEST"
    set "SORT_DESC=0"
)
set "page=1"
set "SEL_INDEX=1"
call :apply_sort
goto show_models_page

:handle_expand_all
REM Toggle hardware-aware tag expansion directly from the model browse screen.
REM This is the shortcut form of the old [H] -> [T] flow: turn the filter
REM on/off, recompute repo cache paths, and refetch the catalog.
if "!HW_FILTER!"=="1" (
    set "HW_FILTER=0"
) else (
    set "HW_FILTER=1"
)
call :set_repo_paths
set "page=1"
set "SEL_INDEX=1"
goto fetch_list

:handle_hardware
echo.
echo =============== System Hardware ===============
echo   VRAM (GPU)  : !VRAM_GB! GB
echo   System RAM  : !RAM_GB! GB
echo   Disk Free   : !DISK_GB! GB
if defined OLLAMA_MODELS_PATH echo   Models Path : !OLLAMA_MODELS_PATH!
echo.
echo Color legend:
echo   [Green]  Fits entirely in VRAM (best performance)
echo   [Yellow] Will spill from VRAM into system RAM (slower)
echo   [Red]    Will not fit in VRAM + RAM, or exceeds free disk space
echo   [Gray]   Size unknown - cannot estimate fit
echo.
if "!HW_FILTER!"=="1" (
    echo Hardware filter is currently: ON
    echo   - Listing every published tag/quant that fits your hardware
    echo   - Cache: %TEMP%\ollama-models-!CURRENT_REPO!-compat.txt
) else (
    echo Hardware filter is currently: OFF ^(showing top base models only^)
)
echo.
set "hw_choice="
set /p hw_choice="[T] Toggle filter   [R] Re-detect hardware   [C] Back: "
if /i "!hw_choice!"=="t" (
    if "!HW_FILTER!"=="1" ( set "HW_FILTER=0" ) else ( set "HW_FILTER=1" )
    call :set_repo_paths
    set "page=1"
    goto fetch_list
)
if /i "!hw_choice!"=="r" (
    call :detect_hardware
    set "page=1"
    if "!HW_COMPAT_MODE!"=="1" (
        REM Hardware changed - compat cache is stale, force refetch
        del /q "%MODELS_CACHE%" 2>nul
        goto fetch_list
    )
    call :apply_sort
    goto show_models_page
)
goto show_models_page

:handle_context_length
if exist "%CONTEXT_SELECTOR_RESULT%" del "%CONTEXT_SELECTOR_RESULT%" >nul 2>&1
set "ctx_result="
set "ACTIVE_CONTEXT_SELECTOR=%CONTEXT_SELECTOR_SCRIPT%"
if exist "%~dp0context_selector.ps1" set "ACTIVE_CONTEXT_SELECTOR=%~dp0context_selector.ps1"

REM Try PowerShell context selector first
if not exist "!ACTIVE_CONTEXT_SELECTOR!" goto context_basic_menu

powershell -NoProfile -ExecutionPolicy Bypass -File "!ACTIVE_CONTEXT_SELECTOR!" ^
    -CurrentContext !CONTEXT_LENGTH! ^
    -ResultFile "%CONTEXT_SELECTOR_RESULT%"

if not exist "%CONTEXT_SELECTOR_RESULT%" goto context_basic_menu

for /f "usebackq delims=" %%a in ("%CONTEXT_SELECTOR_RESULT%") do set "ctx_result=%%a"

if /i "!ctx_result!"=="CANCEL" goto show_models_page
if /i "!ctx_result!"=="EXIT" goto cleanup
if "!ctx_result!"=="" goto show_models_page

call :apply_context_result "!ctx_result!"
goto show_models_page

REM Fallback: Basic batch menu if PowerShell script not found
:context_basic_menu
echo.
echo =============== Context Length Selection ===============
echo Current context length: !CONTEXT_LENGTH! tokens
echo.
echo Select context length (affects model usability estimates^):
echo   1. 4K   (4,096 tokens^)
echo   2. 8K   (8,192 tokens^)
echo   3. 16K  (16,384 tokens^)
echo   4. 32K  (32,768 tokens^)
echo   5. 64K  (65,536 tokens^)
echo   6. 128K (131,072 tokens^)
echo   7. 256K (262,144 tokens^)
echo.
set "ctx_choice="
set /p ctx_choice="Enter choice (1-7) or C to cancel: "
if /i "!ctx_choice!"=="c" goto show_models_page
if "!ctx_choice!"=="1" set "CONTEXT_LENGTH=4096"
if "!ctx_choice!"=="2" set "CONTEXT_LENGTH=8192"
if "!ctx_choice!"=="3" set "CONTEXT_LENGTH=16384"
if "!ctx_choice!"=="4" set "CONTEXT_LENGTH=32768"
if "!ctx_choice!"=="5" set "CONTEXT_LENGTH=65536"
if "!ctx_choice!"=="6" set "CONTEXT_LENGTH=131072"
if "!ctx_choice!"=="7" set "CONTEXT_LENGTH=262144"
if not "!ctx_choice!"=="" (
    call :apply_context_result "!CONTEXT_LENGTH!"
)
goto show_models_page

:handle_show_tags
REM On-demand: fetch and display every tag / quant / finetune variant
REM for a model from the active repository's configured tagFetch source
REM (Ollama library /tags scrape, or HuggingFace base_model API filter,
REM etc.). Useful when the main listing only shows base parameter sizes
REM and you want a specific quantization or related fine-tune.
if not "!CURRENT_REPO_HASTAGS!"=="1" (
    echo.
    echo Tag listing is not configured for repository "!CURRENT_REPO!".
    echo Add a 'tagFetch' block to %REPOS_CONFIG% to enable it.
    timeout /t 3 /nobreak >nul
    set "tag_prefill="
    goto show_models_page
)
set "tag_target="
if defined tag_prefill (
    set "tag_target=!tag_prefill!"
    set "tag_prefill="
) else (
    echo.
    set /p tag_target="Enter model number (from current list) to view all tags, or C to cancel: "
)
if /i "!tag_target!"=="c" goto show_models_page
if "!tag_target!"=="" goto show_models_page
REM Strip trailing period
if "!tag_target:~-1!"=="." set "tag_target=!tag_target:~0,-1!"

REM Resolve number -> model name, or accept a direct name
set "tag_model_name="
set "is_numeric=true"
for /f "delims=0123456789" %%a in ("!tag_target!") do set "is_numeric=false"
if "!is_numeric!"=="true" (
    if !tag_target! geq 1 if !tag_target! leq !remote_count! (
        for %%i in (!tag_target!) do set "tag_model_name=!r_model[%%i]!"
    )
) else (
    set "tag_model_name=!tag_target!"
)
if "!tag_model_name!"=="" (
    echo.
    echo Invalid selection.
    timeout /t 2 /nobreak >nul
    goto show_models_page
)

REM Strip any :variant suffix to get the library base name (e.g. qwen3:30b -> qwen3)
for /f "tokens=1 delims=:" %%a in ("!tag_model_name!") do set "tag_base=%%a"

REM Sanitize for use in a file name (Ollama model names are [A-Za-z0-9._-]+ but be defensive)
set "tag_base_safe=!tag_base:/=_!"
set "tag_base_safe=!tag_base_safe:\=_!"
set "TAGS_CACHE=%TEMP%\ollama-tags-!tag_base_safe!.txt"
if exist "!TAGS_CACHE!" del "!TAGS_CACHE!" >nul 2>&1

echo.
echo Fetching all tags for "!tag_base!" from !CURRENT_REPO!...
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -FetchTags -ModelName "!tag_base!" -Repo "!CURRENT_REPO!" -CacheFile "!TAGS_CACHE!" -ConfigFile "%REPOS_CONFIG%"
if not exist "!TAGS_CACHE!" (
    echo.
    echo Error: Failed to fetch tags for "!tag_base!".
    pause
    goto show_models_page
)

REM Load tags into arrays and create TAGS_SORTED with applied sort mode
set "tag_count=0"
set "TAGS_SORTED=%TEMP%\ollama-tags-sorted-!tag_base_safe!.txt"
if exist "!TAGS_SORTED!" del "!TAGS_SORTED!" >nul 2>&1

REM Apply the user's current sort mode to tags
set "SORT_FIELD_REGEX_ENV=!SORT_FIELD_REGEX!"
set "SORT_FIELD_NUMERIC_ENV=!SORT_FIELD_NUMERIC!"
powershell -NoProfile -Command "$s='!TAGS_CACHE!'; $d='!TAGS_SORTED!'; $m='!SORT_MODE!'; $desc=('!SORT_DESC!' -eq '1'); $vram=0.0;[double]::TryParse($env:HW_VRAM,[ref]$vram)|Out-Null; $ram=0.0;[double]::TryParse($env:HW_RAM,[ref]$ram)|Out-Null; $disk=0.0;[double]::TryParse($env:HW_DISK,[ref]$disk)|Out-Null; $ctx=4096;[int]::TryParse($env:OLLAMA_LAUNCHER_CTX,[ref]$ctx)|Out-Null; $GetFitTier={param($sz);if($sz -lt 0){return 3};$eff=$sz*(1+($ctx/50000.0));if($disk -gt 0 -and $eff -gt $disk){return 2};if($vram -gt 0 -and $eff -le $vram){return 0};if($eff -le ($vram+$ram)){return 1};return 2}; $GetSize={if($args[0] -match '([\d\.]+)\s*GB'){return [double]$matches[1]}elseif($args[0] -match '([\d\.]+)\s*MB'){return [double]$matches[1]/1024}elseif($args[0] -match '<\s*1'){return 0.1}else{return -1}}; $data=Import-Csv $s -Delimiter '|' -Header 'Name','Size','Params','Description' -Encoding UTF8; if($m -eq 'SIZE'){$data=$data | Sort-Object -Property @{Expression={if($_.Size -match '([\d\.]+) GB'){[double]$matches[1]}elseif($_.Size -match '([\d\.]+) MB'){[double]$matches[1]/1024}elseif($_.Size -match '< 1'){0.1}else{-1}}} -Descending:$desc}; if($m -eq 'BEST'){$g=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 0}|Sort-Object{&$GetSize $_.Size} -Descending);$y=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 1}|Sort-Object{&$GetSize $_.Size});$r=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 2}|Sort-Object{&$GetSize $_.Size});$u=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 3});$data=@($g)+@($y)+@($r)+@($u)}; $output=@($data | ForEach-Object { $_.Name+'|'+$_.Size+'|'+$_.Params+'|'+$_.Description }); if($output.Count -gt 0){[System.IO.File]::WriteAllLines($d, $output)}else{Set-Content -Path $d -Value '' -Encoding UTF8}"

for /f "usebackq tokens=1,2,3* delims=|" %%a in ("!TAGS_SORTED!") do (
    if "%%a" neq "" (
        set /a tag_count+=1
        set "t_model[!tag_count!]=%%a"
        set "t_size[!tag_count!]=%%b"
        set "t_params[!tag_count!]=%%c"
        set "t_desc[!tag_count!]=%%d"
    )
)
if !tag_count! equ 0 (
    echo.
    echo No tags found for "!tag_base!".
    pause
    goto show_models_page
)

set "TAG_PAGE=1"
set "TAG_SEL_INDEX=1"
set "TAG_SEARCH_TERM="
set "TAG_SORT_MODE=!SORT_MODE!"
set "TAG_SORT_DESC=!SORT_DESC!"

:show_tags_page
REM Calculate total pages for tags
set /a TAG_TOTAL_PAGES=(tag_count + 50 - 1) / 50
if !TAG_TOTAL_PAGES! lss 1 set "TAG_TOTAL_PAGES=1"

set "sort_info=Default"
if "!TAG_SORT_MODE!"=="SIZE" (
    if "!TAG_SORT_DESC!"=="1" (set "sort_info=Size (Desc)") else (set "sort_info=Size (Asc)"))
if "!TAG_SORT_MODE!"=="BEST" (
    set "sort_info=Best Fit")

if exist "%SELECTOR_RESULT%" del "%SELECTOR_RESULT%" >nul 2>&1

set "ACTIVE_SELECTOR_SCRIPT=%SELECTOR_SCRIPT%"
if exist "%~dp0model_selector.ps1" set "ACTIVE_SELECTOR_SCRIPT=%~dp0model_selector.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "!ACTIVE_SELECTOR_SCRIPT!" ^
    -SortedFile "!TAGS_SORTED!" -LocalFile "%LOCAL_MODELS_LIST%" ^
    -Page !TAG_PAGE! -PerPage 50 -TotalPages !TAG_TOTAL_PAGES! ^
    -SelIndex !TAG_SEL_INDEX! -Repo "!CURRENT_REPO!" -SearchTerm "!TAG_SEARCH_TERM!" ^
    -SortInfo "!sort_info!" -HwFilterLabel "OFF" ^
    -VramGb "!VRAM_GB!" -RamGb "!RAM_GB!" -DiskGb "!DISK_GB!" ^
    -ContextLength "!CONTEXT_LENGTH!" ^
    -HasTags "0" ^
    -ResultFile "%SELECTOR_RESULT%"

if not exist "%SELECTOR_RESULT%" goto show_tags_page

set "sel_action="
set "sel_arg="
REM Result file: line 1 = ACTION[|ARG]; line 2 = SEL_INDEX=<n>; optional line 3 = PAGE=<n>
REM Use same tokens=1,* + if-not-defined guard as the main list parser so that
REM the SEL_INDEX= and PAGE= lines that follow don't overwrite sel_action.
for /f "usebackq tokens=1,* delims=|" %%a in ("%SELECTOR_RESULT%") do (
    if not defined sel_action (
        set "sel_action=%%a"
        set "sel_arg=%%b"
    )
)
for /f "usebackq tokens=1,2 delims==" %%a in ("%SELECTOR_RESULT%") do (
    if /i "%%a"=="SEL_INDEX" set "TAG_SEL_INDEX=%%b"
    if /i "%%a"=="PAGE" set "TAG_PAGE=%%b"
)

if /i "!sel_action!"=="PULL" (
    set "tag_pick=!sel_arg!"
    goto process_tag_selection
)
if /i "!sel_action!"=="SELECT" (
    set "tag_pick=!sel_arg!"
    goto process_tag_selection
)
if /i "!sel_action!"=="INPUT" (
    set "tag_pick=!sel_arg!"
    goto process_tag_selection
)
if /i "!sel_action!"=="CMD" (
    if /i "!sel_arg!"=="S" goto tag_sort_size
    if /i "!sel_arg!"=="B" goto tag_sort_best
    if /i "!sel_arg!"=="F" goto tag_search
    if /i "!sel_arg!"=="D" goto tag_sort_default
    if /i "!sel_arg!"=="C" (
        if not "!TAG_SEARCH_TERM!"=="" (
            set "TAG_SEARCH_TERM="
            set "TAG_PAGE=1"
            set "TAG_SEL_INDEX=1"
            goto apply_tag_sort
        ) else (
            goto show_models_page
        )
    )
    if /i "!sel_arg!"=="X" goto cleanup
)
goto show_tags_page

:tag_sort_size
if "!TAG_SORT_MODE!"=="SIZE" (
    if "!TAG_SORT_DESC!"=="1" ( set "TAG_SORT_DESC=0" ) else ( set "TAG_SORT_DESC=1" )
) else (
    set "TAG_SORT_MODE=SIZE"
    set "TAG_SORT_DESC=1"
)
set "TAG_PAGE=1"
set "TAG_SEL_INDEX=1"
goto apply_tag_sort

:tag_sort_best
if "!TAG_SORT_MODE!"=="BEST" (
    set "TAG_SORT_MODE=DEFAULT"
) else (
    set "TAG_SORT_MODE=BEST"
    set "TAG_SORT_DESC=0"
)
set "TAG_PAGE=1"
set "TAG_SEL_INDEX=1"
goto apply_tag_sort

:tag_sort_default
set "TAG_SORT_MODE=DEFAULT"
set "TAG_SORT_DESC=0"
set "TAG_PAGE=1"
set "TAG_SEL_INDEX=1"
goto apply_tag_sort

:tag_search
set "search_query="
set /p search_query="Enter search term: "
if not "!search_query!"=="" (
    set "TAG_SEARCH_TERM=!search_query!"
    set "TAG_PAGE=1"
    set "TAG_SEL_INDEX=1"
)
goto apply_tag_sort

:apply_tag_sort
REM Apply sort to tags with search filter
set "SORT_FIELD_REGEX_ENV=!SORT_FIELD_REGEX!"
set "SORT_FIELD_NUMERIC_ENV=!SORT_FIELD_NUMERIC!"
powershell -NoProfile -Command "$s='!TAGS_CACHE!'; $d='!TAGS_SORTED!'; $m='!TAG_SORT_MODE!'; $desc=('!TAG_SORT_DESC!' -eq '1'); $q='!TAG_SEARCH_TERM!'; $vram=0.0;[double]::TryParse($env:HW_VRAM,[ref]$vram)|Out-Null; $ram=0.0;[double]::TryParse($env:HW_RAM,[ref]$ram)|Out-Null; $disk=0.0;[double]::TryParse($env:HW_DISK,[ref]$disk)|Out-Null; $ctx=4096;[int]::TryParse($env:OLLAMA_LAUNCHER_CTX,[ref]$ctx)|Out-Null; $GetFitTier={param($sz);if($sz -lt 0){return 3};$eff=$sz*(1+($ctx/50000.0));if($disk -gt 0 -and $eff -gt $disk){return 2};if($vram -gt 0 -and $eff -le $vram){return 0};if($eff -le ($vram+$ram)){return 1};return 2}; $GetSize={if($args[0] -match '([\d\.]+)\s*GB'){return [double]$matches[1]}elseif($args[0] -match '([\d\.]+)\s*MB'){return [double]$matches[1]/1024}elseif($args[0] -match '<\s*1'){return 0.1}else{return -1}}; $data=Import-Csv $s -Delimiter '|' -Header 'Name','Size','Params','Description' -Encoding UTF8; if($q){$data=$data | Where-Object {$_.Name -like '*'+$q+'*'}}; if($m -eq 'SIZE'){$data=$data | Sort-Object -Property @{Expression={if($_.Size -match '([\d\.]+) GB'){[double]$matches[1]}elseif($_.Size -match '([\d\.]+) MB'){[double]$matches[1]/1024}elseif($_.Size -match '< 1'){0.1}else{-1}}} -Descending:$desc}; if($m -eq 'BEST'){$g=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 0}|Sort-Object{&$GetSize $_.Size} -Descending);$y=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 1}|Sort-Object{&$GetSize $_.Size});$r=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 2}|Sort-Object{&$GetSize $_.Size});$u=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 3});$data=@($g)+@($y)+@($r)+@($u)}; $output=@($data | ForEach-Object { $_.Name+'|'+$_.Size+'|'+$_.Params+'|'+$_.Description }); if($output.Count -gt 0){[System.IO.File]::WriteAllLines($d, $output)}else{Set-Content -Path $d -Value '' -Encoding UTF8}"
goto show_tags_page

:process_tag_selection
REM Strip trailing period
if "!tag_pick:~-1!"=="." set "tag_pick=!tag_pick:~0,-1!"

REM Check if input is a number
set "is_numeric=true"
for /f "delims=0123456789" %%a in ("!tag_pick!") do set "is_numeric=false"

if "!is_numeric!"=="false" (
    echo Invalid selection.
    timeout /t 2 /nobreak >nul
    goto show_tags_page
)
if !tag_pick! lss 1 goto show_tags_page
if !tag_pick! gtr !tag_count! goto show_tags_page

for %%i in (!tag_pick!) do set "model_name=!t_model[%%i]!"
set "pull_target=!CURRENT_REPO_PREFIX!!model_name!"

REM Reuse the same safety validation as the main pull flow.
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -ValidatePull -Repo "!CURRENT_REPO!" -ModelName "!pull_target!" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
if errorlevel 1 (
    echo.
    echo Error: Pull target "!pull_target!" failed safety validation for repo "!CURRENT_REPO!".
    pause
    goto show_tags_page
)

echo.
echo Running: ollama pull "!pull_target!"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ollama_wrapper.ps1" -Pull -ModelName "!pull_target!"
if %errorlevel% neq 0 (
    echo.
    echo Error: Failed to pull "!pull_target!".
    echo This could be due to:
    echo   - Network connectivity issues
    echo   - Insufficient disk space
    echo   - A transient registry error (try again)
    echo.
    pause
    goto show_tags_page
)
echo.
echo Model installed successfully. Restarting launcher...
echo.
timeout /t 2 /nobreak >nul
cls
goto start

:handle_sort_field
set "SORT_FIELDS_LIST=%APPDATA_OLLAMA%\sort_fields.txt"
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -ListSortFields -Repo "!CURRENT_REPO!" -CacheFile "!SORT_FIELDS_LIST!" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
if not exist "!SORT_FIELDS_LIST!" (
    echo.
    echo No sort fields configured for repository "!CURRENT_REPO!".
    timeout /t 2 /nobreak >nul
    goto show_models_page
)
set "sf_count=0"
for /f "usebackq tokens=1,2,3 delims=|" %%a in ("!SORT_FIELDS_LIST!") do (
    set /a sf_count+=1
    set "sf_name[!sf_count!]=%%a"
    set "sf_regex[!sf_count!]=%%b"
    set "sf_num[!sf_count!]=%%c"
)
if !sf_count! equ 0 (
    echo.
    echo No sort fields configured for repository "!CURRENT_REPO!".
    timeout /t 2 /nobreak >nul
    goto show_models_page
)
echo.
echo =============== Sort by Field ===============
for /L %%i in (1,1,!sf_count!) do (
    echo   %%i. !sf_name[%%i]!
)
echo.
set "sf_choice="
set /p sf_choice="Enter field number (or C to cancel): "
if /i "!sf_choice!"=="c" goto show_models_page
if "!sf_choice!"=="" goto show_models_page
set "is_numeric=true"
for /f "delims=0123456789" %%a in ("!sf_choice!") do set "is_numeric=false"
if "!is_numeric!"=="false" goto handle_sort_field
if !sf_choice! lss 1 goto handle_sort_field
if !sf_choice! gtr !sf_count! goto handle_sort_field

REM Toggle direction if same field is reselected, otherwise default to descending
if "!SORT_MODE!"=="FIELD" if /i "!SORT_FIELD_NAME!"=="!sf_name[%sf_choice%]!" (
    if "!SORT_DESC!"=="1" ( set "SORT_DESC=0" ) else ( set "SORT_DESC=1" )
    goto sf_apply
)
set "SORT_MODE=FIELD"
set "SORT_DESC=1"
set "SORT_FIELD_NAME=!sf_name[%sf_choice%]!"
set "SORT_FIELD_REGEX=!sf_regex[%sf_choice%]!"
set "SORT_FIELD_NUMERIC=!sf_num[%sf_choice%]!"
:sf_apply
set "page=1"
set "SEL_INDEX=1"
call :apply_sort
goto show_models_page

:handle_next_page
REM Check if more pages exist in current cache
if !page! lss !total_pages! (
    set /a page+=1
    set /a SEL_INDEX=(page-1)*items_per_page+1
    goto show_models_page
) else (
    echo.
    echo Already on the last page of available models.
    timeout /t 2 /nobreak
    goto show_models_page
)

:handle_prev_page
if !page! gtr 1 (
    set /a page-=1
    set /a SEL_INDEX=(page-1)*items_per_page+1
    goto show_models_page
) else (
    echo Already on first page.
    timeout /t 1 /nobreak
    goto show_models_page
)

:handle_refresh
echo.
echo =============== Re-pull Models ===============
echo This will clear the cached model list and re-fetch from the server.
echo This may take a moment depending on your connection speed.
echo.
set "refresh_confirm="
set /p refresh_confirm="Are you sure you want to refresh? (Y/N): "
if /i "!refresh_confirm!"=="y" (
    del "%MODELS_CACHE%"
    set "reached_end="
    set "SEARCH_TERM="
    set "SEL_INDEX=1"
    goto fetch_list
) else (
    goto show_models_page
)

:handle_run_model
echo.
echo =============== Run Installed Model ===============
echo.
set "run_model="
set /p run_model="Enter model name to run (or press Enter to cancel): "
if "!run_model!"=="" goto show_models_page
echo.
echo Running: ollama run "!run_model!"
echo Context length: !CONTEXT_LENGTH! tokens
echo Displaying tokens per second in top right corner...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ollama_wrapper.ps1" -Run -ModelName "!run_model!" -ContextLength !CONTEXT_LENGTH!
if %errorlevel% neq 0 (
    echo.
    echo Error: Failed to run "!run_model!".
    echo.
    pause
)
goto show_models_page

:handle_selection
REM Determine if user entered a number or model name
set "model_name="

REM Strip trailing period if present
if "!model_input:~-1!"=="." set "model_input=!model_input:~0,-1!"

REM Check if input is a number and within range
set "is_numeric=true"
for /f "delims=0123456789" %%a in ("!model_input!") do set "is_numeric=false"

if "!is_numeric!"=="true" (
    if !model_input! geq 1 if !model_input! leq !remote_count! (
        for %%i in (!model_input!) do set "model_name=!r_model[%%i]!"
    ) else (
        echo.
        echo Error: Invalid model number. Please enter a number between 1 and !remote_count!.
        echo.
        timeout /t 2 /nobreak >nul
        goto show_models_page
    )
) else (
    REM User entered a model name - check if it exists in the list
    set "model_name=!model_input!"
    set "model_found=false"
    for /L %%i in (1,1,!remote_count!) do (
        if "!r_model[%%i]!"=="!model_name!" (
            set "model_found=true"
        )
    )
    
    if "!model_found!"=="false" (
        echo.
        echo Error: Model '!model_name!' not found in the available models list.
        echo Please enter a valid model number or name from the list.
        echo.
        timeout /t 2 /nobreak >nul
        goto show_models_page
    )
)

if "!model_name!"=="" (
    echo.
    echo Error: No valid model selected.
    echo.
    timeout /t 2 /nobreak >nul
    goto show_models_page
)

echo.
echo Pulling !model_name!...
echo.
REM Sanitize model name - remove any remaining problematic characters for safety
set "sanitized_model=!model_name:"=!"
set "sanitized_model=!sanitized_model:'=!"
set "sanitized_model=!sanitized_model:^=!"
set "sanitized_model=!sanitized_model:&=!"
set "sanitized_model=!sanitized_model:|=!"
if not "!sanitized_model!"=="" set "model_name=!sanitized_model!"

REM Apply repo-specific pull prefix (e.g. hf.co/ for HuggingFace)
set "pull_target=!CURRENT_REPO_PREFIX!!model_name!"

REM Validate pull target shape against the active repo's rules
REM (defense vs a tampered repos.json redirecting pulls to an attacker registry).
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -ValidatePull -Repo "!CURRENT_REPO!" -ModelName "!pull_target!" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
if errorlevel 1 (
    echo.
    echo Error: Pull target "!pull_target!" failed safety validation for repo "!CURRENT_REPO!".
    echo This can occur if repos.json was tampered with or contains an unexpected entry.
    echo.
    pause
    goto show_models_page
)

echo Running: ollama pull "!pull_target!"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ollama_wrapper.ps1" -Pull -ModelName "!pull_target!"
if %errorlevel% neq 0 (
    echo.
    echo Error: Failed to pull model !model_name!.
    echo This could be due to:
    echo   - Invalid model name
    echo   - Network connectivity issues
    echo   - Insufficient disk space
    echo.
    pause
    goto show_models_page
)
echo.
echo Model installed successfully. Restarting launcher...
echo.
timeout /t 2 /nobreak >nul
cls
goto start

:load_models
REM Parse models cache file and load into arrays for fast access
REM File format: Name|SizeGB|Params|TagCount|Description (pipe-delimited)
set "remote_count=0"
if not exist "%MODELS_SORTED%" exit /b
for /f "usebackq tokens=1,2,3,4* delims=|" %%a in ("%MODELS_SORTED%") do (
    if "%%a" neq "" (
        set /a remote_count+=1
        set "r_model[!remote_count!]=%%a"
        set "r_size[!remote_count!]=%%b"
        set "r_params[!remote_count!]=%%c"
        set "r_tagcount[!remote_count!]=%%d"
        set "r_desc[!remote_count!]=%%e"
    )
)
exit /b

:apply_sort
REM Sort the cache file based on current mode and save to sorted file
REM Always start from the original cache to avoid corrupting it with search results
set "CURRENT_SORT=!SORT_MODE!"

set "DO_COPY=0"
if "!CURRENT_SORT!"=="DEFAULT" if "!SEARCH_TERM!"=="" if not "!HW_FILTER!"=="1" set "DO_COPY=1"

if "!DO_COPY!"=="1" (
    copy /Y "%MODELS_CACHE%" "%MODELS_SORTED%" >nul
) else (
    set "SORT_FIELD_REGEX_ENV=!SORT_FIELD_REGEX!"
    set "SORT_FIELD_NUMERIC_ENV=!SORT_FIELD_NUMERIC!"
    powershell -NoProfile -Command "$s='%MODELS_CACHE%'; $d='%MODELS_SORTED%'; $m='!CURRENT_SORT!'; $desc=('!SORT_DESC!' -eq '1'); $q=$env:SEARCH_TERM; $rx=$env:SORT_FIELD_REGEX_ENV; $num=($env:SORT_FIELD_NUMERIC_ENV -eq '1'); $hf=($env:HW_FILTER -eq '1'); $vram=0.0;[double]::TryParse($env:HW_VRAM,[ref]$vram)|Out-Null; $ram=0.0;[double]::TryParse($env:HW_RAM,[ref]$ram)|Out-Null; $disk=0.0;[double]::TryParse($env:HW_DISK,[ref]$disk)|Out-Null; $ctx=4096;[int]::TryParse($env:OLLAMA_LAUNCHER_CTX,[ref]$ctx)|Out-Null; $GetFitTier={param($sz);if($sz -lt 0){return 3};$eff=$sz*(1+($ctx/50000.0));if($disk -gt 0 -and $eff -gt $disk){return 2};if($vram -gt 0 -and $eff -le $vram){return 0};if($eff -le ($vram+$ram)){return 1};return 2}; $GetSize={if($args[0] -match '([\d\.]+)\s*GB'){return [double]$matches[1]}elseif($args[0] -match '<\s*1'){return 0.1}else{return -1}}; $data=Import-Csv $s -Delimiter '|' -Header 'Name','Size','Params','TagCount','Description' -Encoding UTF8; if($q){$data=$data | Where-Object {$_.Name -like '*'+$q+'*'}}; if($hf){ $data=$data | Where-Object { $sz=-1.0; if($_.Size -match '([\d\.]+)\s*GB'){$sz=[double]$matches[1]} elseif($_.Size -match '<\s*1'){$sz=0.5}; if($sz -lt 0){return $true}; $need=$sz; if($disk -gt 0 -and $sz -gt $disk){return $false}; if($need -le ($vram+$ram)){return $true}; return $false } }; if($m -eq 'SIZE'){$data=$data | Sort-Object -Property @{Expression={if($_.Size -match '([\d\.]+) GB'){[double]$matches[1]}elseif($_.Size -match '< 1 GB'){0.1}else{-1}}} -Descending:$desc}; if($m -eq 'BEST'){$g=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 0}|Sort-Object{&$GetSize $_.Size} -Descending);$y=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 1}|Sort-Object{&$GetSize $_.Size});$r=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 2}|Sort-Object{&$GetSize $_.Size});$u=@($data|Where-Object{$sz=&$GetSize $_.Size;(&$GetFitTier $sz)-eq 3});$data=@($g)+@($y)+@($r)+@($u)}; if($m -eq 'FIELD' -and $rx){$data=$data | Sort-Object -Property @{Expression={ $v=$null; if($_.Description -match $rx){ $v=$matches[1] }; if($num){ if($v){ try{[double]$v}catch{-1} } else { -1 } } else { if($v){ $v } else { '' } } }} -Descending:$desc}; $output=@($data | ForEach-Object { $_.Name+'|'+$_.Size+'|'+$_.Params+'|'+$_.TagCount+'|'+$_.Description }); if($output.Count -gt 0){[System.IO.File]::WriteAllLines($d, $output)}else{Set-Content -Path $d -Value '' -Encoding UTF8}"
)
call :load_models
exit /b

:load_context_length
if exist "%CONTEXT_FILE%" (
    for /f "usebackq delims=" %%a in ("%CONTEXT_FILE%") do (
        set "ctx_temp=%%a"
        for /f "tokens=*" %%b in ("!ctx_temp!") do set "CONTEXT_LENGTH=%%b"
    )
)
exit /b

:apply_context_result
set "new_context=%~1"
if "!new_context!"=="4096" goto context_value_valid
if "!new_context!"=="8192" goto context_value_valid
if "!new_context!"=="16384" goto context_value_valid
if "!new_context!"=="32768" goto context_value_valid
if "!new_context!"=="65536" goto context_value_valid
if "!new_context!"=="131072" goto context_value_valid
if "!new_context!"=="262144" goto context_value_valid
echo.
echo Invalid context selection: !new_context!
timeout /t 1 /nobreak >nul
exit /b

:context_value_valid
set "CONTEXT_LENGTH=!new_context!"
call :save_context_length
call :load_context_length
set "OLLAMA_CONTEXT_LENGTH=!CONTEXT_LENGTH!"
set "OLLAMA_LAUNCHER_CTX=!CONTEXT_LENGTH!"
echo.
echo Context length updated to !CONTEXT_LENGTH! tokens
REM Refresh model order so BEST sort fit-tiers reflect the new context size
call :apply_sort
call :restart_ollama_for_context
timeout /t 1 /nobreak >nul
exit /b

:save_context_length
> "%CONTEXT_FILE%" echo(!CONTEXT_LENGTH!
exit /b

:restart_ollama_for_context
if not "!OLLAMA_STARTED!"=="1" goto context_external_ollama
echo Restarting Ollama server to apply context length...
taskkill /F /IM ollama.exe >nul 2>&1
start "" /B ollama serve >nul 2>&1
echo Waiting for Ollama to be ready...
call :wait_ollama_ready_context
echo Ollama context length applied.
exit /b

:context_external_ollama
tasklist /FI "IMAGENAME eq ollama.exe" 2>nul | find /I "ollama.exe" >nul
if !errorlevel! equ 0 (
    echo Ollama is already running outside this launcher.
    set "restart_context_ollama="
    set /p restart_context_ollama="Restart Ollama now to apply the new context length? (Y/N): "
    if /i "!restart_context_ollama!"=="Y" (
        taskkill /F /IM ollama.exe >nul 2>&1
        start "" /B ollama serve >nul 2>&1
        set "OLLAMA_STARTED=1"
        echo Waiting for Ollama to be ready...
        call :wait_ollama_ready_context
        echo Ollama context length applied.
    ) else (
        echo Restart Ollama later for the new context length to affect loaded models.
    )
)
exit /b

:wait_ollama_ready_context
timeout /t 1 /nobreak >nul
curl -s http://localhost:11434 >nul 2>&1
if !errorlevel! neq 0 goto wait_ollama_ready_context
exit /b

:create_fetch_script
REM Create the fetch_models.ps1 script - copy from script directory to %appdata% if available
if exist "%~dp0fetch_models.ps1" (
    copy /Y "%~dp0fetch_models.ps1" "%FETCH_MODELS_SCRIPT%" >nul 2>&1
    if exist "%FETCH_MODELS_SCRIPT%" (
        del "%~dp0fetch_models.ps1"
        echo Moved fetch_models.ps1 to AppData and cleaned up local file.
        timeout /t 2 /nobreak >nul
    )
)

if not exist "%FETCH_MODELS_SCRIPT%" (
    echo.
    echo Error: Critical file 'fetch_models.ps1' is missing.
    echo Please download 'fetch_models.ps1' and place it in the same folder as this script.
    echo.
    pause
    goto cleanup
)
exit /b

:create_selector_script
REM Copy model_selector.ps1 from script directory to %appdata% if available
if exist "%~dp0model_selector.ps1" (
    copy /Y "%~dp0model_selector.ps1" "%SELECTOR_SCRIPT%" >nul 2>&1
    if exist "%SELECTOR_SCRIPT%" (
        echo Updated model_selector.ps1 in AppData.
    )
)
if not exist "%SELECTOR_SCRIPT%" (
    echo.
    echo Warning: 'model_selector.ps1' is missing - arrow-key navigation will be disabled.
    echo Place 'model_selector.ps1' next to this script for the enhanced UI.
    echo.
    timeout /t 2 /nobreak >nul
)

REM Copy context_selector.ps1 from script directory to %appdata% if available
if exist "%~dp0context_selector.ps1" (
    copy /Y "%~dp0context_selector.ps1" "%CONTEXT_SELECTOR_SCRIPT%" >nul 2>&1
    if exist "%CONTEXT_SELECTOR_SCRIPT%" (
        echo Updated context_selector.ps1 in AppData.
    )
)

exit /b

:main_repository
set "REPO_RETURN=main"
goto handle_repository

:handle_repository
if not defined REPO_RETURN set "REPO_RETURN=models"
REM Show available repositories from repos.json and let user choose the active one
echo.
echo Refreshing repository list...
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -ListRepos -CacheFile "%REPOS_LIST%" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
if not exist "%REPOS_LIST%" (
    echo Error: Failed to read repository config at "%REPOS_CONFIG%".
    pause
    goto repo_return
)

set "repo_count=0"
for /f "usebackq tokens=1,2,3,4,5,6,7 delims=|" %%a in ("%REPOS_LIST%") do (
    set /a repo_count+=1
    set "repo_name[!repo_count!]=%%a"
    set "repo_type[!repo_count!]=%%b"
    set "repo_desc[!repo_count!]=%%c"
    set "repo_prefix[!repo_count!]=%%d"
    set "repo_host[!repo_count!]=%%f"
    set "repo_hastags[!repo_count!]=%%g"
    REM Sentinel "(none)" represents an empty pullPrefix (avoids consecutive | collapse in for/f).
    if /i "!repo_prefix[!repo_count!]!"=="(none)" set "repo_prefix[!repo_count!]="
)

echo.
echo =============== Model Repositories ===============
echo Current repository : !CURRENT_REPO!
echo Config file        : %REPOS_CONFIG%
echo (Edit the config file to add or remove repositories)
echo.
for /L %%i in (1,1,!repo_count!) do (
    set "marker= "
    if /i "!repo_name[%%i]!"=="!CURRENT_REPO!" set "marker=*"
    echo  !marker! %%i. !repo_name[%%i]!  [!repo_type[%%i]!]
    echo        !repo_desc[%%i]!
)
echo.
set "repo_choice="
set /p repo_choice="Enter the repository number to switch to (or C to cancel): "

if /i "!repo_choice!"=="c" goto repo_return
if /i "!repo_choice!"=="" goto repo_return

set "is_numeric=true"
for /f "delims=0123456789" %%a in ("!repo_choice!") do set "is_numeric=false"
if "!is_numeric!"=="false" (
    echo Invalid selection.
    timeout /t 2 /nobreak >nul
    goto handle_repository
)
if !repo_choice! lss 1 goto handle_repository
if !repo_choice! gtr !repo_count! goto handle_repository

set "PREV_REPO=!CURRENT_REPO!"
set "PREV_REPO_TYPE=!CURRENT_REPO_TYPE!"
set "PREV_REPO_PREFIX=!CURRENT_REPO_PREFIX!"
set "PREV_REPO_HOST=!CURRENT_REPO_HOST!"
set "PREV_REPO_HASTAGS=!CURRENT_REPO_HASTAGS!"
set "CURRENT_REPO=!repo_name[%repo_choice%]!"
set "CURRENT_REPO_TYPE=!repo_type[%repo_choice%]!"
set "CURRENT_REPO_PREFIX=!repo_prefix[%repo_choice%]!"
set "CURRENT_REPO_HOST=!repo_host[%repo_choice%]!"
set "CURRENT_REPO_HASTAGS=!repo_hastags[%repo_choice%]!"
call :check_repo_trust
if errorlevel 1 (
    set "CURRENT_REPO=!PREV_REPO!"
    set "CURRENT_REPO_TYPE=!PREV_REPO_TYPE!"
    set "CURRENT_REPO_PREFIX=!PREV_REPO_PREFIX!"
    set "CURRENT_REPO_HOST=!PREV_REPO_HOST!"
    set "CURRENT_REPO_HASTAGS=!PREV_REPO_HASTAGS!"
    timeout /t 2 /nobreak >nul
    goto handle_repository
)
call :set_repo_paths
call :save_repo_state

REM Reset paging/search state and force fresh fetch for the new repo
set "page=1"
set "SEARCH_TERM="
set "SORT_MODE=DEFAULT"
set "SORT_DESC=0"
set "SORT_FIELD_NAME="
set "SORT_FIELD_REGEX="
set "SORT_FIELD_NUMERIC="
echo.
echo Switched to repository: !CURRENT_REPO!
timeout /t 1 /nobreak >nul
if /i "!REPO_RETURN!"=="main" (
    set "REPO_RETURN="
    cls
    goto start
)
set "REPO_RETURN="
goto fetch_list

:repo_return
if /i "!REPO_RETURN!"=="main" (
    set "REPO_RETURN="
    cls
    goto start
)
set "REPO_RETURN="
goto show_models_page

:set_repo_paths
REM Recompute per-repo cache file paths based on CURRENT_REPO.
REM When HW_FILTER=1 and we're on the Ollama repo, use a separate cache
REM that holds the hardware-filtered tag-expanded catalog (one row per
REM compatible quant/tag variant) so we don't clobber the normal cache.
set "HW_COMPAT_MODE=0"
if /i "!CURRENT_REPO!"=="Ollama" if "!HW_FILTER!"=="1" set "HW_COMPAT_MODE=1"
if "!HW_COMPAT_MODE!"=="1" (
    set "MODELS_CACHE=%TEMP%\ollama-models-!CURRENT_REPO!-compat.txt"
    set "MODELS_SORTED=%TEMP%\ollama-models-sorted-!CURRENT_REPO!-compat.txt"
) else (
    set "MODELS_CACHE=%TEMP%\ollama-models-!CURRENT_REPO!.txt"
    set "MODELS_SORTED=%TEMP%\ollama-models-sorted-!CURRENT_REPO!.txt"
)
exit /b

:detect_hardware
REM Probe VRAM / RAM / Disk free via fetch_models.ps1 and load into env vars.
REM Sets VRAM_GB, RAM_GB, DISK_GB, OLLAMA_MODELS_PATH and the HW_* env vars
REM that the display/sort PowerShell snippets read.
echo.
echo Detecting system hardware (VRAM / RAM / Disk)...
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -DetectHardware -CacheFile "%HW_CACHE_FILE%" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
if not exist "%HW_CACHE_FILE%" (
    echo Warning: Hardware detection failed; model-fit hints disabled.
    set "VRAM_GB=0"
    set "RAM_GB=0"
    set "DISK_GB=0"
    set "OLLAMA_MODELS_PATH="
    goto detect_hw_export
)
for /f "usebackq tokens=1,2,3,4 delims=|" %%a in ("%HW_CACHE_FILE%") do (
    for /f "tokens=1,* delims==" %%x in ("%%a") do set "VRAM_GB=%%y"
    for /f "tokens=1,* delims==" %%x in ("%%b") do set "RAM_GB=%%y"
    for /f "tokens=1,* delims==" %%x in ("%%c") do set "DISK_GB=%%y"
    for /f "tokens=1,* delims==" %%x in ("%%d") do set "OLLAMA_MODELS_PATH=%%y"
)
:detect_hw_export
set "HW_VRAM=!VRAM_GB!"
set "HW_RAM=!RAM_GB!"
set "HW_DISK=!DISK_GB!"
echo   VRAM (GPU)  : !VRAM_GB! GB
echo   System RAM  : !RAM_GB! GB
echo   Disk Free   : !DISK_GB! GB  (!OLLAMA_MODELS_PATH!)
timeout /t 1 /nobreak >nul
exit /b

:load_repo_state
REM Ensure repos.json exists by asking the PS script to materialize defaults if needed
if not exist "%REPOS_CONFIG%" (
    powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -ListRepos -CacheFile "%REPOS_LIST%" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
)
REM Read previously selected repo, if any
if exist "%REPO_STATE_FILE%" (
    set /p saved_repo=<"%REPO_STATE_FILE%"
    if not "!saved_repo!"=="" set "CURRENT_REPO=!saved_repo!"
)
REM Refresh repos_list.txt and look up type+prefix for CURRENT_REPO
powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -ListRepos -CacheFile "%REPOS_LIST%" -ConfigFile "%REPOS_CONFIG%" >nul 2>&1
if exist "%REPOS_LIST%" (
    for /f "usebackq tokens=1,2,3,4,5,6,7 delims=|" %%a in ("%REPOS_LIST%") do (
        if /i "%%a"=="!CURRENT_REPO!" (
            set "CURRENT_REPO_TYPE=%%b"
            set "CURRENT_REPO_PREFIX=%%d"
            set "CURRENT_REPO_HOST=%%f"
            set "CURRENT_REPO_HASTAGS=%%g"
            REM Sentinel "(none)" represents an empty pullPrefix (avoids consecutive | collapse in for/f).
            if /i "!CURRENT_REPO_PREFIX!"=="(none)" set "CURRENT_REPO_PREFIX="
        )
    )
)
call :set_repo_paths
call :check_repo_trust
if errorlevel 1 (
    echo.
    echo The previously selected repository is no longer trusted.
    echo Please choose a different repository.
    timeout /t 2 /nobreak >nul
    set "REPO_RETURN=main"
    call :handle_repository
)
exit /b

:save_repo_state
> "%REPO_STATE_FILE%" echo !CURRENT_REPO!
exit /b

:check_repo_trust
REM Verify the active repo's host has been explicitly trusted by the user.
REM Trusted hosts persisted in %TRUSTED_HOSTS_FILE% as a single ;-delimited line.
REM Returns errorlevel 0 if trusted (or no host to check), 1 if user declined.
if not defined CURRENT_REPO_HOST exit /b 0
if "!CURRENT_REPO_HOST!"=="" exit /b 0
if not exist "%TRUSTED_HOSTS_FILE%" (
    > "%TRUSTED_HOSTS_FILE%" echo huggingface.co;ollama.com
)
set "TRUSTED_HOSTS="
set /p TRUSTED_HOSTS=<"%TRUSTED_HOSTS_FILE%"
echo ;!TRUSTED_HOSTS!;| findstr /i /c:";!CURRENT_REPO_HOST!;" >nul
if %errorlevel% equ 0 exit /b 0
echo.
echo =================== SECURITY WARNING ===================
echo Repository "!CURRENT_REPO!" uses an UNTRUSTED host:
echo     !CURRENT_REPO_HOST!
echo.
echo Currently trusted hosts: !TRUSTED_HOSTS!
echo.
echo Only trust this host if YOU added it to repos.json.
echo A malicious config could redirect model downloads to an
echo attacker-controlled registry.
echo =========================================================
echo.
set "trust_choice="
set /p trust_choice="Trust this host and continue? (y/N): "
if /i not "!trust_choice!"=="y" (
    echo Host not trusted. Aborting use of this repository.
    exit /b 1
)
> "%TRUSTED_HOSTS_FILE%" echo !TRUSTED_HOSTS!;!CURRENT_REPO_HOST!
echo Host trusted and recorded.
exit /b 0

:cleanup
if "!OLLAMA_STARTED!"=="1" (
    echo.
    echo Stopping Ollama server...
    taskkill /F /IM ollama.exe >nul 2>&1
)
exit /b
