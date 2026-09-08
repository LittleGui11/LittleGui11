Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'TaskbarStyleTool\\Run\.ps1' } |
  ForEach-Object {
    Write-Host ("Stopping PID " + $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Write-Host "Done."
