#!/bin/bash

# Function to display logo
display_logo() {
  sleep 2
  curl -s https://raw.githubusercontent.com/HustleAirdrops/Ritual-Node-Guide/main/logo.sh | bash
  sleep 1
}

# Function to display menu
display_menu() {
  clear
  display_logo
  echo "===================================================="
  echo "     RITUAL NETWORK INFERNET AUTO INSTALLER         "
  echo "===================================================="
  echo ""
  echo "Please select an option:"
  echo "1) Install Ritual Network Infernet"
  echo "2) Uninstall Ritual Network Infernet"
  echo "3) Exit"
  echo ""
  echo "===================================================="
  read -p "Enter your choice (1-3): " choice
}

# Function to install Ritual Network Infernet
install_ritual() {
  clear
  display_logo
  echo "===================================================="
  echo "     ?? INSTALLING RITUAL NETWORK INFERNET ??       "
  echo "===================================================="
  echo ""
  
  # Ask for private key with hidden input
  echo "Please enter your private key (with 0x prefix if needed)"
  echo "Note: Input will be hidden for security"
  read -s private_key
  echo "Private key received (hidden for security)"
  
  # Add 0x prefix if missing
  if [[ ! $private_key =~ ^0x ]]; then
    private_key="0x$private_key"
    echo "Added 0x prefix to private key"
  fi
  
  # Ask for RPC URL from user
  echo "Please enter the RPC URL (e.g., https://mainnet.base.org/):"
  read rpc_url
  echo "RPC URL received: $rpc_url"
  
  echo "Installing dependencies..."
  
  # Update packages & build tools
  sudo apt update && sudo apt upgrade -y
  sudo apt -qy install curl git jq lz4 build-essential screen
  
  # Install Docker
  echo "Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  sudo docker run hello-world
  
  # Install Docker Compose
  echo "Installing Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p $DOCKER_CONFIG/cli-plugins
  curl -SL https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
  chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
  docker compose version
  sudo usermod -aG docker $USER
  docker run hello-world
  
  # Clone Repository
  echo "Cloning repository..."
  git clone https://github.com/ritual-net/infernet-container-starter
  cd infernet-container-starter
  
  # Create config files
  echo "Creating configuration files..."
  
  # Create config.json with private key and user-provided RPC URL
  cat > ~/infernet-container-starter/deploy/config.json << EOL
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
        "rpc_url": "${rpc_url}",
        "registry_address": "0x3B1554f346DFe5c482Bb4BA31b880c1C18412170",
        "wallet": {
          "max_gas_limit": 4000000,
          "private_key": "${private_key}",
          "allowed_sim_errors": []
        },
        "snapshot_sync": {
          "sleep": 3,
          "batch_size": 10000,
          "starting_sub_id": 180000,
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
EOL

  # Copy config to container folder
  cp ~/infernet-container-starter/deploy/config.json ~/infernet-container-starter/projects/hello-world/container/config.json
  
  # Create Deploy.s.sol
  cat > ~/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol << EOL
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

  # Create Makefile with user-provided RPC URL
  cat > ~/infernet-container-starter/projects/hello-world/contracts/Makefile << EOL
# phony targets are targets that don't actually create a file
.phony: deploy

# anvil's third default address
sender := ${private_key}
RPC_URL := ${rpc_url}

# deploying the contract
deploy:
    @PRIVATE_KEY=\$(sender) forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url \$(RPC_URL)

# calling sayGM()
call-contract:
    @PRIVATE_KEY=\$(sender) forge script script/CallContract.s.sol:CallContract --broadcast --rpc-url \$(RPC_URL)
EOL

  # Edit node version in docker-compose.yaml
  sed -i 's/infernet-node:.*/infernet-node:1.4.0/g' ~/infernet-container-starter/deploy/docker-compose.yaml
  
  # Deploy container using systemd instead of screen
  echo "Creating systemd service for Ritual Network..."
  cd ~/infernet-container-starter
  
  # Create a script to be run by systemd
  cat > ~/ritual-service.sh << EOL
#!/bin/bash
cd ~/infernet-container-starter
echo "Starting container deployment at \$(date)" > ~/ritual-deployment.log
project=hello-world make deploy-container >> ~/ritual-deployment.log 2>&1
echo "Container deployment completed at \$(date)" >> ~/ritual-deployment.log

# Keep containers running
cd ~/infernet-container-starter
while true; do
  echo "Checking containers at \$(date)" >> ~/ritual-deployment.log
  if ! docker ps | grep -q "infernet"; then
    echo "Containers stopped. Restarting at \$(date)" >> ~/ritual-deployment.log
    docker compose -f deploy/docker-compose.yaml up -d >> ~/ritual-deployment.log 2>&1
  else
    echo "Containers running normally at \$(date)" >> ~/ritual-deployment.log
  fi
  sleep 300
done
EOL
  
  chmod +x ~/ritual-service.sh
  
  # Create systemd service file
  sudo tee /etc/systemd/system/ritual-network.service > /dev/null << EOL
[Unit]
Description=Ritual Network Infernet Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash /root/ritual-service.sh
Restart=always
RestartSec=30
StandardOutput=append:/root/ritual-service.log
StandardError=append:/root/ritual-service.log

[Install]
WantedBy=multi-user.target
EOL

  # Reload systemd, enable and start service
  sudo systemctl daemon-reload
  sudo systemctl enable ritual-network.service
  sudo systemctl start ritual-network.service
  
  # Verify service is running
  sleep 5
  if sudo systemctl is-active --quiet ritual-network.service; then
    echo "? Ritual Network service started successfully!"
  else
    echo "?? Warning: Service might not have started correctly. Checking status..."
    sudo systemctl status ritual-network.service
  fi
  
  echo "Service logs are being saved to ~/ritual-deployment.log"
  echo "You can check service status with: sudo systemctl status ritual-network.service"
  echo "Continuing with installation..."
  echo ""
  
  # Wait a bit for deployment to start
  echo "Waiting for deployment to initialize..."
  sleep 10
  
  # Check service status again
  echo "Verifying service status..."
  if sudo systemctl is-active --quiet ritual-network.service; then
    echo "? Ritual Network service is running properly."
  else
    echo "?? Service not running correctly. Attempting to restart..."
    sudo systemctl restart ritual-network.service
    sleep 5
    sudo systemctl status ritual-network.service
  fi
  
  # Start containers
  echo "Starting containers..."
  docker compose -f deploy/docker-compose.yaml up -d
  
  # Install Foundry
  echo "Installing Foundry..."
  cd
  mkdir -p foundry
  cd foundry
  
  # Kill any running anvil processes
  pkill anvil 2>/dev/null || true
  sleep 2
  
  # Install Foundry
  curl -L https://foundry.paradigm.xyz | bash
  source ~/.bashrc
  
  echo "Executing foundryup..."
  export PATH="$HOME/.foundry/bin:$PATH"
  $HOME/.foundry/bin/foundryup || foundryup
  
  # Check if forge is in standard path, if not update PATH
  if ! command -v forge &> /dev/null; then
    echo "Adding Foundry to PATH..."
    export PATH="$HOME/.foundry/bin:$PATH"
    echo 'export PATH="$PATH:$HOME/.foundry/bin"' >> ~/.bashrc
    
    # Check if there's an old forge binary
    if [ -f /usr/bin/forge ]; then
      echo "Removing old forge binary..."
      sudo rm /usr/bin/forge
    fi
  fi
  
  # Install libraries with proper error handling
  echo "Installing required libraries..."
  cd ~/infernet-container-starter/projects/hello-world/contracts
  
  # Remove existing libs if they exist
  rm -rf lib/forge-std 2>/dev/null || true
  rm -rf lib/infernet-sdk 2>/dev/null || true
  
  # Try installing with forge-std
  echo "Installing forge-std..."
  forge install --no-commit foundry-rs/forge-std || $HOME/.foundry/bin/forge install --no-commit foundry-rs/forge-std
  
  # Verify forge-std was installed
  if [ ! -d "lib/forge-std" ]; then
    echo "Retrying forge-std installation..."
    rm -rf lib/forge-std 2>/dev/null || true
    $HOME/.foundry/bin/forge install --no-commit foundry-rs/forge-std
  fi
  
  # Try installing infernet-sdk
  echo "Installing infernet-sdk..."
  forge install --no-commit ritual-net/infernet-sdk || $HOME/.foundry/bin/forge install --no-commit ritual-net/infernet-sdk
  
  # Verify infernet-sdk was installed
  if [ ! -d "lib/infernet-sdk" ]; then
    echo "Retrying infernet-sdk installation..."
    rm -rf lib/infernet-sdk 2>/dev/null || true
    $HOME/.foundry/bin/forge install --no-commit ritual-net/infernet-sdk
  fi
  
  # Return to root directory
  cd ~/infernet-container-starter
  
  # Restart Docker containers again
  echo "Restarting Docker containers one more time..."
  docker compose -f deploy/docker-compose.yaml down
  docker rm -f infernet-fluentbit infernet-redis infernet-anvil infernet-node 2>/dev/null || true
  docker compose -f deploy/docker-compose.yaml up -d
  
  # Deploy consumer contract
  echo "Deploying consumer contract..."
  export PRIVATE_KEY="${private_key#0x}"  # Remove 0x prefix if present for foundry
  cd ~/infernet-container-starter
  
  # Run deployment and capture output to extract contract address
  echo "Running contract deployment and capturing address..."
  deployment_output=$(project=hello-world make deploy-contracts 2>&1)
  echo "$deployment_output" > ~/deployment-output.log
  
  # Extract contract address using grep and regex pattern
  contract_address=$(echo "$deployment_output" | grep -oE "Contract Address: 0x[a-fA-F0-9]+" | awk '{print $3}')
  
  if [ -z "$contract_address" ]; then
    echo "?? Could not extract contract address automatically."
    echo "Please check ~/deployment-output.log and enter the contract address manually:"
    read -p "Paste Your Address on basescan, Copy Smartcontract and paste Here (in format 0x...): " contract_address
  else
    echo "? Successfully extracted contract address: $contract_address"
  fi
  
  # Save contract address for future use
  echo "$contract_address" > ~/contract-address.txt
  
  # Update CallContract.s.sol with the new contract address
  echo "Updating CallContract.s.sol with contract address: $contract_address"
  cat > ~/infernet-container-starter/projects/hello-world/contracts/script/CallContract.s.sol << EOL
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {SaysGM} from "../src/SaysGM.sol";

contract CallContract is Script {
    function run() public {
        // Setup wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Call the contract
        SaysGM saysGm = SaysGM($contract_address);
        saysGm.sayGM();

        // Execute
        vm.stopBroadcast();
        vm.broadcast();
    }
}
EOL

  # Call the contract
  echo "Calling contract to test functionality..."
  cd ~/infernet-container-starter
  project=hello-world make call-contract
  
  echo "Checking if containers are running..."
  docker ps | grep infernet
  
  echo "Checking node logs..."
  docker logs infernet-node 2>&1 | tail -n 20
  
  echo ""
  echo "Press any key to return to menu..."
  read -n 1
}

# Function to uninstall Ritual Network Infernet
uninstall_ritual() {
  clear
  display_logo
  echo "===================================================="
  echo "     ?? UNINSTALLING RITUAL NETWORK INFERNET ??    "
  echo "===================================================="
  echo ""
  
  read -p "Are you sure you want to uninstall? (y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Uninstallation cancelled."
    echo "Press any key to return to menu..."
    read -n 1
    return
  fi
  
  echo "Stopping and removing systemd service..."
  # Stop and disable systemd service
  sudo systemctl stop ritual-network.service
  sudo systemctl disable ritual-network.service
  sudo rm /etc/systemd/system/ritual-network.service
  sudo systemctl daemon-reload
  
  echo "Stopping and removing Docker containers..."
  # Stop and remove Docker containers
  docker compose -f ~/infernet-container-starter/deploy/docker-compose.yaml down 2>/dev/null
  
  # Remove the containers manually if they still exist
  echo "Removing containers if they exist..."
  docker rm -f infernet-fluentbit infernet-redis infernet-anvil infernet-node 2>/dev/null || true
  
  echo "Removing installation files..."
  # Remove installation directories and scripts
  rm -rf ~/infernet-container-starter
  rm -rf ~/foundry
  rm -f ~/ritual-service.sh
  rm -f ~/ritual-deployment.log
  rm -f ~/ritual-service.log
  
  echo "Cleaning up Docker resources..."
  # Remove unused Docker resources
  docker system prune -f
  
  echo ""
  echo "===================================================="
  echo "? RITUAL NETWORK INFERNET UNINSTALLATION COMPLETE ?"
  echo "===================================================="
  echo ""
  echo "If you want to completely remove Docker as well, run these commands:"
  echo "sudo apt-get purge docker-ce docker-ce-cli containerd.io"
  echo "sudo rm -rf /var/lib/docker"
  echo "sudo rm -rf /etc/docker"
  echo ""
  echo "Press any key to return to menu..."
  read -n 1
}

# Main program
main() {
  while true; do
    display_menu
    
    case $choice in
      1)
        install_ritual
        ;;
      2)
        uninstall_ritual
        ;;
      3)
        clear
        display_logo
        echo "Thank you for using the Ritual Network Infernet Auto Installer!"
        echo "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid option. Press any key to try again..."
        read -n 1
        ;;
    esac
  done
}

# Run the main program
main
