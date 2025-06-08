#!/bin/bash

# Exit on error, unset variable, and pipeline failure
set -euo pipefail

# Function for secure user input
secure_input() {
    local prompt="$1"
    local var_name="$2"
    local hidden="$3"
    
    if [ "$hidden" = true ]; then
        IFS= read -rsp "$prompt: " $var_name
        echo
    else
        read -rp "$prompt: " $var_name
    fi
}

# Function to validate Ethereum private key
validate_private_key() {
    [[ "$1" =~ ^0x[a-fA-F0-9]{64}$ ]] || {
        echo "Invalid private key format. Must start with 0x followed by 64 hex characters"
        return 1
    }
}

# Function to validate RPC URL
validate_rpc_url() {
    [[ "$1" =~ ^https?://.+\..+ ]] || {
        echo "Invalid RPC URL format"
        return 1
    }
}

# Function to replace placeholders in files
replace_placeholder() {
    local file="$1"
    local placeholder="$2"
    local value="$3"
    
    if [ -f "$file" ]; then
        sed -i "s/$placeholder/$value/g" "$file"
    else
        echo "Error: File $file not found for replacement"
        return 1
    fi
}

# Function to handle container deployment with timeout
deploy_with_timeout() {
    local timeout=8
    echo "Starting container deployment (will auto-stop after ${timeout}s)..."
    
    # Start in background
    project=hello-world make deploy-container > /dev/null 2>&1 &
    local pid=$!
    
    # Wait for specified time
    sleep $timeout
    
    # Stop the process
    if kill -0 $pid > /dev/null 2>&1; then
        kill -TERM $pid
        wait $pid
    fi
    echo "Container deployment stopped"
}

# Main installation process
install_infernet_node() {
    echo "Starting Infernet Node installation..."
    
    # System updates
    echo -e "\nUpdating system packages..."
    sudo apt update -y && sudo apt upgrade -y
    sudo apt -qy install curl git nano jq lz4 build-essential screen apt-transport-https ca-certificates software-properties-common
    
    # Docker installation
    echo -e "\nInstalling Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y && sudo apt install -y docker-ce
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    
    # Docker Compose installation
    echo -e "\nInstalling Docker Compose..."
    local compose_url=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.assets[].browser_download_url | select(contains("linux-x86_64"))')
    sudo curl -L "$compose_url" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Firewall setup
    echo -e "\nConfiguring firewall..."
    sudo apt install ufw -y
    sudo ufw allow 22
    sudo ufw allow 3000
    sudo ufw allow 4000
    sudo ufw allow 6379
    sudo ufw allow 8545
    sudo ufw allow 8600
    sudo ufw allow ssh
    echo "y" | sudo ufw enable
    
    # Clone and modify project
    echo -e "\nSetting up project..."
    cd "$HOME"
    git clone https://github.com/ritual-net/infernet-container-starter
    cd infernet-container-starter
    grep -rl "3000" . | xargs sed -i 's/3000/8600/g'
    
    # Pull Docker image
    echo -e "\nPulling container image..."
    docker pull ritualnetwork/hello-world-infernet:latest
    
    # Deploy container with timeout
    deploy_with_timeout
    
    # Get user inputs
    echo -e "\nEnter your credentials:"
    while true; do
        secure_input "Enter Base RPC URL" RPC_URL false
        validate_rpc_url "$RPC_URL" && break
    done
    
    while true; do
        secure_input "Enter EVM private key (0x...)" PRIVATE_KEY true
        validate_private_key "$PRIVATE_KEY" && break
    done
    
    # Generate escaped values for sed
    ESC_RPC_URL=$(printf '%s\n' "$RPC_URL" | sed 's:[\/&]:\\&:g;$!s/$/\\/')
    ESC_PRIVATE_KEY=$(printf '%s\n' "$PRIVATE_KEY" | sed 's:[\/&]:\\&:g;$!s/$/\\/')
    
    # Configuration files setup
    echo -e "\nConfiguring application..."
    
    # Create config files
    CONFIG_CONTENT='{
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
        "rpc_url": "RPC_URL",
        "registry_address": "0x3B1554f346DFe5c482Bb4BA31b880c1C18412170",
        "wallet": {
          "max_gas_limit": 4000000,
          "private_key": "PRIVATE_KEY",
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
            "port": "8600",
            "allowed_delegate_addresses": [],
            "allowed_addresses": [],
            "allowed_ips": [],
            "command": "--bind=0.0.0.0:8600 --workers=2",
            "env": {},
            "volumes": [],
            "accepted_payments": {},
            "generates_proofs": false
        }
    ]
}'
    
    # Write config files
    echo "$CONFIG_CONTENT" | sed "s/RPC_URL/$ESC_RPC_URL/g; s/PRIVATE_KEY/$ESC_PRIVATE_KEY/g" > deploy/config.json
    echo "$CONFIG_CONTENT" | sed "s/RPC_URL/$ESC_RPC_URL/g; s/PRIVATE_KEY/$ESC_PRIVATE_KEY/g" > projects/hello-world/container/config.json
    
    # Create contract deployment script
    cat > projects/hello-world/contracts/script/Deploy.s.sol << 'EOL'
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
EOL

    # Create Makefile
    cat > projects/hello-world/contracts/Makefile << EOL
# phony targets are targets that don't actually create a file
.phony: deploy

# anvil's third default address
sender := $PRIVATE_KEY
RPC_URL := $RPC_URL

# deploying the contract
deploy:
	@PRIVATE_KEY=\$(sender) forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url \$(RPC_URL)

# calling sayGM()
call-contract:
	@PRIVATE_KEY=\$(sender) forge script script/CallContract.s.sol:CallContract --broadcast --rpc-url \$(RPC_URL)
EOL

    # Create docker-compose.yaml
    cat > deploy/docker-compose.yaml << 'EOL'
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
EOL

    # Install Foundry
    echo -e "\nInstalling Foundry..."
    cd "$HOME"
    curl -L https://foundry.paradigm.xyz | bash
    echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    foundryup

    # Setup contracts
    echo -e "\nSetting up contracts..."
    cd ~/infernet-container-starter/projects/hello-world/contracts
    rm -rf lib/forge-std lib/infernet-sdk
    forge install foundry-rs/forge-std
    forge install ritual-net/infernet-sdk

    # Start services
    echo -e "\nStarting Docker services..."
    cd "$HOME"
    docker compose -f infernet-container-starter/deploy/docker-compose.yaml up -d

    # Deploy contracts
    echo -e "\nDeploying contracts..."
    cd ~/infernet-container-starter
    if output=$(project=hello-world make deploy-contracts 2>&1); then
        contract_address=$(echo "$output" | awk '/Contract Address:/ {print $3}')
        echo "Contract deployed at: $contract_address"
        
        # Update call contract script
        sed -i "s/SaysGM(.*)/SaysGM($contract_address)/" projects/hello-world/contracts/script/CallContract.s.sol
        
        # Call contract
        echo -e "\nCalling contract..."
        project=hello-world make call-contract
        
        # Final output
        echo -e "\n\nInstallation completed successfully!"
        echo "========================================"
        echo "Infernet Node running on port 4000"
        echo "Container running on port 8600"
        echo "Contract address: $contract_address"
        echo "========================================"
    else
        echo "Contract deployment failed:"
        echo "$output"
        exit 1
    fi
}

# Run installation
install_infernet_node
