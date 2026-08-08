@echo off
setlocal
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" > "%~dp0\vs-buildtools-install.log" 2>&1
echo %ERRORLEVEL%> "%~dp0\vs-buildtools-install.exit"
endlocal
