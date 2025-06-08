#!/bin/bash

# Advanced Node Installation Script
# Purpose: Automate the setup of an Infernet node with Docker, Foundry, and contract deployment
# Date: June 08, 2025

# Configuration Variables
LOG_FILE="$HOME/node_installation.log"
CONTRACT_ADDRESS_FILE="$HOME/contract_address.txt"
CONFIG_DIR="$HOME/infernet-container-starter"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color Codes for Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging Function
log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "${2:-$NC}$1${NC}"
}

# Error Handling Function
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Check Command Status
check_status() {
    if [ $? -ne 0 ]; then
        error_exit "$1"
    fi
}

# Validate Private Key Format
validate_private_key() {
    local key=$1
    if [[ ! $key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        error_exit "Invalid private key format. Must start with '0x' followed by 64 hexadecimal characters."
    fi
}

# Validate RPC URL Format
validate_rpc_url() {
    local url=$1
    if [[ ! $url =~ ^https?://[a-zA-Z0-9.-]+ ]]; then
        error_exit "Invalid RPC URL format. Must start with http:// or https://."
    fi
}

# Initialize Log
echo "Node Installation Log - $TIMESTAMP" > "$LOG_FILE"
log "Starting node installation process..."

# **Step 1: Update System and Install Dependencies**
log "Updating system and installing dependencies..." "$YELLOW"
cd "$HOME" || error_exit "Failed to change to home directory"
sudo apt update && sudo apt upgrade -y
check_status "Failed to update system packages"
sudo apt -qy install curl git nano jq lz4 build-essential screen -y
check_status "Failed to install basic dependencies"
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
check_status "Failed to install additional dependencies"

# **Step 2: Install Docker**
log "Installing Docker..." "$YELLOW"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    check_status "Failed to add Docker GPG key"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_status "Failed to add Docker repository"
    sudo apt update && sudo apt install -y docker-ce
    check_status "Failed to install Docker"
    sudo systemctl enable --now docker
    check_status "Failed to enable Docker service"
    sudo usermod -aG docker "$USER"
    check_status "Failed to add user to Docker group"
    newgrp docker
else
    log "Docker already installed, skipping." "$GREEN"
fi

# **Step 3: Install Docker Compose**
log "Installing Docker Compose..." "$YELLOW"
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    check_status "Failed to download Docker Compose"
    sudo chmod +x /usr/local/bin/docker-compose
    check_status "Failed to set Docker Compose permissions"
else
    log "Docker Compose already installed, skipping." "$GREEN"
fi

# **Step 4: Configure UFW Firewall**
log "Configuring UFW firewall..." "$YELLOW"
if ! command -v ufw &> /dev/null; then
    sudo apt install ufw -y
    check_status "Failed to install UFW"
fi
sudo ufw allow 22
sudo ufw allow 3000
sudo ufw allow 4000
sudo ufw allow 6379
sudo ufw allow 8545
sudo ufw allow ssh
sudo ufw --force enable
check_status "Failed to configure UFW"

# **Step 5: Clone Repository and Modify Port**
log "Cloning repository and modifying port..." "$YELLOW"
if [ ! -d "$CONFIG_DIR" ]; then
    git clone https://github.com/ritual-net/infernet-container-starter "$CONFIG_DIR"
    check_status "Failed to clone repository"
fi
cd "$CONFIG_DIR" || error_exit "Failed to change to $CONFIG_DIR"
find . -type f -exec grep -l "3000" {} + | xargs sed -i 's/3000/8600/g'
check_status "Failed to replace port 3000 with 8600"

# **Step 6: Pull and Deploy Hello-World Container**
log "Pulling and deploying hello-world container..." "$YELLOW"
docker pull ritualnetwork/hello-world-infernet:latest
check_status "Failed to pull Docker image"
project=hello-world make deploy-container
check_status "Failed to deploy container"
log "Stopping container..." "$YELLOW"
docker compose -f deploy/docker-compose.yaml stop
check_status "Failed to stop container"

# **Step 7: Prompt for Private Key and RPC URL**
log "Prompting for private key and RPC URL..." "$YELLOW"
read -s -p "Enter your EVM wallet private key (starts with 0x): " PRIVATE_KEY
echo
validate_private_key "$PRIVATE_KEY"
read -p "Enter your Base Mainnet RPC URL: " RPC_URL
validate_rpc_url "$RPC_URL"

# **Step 8: Update deploy/config.json**
log "Updating deploy/config.json..." "$YELLOW"
CONFIG_FILE="$CONFIG_DIR/deploy/config.json"
rm -f "$CONFIG_FILE"
cat << EOF > "$CONFIG_FILE"
{
    "log_path": "infernet_node.log",
    "server": {
        "port": 4000,
        "rate_limit": {
            "num_requests": 100,
            "period": 100
        }
    },
    "chain": {
        "enabled": true,
        "trail_head_blocks": 3,
        "rpc_url": "$RPC_URL",
        "registry_address": "0x3B1554f346DFe5c482Bb4BA31b880c1C18412170",
        "wallet": {
          "max_gas_limit": 4000000,
          "private_key": "$PRIVATE_KEY",
          "allowed_sim_errors": []
        },
        "snapshot_sync": {
          "sleep": 3,
          "batch_size": 500,
          "starting_sub_id": 240000,
          "sync_period": 30
        }
    },
    "startup_wait": 1.0,
    "redis": {
        "host": "redis",
        "port": 6379
    },
    "forward_stats": true,
    "containers": [
        {
            "id": "hello-world",
            "image": "ritualnetwork/hello-world-infernet:latest",
            "external": true,
            "port": "3000",
            "allowed_delegate_addresses": [],
            "allowed_addresses": [],
            "allowed_ips": [],
            "command": "--bind=0.0.0.0:3000 --workers=2",
            "env": {},
            "volumes": [],
            "accepted_payments": {},
            "generates_proofs": false
        }
    ]
}
EOF
check_status "Failed to create deploy/config.json"

# **Step 9: Update projects/hello-world/container/config.json**
log "Updating projects/hello-world/container/config.json..." "$YELLOW"
CONFIG_FILE="$CONFIG_DIR/projects/hello-world/container/config.json"
rm -f "$CONFIG_FILE"
cat << EOF > "$CONFIG_FILE"
{
    "log_path": "infernet_node.log",
    "server": {
        "port": 4000,
        "rate_limit": {
            "num_requests": 100,
            "period": 100
        }
    },
    "chain": {
        "enabled": true,
        "trail_head_blocks": 3,
        "rpc_url": "$RPC_URL",
        "registry_address": "0x3B1554f346DFe5c482Bb4BA31b880c1C18412170",
        "wallet": {
          "max_gas_limit": 4000000,
          "private_key": "$PRIVATE_KEY",
          "allowed_sim_errors": []
        },
        "snapshot_sync": {
          "sleep": 3,
          "batch_size": 500,
          "starting_sub_id": 240000,
          "sync_period": 30
        }
    },
    "startup_wait": 1.0,
    "redis": {
        "host": "redis",
        "port": 6379
    },
    "forward_stats": true,
    "containers": [
        {
            "id": "hello-world",
            "image": "ritualnetwork/hello-world-infernet:latest",
            "external": true,
            "port": "3000",
            "allowed_delegate_addresses": [],
            "allowed_addresses": [],
            "allowed_ips": [],
            "command": "--bind=0.0.0.0:3000 --workers=2",
            "env": {},
            "volumes": [],
            "accepted_payments": {},
            "generates_proofs": false
        }
    ]
}
EOF
check_status "Failed to create projects/hello-world/container/config.json"

# **Step 10: Update Deploy.s.sol**
log "Updating Deploy.s.sol..." "$YELLOW"
DEPLOY_FILE="$CONFIG_DIR/projects/hello-world/contracts/script/Deploy.s.sol"
rm -f "$DEPLOY_FILE"
cat <<EOF > "$DEPLOY_FILE"
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {SaysGM} from "../src/SaysGM.sol";

contract Deploy is Script {
    function run() public {
        // Setup wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Log address
        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Loaded deployer: ", deployerAddress);

        address registry = 0x3B1554f346DFe5c482Bb4BA31b880c1C18412170;
        // Create consumer
        SaysGM saysGm = new SaysGM(registry);
        console2.log("Deployed SaysHello: ", address(saysGm));

        // Execute
        vm.stopBroadcast();
        vm.broadcast();
    }
}
EOF
check_status "Failed to create Deploy.s.sol"

# **Step 11: Update Makefile**
log "Updating Makefile..." "$YELLOW"
MAKEFILE="$CONFIG_DIR/projects/hello-world/contracts/Makefile"
rm -f "$MAKEFILE"
cat << EOF > "$MAKEFILE"
# phony targets
.PHONY: deploy

# anvil's third default address
sender:=$PRIVATE_KEY
RPC_URL:=$RPC_URL

# deploying the contract
deploy:
    @PRIVATE_KEY=\$(sender) forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url \$(RPC_URL)

# calling sayGM()
call-contract:
    @PRIVATE_KEY=\$(sender) forge script script/CallContract.s.sol:CallContract --broadcast --rpc-url \$(RPC_URL)
EOF
check_status "Failed to create Makefile"

# **Step 12: Update docker-compose.yaml**
log "Updating docker-compose.yaml..." "$YELLOW"
DOCKER_COMPOSE="$CONFIG_DIR/deploy/docker-compose.yaml"
rm -f "$DOCKER_COMPOSE"
cat <<EOF > "$DOCKER_COMPOSE"
services:
  node:
    image: ritualnetwork/infernet-node:1.4.0
    ports:
      - "0.0.0.0:4000:4000"
    volumes:
      - ./config.json:/app/config.json
      - node-logs:/logs
      - /var/run/docker.sock:/var/run/docker.sock
    tty: true
    networks:
      - network
    depends_on:
      - redis
      - infernet-anvil
    restart:
      on-failure
    extra_hosts:
      - "host.docker.internal:host-gateway"
    stop_grace_period: 1m
    container_name: infernet-node

  redis:
    image: redis:7.4.0
    ports:
    - "6379:6379"
    networks:
      - network
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf
      - redis-data:/data
    restart:
      on-failure
    container_name: infernet-redis

  fluentbit:
    image: fluent/fluent-bit:3.1.4
    expose:
      - "24224"
    environment:
      - FLUENTBIT_CONFIG_PATH=/fluent-bit/etc/fluent-bit.conf
    volumes:
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
      - /var/log:/var/log:ro
    networks:
      - network
    restart:
      on-failure
    container_name: infernet-fluentbit

  infernet-anvil:
    image: ritualnetwork/infernet-anvil:1.0.0
    command: --host 0.0.0.0 --port 3000 --load-state infernet_deployed.json -b 1
    ports:
      - "8545:3000"
    networks:
      - network
    container_name: infernet-anvil

networks:
  network:

volumes:
  node-logs:
  redis-data:
EOF
check_status "Failed to create docker-compose.yaml"

# **Step 13: Install Foundry**
log "Installing Foundry..." "$YELLOW"
if ! command -v forge &> /dev/null; then
    curl -L https://foundry.paradigm.xyz | bash
    check_status "Failed to install Foundry"
    echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> "$HOME/.bashrc"
    source "$HOME/.bashrc"
    foundryup
    check_status "Failed to update Foundry"
else
    log "Foundry already installed, skipping." "$GREEN"
fi

# **Step 14: Install Forge Dependencies**
log "Installing Forge dependencies..." "$YELLOW"
cd "$CONFIG_DIR/projects/hello-world/contracts" || error_exit "Failed to change to contracts directory"
rm -rf lib/forge-std lib/infernet-sdk
forge install foundry-rs/forge-std
check_status "Failed to install forge-std"
forge install ritual-net/infernet-sdk
check_status "Failed to install infernet-sdk"
ls -ld "$CONFIG_DIR/projects/hello-world/contracts/lib/forge-std" || error_exit "forge-std lib not found"
ls -ld "$CONFIG_DIR/projects/hello-world/contracts/lib/infernet-sdk" || error_exit "infernet-sdk lib not found"

# **Step 15: Start Docker Compose**
log "Starting Docker Compose..." "$YELLOW"
cd "$HOME" || error_exit "Failed to change to home directory"
docker compose -f "$CONFIG_DIR/deploy/docker-compose.yaml" up -d
check_status "Failed to start Docker Compose"

# **Step 16: Deploy Contracts and Capture Address**
log "Deploying contracts..." "$YELLOW"
cd "$CONFIG_DIR" || error_exit "Failed to change to $CONFIG_DIR"
CONTRACT_OUTPUT=$(project=hello-world make deploy-contracts 2>&1)
check_status "Failed to deploy contracts"
CONTRACT_ADDRESS=$(echo "$CONTRACT_OUTPUT" | grep "Contract Address" | awk '{print $3}' | head -n 1)
if [ -z "$CONTRACT_ADDRESS" ]; then
    error_exit "Failed to extract contract address"
fi
echo "$CONTRACT_ADDRESS" > "$CONTRACT_ADDRESS_FILE"
log "Contract Address: $CONTRACT_ADDRESS saved to $CONTRACT_ADDRESS_FILE" "$GREEN"

# **Step 17: Update CallContract.s.sol**
log "Updating CallContract.s.sol..." "$YELLOW"
CALL_CONTRACT_FILE="$CONFIG_DIR/projects/hello-world/contracts/script/CallContract.s.sol"
cat << EOF > "$CALL_CONTRACT_FILE"
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {SaysGM} from "../src/SaysGM.sol";

contract CallContract is Script {
    function run() public {
        // Setup wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        SaysGM saysGm = SaysGM($CONTRACT_ADDRESS);

        saysGm.sayGM();

        vm.stopBroadcast();
    }
}
EOF
check_status "Failed to update CallContract.s.sol"

# **Step 18: Call Contract**
log "Calling contract..." "$YELLOW"
project=hello-world make call-contract
check_status "Failed to call contract"

# **Step 19: Display Completion Message**
log "Node installation and configuration completed successfully!" "$GREEN"
cat << EOF

Congratulations! Your node is up and running. Please save the following details:

- **Contract Address**: $CONTRACT_ADDRESS
- **Log File**: $LOG_FILE
- **Contract Address File**: $CONTRACT_ADDRESS_FILE
- **Important Notes**:
  - Keep your private key and RPC URL secure.
  - Check $LOG_FILE for troubleshooting.
  - Your node is running in the background via Docker Compose.

You can monitor the node with:
$ docker compose -f $CONFIG_DIR/deploy/docker-compose.yaml logs -f

Thank you for using this script!
EOF

log "Installation process ended." "$GREEN"
