# ============================================================
# 01-install-iis.ps1 — Install and Configure IIS on Windows Server 2022
#
# HOW TO RUN:
#   1. RDP into the Windows IIS VM
#   2. Open PowerShell as Administrator (right-click → Run as Administrator)
#   3. If needed, allow script execution:
#      Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
#   4. Run: .\01-install-iis.ps1
#
# WHAT THIS DOES:
#   - Installs IIS (Internet Information Services) web server
#   - Enables IIS logging (required for Alloy to collect access logs)
#   - Creates a sample web page so you can verify IIS is working
#   - Opens Windows Firewall ports for HTTP and HTTPS
# ============================================================

# Stop script if any command fails
$ErrorActionPreference = "Stop"

Write-Host "=== Step 1: Installing IIS and required features ===" -ForegroundColor Cyan

# Install IIS with management tools and common HTTP features
# Each feature name explained:
#   Web-Server              = Core IIS web server
#   Web-Common-Http         = Default page, directory browsing, errors
#   Web-Static-Content      = Serve HTML, images, CSS, JS files
#   Web-Default-Doc         = Serve index.html when no file specified
#   Web-Http-Logging        = Write access logs (NEEDED for Alloy!)
#   Web-Request-Monitor     = Current request tracking
#   Web-Mgmt-Console        = IIS Manager GUI
Install-WindowsFeature -Name `
    Web-Server, `
    Web-Common-Http, `
    Web-Static-Content, `
    Web-Default-Doc, `
    Web-Http-Logging, `
    Web-Request-Monitor, `
    Web-Mgmt-Console `
    -IncludeManagementTools

Write-Host "✅ IIS installed" -ForegroundColor Green

# ── Configure IIS Logging ────────────────────────────────────
Write-Host "=== Step 2: Configuring IIS logging ===" -ForegroundColor Cyan

# IIS logs will be written to this folder.
# Alloy will tail these log files.
$iisLogPath = "C:\inetpub\logs\LogFiles"

# Make sure the log directory exists
New-Item -ItemType Directory -Force -Path $iisLogPath | Out-Null

# Load IIS administration module
Import-Module WebAdministration

# Configure IIS to write W3C format logs (standard, readable by most tools)
Set-WebConfigurationProperty `
    -pspath 'MACHINE/WEBROOT/APPHOST' `
    -filter "system.applicationHost/sites/siteDefaults/logFile" `
    -name "logFormat" `
    -value "W3C"

# Enable common log fields: date, time, client IP, method, URI, status code, bytes sent
Set-WebConfigurationProperty `
    -pspath 'MACHINE/WEBROOT/APPHOST' `
    -filter "system.applicationHost/sites/siteDefaults/logFile" `
    -name "logExtFileFlags" `
    -value "Date,Time,ClientIP,UserName,ServerIP,Method,UriStem,UriQuery,HttpStatus,BytesSent,BytesRecv,TimeTaken"

# Set log directory
Set-WebConfigurationProperty `
    -pspath 'MACHINE/WEBROOT/APPHOST' `
    -filter "system.applicationHost/sites/siteDefaults/logFile" `
    -name "directory" `
    -value $iisLogPath

Write-Host "✅ IIS logging configured at: $iisLogPath" -ForegroundColor Green
Write-Host "   Log files will appear at: $iisLogPath\W3SVC1\" -ForegroundColor Gray

# ── Create a sample web page ─────────────────────────────────
Write-Host "=== Step 3: Creating sample web page ===" -ForegroundColor Cyan

$webRoot = "C:\inetpub\wwwroot"
$indexContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Enterprise Monitoring Test - IIS Server</title>
    <style>
        body { font-family: Segoe UI, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }
        .status { background: #e8f5e9; padding: 15px; border-radius: 8px; border-left: 4px solid #4caf50; }
        code { background: #f5f5f5; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>🪟 Windows Server + IIS</h1>
    <div class="status">
        <strong>✅ IIS is running</strong>
        <p>This server is being monitored by Grafana Alloy.</p>
        <p>Metrics and logs are flowing to Prometheus and Loki.</p>
    </div>
    <h2>Monitoring Stack</h2>
    <ul>
        <li><strong>Alloy</strong> — collecting IIS metrics via <code>prometheus.exporter.windows</code></li>
        <li><strong>Prometheus</strong> — storing metrics time-series data</li>
        <li><strong>Loki</strong> — storing IIS access logs</li>
        <li><strong>Grafana</strong> — dashboards and alerting</li>
    </ul>
    <p><em>No WMI required — using PDH API + Event Log API</em></p>
</body>
</html>
"@

Set-Content -Path "$webRoot\index.html" -Value $indexContent -Encoding UTF8
Write-Host "✅ Sample page created at: $webRoot\index.html" -ForegroundColor Green

# ── Create additional test pages (to generate varied log entries) ─
$pages = @("about", "contact", "status", "health")
foreach ($page in $pages) {
    $pageContent = "<html><body><h1>$page</h1><p>Test page for monitoring.</p></body></html>"
    New-Item -ItemType Directory -Force -Path "$webRoot\$page" | Out-Null
    Set-Content -Path "$webRoot\$page\index.html" -Value $pageContent
}
Write-Host "✅ Created test pages: /about, /contact, /status, /health" -ForegroundColor Green

# ── Windows Firewall Rules ───────────────────────────────────
Write-Host "=== Step 4: Configuring Windows Firewall ===" -ForegroundColor Cyan

# HTTP inbound
New-NetFirewallRule `
    -DisplayName "IIS HTTP" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Enabled True | Out-Null

# HTTPS inbound
New-NetFirewallRule `
    -DisplayName "IIS HTTPS" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Enabled True | Out-Null

# Alloy UI inbound (admin only — but firewall is source-IP-agnostic here; NSG handles source IP)
New-NetFirewallRule `
    -DisplayName "Grafana Alloy UI" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 12345 `
    -Action Allow `
    -Enabled True | Out-Null

Write-Host "✅ Firewall rules added for ports 80, 443, 12345" -ForegroundColor Green

# ── Verify IIS is running ────────────────────────────────────
Write-Host "=== Step 5: Verifying IIS ===" -ForegroundColor Cyan

$iisService = Get-Service -Name "W3SVC"
if ($iisService.Status -eq "Running") {
    Write-Host "✅ IIS service is running" -ForegroundColor Green
} else {
    Start-Service -Name "W3SVC"
    Write-Host "✅ IIS service started" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== IIS Setup Complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "VERIFY: Open a browser on your laptop and go to:" -ForegroundColor Yellow
$publicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
Write-Host "  http://$publicIP" -ForegroundColor White
Write-Host ""
Write-Host "IIS log files location (for Alloy config):" -ForegroundColor Yellow
Write-Host "  C:\inetpub\logs\LogFiles\W3SVC1\" -ForegroundColor White
Write-Host ""
Write-Host "Next: Run 02-install-alloy.ps1 (fill in private IPs first!)" -ForegroundColor Yellow
