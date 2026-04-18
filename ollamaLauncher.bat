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
set "REPOS_CONFIG=%APPDATA_OLLAMA%\repos.json"
set "REPOS_LIST=%APPDATA_OLLAMA%\repos_list.txt"
set "REPO_STATE_FILE=%APPDATA_OLLAMA%\state.txt"
set "TRUSTED_HOSTS_FILE=%APPDATA_OLLAMA%\trusted_hosts.txt"

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
set "CACHE_EXPIRY_HOURS=1"
set "OLLAMA_RUN_TIMEOUT_SECONDS=3600"

REM Create APPDATA directory if it doesn't exist
if not exist "%APPDATA_OLLAMA%" mkdir "%APPDATA_OLLAMA%"

REM Create fetch_models.ps1 in APPDATA on first run
call :create_fetch_script

REM Load saved active repo (if any) and ensure repos.json exists
call :load_repo_state

:start
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

REM Query and store all installed Ollama models
echo Fetching available Ollama models...
echo   0. Update/Pull a new model
echo.
set "LOCAL_MODELS_LIST=%TEMP%\ollama-local-list.txt"

REM Use PowerShell script to list, parse, and display local models with details
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
if not exist "%MODELS_CACHE%" (
    REM Fetch top 100 models from the active repository using PowerShell script
    echo.
    echo Fetching latest top 100 models from !CURRENT_REPO!...
    powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -CacheFile "%MODELS_CACHE%" -Repo "!CURRENT_REPO!"
    
    if not exist "%MODELS_CACHE%" (
        echo.
        echo Error: Failed to fetch models. models.txt was not created.
        echo.
        pause
        goto start
    )
) else (
    REM Check if cache is older than 1 hour
    powershell -NoProfile -Command "if ((Get-Date) - (Get-Item '%MODELS_CACHE%').LastWriteTime -gt (New-TimeSpan -Hours 1)) { exit 1 } else { exit 0 }"
    
    if !errorlevel! neq 0 (
        echo.
        echo Cache is older than 1 hour. Refreshing models from !CURRENT_REPO!...
        REM Fetch to temporary file first to avoid losing old cache if fetch fails
        powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -CacheFile "%MODELS_CACHE%.tmp" -Repo "!CURRENT_REPO!"
        
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

:show_models_page
REM Calculate total pages needed for pagination
set /a total_pages=(remote_count + items_per_page - 1) / items_per_page
if !total_pages! lss 1 set "total_pages=1"

echo Using cached model list, enter [R] to re-pull and refresh.
if !count! equ 0 (echo No models found locally. Please select a model to download.) else (echo Select a model to download from the Ollama library.)
echo.
if not "!SEARCH_TERM!"=="" (
    echo Showing Models (Page !page!/!total_pages!^) - Search Results: !SEARCH_TERM!
) else (
    set "sort_info=Default"
    if "!SORT_MODE!"=="SIZE" (
        if "!SORT_DESC!"=="1" (set "sort_info=Size (Desc)") else (set "sort_info=Size (Asc)")
    )
    if "!SORT_MODE!"=="FIELD" (
        if "!SORT_DESC!"=="1" (set "sort_info=!SORT_FIELD_NAME! (Desc)") else (set "sort_info=!SORT_FIELD_NAME! (Asc)")
    )
    echo Showing Models (Page !page!/!total_pages!^) - Sorted by: !sort_info!
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=!page!; $l=!items_per_page!; $f='%MODELS_SORTED%'; $lf='%LOCAL_MODELS_LIST%'; $s=($p-1)*$l; $installed=@{}; if(Test-Path $lf){Get-Content $lf -Encoding UTF8 | ForEach-Object {$installed[$_]=$true}}; try{$w=$Host.UI.RawUI.WindowSize.Width}catch{$w=80}; if($w -lt 60){$w=60}; $dw=$w-53; if($dw -lt 5){$dw=5}; Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f 'Num','Model Name','Size (GB)','Params','Description'); Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f ('-'*4),('-'*25),('-'*10),('-'*8),('-'*$dw)); $k=0; Import-Csv $f -Delimiter '|' -Header 'Name','Size','Params','Description' -Encoding UTF8 | Select-Object -Skip $s -First $l | ForEach-Object { $k++; $i=$s+$k; $n=$_.Name; if($n.Length -gt 25){$n=$n.Substring(0,22)+'...'}; $d=$_.Description; if($installed.ContainsKey($_.Name)){$d='   [Installed]    '+$d}; if($d.Length -gt $dw){$d=$d.Substring(0,$dw-3)+'...'}; Write-Host ('{0,3}. {1,-25} {2,-10} {3,-8}  {4}' -f $i,$n,$_.Size,$_.Params,$d) }"

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
    REM Show navigation options based on current page position
    set "nav_line="
    if !page! gtr 1 set "nav_line=[P] Previous    "
    if !page! lss !total_pages! set "nav_line=!nav_line![N] Next Page   "
    set "nav_line=!nav_line![R] Refresh List   [E] Repository"

    echo !nav_line!
    echo [F] Find Model  [S] Sort Size   [I] Sort Field  [D] Default Sort  [C] Cancel  [X] Exit
)
set /p model_input="Enter model number or name to pull: "

REM Handle pagination navigation commands
if /i "!model_input!"=="n" goto handle_next_page
if /i "!model_input!"=="p" goto handle_prev_page
if /i "!model_input!"=="r" goto handle_refresh
if /i "!model_input!"=="e" goto handle_repository
if /i "!model_input!"=="f" goto handle_search
if /i "!model_input!"=="s" goto handle_sort_size
if /i "!model_input!"=="i" goto handle_sort_field
if /i "!model_input!"=="d" goto handle_sort_default
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
call :apply_sort
goto show_models_page

:handle_sort_default
set "SORT_MODE=DEFAULT"
set "SORT_DESC=0"
set "SORT_FIELD_NAME="
set "SORT_FIELD_REGEX="
set "SORT_FIELD_NUMERIC="
call :apply_sort
goto show_models_page

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
call :apply_sort
goto show_models_page

:handle_next_page
REM Check if more pages exist in current cache
if !page! lss !total_pages! (
    set /a page+=1
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
    goto show_models_page
) else (
    echo Already on first page.
    timeout /t 1 /nobreak
    goto show_models_page
)

:handle_refresh
del "%MODELS_CACHE%"
set "reached_end="
set "SEARCH_TERM="
goto fetch_list

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
ollama pull "!pull_target!"
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
REM File format: Name|SizeGB|Params|Description (pipe-delimited)
set "remote_count=0"
if not exist "%MODELS_SORTED%" exit /b
for /f "usebackq tokens=1,2,3* delims=|" %%a in ("%MODELS_SORTED%") do (
    if "%%a" neq "" (
        set /a remote_count+=1
        set "r_model[!remote_count!]=%%a"
        set "r_size[!remote_count!]=%%b"
        set "r_params[!remote_count!]=%%c"
        set "r_desc[!remote_count!]=%%d"
    )
)
exit /b

:apply_sort
REM Sort the cache file based on current mode and save to sorted file
REM Always start from the original cache to avoid corrupting it with search results
set "CURRENT_SORT=!SORT_MODE!"
if not "!SEARCH_TERM!"=="" set "CURRENT_SORT=DEFAULT"

set "DO_COPY=0"
if "!CURRENT_SORT!"=="DEFAULT" if "!SEARCH_TERM!"=="" set "DO_COPY=1"

if "!DO_COPY!"=="1" (
    copy /Y "%MODELS_CACHE%" "%MODELS_SORTED%" >nul
) else (
    set "SORT_FIELD_REGEX_ENV=!SORT_FIELD_REGEX!"
    set "SORT_FIELD_NUMERIC_ENV=!SORT_FIELD_NUMERIC!"
    powershell -NoProfile -Command "$s='%MODELS_CACHE%'; $d='%MODELS_SORTED%'; $m='!CURRENT_SORT!'; $desc=('!SORT_DESC!' -eq '1'); $q=$env:SEARCH_TERM; $rx=$env:SORT_FIELD_REGEX_ENV; $num=($env:SORT_FIELD_NUMERIC_ENV -eq '1'); $data=Import-Csv $s -Delimiter '|' -Header 'Name','Size','Params','Description' -Encoding UTF8; if($q){$data=$data | Where-Object {$_.Name -like '*'+$q+'*'}}; if($m -eq 'SIZE'){$data=$data | Sort-Object -Property @{Expression={if($_.Size -match '([\d\.]+) GB'){[double]$matches[1]}elseif($_.Size -match '< 1 GB'){0.1}else{-1}}} -Descending:$desc}; if($m -eq 'FIELD' -and $rx){$data=$data | Sort-Object -Property @{Expression={ $v=$null; if($_.Description -match $rx){ $v=$matches[1] }; if($num){ if($v){ try{[double]$v}catch{-1} } else { -1 } } else { if($v){ $v } else { '' } } }} -Descending:$desc}; $output=@($data | ForEach-Object { $_.Name+'|'+$_.Size+'|'+$_.Params+'|'+$_.Description }); if($output.Count -gt 0){[System.IO.File]::WriteAllLines($d, $output)}else{Set-Content -Path $d -Value '' -Encoding UTF8}"
)
call :load_models
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
for /f "usebackq tokens=1,2,3,4,5,6 delims=|" %%a in ("%REPOS_LIST%") do (
    set /a repo_count+=1
    set "repo_name[!repo_count!]=%%a"
    set "repo_type[!repo_count!]=%%b"
    set "repo_desc[!repo_count!]=%%c"
    set "repo_prefix[!repo_count!]=%%d"
    set "repo_host[!repo_count!]=%%f"
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
set "CURRENT_REPO=!repo_name[%repo_choice%]!"
set "CURRENT_REPO_TYPE=!repo_type[%repo_choice%]!"
set "CURRENT_REPO_PREFIX=!repo_prefix[%repo_choice%]!"
set "CURRENT_REPO_HOST=!repo_host[%repo_choice%]!"
call :check_repo_trust
if errorlevel 1 (
    set "CURRENT_REPO=!PREV_REPO!"
    set "CURRENT_REPO_TYPE=!PREV_REPO_TYPE!"
    set "CURRENT_REPO_PREFIX=!PREV_REPO_PREFIX!"
    set "CURRENT_REPO_HOST=!PREV_REPO_HOST!"
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
REM Recompute per-repo cache file paths based on CURRENT_REPO
set "MODELS_CACHE=%TEMP%\ollama-models-!CURRENT_REPO!.txt"
set "MODELS_SORTED=%TEMP%\ollama-models-sorted-!CURRENT_REPO!.txt"
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
    for /f "usebackq tokens=1,2,3,4,5,6 delims=|" %%a in ("%REPOS_LIST%") do (
        if /i "%%a"=="!CURRENT_REPO!" (
            set "CURRENT_REPO_TYPE=%%b"
            set "CURRENT_REPO_PREFIX=%%d"
            set "CURRENT_REPO_HOST=%%f"
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
