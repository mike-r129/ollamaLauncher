# Release Checklist

- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Invoke-Tests.ps1`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\SmokeTest.ps1`.
- Verify portable launch with `ollamaLauncher.bat`.
- Verify PowerShell launch with `powershell -NoProfile -ExecutionPolicy Bypass -File src\OllamaLauncher.ps1`.
- Review README install and uninstall notes.
- Generate release checksums from the packaged files, not from static README text.
