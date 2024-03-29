# Set strict mode
Set-StrictMode -Version Latest

$CHECKMARK_SYMBOL = @{
  Object = [Char]8730
  ForegroundColor = 'Green'
  NoNewLine = $false
  }

# Function to check command dependencies
function check_cmd_dep {
    Param(
        [string]$cmd
    )
    if ($cmd -eq "docker compose") {
      $check_cmd = docker compose 2>$null
    } else {
      $check_cmd = Get-Command $cmd 2>$null
    }
    if ($check_cmd) {
        Write-Host "$cmd " -NoNewLine
        Write-Host @CHECKMARK_SYMBOL
        return $true
    } else {
        Write-Host "$cmd "
        Write-Host "X" -ForegroundColor Red
        return $false
    }
}

# Check required commands
Write-Host "Checking for requirements on this machine:" -ForegroundColor Yellow
$check_deps = $true
if (-not (check_cmd_dep "Invoke-WebRequest")) {
  $check_deps = $false
}
if (-not (check_cmd_dep "docker")) {
  $check_deps = $false
}
if (-not (check_cmd_dep "docker compose")) {
  $check_deps = $false
}
if (-not (check_cmd_dep "mkdir")) {
  $check_deps = $false
}
if (-not (check_cmd_dep "Get-Location")) {
  $check_deps = $false
}
if (-not $check_deps) {
    Write-Host "All requirements must be satisfied to run this script!" -ForegroundColor Red
    exit 1
}

$DIR = Get-Location
$MGPLAT_DIR = "$DIR\memgraph-platform"
$MGPLAT_COMPOSE_PATH = "$MGPLAT_DIR\docker-compose.yml"
$DOCKER_COMPOSE_URL = "https://raw.githubusercontent.com/memgraph/memgraph-platform/main/docker-compose.yml"

# Check if compose file already exists
if (Test-Path $MGPLAT_COMPOSE_PATH) {
    Write-Host "Overwriting docker compose file found at: $MGPLAT_COMPOSE_PATH" -ForegroundColor Yellow
} elseif (-not (Test-Path $MGPLAT_DIR)) {
    New-Item -ItemType Directory -Path $MGPLAT_DIR | Out-Null
}

# Download compose file
Write-Host "Downloading docker compose file to: $MGPLAT_COMPOSE_PATH" -ForegroundColor Yellow
Invoke-WebRequest -Uri $DOCKER_COMPOSE_URL -OutFile "$MGPLAT_COMPOSE_PATH"
if (-not $?) {
    Write-Host "Something went wrong when downloading docker-compose.yml from $DOCKER_COMPOSE_URL" -ForegroundColor Red
}

# Run compose
Set-Location $MGPLAT_DIR
Write-Host "Pulling memgraph/lab:latest and memgraph/memgraph-mage:latest" -ForegroundColor Yellow
docker pull memgraph/lab:latest
docker pull memgraph/memgraph-mage:latest
Write-Host "Spinning up memgraph lab and memgraph with mage using docker compose file from: $MGPLAT_COMPOSE_PATH" -ForegroundColor Yellow
docker compose up
