#!/bin/bash

# Node Installation Script
# Purpose: Infernet node setup with Docker, Foundry, and contract deployment
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
log "System update aur dependencies install kar raha hu..." "$YELLOW"
cd "$HOME" || error_exit "Home directory mein jane mein fail hua"
sudo apt update && sudo apt upgrade -y
check_status "System packages update nahi hue"
sudo apt -qy install curl git nano jq lz4 build-essential screen -y
check_status "Basic dependencies install nahi hue"
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
check_status "Additional dependencies install nahi hue"

# **Step 2: Install Docker**
log "Docker install kar raha hu..." "$YELLOW"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    check_status "Docker GPG key add nahi hui"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_status "Docker repository add nahi hua"
    sudo apt update && sudo apt install -y docker-ce
    check_status "Docker install nahi hua"
    sudo systemctl enable --now docker
    check_status "Docker service enable nahi hui"
    sudo usermod -aG docker "$USER"
    check_status "User ko Docker group mein add nahi kiya"
    newgrp docker
else
    log "Docker pehle se installed hai, skip kar raha hu." "$GREEN"
fi

# **Step 3: Install Docker Compose**
log "Docker Compose install kar raha hu..." "$YELLOW"
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    check_status "Docker Compose download nahi hua"
    sudo chmod +x /usr/local/bin/docker-compose
    check_status "Docker Compose permissions set nahi hue"
else
    log "Docker Compose pehle se installed hai, skip kar raha hu." "$GREEN"
fi

# **Step 4: Configure UFW Firewall**
log "UFW firewall configure kar raha hu..." "$YELLOW"
if ! command -v ufw &> /dev/null; then
    sudo apt install ufw -y
    check_status "UFW install nahi hua"
fi
sudo ufw allow 22
sudo ufw allow 3000
sudo ufw allow 4000
sudo ufw allow 6379
sudo ufw allow 8545
sudo ufw allow ssh
sudo ufw --force enable
check_status "UFW configure nahi hua"

# **Step 5: Clone Repository and Modify Port**
log "Repository clone kar raha hu aur port modify kar raha hu..." "$YELLOW"
if [ ! -d "$CONFIG_DIR" ]; then
    git clone https://github.com/ritual-net/infernet-container-starter "$CONFIG_DIR"
    check_status "Repository clone nahi hua"
fi
cd "$CONFIG_DIR" || error_exit "$CONFIG_DIR mein jane mein fail hua"
find . -type f -exec grep -l "3000" {} + | xargs sed -i 's/3000/8600/g'
check_status "Port 3000 ko 8600 se replace nahi kiya"

# **Step 6: Pull and Run Hello-World Container for 5 Seconds**
log "Hello-world Docker image pull kar raha hu..." "$YELLOW"
docker pull ritualnetwork/hello-world-infernet:latest
check_status "Docker image pull nahi hui"

log "project=hello-world make deploy-container 5 seconds ke liye run kar raha hu..." "$YELLOW"
timeout 5s project=hello-world make deploy-container
check_status "make deploy-container run nahi hua"

log "Running containers stop kar raha hu..." "$YELLOW"
docker compose -f deploy/docker-compose.yaml stop
check_status "Containers stop nahi hue"

# **Step 7: Prompt for Private Key and RPC URL**
log "Private key aur RPC URL mang raha hu..." "$YELLOW"
read -s -p "Apna EVM wallet private key daal do (0x se start hona chahiye): " PRIVATE_KEY
echo
validate_private_key "$PRIVATE_KEY"
read -p "Apna Base Mainnet RPC URL daal do: " RPC_URL
validate_rpc_url "$RPC_URL"

# **Step 8: Update deploy/config.json**
log "deploy/config.json update kar raha hu..." "$YELLOW"
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
check_status "deploy/config.json create nahi hua"

# **Step 9: Update projects/hello-world/container/config.json**
log "projects/hello-world/container/config.json update kar raha hu..." "$YELLOW"
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
check_status "projects/hello-world/container/config.json create nahi hua"

# **Step 10: Update Deploy.s.sol**
log "Deploy.s.sol update kar raha hu..." "$YELLOW"
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
check_status "Deploy.s.sol create nahi hua"

# **Step 11: Update Makefile**
log "Makefile update kar raha hu..." "$YELLOW"
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
check_status "Makefile create nahi hua"

# **Step 12: Update docker-compose.yaml**
log "docker-compose.yaml update kar raha hu..." "$YELLOW"
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
check_status "docker-compose.yaml create nahi hua"

# **Step 13: Install Foundry**
log "Foundry install kar raha hu..." "$YELLOW"
if ! command -v forge &> /dev/null; then
    curl -L https://foundry.paradigm.xyz | bash
    check_status "Foundry install nahi hua"
    echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> "$HOME/.bashrc"
    source "$HOME/.bashrc"
    foundryup
    check_status "Foundry update nahi hua"
else
    log "Foundry pehle se installed hai, skip kar raha hu." "$GREEN"
fi

# **Step 14: Install Forge Dependencies**
log "Forge dependencies install kar raha hu..." "$YELLOW"
cd "$CONFIG_DIR/projects/hello-world/contracts" || error_exit "Contracts directory mein jane mein fail hua"
rm -rf lib/forge-std lib/infernet-sdk
forge install foundry-rs/forge-std
check_status "forge-std install nahi hua"
forge install ritual-net/infernet-sdk
check_status "infernet-sdk install nahi hua"
ls -ld "$CONFIG_DIR/projects/hello-world/contracts/lib/forge-std" || error_exit "forge-std lib nahi mili"
ls -ld "$CONFIG_DIR/projects/hello-world/contracts/lib/infernet-sdk" || error_exit "infernet-sdk lib nahi mili"

# **Step 15: Start Docker Compose**
log "Docker Compose start kar raha hu..." "$YELLOW"
cd "$HOME" || error_exit "Home directory mein jane mein fail hua"
docker compose -f "$CONFIG_DIR/deploy/docker-compose.yaml" up -d
check_status "Docker Compose start nahi hua"

# **Step 16: Deploy Contracts and Capture Address**
log "Contracts deploy kar raha hu..." "$YELLOW"
cd "$CONFIG_DIR" || error_exit "$CONFIG_DIR mein jane mein fail hua"
CONTRACT_OUTPUT=$(project=hello-world make deploy-contracts 2>&1)
check_status "Contracts deploy nahi hue"
CONTRACT_ADDRESS=$(echo "$CONTRACT_OUTPUT" | grep "Contract Address" | awk '{print $3}' | head -n 1)
if [ -z "$CONTRACT_ADDRESS" ]; then
    error_exit "Contract address extract nahi hua"
fi
echo "$CONTRACT_ADDRESS" > "$CONTRACT_ADDRESS_FILE"
log "Contract Address: $CONTRACT_ADDRESS saved to $CONTRACT_ADDRESS_FILE" "$GREEN"

# **Step 17: Update CallContract.s.sol**
log "CallContract.s.sol update kar raha hu..." "$YELLOW"
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
check_status "CallContract.s.sol update nahi hua"

# **Step 18: Call Contract**
log "Contract call kar raha hu..." "$YELLOW"
project=hello-world make call-contract
check_status "Contract call nahi hua"

# **Step 19: Display Completion Message**
log "Node installation aur configuration successfully complete hua!" "$GREEN"
cat << EOF

Congratulations! Aapka node setup ho gaya hai. Niche details save kar lo:

- **Contract Address**: $CONTRACT_ADDRESS
- **Log File**: $LOG_FILE
- **Contract Address File**: $CONTRACT_ADDRESS_FILE
- **Important Notes**:
  - Apna private key aur RPC URL secure rakho.
  - Agar problem ho to $LOG_FILE check karo.
  - Node background mein Docker Compose ke through chal raha hai.

Node ko monitor karne ke liye:
$ docker compose -f $CONFIG_DIR/deploy/docker-compose.yaml logs -f

Script use karne ke liye shukriya!
EOF

log "Installation process khatam hua." "$GREEN"
