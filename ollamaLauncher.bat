@echo off
REM ollamaLauncher.bat
REM Version: 1.0 
REM Date: 11/22/2025
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
REM         -if the fetch_models.ps1 is missing in local folder then the .bat re-creates fetch_models.ps1 by Base64 encoding.
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

REM Use system temp directory for models cache to avoid desktop clutter
set "MODELS_CACHE=%TEMP%\ollama-models.txt"

REM Use APPDATA for storing fetch_models.ps1 script
set "APPDATA_OLLAMA=%APPDATA%\ollamaLauncher"
set "FETCH_MODELS_SCRIPT=%APPDATA_OLLAMA%\fetch_models.ps1"

REM Configurable pagination settings
set "ITEMS_PER_PAGE=50"
set "MODELS_PER_FETCH=100"
set "CACHE_EXPIRY_HOURS=1"
set "OLLAMA_RUN_TIMEOUT_SECONDS=3600"

REM Create APPDATA directory if it doesn't exist
if not exist "%APPDATA_OLLAMA%" mkdir "%APPDATA_OLLAMA%"

REM Create fetch_models.ps1 in APPDATA on first run
call :create_fetch_script

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
echo                                                                                               v1.0 by Mike 11/22/2025
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
            exit /b
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
        exit /b
    )
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
        exit /b
    )
)

REM Read the models into the batch array
set count=0
for /f "usebackq delims=" %%a in ("%LOCAL_MODELS_LIST%") do (
    set /a count+=1
    set "model[!count!]=%%a"
)

echo. 
echo [0/U] Update/Pull a new Model    [R] Remove a model   [X] Exit
echo.
:prompt
set "choice="
set /p choice="Enter the number or model name for the model you want to use (r to remove, or 0 / u to pull a new one): "

REM Strip trailing period if present
if "%choice:~-1%"=="." set "choice=%choice:~0,-1%"

if /i "%choice%"=="x" exit /b
if /i "%choice%"=="exit" exit /b
if /i "%choice%"=="R" goto remove_model
if /i "%choice%"=="u" goto fetch_list
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
    REM Fetch top 100 models from Ollama.com using PowerShell script
    echo.
    echo Fetching latest top 100 models from Ollama.com...
    powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -CacheFile "%MODELS_CACHE%" -Limit 100
    
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
    
    if %errorlevel% neq 0 (
        echo.
        echo Cache is older than 1 hour. Refreshing models from Ollama.com...
        REM Fetch to temporary file first to avoid losing old cache if fetch fails
        powershell -ExecutionPolicy Bypass -File "%FETCH_MODELS_SCRIPT%" -CacheFile "%MODELS_CACHE%.tmp" -Limit 100
        
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

REM Load remote models from cache file and setup pagination
call :load_models
set "page=1"
set "items_per_page=50"
REM Calculate total pages needed for pagination
set /a total_pages=(remote_count + items_per_page - 1) / items_per_page

:show_models_page
echo.
if !count! equ 0 (
    echo No models found locally. Please select a model to download.
) else (
    echo Select a model to download from the Ollama library.
)
echo.
echo Showing Models (Page !page!/!total_pages!)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=!page!; $l=!items_per_page!; $f='%MODELS_CACHE%'; $lf='%LOCAL_MODELS_LIST%'; $s=($p-1)*$l; $installed=@{}; if(Test-Path $lf){Get-Content $lf -Encoding UTF8 | ForEach-Object {$installed[$_]=$true}}; try{$w=$Host.UI.RawUI.WindowSize.Width}catch{$w=80}; if($w -lt 60){$w=60}; $dw=$w-53; if($dw -lt 5){$dw=5}; Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f 'Num','Model Name','Size (GB)','Params','Description'); Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f ('-'*4),('-'*25),('-'*10),('-'*8),('-'*$dw)); $k=0; Import-Csv $f -Delimiter '|' -Header 'Name','Size','Params','Description' -Encoding UTF8 | Select-Object -Skip $s -First $l | ForEach-Object { $k++; $i=$s+$k; $n=$_.Name; if($n.Length -gt 25){$n=$n.Substring(0,22)+'...'}; $d=$_.Description; if($installed.ContainsKey($_.Name)){$d='   [Installed]    '+$d}; if($d.Length -gt $dw){$d=$d.Substring(0,$dw-3)+'...'}; Write-Host ('{0,3}. {1,-25} {2,-10} {3,-8}  {4}' -f $i,$n,$_.Size,$_.Params,$d) }"

echo.
echo For descriptions and the full list, visit https://ollama.com/library
echo.
REM Show navigation options based on current page position
if !page! lss !total_pages! (
    if !page! gtr 1 (
        echo [N] Next Page  [P] Previous Page  [R] Refresh List  [C] Cancel  [X] Exit
    ) else (
        echo [N] Next Page  [R] Refresh List  [C] Cancel  [X] Exit
    )
) else (
    if !page! gtr 1 (
        echo [P] Previous Page  [R] Refresh List  [C] Cancel  [X] Exit
    ) else (
        echo [R] Refresh List  [C] Cancel  [X] Exit
    )
)
set /p model_input="Enter model number or name to pull: "

REM Handle pagination navigation commands
if /i "!model_input!"=="n" goto handle_next_page
if /i "!model_input!"=="p" goto handle_prev_page
if /i "!model_input!"=="r" goto handle_refresh
if /i "!model_input!"=="x" (
    exit /b
)
if /i "!model_input!"=="c" (
    cls
    if !count! equ 0 (
        exit /b
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

ollama pull "!model_name!"
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
if not exist "%MODELS_CACHE%" exit /b
for /f "usebackq tokens=1,2,3* delims=|" %%a in ("%MODELS_CACHE%") do (
    if "%%a" neq "" (
        set /a remote_count+=1
        set "r_model[!remote_count!]=%%a"
        set "r_size[!remote_count!]=%%b"
        set "r_params[!remote_count!]=%%c"
        set "r_desc[!remote_count!]=%%d"
    )
)
exit /b

:create_fetch_script
REM Create the fetch_models.ps1 script - copy from script directory to %appdata% if available
if exist "%~dp0fetch_models.ps1" (
    copy /Y "%~dp0fetch_models.ps1" "%FETCH_MODELS_SCRIPT%" >nul 2>&1
    if exist "%FETCH_MODELS_SCRIPT%" (
        del "%~dp0fetch_models.ps1"
        echo Moved fetch_models.ps1 to AppData and cleaned up local file.
    )
    exit /b
)

REM Fallback: Generate from Base64 if fetch_models.ps1 not found locally
set "B64_FILE=%TEMP%\fetch_models.b64"
(
REM re-create fetch_models.ps1 Base64 encoded PowerShell script to fetch models from Ollama.com in %appdata%
echo cGFyYW0oW2ludF0kU2tpcD0wLFtpbnRdJExpbWl0PTEwMCxbc3dpdGNoXSRBcHBlbmQsW3N0cmluZ10kQ2FjaGVGaWxlLFtzd2l0Y2hdJExvY2FsKQ0KJEVycm9yQWN0aW9uUHJlZmVyZW5jZT0nU3RvcCcNCltDb25zb2xlXTo6T3V0cHV0RW5jb2Rpbmc9W1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6VVRGOA0KIyBTZXQgZGVmYXVsdCBjYWNoZSBmaWxlIGlmIG5vdCBwcm92aWRlZA0KaWYgKC1ub3QgJENhY2hlRmlsZSkgew0KICAgICRDYWNoZUZpbGUgPSAiJGVudjpBUFBEQVRBXG9sbGFtYUxhdW5jaGVyXG1vZGVsc19jYWNoZS50eHQiDQp9DQojIEVuc3VyZSBjYWNoZSBkaXJlY3RvcnkgZXhpc3RzDQokQ2FjaGVEaXIgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJENhY2hlRmlsZQ0KaWYgKC1ub3QgKFRlc3QtUGF0aCAkQ2FjaGVEaXIpKSB7DQogICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkQ2FjaGVEaXIgLUZvcmNlIHwgT3V0LU51bGwNCn0NCmlmICgkTG9jYWwpIHsNCiAgICAjIExvY2FsIG1vZGU6IExpc3QgaW5zdGFsbGVkIG1vZGVscw0KICAgIHRyeSB7DQogICAgICAgICRvdXRwdXQgPSBvbGxhbWEgbGlzdCB8IFNlbGVjdC1PYmplY3QgLVNraXAgMQ0KICAgICAgICAkbW9kZWxzID0gQCgpDQogICAgICAgIGZvcmVhY2ggKCRsaW5lIGluICRvdXRwdXQpIHsNCiAgICAgICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ14oXFMrKVxzK1xTK1xzKyhcUytccytcUyspJykgew0KICAgICAgICAgICAgICAgICRuYW1lID0gJG1hdGNoZXNbMV0NCiAgICAgICAgICAgICAgICAkc2l6ZSA9ICRtYXRjaGVzWzJdDQogICAgICAgICAgICAgICAgJHBhcmFtcyA9ICdOL0EnDQogICAgICAgICAgICAgICAgaWYgKCRuYW1lIC1tYXRjaCAnOihcZCsoXC5cZCspP1tibV0pJykgeyAkcGFyYW1zID0gJG1hdGNoZXNbMV0gfQ0KICAgICAgICAgICAgICAgIGVsc2VpZiAoJG5hbWUgLW1hdGNoICcoXGQrKFwuXGQrKT9bYm1dKScpIHsgJHBhcmFtcyA9ICRtYXRjaGVzWzFdIH0NCiAgICAgICAgICAgICAgICAkbW9kZWxzICs9IFtQU0N1c3RvbU9iamVjdF1Ae05hbWU9JG5hbWU7IFNpemU9JHNpemU7IFBhcmFtcz0kcGFyYW1zOyBEZXNjcmlwdGlvbj0nSW5zdGFsbGVkJ30NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICBpZiAoJG1vZGVscy5Db3VudCAtZXEgMCkgeyBleGl0IDEgfQ0KICAgICAgICAjIE91dHB1dCB0byBjYWNoZSBmaWxlIGZvciBiYXRjaCBzY3JpcHQgdG8gcmVhZA0KICAgICAgICBpZiAoJENhY2hlRmlsZSkgew0KICAgICAgICAgICAgW1N5c3RlbS5JTy5GaWxlXTo6V3JpdGVBbGxMaW5lcygkQ2FjaGVGaWxlLCBAKCRtb2RlbHMuTmFtZSkpDQogICAgICAgIH0NCiAgICAgICAgIyBEaXNwbGF5IHRhYmxlDQogICAgICAgIHRyeXskdz0kSG9zdC5VSS5SYXdVSS5XaW5kb3dTaXplLldpZHRofWNhdGNoeyR3PTgwfTsgaWYoJHcgLWx0IDYwKXskdz02MH07ICRkdz0kdy01MzsgaWYoJGR3IC1sdCA1KXskZHc9NX0NCiAgICAgICAgV3JpdGUtSG9zdCAoJ3swLC00fSB7MSwtMjV9IHsyLC0xMH0gezMsLTh9ICB7NH0nIC1mICdOdW0nLCdNb2RlbCBOYW1lJywnU2l6ZScsJ1BhcmFtcycsJ0Rlc2NyaXB0aW9uJykNCiAgICAgICAgV3JpdGUtSG9zdCAoJ3swLC00fSB7MSwtMjV9IHsyLC0xMH0gezMsLTh9ICB7NH0nIC1mICgnLScqNCksKCctJyoyNSksKCctJyoxMCksKCctJyo4KSwoJy0nKiRkdykpDQogICAgICAgICRrPTANCiAgICAgICAgZm9yZWFjaCAoJG0gaW4gJG1vZGVscykgew0KICAgICAgICAgICAgJGsrKw0KICAgICAgICAgICAgJG49JG0uTmFtZTsgaWYoJG4uTGVuZ3RoIC1ndCAyNSl7JG49JG4uU3Vic3RyaW5nKDAsMjIpKycuLi4nfTsNCiAgICAgICAgICAgIFdyaXRlLUhvc3QgKCd7MCwzfS4gezEsLTI1fSB7MiwtMTB9IHszLC04fSAgezR9JyAtZiAkaywkbiwkbS5TaXplLCRtLlBhcmFtcywkbS5EZXNjcmlwdGlvbikNCiAgICAgICAgfQ0KICAgICAgICBleGl0IDANCiAgICB9IGNhdGNoIHsNCiAgICAgICAgV3JpdGUtRXJyb3IgJF8NCiAgICAgICAgZXhpdCAxDQogICAgfQ0KfQ0KIyBGZXRjaCBIVE1MIGZyb20gT2xsYW1hIG1vZGVsIGxpYnJhcnkNCiR1cmw9J2h0dHBzOi8vb2xsYW1hLmNvbS9zZWFyY2gnDQp0cnkgew0KICAgICRyZXNwb25zZT1JbnZva2UtV2ViUmVxdWVzdCAtVXJpICR1cmwgLVVzZUJhc2ljUGFyc2luZw0KICAgICRjb250ZW50PSRyZXNwb25zZS5Db250ZW50DQp9IGNhdGNoIHsNCiAgICBXcml0ZS1FcnJvciAkXw0KICAgIGV4aXQgMQ0KfQ0KIyBFeHRyYWN0IG1vZGVsIGxpc3QgaXRlbXMgZnJvbSBIVE1MDQokbW9kZWxSZWdleD1bcmVnZXhdJyg/cyk8bGkgeC10ZXN0LW1vZGVsKC4qPyk8L2xpPicNCiRtYXRjaGVzPSRtb2RlbFJlZ2V4Lk1hdGNoZXMoJGNvbnRlbnQpDQokbW9kZWxzPUAoKQ0KJGNvdW50PTANCiRza2lwcGVkPTANCiMgUHJvY2VzcyBlYWNoIG1vZGVsOiBleHRyYWN0IG5hbWUsIGRlc2NyaXB0aW9uLCBhbmQgc2l6ZSBlc3RpbWF0ZXMNCmZvcmVhY2goJG1hdGNoIGluICRtYXRjaGVzKSB7DQogICAgaWYoJHNraXBwZWQgLWx0ICRTa2lwKSB7ICRza2lwcGVkKys7IGNvbnRpbnVlIH0NCiAgICBpZigkY291bnQgLWdlICRMaW1pdCkgeyBicmVhayB9DQogICAgJG1vZGVsSHRtbD0kbWF0Y2guR3JvdXBzWzFdLlZhbHVlDQogICAgIyBFeHRyYWN0IG1vZGVsIG5hbWUgZnJvbSB0aXRsZQ0KICAgICRuYW1lUmVnZXg9W3JlZ2V4XSd4LXRlc3Qtc2VhcmNoLXJlc3BvbnNlLXRpdGxlPihbXjxdKyk8Jw0KICAgICRuYW1lTWF0Y2g9JG5hbWVSZWdleC5NYXRjaCgkbW9kZWxIdG1sKQ0KICAgICRuYW1lPWlmKCRuYW1lTWF0Y2guU3VjY2Vzcyl7W1N5c3RlbS5OZXQuV2ViVXRpbGl0eV06Okh0bWxEZWNvZGUoJG5hbWVNYXRjaC5Hcm91cHNbMV0uVmFsdWUuVHJpbSgpKX1lbHNleydVbmtub3duJ30NCiAgICAjIEV4dHJhY3QgZGVzY3JpcHRpb24NCiAgICAkZGVzY1JlZ2V4PVtyZWdleF0nKD9zKTxwW14+XSp0ZXh0LW5ldXRyYWwtODAwW14+XSo+KC4qPyk8L3A+Jw0KICAgICRkZXNjTWF0Y2g9JGRlc2NSZWdleC5NYXRjaCgkbW9kZWxIdG1sKQ0KICAgICRkZXNjcmlwdGlvbj1pZigkZGVzY01hdGNoLlN1Y2Nlc3MpeygkZGVzY01hdGNoLkdyb3Vwc1sxXS5WYWx1ZS5UcmltKCktcmVwbGFjZSAnXHMrJywgJyAnKX1lbHNleydObyBkZXNjcmlwdGlvbiBhdmFpbGFibGUnfQ0KICAgICMgRXh0cmFjdCBhbmQgZXN0aW1hdGUgZG93bmxvYWQgc2l6ZSBiYXNlZCBvbiBwYXJhbWV0ZXJzDQogICRzaXplUmVnZXg9W3JlZ2V4XSd4LXRlc3Qtc2l6ZVtePl0qPihbXjxdKyk8Jw0KICAkc2l6ZU1hdGNoZXM9JHNpemVSZWdleC5NYXRjaGVzKCRtb2RlbEh0bWwpDQogIGlmKCRzaXplTWF0Y2hlcy5Db3VudCAtZ3QgMCkgew0KICAgICAgICBmb3JlYWNoKCRzbSBpbiAkc2l6ZU1hdGNoZXMpIHsNCiAgICAgICAgICAgICRwYXJhbVNpemU9JHNtLkdyb3Vwc1sxXS5WYWx1ZS5UcmltKCkNCiAgICAgICAgICAgICRnYlNpemU9J1Vua25vd24nDQogICAgICAgICAgICAjIFN0YW5kYXJkIG1vZGVsczogc2l6ZSA9IChwYXJhbXMgKiBjb21wcmVzc2lvbikgKyBvdmVyaGVhZA0KICAgICAgICAgICAgaWYoJHBhcmFtU2l6ZSAtbWF0Y2ggJyhcZCsoXC5cZCspPyliJyl7DQogICAgICAgICAgICAgICAgJHBNYXRjaD0kTWF0Y2hlcw0KICAgICAgICAgICAgICAgICR2YWw9W2RvdWJsZV0kcE1hdGNoWzFdDQogICAgICAgICAgICAgICAgaWYoJHZhbCAtbGUgMyl7JGVzdD0kdmFsKjAuNiswLjV9ZWxzZWlmKCR2YWwgLWxlIDEwKXskZXN0PSR2YWwqMC41NSswLjV9ZWxzZXskZXN0PSR2YWwqMC41Nn0NCiAgICAgICAgICAgICAgICAkZ2JTaXplPSd7MDpOMX0gR0InLWYgJGVzdA0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgIyBUaW55IG1vZGVscw0KICAgICAgICAgICAgZWxzZWlmKCRwYXJhbVNpemUgLW1hdGNoICcoXGQrKW0nKSB7DQogICAgICAgICAgICAgICAgJGdiU2l6ZT0nPCAxIEdCJw0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgIyBNb0UgbW9kZWxzIChlLmcuIE1peHRyYWwgOHg3Qik6IHNpemUgPSAoZXhwZXJ0cyAqIGV4cGVydF9zaXplKSAqIGNvbXByZXNzaW9uDQogICAgICAgICAgICBlbHNlaWYoJHBhcmFtU2l6ZSAtbWF0Y2ggJyhcZCspeChcZCsoXC5cZCspPyliJyl7DQogICAgICAgICAgICAgICAgJG1NYXRjaD0kTWF0Y2hlcw0KICAgICAgICAgICAgICAgICRleHBlcnRzPVtkb3VibGVdJG1NYXRjaFsxXQ0KICAgICAgICAgICAgICAgICRlU2l6ZT1bZG91YmxlXSRtTWF0Y2hbMl0NCiAgICAgICAgICAgICAgICAkdG90YWw9JGV4cGVydHMqJGVTaXplDQogICAgICAgICAgICAgICAgJGVzdD0kdG90YWwqMC40Ng0KICAgICAgICAgICAgICAgICRnYlNpemU9J3swOk4xfSBHQictZiAkZXN0DQogICAgICAgICAgICB9DQogICAgICAgICAgICAkZnVsbE5hbWU9IiRuYW1lYDokcGFyYW1TaXplIg0KICAgICAgICAgICAgJG1vZGVscys9W1BTQ3VzdG9tT2JqZWN0XUB7TmFtZT0kZnVsbE5hbWU7U2l6ZUdCPSRnYlNpemU7UGFyYW1zPSRwYXJhbVNpemU7RGVzY3JpcHRpb249JGRlc2NyaXB0aW9ufQ0KICAgICAgICB9DQogICAgfSBlbHNlIHsNCiAgICAgICAgJG1vZGVscys9W1BTQ3VzdG9tT2JqZWN0XUB7TmFtZT0kbmFtZTtTaXplR0I9J1Vua25vd24nO1BhcmFtcz0nTi9BJztEZXNjcmlwdGlvbj0kZGVzY3JpcHRpb259DQogICAgfQ0KICAgICRjb3VudCsrDQp9DQojIE91dHB1dCByZXN1bHRzIGluIHBpcGUtZGVsaW1pdGVkIGZvcm1hdCAoTmFtZXxTaXplfFBhcmFtc3xEZXNjcmlwdGlvbikNCiRsaW5lcz1AKCkNCmZvcmVhY2goJG1vZGVsIGluICRtb2RlbHMpIHsNCiAgICAkbGluZXMrPSIkKCRtb2RlbC5OYW1lKXwkKCRtb2RlbC5TaXplR0IpfCQoJG1vZGVsLlBhcmFtcyl8JCgkbW9kZWwuRGVzY3JpcHRpb24pIg0KfQ0KaWYoJEFwcGVuZCkgew0KICAgIFtTeXN0ZW0uSU8uRmlsZV06OkFwcGVuZEFsbExpbmVzKCRDYWNoZUZpbGUsICRsaW5lcykNCn0gZWxzZSB7DQogICAgW1N5c3RlbS5JTy5GaWxlXTo6V3JpdGVBbGxMaW5lcygkQ2FjaGVGaWxlLCAkbGluZXMpDQp9DQpXcml0ZS1Ib3N0ICJTdWNjZXNzZnVsbHkgZmV0Y2hlZCAkKCRtb2RlbHMuQ291bnQpIG1vZGVscy4iDQo=
) > "%B64_FILE%"
powershell -NoProfile -Command "$bytes=[Convert]::FromBase64String((Get-Content '%B64_FILE%')); [System.IO.File]::WriteAllBytes('%FETCH_MODELS_SCRIPT%', $bytes)"
del "%B64_FILE%"
exit /b
