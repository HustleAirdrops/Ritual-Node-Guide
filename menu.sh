#!/bin/bash

display_logo() {
  sleep 2
  curl -s https://raw.githubusercontent.com/HustleAirdrops/Ritual-Node-Guide/main/logo.sh | bash || { echo "Error: Failed to display logo."; exit 1; }
  sleep 1
}

display_menu() {
  clear
  display_logo
  echo "===================================================="
  echo " RITUAL NETWORK INFERNET AUTO INSTALLER "
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

install_ritual() {
  clear
  display_logo
  echo "===================================================="
  echo " ?? INSTALLING RITUAL NETWORK INFERNET ?? "
  echo "===================================================="
  echo ""

  HOME_DIR=$(eval echo ~$USER)
  CONFIG_DIR="$HOME_DIR/infernet-container-starter"
  LOG_FILE="$HOME_DIR/ritual-deployment.log"
  SERVICE_SCRIPT="$HOME_DIR/ritual-service.sh"
  if [ ! -w "$HOME_DIR" ]; then
    echo "Error: Home directory ($HOME_DIR) is not writable."
    exit 1
  fi

  echo "Please enter your private key (with 0x prefix if needed)"
  echo "Note: Input will be hidden for security"
  read -s private_key
  echo "Private key received (hidden for security)"
  if [[ ! $private_key =~ ^0x ]]; then
    private_key="0x$private_key"
    echo "Added 0x prefix to private key"
  fi
  if [[ ! $private_key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "Error: Invalid private key format."
    exit 1
  fi

  echo "Please enter the RPC URL (e.g., https://mainnet.base.org/):"
  read rpc_url
  echo "RPC URL received: $rpc_url"
  if [[ ! $rpc_url =~ ^https?:// ]]; then
    echo "Error: Invalid RPC URL."
    exit 1
  fi

  echo "Installing dependencies..."
  sudo apt update && sudo apt upgrade -y || { echo "Error: Failed to update packages."; exit 1; }
  sudo apt -qy install curl git nano jq lz4 build-essential screen || { echo "Error: Failed to install packages."; exit 1; }
  sudo apt install -y apt-transport-https ca-certificates curl software-properties-common || { echo "Error: Failed to install Docker prerequisites."; exit 1; }
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { echo "Error: Failed to download Docker GPG key."; exit 1; }
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update && sudo apt install -y docker-ce && sudo systemctl enable --now docker || { echo "Error: Failed to install Docker."; exit 1; }
  sudo usermod -aG docker "$USER" && echo "Added user to docker group. Log out and back in for changes to take effect."

  echo "Checking Docker daemon access..."
  if ! sudo docker version > /dev/null 2>&1; then
    echo "Error: Cannot connect to Docker daemon. Ensure Docker is running and you have permissions."
    exit 1
  fi

  LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name' || echo "v2.29.2")
  sudo curl -L "https://github.com/docker/compose/releases/download/$LATEST_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "Error: Failed to download Docker Compose."; exit 1; }
  sudo chmod +x /usr/local/bin/docker-compose

  echo "Configuring firewall..."
  sudo apt install ufw -y || { echo "Error: Failed to install ufw."; exit 1; }
  sudo ufw allow 22
  sudo ufw allow 8600
  sudo ufw allow 4000
  sudo ufw allow 6379
  sudo ufw allow 8545
  sudo ufw allow ssh
  sudo ufw enable <<< "y"

  echo "Cloning repository..."
  git clone https://github.com/ritual-net/infernet-container-starter "$CONFIG_DIR" || { echo "Error: Failed to clone repository."; exit 1; }
  cd "$CONFIG_DIR" || exit 1
  [ -d "$CONFIG_DIR" ] && grep -rl "3000" . | xargs sed -i 's/3000/8600/g'

  echo "Pulling Docker image..."
  sudo docker pull ritualnetwork/hello-world-infernet:latest || { echo "Error: Failed to pull Docker image."; exit 1; }
  project=hello-world make deploy-container || { echo "Error: Failed to deploy container."; exit 1; }
  sudo docker compose -f deploy/docker-compose.yaml stop

  echo "Creating configuration files..."
  cat > "$CONFIG_DIR/deploy/config.json" << EOL
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
}
EOL
  chmod 600 "$CONFIG_DIR/deploy/config.json"
  cat > "$CONFIG_DIR/projects/hello-world/container/config.json" << EOL
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
}
EOL
  chmod 600 "$CONFIG_DIR/projects/hello-world/container/config.json"

  cat > "$CONFIG_DIR/projects/hello-world/contracts/script/Deploy.s.sol" << EOL
// SPDX-License-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.13;
import {Script, console2} from "forge-std/Script.sol";
import {SaysGM} from "../src/SaysGM.sol";
contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Loaded deployer: ", deployerAddress);
        address registry = 0x3B1554f346DFe5c482Bb4BA31b880c1C18412170;
        SaysGM saysGm = new SaysGM(registry);
        console2.log("Deployed SaysHello: ", address(saysGm));
        vm.stopBroadcast();
        vm.broadcast();
    }
}
EOL
  cat > "$CONFIG_DIR/projects/hello-world/contracts/Makefile" << EOL
.phony: deploy
sender := ${private_key}
RPC_URL := ${rpc_url}
deploy:
	@PRIVATE_KEY=\$(sender) forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url \$(RPC_URL)
call-contract:
	@PRIVATE_KEY=\$(sender) forge script script/CallContract.s.sol:CallContract --broadcast --rpc-url \$(RPC_URL)
EOL
  cat > "$CONFIG_DIR/deploy/docker-compose.yaml" << EOL
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
    command: --host 0.0.0.0 --port 8600 --load-state infernet_deployed.json -b 1
    ports:
      - "8545:8600"
    networks:
      - network
    container_name: infernet-anvil
networks:
  network:
volumes:
  node-logs:
  redis-data:
EOL

  echo "Creating systemd service..."
  sudo useradd -m -s /bin/bash ritual 2>/dev/null || true
  sudo chown -R ritual:ritual "$CONFIG_DIR"
  cat > "$SERVICE_SCRIPT" << EOL
#!/bin/bash
cd $CONFIG_DIR
echo "Starting container deployment at \$(date)" >> $LOG_FILE
project=hello-world make deploy-container >> $LOG_FILE 2>&1
echo "Container deployment completed at \$(date)" >> $LOG_FILE
cd $CONFIG_DIR
while true; do
  echo "Checking containers at \$(date)" >> $LOG_FILE
  if ! sudo docker ps | grep -q "infernet"; then
    echo "Containers stopped. Restarting at \$(date)" >> $LOG_FILE
    sudo docker compose -f deploy/docker-compose.yaml up -d >> $LOG_FILE 2>&1
  else
    echo "Containers running normally at \$(date)" >> $LOG_FILE
  fi
  sleep 300
done
EOL
  chmod +x "$SERVICE_SCRIPT"
  sudo chown ritual:ritual "$SERVICE_SCRIPT"
  sudo tee /etc/systemd/system/ritual-network.service > /dev/null << EOL
[Unit]
Description=Ritual Network Infernet Service
After=network.target docker.service
Requires=docker.service
[Service]
Type=simple
User=ritual
Group=ritual
ExecStart=/bin/bash $SERVICE_SCRIPT
Restart=always
RestartSec=30
StandardOutput=append:$HOME_DIR/ritual-service.log
StandardError=append:$HOME_DIR/ritual-service.log
[Install]
WantedBy=multi-user.target
EOL
  sudo systemctl daemon-reload
  sudo systemctl enable ritual-network.service
  sudo systemctl start ritual-network.service
  sleep 5
  if sudo systemctl is-active --quiet ritual-network.service; then
    echo "? Ritual Network service started successfully!"
  else
    echo "?? Warning: Service failed to start."
    sudo systemctl status ritual-network.service
    exit 1
  fi
  echo "Service logs are being saved to $LOG_FILE"

  echo "Installing Foundry..."
  cd "$HOME_DIR" || exit 1
  curl -L https://foundry.paradigm.xyz | bash || { echo "Error: Failed to install Foundry."; exit 1; }
  echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  "$HOME_DIR/.foundry/bin/foundryup" || foundryup || { echo "Error: Foundryup failed."; exit 1; }

  echo "Installing libraries..."
  cd "$CONFIG_DIR/projects/hello-world/contracts" || exit 1
  rm -rf lib/forge-std lib/infernet-sdk
  forge install foundry-rs/forge-std || { echo "Error: Failed to install forge-std."; exit 1; }
  forge install ritual-net/infernet-sdk || { echo "Error: Failed to install infernet-sdk."; exit 1; }
  ls lib/forge-std || { echo "Error: forge-std not installed."; exit 1; }
  ls lib/infernet-sdk || { echo "Error: infernet-sdk not installed."; exit 1; }

  echo "Starting containers..."
  cd "$HOME_DIR" || exit 1
  sudo docker compose -f "$CONFIG_DIR/deploy/docker-compose.yaml" up -d || { echo "Error: Failed to start containers."; exit 1; }
  cd "$CONFIG_DIR" || exit 1

  echo "Deploying contract..."
  export PRIVATE_KEY="${private_key#0x}"
  deployment_output=$(project=hello-world make deploy-contracts 2>&1)
  echo "$deployment_output" > "$HOME_DIR/deployment-output.log"
  contract_address=$(echo "$deployment_output" | grep -oE "Deployed SaysHello: 0x[a-fA-F0-9]+" | awk '{print $3}')
  if [[ ! $contract_address =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "?? Could not extract contract address."
    echo "Please check $HOME_DIR/deployment-output.log and enter the contract address manually:"
    read -p "Enter contract address (0x...): " contract_address
    if [[ ! $contract_address =~ ^0x[a-fA-F0-9]{40}$ ]]; then
      echo "Error: Invalid contract address format."
      exit 1
    fi
  else
    echo "? Successfully extracted contract address: $contract_address"
  fi
  echo "$contract_address" > "$HOME_DIR/contract-address.txt"

  echo "Updating CallContract.s.sol..."
  cat > "$CONFIG_DIR/projects/hello-world/contracts/script/CallContract.s.sol" << EOL
// SPDX-License-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.13;
import {Script} from "forge-std/Script.sol";
import {SaysGM} from "../src/SaysGM.sol";
contract CallContract is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        SaysGM saysGm = SaysGM($contract_address);
        saysGm.sayGM();
        vm.stopBroadcast();
    }
}
EOL
  echo "Calling contract..."
  project=hello-world make call-contract || { echo "Error: Failed to call contract."; exit 1; }

  echo "Checking containers..."
  sudo docker ps | grep infernet || { echo "Error: No infernet containers running."; exit 1; }
  echo "Checking node logs..."
  sudo docker logs infernet-node 2>&1 | tail -n 20

  echo ""
  echo "===================================================="
  echo "? RITUAL NETWORK INFERNET INSTALLED SUCCESSFULLY ?"
  echo "===================================================="
  echo "Please save this contract address: $contract_address"
  echo "It has been saved to $HOME_DIR/contract-address.txt"
  echo "Node is running. Check logs at $LOG_FILE"
  echo "Check service status with: sudo systemctl status ritual-network.service"
  echo ""
  echo "Press any key to return to menu..."
  read -n 1
}

uninstall_ritual() {
  clear
  display_logo
  echo "===================================================="
  echo " ?? UNINSTALLING RITUAL NETWORK INFERNET ?? "
  echo "===================================================="
  echo ""
  read -p "Are you sure you want to uninstall? (y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Uninstallation cancelled."
    echo "Press any key to return to menu..."
    read -n 1
    return
  fi
  HOME_DIR=$(eval echo ~$USER)
  CONFIG_DIR="$HOME_DIR/infernet-container-starter"
  sudo systemctl stop ritual-network.service 2>/dev/null || true
  sudo systemctl disable ritual-network.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/ritual-network.service
  sudo systemctl daemon-reload
  sudo docker compose -f "$CONFIG_DIR/deploy/docker-compose.yaml" down 2>/dev/null || true
  sudo docker rm -f infernet-fluentbit infernet-redis infernet-anvil infernet-node 2>/dev/null || true
  rm -rf "$CONFIG_DIR" "$HOME_DIR/foundry" "$HOME_DIR/ritual-service.sh" "$HOME_DIR/ritual-deployment.log" "$HOME_DIR/ritual-service.log" "$HOME_DIR/deployment-output.log" "$HOME_DIR/contract-address.txt"
  sudo docker system prune -f
  sudo userdel -r ritual 2>/dev/null || true
  echo ""
  echo "===================================================="
  echo "? RITUAL NETWORK INFERNET UNINSTALLATION COMPLETE ?"
  echo "===================================================="
  echo "To remove Docker completely, run:"
  echo "sudo apt-get purge docker-ce docker-ce-cli containerd.io"
  echo "sudo rm -rf /var/lib/docker"
  echo "sudo rm -rf /etc/docker"
  echo ""
  echo "Press any key to return to menu..."
  read -n 1
}

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

main
