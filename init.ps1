# PowerShell script equivalent

# Set strict mode
Set-StrictMode -Version Latest

# Define Unicode characters
$CHECK_UNICODE=@{
  Object = [Char]8730
  ForegroundColor = 'Green'
  NoNewLine = $true
  }

# Function to print messages
function msg_out {
    Param(
        [string]$message
    )
    Write-Output "$message"
}

# Function to print error messages and exit
function err_out {
    Param(
        [string]$message
    )
    msg_out "ERROR: $message"
    exit 1
}

# Function to print bold messages
function bold {
    Param(
        [string]$message
    )
    Write-Host "$message" -ForegroundColor Yellow
}

# Function to check command dependencies
function check_cmd_dep {
    Param(
        [string]$cmd
    )
    $check_cmd = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($check_cmd) {
        msg_out "$cmd @CHECK_UNICODE"
        return $true
    } else {
        msg_out "$cmd $(bold "x")"
        return $false
    }
}

# Check required commands
bold "Checking for requirements on this machine:"
$check_deps = $true
$download_cmd = ""

if (check_cmd_dep "curl") {
    $download_cmd = "curl"
} elseif (check_cmd_dep "Invoke-WebRequest") {
    $download_cmd = "Invoke-WebRequest"
} else {
    $check_deps = $false
    err_out "you need to have 'curl' or 'Invoke-WebRequest' installed"
}

check_cmd_dep "docker" -or ($check_deps = $false)
check_cmd_dep "docker-compose" -or ($check_deps = $false)
check_cmd_dep "Select-String" -or ($check_deps = $false)
check_cmd_dep "mkdir" -or ($check_deps = $false)
check_cmd_dep "Get-Location" -or ($check_deps = $false)

if (-not $check_deps) {
    err_out "All requirements must be satisfied to run this script!"
}

$DIR = Get-Location
$MGPLAT_DIR = "$DIR\memgraph-platform"
$MGPLAT_COMPOSE_PATH = "$MGPLAT_DIR\docker-compose.yml"
$DOCKER_COMPOSE_URL = "https://raw.githubusercontent.com/memgraph/memgraph-platform/add-docker-compose/docker-compose.yml"

# Check if compose file already exists
if (Test-Path $MGPLAT_COMPOSE_PATH) {
    msg_out "$(bold "Overwriting docker compose file found at:") $MGPLAT_COMPOSE_PATH"
} elseif (-not (Test-Path $MGPLAT_DIR)) {
    New-Item -ItemType Directory -Path $MGPLAT_DIR | Out-Null
}

# Download compose file
msg_out "$(bold "Downloading docker compose file to:") $MGPLAT_COMPOSE_PATH"
if ($download_cmd -eq "curl") {
    curl $DOCKER_COMPOSE_URL -o "$MGPLAT_COMPOSE_PATH"
} else {
    Invoke-WebRequest -Uri $DOCKER_COMPOSE_URL -OutFile "$MGPLAT_COMPOSE_PATH"
}

if (-not $?) {
    err_out "Something went wrong when downloading docker-compose.yml from $DOCKER_COMPOSE_URL"
}

# Run compose
Set-Location $MGPLAT_DIR
msg_out "$(bold "Spinning up memgraph lab and memgraph with mage using docker compose file from:") $MGPLAT_COMPOSE_PATH"
docker-compose up
