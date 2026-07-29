@echo off
rem createAppHelpGuides.cmd
rem Creates the AppHelpGuides repository, connects it to GitHub, and pushes.
rem Writes createAppHelpGuides.log. Pass -bPrivate for a private repository.
setlocal
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "createAppHelpGuides.ps1" %*
set exitCode=%errorlevel%
popd
endlocal & exit /b %exitCode%
