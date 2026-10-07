# Launch the Hand Gesture Control desktop app (Windows PowerShell).
# First-time setup:
#   python -m venv .venv
#   .\.venv\Scripts\pip install -r requirements.txt
#   .\.venv\Scripts\python -m hgr.download_model
# Pass extra options through, e.g.  .\run_app.ps1 --dry-run

$python = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) { $python = "python" }
Set-Location $PSScriptRoot
& $python -m hgr.app @args
