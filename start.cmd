@echo off
cd /d "%~dp0"
echo.
echo   Starting local server...  http://localhost:8080
echo   (Press Ctrl+C to stop)
echo.
start "" http://localhost:8080
node serve.js
pause
