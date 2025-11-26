# name: scripts/create_zips.ps1
# Usage: Open PowerShell in repo root and run: .\scripts\create_zips.ps1
# Notes: Requires: 7zip (optional) or built-in Compress-Archive, and mysqldump or Docker

param()
$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Location).Path
$dist = Join-Path $repoRoot 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null

$backend = Join-Path $repoRoot 'backend'
$frontend = Join-Path $repoRoot 'frontend'
$dbDumpFile = Join-Path $dist 'db_dump.sql'
$dbZip = Join-Path $dist 'db_dump.zip'
$backendZip = Join-Path $dist 'backend.zip'
$frontendZip = Join-Path $dist 'frontend.zip'

# Try docker container dump first
$dbContainer = 'ecomm-db'
$dumpDone = $false
$dockerPresent = (Get-Command docker -ErrorAction SilentlyContinue) -ne $null

if ($dockerPresent) {
  $running = docker ps --format '{{.Names}}' | Select-String "^$dbContainer$"
  if ($running) {
    Write-Host "Detected docker container $dbContainer; attempting mysqldump inside container..."
    # Attempt to run mysqldump inside container
    try {
      docker exec $dbContainer sh -c "mysqldump -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\"" > $dbDumpFile
      $dumpDone = $true
      Write-Host "DB dump created at $dbDumpFile"
    } catch {
      Write-Warning "Failed to run mysqldump in container: $_"
    }
  }
}

if (-not $dumpDone) {
  # Try local mysqldump (use backend/.env if available)
  $envFile = Join-Path $backend '.env'
  $dbHost='127.0.0.1'; $dbPort='3306'; $dbName='ecomm_db'; $dbUser='root'; $dbPass='rootpassword'
  if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
      if ($_ -match '^DB_HOST=(.*)') { $dbHost=$matches[1].Trim('"') }
      if ($_ -match '^DB_PORT=(.*)') { $dbPort=$matches[1].Trim('"') }
      if ($_ -match '^DB_NAME=(.*)') { $dbName=$matches[1].Trim('"') }
      if ($_ -match '^DB_USER=(.*)') { $dbUser=$matches[1].Trim('"') }
      if ($_ -match '^DB_PASS=(.*)') { $dbPass=$matches[1].Trim('"') }
    }
  }
  if (Get-Command mysqldump -ErrorAction SilentlyContinue) {
    Write-Host "Running local mysqldump..."
    & mysqldump -h $dbHost -P $dbPort -u $dbUser -p$dbPass $dbName > $dbDumpFile
    $dumpDone = Test-Path $dbDumpFile
    if ($dumpDone) { Write-Host "DB dump created at $dbDumpFile" }
    else { Write-Warning "Local mysqldump failed or produced no file." }
  } else {
    Write-Warning "mysqldump not found locally and docker container not available - skipping DB dump."
  }
}

if ($dumpDone) {
  Compress-Archive -Path $dbDumpFile -DestinationPath $dbZip -Force
  Write-Host "DB zip created at $dbZip"
}

# Create backend zip (exclude node_modules, storage, .env)
Write-Host "Zipping backend..."
$backendFiles = Get-ChildItem -Path $backend -Recurse | Where-Object {
  -not ($_.FullName -like "*\node_modules\*") -and
  -not ($_.FullName -like "*\storage\*") -and
  -not ($_.Name -match "^\.env$")
}
$backendFiles | Compress-Archive -DestinationPath $backendZip -Force
Write-Host "Backend zip created at $backendZip"

# Create frontend zip
Write-Host "Zipping frontend..."
$frontendFiles = Get-ChildItem -Path $frontend -Recurse | Where-Object {
  -not ($_.FullName -like "*\node_modules\*") -and
  -not ($_.FullName -like "*\dist\*") -and
  -not ($_.Name -match "^\.env$")
}
$frontendFiles | Compress-Archive -DestinationPath $frontendZip -Force
Write-Host "Frontend zip created at $frontendZip"

Write-Host "All done. Files in $dist"
Get-ChildItem -Path $dist