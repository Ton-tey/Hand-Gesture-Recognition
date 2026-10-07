@echo off
REM Launch the Hand Gesture Control desktop app (Windows). Extra options are passed through,
REM e.g.  run_app.bat --dry-run
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -m hgr.app %*
) else (
    python -m hgr.app %*
)
