#!/bin/bash

# Blue/Green Nginx Remote Deployment Script via SSH
# Deploys the current directory to a remote VM

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Remote server configuration
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_DEPLOY_DIR="${REMOTE_DEPLOY_DIR:-~/nginx_upstream}"
SSH_KEY="${SSH_KEY:-}"

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Remote Blue/Green Deployment via SSH   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Function to print step headers
print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

# Function to print errors
print_error() {
    echo -e "${RED}✗ Error: $1${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}⚠ Warning: $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Get remote server details
if [ -z "$REMOTE_HOST" ]; then
    echo -e "${YELLOW}Enter remote server details:${NC}"
    read -p "Remote server IP/hostname: " REMOTE_HOST
    
    if [ -z "$REMOTE_HOST" ]; then
        print_error "Remote host is required!"
        exit 1
    fi
    
    read -p "SSH user [$REMOTE_USER]: " INPUT_USER
    REMOTE_USER=${INPUT_USER:-$REMOTE_USER}
    
    read -p "SSH port [$REMOTE_PORT]: " INPUT_PORT
    REMOTE_PORT=${INPUT_PORT:-$REMOTE_PORT}
    
    read -p "SSH key path (press Enter for default): " INPUT_KEY
    SSH_KEY=${INPUT_KEY}
    
    read -p "Remote deploy directory [$REMOTE_DEPLOY_DIR]: " INPUT_DIR
    REMOTE_DEPLOY_DIR=${INPUT_DIR:-$REMOTE_DEPLOY_DIR}
fi

echo ""
echo -e "${BLUE}Deployment Configuration:${NC}"
echo -e "  Remote Host: ${GREEN}$REMOTE_HOST${NC}"
echo -e "  SSH User: ${GREEN}$REMOTE_USER${NC}"
echo -e "  SSH Port: ${GREEN}$REMOTE_PORT${NC}"
if [ -n "$SSH_KEY" ]; then
    echo -e "  SSH Key: ${GREEN}$SSH_KEY${NC}"
else
    echo -e "  SSH Key: ${GREEN}default (~/.ssh/)${NC}"
fi
echo -e "  Deploy Directory: ${GREEN}$REMOTE_DEPLOY_DIR${NC}"
echo ""

read -p "Continue with deployment? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled"
    exit 0
fi

# Check local prerequisites
print_step "Checking local prerequisites..."

if ! command -v ssh &> /dev/null; then
    print_error "SSH is not installed. Please install OpenSSH client."
    exit 1
fi

if ! command -v rsync &> /dev/null; then
    print_error "rsync is not installed. Please install rsync."
    exit 1
fi

print_success "Local prerequisites met"
echo ""

# Validate SSH key if provided
if [ -n "$SSH_KEY" ]; then
    print_step "Validating SSH key..."
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    print_success "SSH key found: $SSH_KEY"
    echo ""
fi

# Build SSH command
SSH_CMD="ssh -p $REMOTE_PORT"
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="$SSH_CMD -i $SSH_KEY"
fi

# Test SSH connection
print_step "Testing SSH connection to $REMOTE_HOST..."

echo -e "${YELLOW}Running: $SSH_CMD $REMOTE_USER@$REMOTE_HOST${NC}"
echo ""

# Try connection with verbose output
SSH_OUTPUT=$(mktemp)
SSH_ERROR=$(mktemp)

if $SSH_CMD -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'Connection successful'" > "$SSH_OUTPUT" 2> "$SSH_ERROR"; then
    print_success "SSH connection successful"
    cat "$SSH_OUTPUT"
    rm -f "$SSH_OUTPUT" "$SSH_ERROR"
else
    EXIT_CODE=$?
    print_error "SSH connection failed (exit code: $EXIT_CODE)"
    echo ""
    echo -e "${YELLOW}Error details:${NC}"
    cat "$SSH_ERROR"
    echo ""
    echo -e "${YELLOW}Diagnostic information:${NC}"
    echo ""
    
    # Show what command was run
    echo -e "${BLUE}Command attempted:${NC}"
    echo "  $SSH_CMD $REMOTE_USER@$REMOTE_HOST \"echo 'Connection successful'\""
    echo ""
    
    # Try verbose connection to show more details
    echo -e "${BLUE}Verbose SSH output:${NC}"
    $SSH_CMD -v -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" "echo 'test'" 2>&1 | head -30
    echo ""
    
    # Troubleshooting tips
    echo -e "${YELLOW}Troubleshooting steps:${NC}"
    echo "  1. Test manually: $SSH_CMD $REMOTE_USER@$REMOTE_HOST"
    if [ -n "$SSH_KEY" ]; then
        echo "  2. Check key permissions: chmod 600 $SSH_KEY"
        echo "  3. Verify public key on server: cat ~/.ssh/authorized_keys"
    else
        echo "  2. Check default SSH keys exist: ls -la ~/.ssh/"
        echo "  3. Try with password: ssh -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST"
    fi
    echo "  4. Check server is reachable: ping $REMOTE_HOST"
    echo "  5. Check port is open: nc -zv $REMOTE_HOST $REMOTE_PORT"
    
    rm -f "$SSH_OUTPUT" "$SSH_ERROR"
    exit 1
fi

echo ""

# Sync files to remote server
print_step "Syncing files to remote server..."

# Build rsync SSH command
RSYNC_SSH="ssh -p $REMOTE_PORT"
if [ -n "$SSH_KEY" ]; then
    RSYNC_SSH="$RSYNC_SSH -i $SSH_KEY"
fi

# Create deployment directory on remote
$SSH_CMD "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DEPLOY_DIR"

# Sync current directory to remote (excluding .git, node_modules, etc.)
rsync -avz --progress \
    -e "$RSYNC_SSH" \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='.env' \
    --exclude='*.log' \
    --exclude='.DS_Store' \
    ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DEPLOY_DIR/"

print_success "Files synced successfully"
echo ""

# Deploy on remote server
print_step "Deploying on remote server..."

$SSH_CMD "$REMOTE_USER@$REMOTE_HOST" bash <<EOF
set -e

cd $REMOTE_DEPLOY_DIR

echo "============================================"
echo "Installing prerequisites on remote server..."
echo "============================================"

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
    echo "✓ Docker installed"
else
    echo "✓ Docker already installed"
fi

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "✓ Docker Compose installed"
else
    echo "✓ Docker Compose already installed"
fi

echo ""
echo "============================================"
echo "Setting up environment..."
echo "============================================"

# Setup .env file if it doesn't exist
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "✓ Created .env from .env.example"
else
    echo "✓ Using existing .env file"
fi

echo ""
echo "============================================"
echo "Stopping existing containers..."
echo "============================================"

docker-compose down -v 2>/dev/null || true

echo ""
echo "============================================"
echo "Building Docker images..."
echo "============================================"

docker-compose build --no-cache

echo ""
echo "============================================"
echo "Starting services..."
echo "============================================"

docker-compose up -d

echo ""
echo "✓ Services started successfully"

echo ""
echo "============================================"
echo "Waiting for services to be ready..."
echo "============================================"

sleep 5

# Health checks
echo "Checking service health..."

check_service() {
    local url=\$1
    local name=\$2
    local max_attempts=10
    local attempt=1

    while [ \$attempt -le \$max_attempts ]; do
        if curl -s -f "\$url" > /dev/null 2>&1; then
            echo "✓ \$name is healthy"
            return 0
        fi
        echo "  Attempt \$attempt/\$max_attempts: \$name not ready yet..."
        sleep 2
        attempt=\$((attempt + 1))
    done

    echo "✗ \$name failed health check"
    return 1
}

check_service "http://localhost:8080/version" "Nginx (port 8080)"
check_service "http://localhost:8081/healthz" "Blue Service (port 8081)"
check_service "http://localhost:8082/healthz" "Green Service (port 8082)"

echo ""
echo "============================================"
echo "Deployment Status"
echo "============================================"

docker-compose ps

echo ""
echo "============================================"
echo "Testing deployment..."
echo "============================================"

RESPONSE=\$(curl -s http://localhost:8080/version)
echo "Response: \$RESPONSE"

echo ""
echo "✓ Remote deployment complete!"

EOF

print_success "Remote deployment completed successfully!"
echo ""

# Display access URLs
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Deployment Successful!           ║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Service Endpoints on Remote Server:      ║${NC}"
echo -e "${BLUE}║                                            ║${NC}"
echo -e "${BLUE}║  Main Service (Nginx):                     ║${NC}"
echo -e "${BLUE}║    http://$REMOTE_HOST:8080                ║${NC}"
echo -e "${BLUE}║                                            ║${NC}"
echo -e "${BLUE}║  Blue Service (Direct):                    ║${NC}"
echo -e "${BLUE}║    http://$REMOTE_HOST:8081                ║${NC}"
echo -e "${BLUE}║                                            ║${NC}"
echo -e "${BLUE}║  Green Service (Direct):                   ║${NC}"
echo -e "${BLUE}║    http://$REMOTE_HOST:8082                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Display useful commands
SSH_CMD_DISPLAY="ssh -p $REMOTE_PORT"
if [ -n "$SSH_KEY" ]; then
    SSH_CMD_DISPLAY="$SSH_CMD_DISPLAY -i $SSH_KEY"
fi
SSH_CMD_DISPLAY="$SSH_CMD_DISPLAY $REMOTE_USER@$REMOTE_HOST"

echo -e "${YELLOW}Useful Commands:${NC}"
echo ""
echo -e "  SSH into server:     ${GREEN}$SSH_CMD_DISPLAY${NC}"
echo -e "  View logs:           ${GREEN}$SSH_CMD_DISPLAY 'cd $REMOTE_DEPLOY_DIR && docker-compose logs -f'${NC}"
echo -e "  Test version:        ${GREEN}curl http://$REMOTE_HOST:8080/version${NC}"
echo -e "  Trigger chaos:       ${GREEN}curl -X POST http://$REMOTE_HOST:8081/chaos/start?mode=error${NC}"
echo -e "  Stop chaos:          ${GREEN}curl -X POST http://$REMOTE_HOST:8081/chaos/stop${NC}"
echo -e "  Stop services:       ${GREEN}$SSH_CMD_DISPLAY 'cd $REMOTE_DEPLOY_DIR && docker-compose down'${NC}"
echo ""

# Optional: Run remote test
read -p "Do you want to run the failover test on remote server? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    print_step "Running remote failover test..."
    echo ""
    
    # Test baseline
    echo -e "${YELLOW}1. Testing baseline (Blue should be active)...${NC}"
    curl -i "http://$REMOTE_HOST:8080/version"
    echo ""
    
    # Trigger chaos
    echo -e "${YELLOW}2. Triggering chaos on Blue...${NC}"
    curl -X POST "http://$REMOTE_HOST:8081/chaos/start?mode=error"
    echo ""
    sleep 2
    
    # Test failover
    echo -e "${YELLOW}3. Testing failover (Green should handle requests)...${NC}"
    for i in {1..5}; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$REMOTE_HOST:8080/version")
        POOL=$(curl -s "http://$REMOTE_HOST:8080/version" | grep -o '"pool":"[^"]*"' | cut -d'"' -f4)
        echo "  Request $i: Status=$STATUS, Pool=$POOL"
        sleep 1
    done
    echo ""
    
    # Stop chaos
    echo -e "${YELLOW}4. Stopping chaos...${NC}"
    curl -X POST "http://$REMOTE_HOST:8081/chaos/stop"
    echo ""
    
    print_success "Failover test complete!"
fi

echo ""
print_success "Deployment script finished!"
echo ""
