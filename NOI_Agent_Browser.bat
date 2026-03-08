@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "DRY_RUN=0"
set "ENABLE_STARTUP_SHORTCUT=0"

:PARSE_ARGS
if "%~1"=="" goto ARGS_DONE
if /I "%~1"=="--dry-run" (
    set "DRY_RUN=1"
) else if /I "%~1"=="--enable-startup" (
    set "ENABLE_STARTUP_SHORTCUT=1"
)
shift
goto PARSE_ARGS

:ARGS_DONE
for /f "usebackq delims=" %%I in (`whoami`) do set "CURRENT_USER=%%I"

set "NC_DIR=%USERPROFILE%\.zeroclaw"
set "NC_EXE=%NC_DIR%\zeroclaw.exe"
set "NC_CFG=%NC_DIR%\config.toml"
set "TOKEN_FILE=%NC_DIR%\bearer.token"
set "PATCH_HELPER=%NC_DIR%\NOI_Agent_Browser_Harden.ps1"
set "SKILLS_DIR=%NC_DIR%\skills"
set "MEMORY_DIR=%NC_DIR%\memory"
set "SESSIONS_DIR=%NC_DIR%\sessions"
set "LOG_DIR=%NC_DIR%\logs"
set "AGENT_DIR=%~dp0"
set "AGENT_DIR=%AGENT_DIR:~0,-1%"
set "SCRIPT_PATH=%~f0"
set "CANONICAL_LAUNCHER=%NC_DIR%\NOI_Agent_Browser.bat"
set "DESKTOP_LAUNCHER=%USERPROFILE%\Desktop\NOI_Agent_Browser.bat"
set "LOG=%LOG_DIR%\noi_agent.log"
set "LAUNCH_LOG=%LOG%"
set "GW_HOST=127.0.0.1"
set "GW_PORT=42617"
set "GW_URL=http://%GW_HOST%:%GW_PORT%"
set "SHORTCUT_NAME=NOI Agent Browser.lnk"

set "NOI_DIR=%USERPROFILE%\AppData\Local\noi"
set "NOI_EXE="
set "NOI_CFG_DIR=%USERPROFILE%\AppData\Roaming\noi"
set "NOI_GATEWAY_CFG=%NOI_CFG_DIR%\gateway.json"

for %%F in ("%NOI_DIR%\*.exe") do (
    if not defined NOI_EXE set "NOI_EXE=%%~fF"
)
if not defined NOI_EXE (
    for /R "%NOI_DIR%" %%F in (*.exe) do (
        if not defined NOI_EXE set "NOI_EXE=%%~fF"
    )
)

echo.
echo  =========================================================
echo   NOI AGENT BROWSER ^| Hardened Local Launcher
echo   Version: 2026.03.08 ^| Host: %GW_HOST%:%GW_PORT%
echo  =========================================================
echo.

if not exist "%NC_EXE%" (
    echo [FAIL] No-Claw engine not found: %NC_EXE%
    pause
    exit /b 1
)
echo [ OK ] No-Claw engine: %NC_EXE%

if not exist "%PATCH_HELPER%" (
    echo [FAIL] Hardening helper not found: %PATCH_HELPER%
    pause
    exit /b 1
)
echo [ OK ] Hardening helper: %PATCH_HELPER%
call :LOCK_DOWN_FILE "%PATCH_HELPER%"

if not defined NOI_EXE (
    echo [FAIL] NOI exe not found in: %NOI_DIR%
    dir "%NOI_DIR%" /B 2>nul
    pause
    exit /b 1
)
echo [ OK ] NOI browser: %NOI_EXE%

call :VERIFY_SIGNATURE "%NC_EXE%" "No-Claw engine"
if errorlevel 1 exit /b 1
call :VERIFY_SIGNATURE "%NOI_EXE%" "NOI browser"
if errorlevel 1 exit /b 1

call :ENSURE_DIR "%SKILLS_DIR%"
call :ENSURE_DIR "%MEMORY_DIR%"
call :ENSURE_DIR "%SESSIONS_DIR%"
call :ENSURE_DIR "%LOG_DIR%"
call :ENSURE_DIR "%NOI_CFG_DIR%"
call :LOCK_DOWN_DIR "%SKILLS_DIR%"
call :LOCK_DOWN_DIR "%MEMORY_DIR%"
call :LOCK_DOWN_DIR "%SESSIONS_DIR%"
call :LOCK_DOWN_DIR "%LOG_DIR%"
echo [ OK ] Directories verified and locked down.
call :TRY_HARDEN_FIREWALL

call :ENSURE_TOKEN
if errorlevel 1 (
    echo [FAIL] Bearer token setup failed.
    pause
    exit /b 1
)
set /p BEARER=<"%TOKEN_FILE%"
echo [ OK ] Bearer token ready.

echo [ .. ] Writing hardened No-Claw config...
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%PATCH_HELPER%" ^
    -ConfigFile "%NC_CFG%" ^
    -Token "%BEARER%" ^
    -SkillsDir "%SKILLS_DIR%" ^
    -MemoryDir "%MEMORY_DIR%" ^
    -SessionsDir "%SESSIONS_DIR%" ^
    -AuditLog "%LOG_DIR%\audit.log"
if errorlevel 1 (
    echo [FAIL] Config hardening failed. Check: %NC_CFG%
    pause
    exit /b 1
)
call :LOCK_DOWN_FILE "%NC_CFG%"
echo [ OK ] Config hardened: local-only bind, pairing required, audit enabled.

if not exist "%SKILLS_DIR%\web-search\SKILL.md" (
    mkdir "%SKILLS_DIR%\web-search" 2>nul
    (
        echo # SKILL: web-search
        echo Use when the user asks about recent or current information.
        echo Output: concise paraphrased summary with attribution.
    ) > "%SKILLS_DIR%\web-search\SKILL.md"
)
if not exist "%MEMORY_DIR%\agent.md" (
    (
        echo # No-Claw Agent Memory
        echo - Engine: No-Claw ^| Interface: NOI WebView
        echo - Gateway: %GW_URL%
        echo - Security: local-only bind, pairing required, supervised autonomy
    ) > "%MEMORY_DIR%\agent.md"
)
call :LOCK_DOWN_DIR "%SKILLS_DIR%"
call :LOCK_DOWN_DIR "%MEMORY_DIR%"
echo [ OK ] Skill and memory scaffolding ready.

call :WRITE_NOI_CONFIG
if errorlevel 1 (
    echo [FAIL] NOI auto-connect config could not be written.
    pause
    exit /b 1
)
echo [ OK ] NOI auto-connect config written and protected.

call :CREATE_DESKTOP_SHORTCUT
call :HANDLE_STARTUP_SHORTCUT

if "%DRY_RUN%"=="1" (
    echo [DRY] Dry run enabled. Skipping gateway stop/start and NOI launch.
    echo.
    echo  =========================================================
    echo   DRY RUN COMPLETE
    echo  ---------------------------------------------------------
    echo   Gateway    : %GW_URL%
    echo   Config     : %NC_CFG%
    echo   Token      : %TOKEN_FILE%
    echo   NOI Config : %NOI_GATEWAY_CFG%
    echo   Log        : %LOG%
    echo  =========================================================
    echo.
    endlocal
    exit /b 0
)

call :CHECK_GATEWAY
if "!ERRORLEVEL!"=="0" (
    echo [ OK ] Reusing healthy local gateway.
    goto LAUNCH_NOI
)

call :STOP_GATEWAY_ON_PORT
echo [ .. ] Starting No-Claw Gateway...
start "" /B "%NC_EXE%" gateway 1>>"%LOG%" 2>&1

set "GW_ATTEMPTS=0"
:HEALTH_LOOP
set /a GW_ATTEMPTS+=1
call :CHECK_GATEWAY
if "!ERRORLEVEL!"=="0" goto GATEWAY_READY
if %GW_ATTEMPTS% geq 30 goto HEALTH_TIMEOUT
echo [ .. ] Waiting for No-Claw Gateway... attempt %GW_ATTEMPTS%/30
timeout /t 1 /nobreak >nul
goto HEALTH_LOOP

:GATEWAY_READY
echo [ OK ] No-Claw Gateway connected and healthy.
goto LAUNCH_NOI

:HEALTH_TIMEOUT
echo [WARN] Gateway did not respond after 30 seconds.
echo [WARN] Last log lines:
powershell -NoProfile -Command "if(Test-Path $env:LAUNCH_LOG){Get-Content -LiteralPath $env:LAUNCH_LOG -Tail 10}else{Write-Host 'No log found.'}"
echo [WARN] NOI will open but may show disconnected.

:LAUNCH_NOI
echo [ .. ] Launching NOI...
start "" "%NOI_EXE%"

echo.
echo  =========================================================
echo   READY - No-Claw Engine Active
echo  ---------------------------------------------------------
echo   NOI App    : %NOI_EXE%
echo   Gateway    : %GW_URL%
echo   Bind       : LOCALHOST ONLY
echo   Pairing    : REQUIRED
echo   Autonomy   : SUPERVISED / WORKSPACE-ONLY
echo   Skills     : %SKILLS_DIR%
echo   Memory     : %MEMORY_DIR%
echo   Log        : %LOG%
echo   Config     : %NC_CFG%
echo  =========================================================
echo.

endlocal
exit /b 0

:ENSURE_DIR
if not exist "%~1" mkdir "%~1" >nul 2>&1
exit /b 0

:LOCK_DOWN_DIR
if not exist "%~1" exit /b 0
icacls "%~1" /inheritance:r /grant:r "%CURRENT_USER%:(OI)(CI)F" /grant:r "*S-1-5-18:(OI)(CI)F" /grant:r "*S-1-5-32-544:(OI)(CI)F" >nul 2>&1
exit /b 0

:LOCK_DOWN_FILE
if not exist "%~1" exit /b 0
icacls "%~1" /inheritance:r /grant:r "%CURRENT_USER%:F" /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F" >nul 2>&1
exit /b 0

:VERIFY_SIGNATURE
set "VERIFY_TARGET=%~1"
set "VERIFY_LABEL=%~2"
powershell -NoProfile -Command "try { Import-Module Microsoft.PowerShell.Security -ErrorAction Stop; $sig = Get-AuthenticodeSignature -LiteralPath $env:VERIFY_TARGET; if ($sig.Status -in @('HashMismatch','NotTrusted')) { exit 2 } elseif ($sig.Status -eq 'Valid') { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if errorlevel 2 (
    echo [FAIL] %VERIFY_LABEL% failed signature validation: %VERIFY_TARGET%
    exit /b 1
)
if errorlevel 1 (
    echo [WARN] %VERIFY_LABEL% is unsigned or not verifiable. Continuing with local-only restrictions.
    exit /b 0
)
echo [ OK ] %VERIFY_LABEL% signature valid.
exit /b 0

:ENSURE_TOKEN
set "TOKEN_ACTION="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "if (-not (Test-Path -LiteralPath $env:TOKEN_FILE)) { 'ROTATE' } elseif (((Get-Date) - (Get-Item -LiteralPath $env:TOKEN_FILE).LastWriteTime).TotalDays -ge 7) { 'ROTATE' } else { 'KEEP' }" 2^>nul`) do set "TOKEN_ACTION=%%I"
if /I "%TOKEN_ACTION%"=="ROTATE" (
    echo [ .. ] Rotating bearer token...
    powershell -NoProfile -Command "$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $bytes = New-Object byte[] 32; $rng.GetBytes($bytes); [BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant() | Set-Content -LiteralPath $env:TOKEN_FILE -NoNewline"
    if errorlevel 1 exit /b 1
)
call :LOCK_DOWN_FILE "%TOKEN_FILE%"
exit /b 0

:WRITE_NOI_CONFIG
powershell -NoProfile -Command "$cfg = [ordered]@{ gateway_url = $env:GW_URL; bearer_token = $env:BEARER; auto_connect = $true; engine = 'no-claw'; local_only = $true; require_pairing = $true }; $json = $cfg | ConvertTo-Json; Set-Content -LiteralPath $env:NOI_GATEWAY_CFG -Value $json -Encoding UTF8"
if errorlevel 1 exit /b 1
call :LOCK_DOWN_FILE "%NOI_GATEWAY_CFG%"
exit /b 0

:CREATE_DESKTOP_SHORTCUT
if exist "%DESKTOP_LAUNCHER%" (
    if exist "%USERPROFILE%\Desktop\NOI Agent Browser.lnk" del /q "%USERPROFILE%\Desktop\NOI Agent Browser.lnk" >nul 2>&1
    echo [ OK ] Desktop launcher file ready: %DESKTOP_LAUNCHER%
    exit /b 0
)
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $path = Join-Path ([Environment]::GetFolderPath('Desktop')) $env:SHORTCUT_NAME; $target = $env:CANONICAL_LAUNCHER; $s = $ws.CreateShortcut($path); $s.TargetPath = $target; $s.WorkingDirectory = Split-Path -Path $target -Parent; $s.IconLocation = $env:NOI_EXE; $s.Description = 'NOI Agent Browser - Hardened Local Launcher'; $s.Save()" >nul 2>&1
echo [ OK ] Desktop shortcut updated.
exit /b 0

:HANDLE_STARTUP_SHORTCUT
set "STARTUP_SHORTCUT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\%SHORTCUT_NAME%"
if "%ENABLE_STARTUP_SHORTCUT%"=="1" (
    powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $path = $env:STARTUP_SHORTCUT; $s = $ws.CreateShortcut($path); $s.TargetPath = $env:CANONICAL_LAUNCHER; $s.WorkingDirectory = $env:NC_DIR; $s.IconLocation = $env:NOI_EXE; $s.Description = 'NOI Agent Browser - Hardened Local Launcher'; $s.Arguments = ''; $s.Save()" >nul 2>&1
    echo [ OK ] Startup shortcut enabled by request.
    exit /b 0
)
if exist "%STARTUP_SHORTCUT%" del /q "%STARTUP_SHORTCUT%" >nul 2>&1
echo [ OK ] Startup shortcut disabled by default.
exit /b 0

:CHECK_GATEWAY
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri ($env:GW_URL + '/health') -UseBasicParsing -TimeoutSec 2; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400) { exit 0 } else { exit 1 } } catch { try { $r2 = Invoke-WebRequest -Uri $env:GW_URL -UseBasicParsing -TimeoutSec 2; if ($r2.StatusCode -ge 200 -and $r2.StatusCode -lt 400) { exit 0 } else { exit 1 } } catch { exit 1 } }" >nul 2>&1
exit /b %ERRORLEVEL%

:STOP_GATEWAY_ON_PORT
set "STOP_RESULT="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$conn = Get-NetTCPConnection -LocalAddress $env:GW_HOST -LocalPort ([int]$env:GW_PORT) -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($conn) { $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue; if ($proc -and $proc.ProcessName -eq 'zeroclaw') { Stop-Process -Id $proc.Id -Force -ErrorAction Stop; 'STOPPED' } }"`) do set "STOP_RESULT=%%I"
if /I "%STOP_RESULT%"=="STOPPED" (
    echo [ .. ] Stopped stale gateway bound to %GW_HOST%:%GW_PORT%.
    timeout /t 2 /nobreak >nul
)
exit /b 0

:TRY_HARDEN_FIREWALL
net session >nul 2>&1
if errorlevel 1 (
    echo [WARN] Firewall hardening skipped ^(admin rights required^).
    exit /b 0
)
powershell -NoProfile -Command "$name = 'NOI Agent Gateway Block Inbound'; Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Block -Protocol TCP -LocalPort ([int]$env:GW_PORT) -Profile Any | Out-Null"
if errorlevel 1 (
    echo [WARN] Firewall hardening could not be applied.
) else (
    echo [ OK ] Inbound firewall block applied for TCP port %GW_PORT%.
)
exit /b 0
