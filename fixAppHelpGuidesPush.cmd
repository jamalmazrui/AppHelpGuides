@echo off
rem fixAppHelpGuidesPush.cmd
rem Clears GitHub's secret-scanning block on the AppHelpGuides repository.
rem Writes fixAppHelpGuidesPush.log. Pass -bNoPush to stop before pushing.
setlocal
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "fixAppHelpGuidesPush.ps1" %*
set exitCode=%errorlevel%
popd
endlocal & exit /b %exitCode%
