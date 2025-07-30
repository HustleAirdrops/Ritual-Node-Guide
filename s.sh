#!/bin/bash

# Check for curl and install if not present
if ! command -v curl &> /dev/null; then
    sudo apt update
    sudo apt install curl -y
fi
sleep 1

# Text colors
TERRACOTTA='\033[38;5;208m'
LIGHT_BLUE='\033[38;5;117m'
RED='\033[0;31m'
BOLD='\033[1m'
PURPLE='\033[0;35m'
VIOLET='\033[38;5;93m'
BEIGE='\033[38;5;228m'
GOLD='\033[38;5;220m'
NC='\033[0m'

# Text formatting functions
function show() {
    echo -e "${TERRACOTTA}$1${NC}"
}

function show_bold() {
    echo -en "${TERRACOTTA}${BOLD}$1${NC}"
}

function show_blue() {
    echo -e "${LIGHT_BLUE}$1${NC}"
}

function show_war() {
    echo -e "${RED}${BOLD}$1${NC}"
}

function show_purple() {
    echo -e "${PURPLE}$1${NC}"
}

function show_violet() {
    echo -e "${VIOLET}$1${NC}"
}

function show_beige() {
    echo -e "${BEIGE}$1${NC}"
}

function show_gold() {
    echo -e "${GOLD}$1${NC}"
}

show_logotip() {
    bash <(curl -s https://raw.githubusercontent.com/NodatekaII/Basic/refs/heads/main/name.sh)
}

final_message() {
    echo ''
    show_bold "Join Nodateka, let's run nodes together!"
    echo ''
    echo -en "${TERRACOTTA}${BOLD}Telegram: ${NC}${LIGHT_BLUE}https://t.me/cryptotesemnikov/778${NC}\n"
    echo -en "${TERRACOTTA}${BOLD}Twitter: ${NC}${LIGHT_BLUE}https://x.com/nodateka${NC}\n"
    echo -e "${TERRACOTTA}${BOLD}YouTube: ${NC}${LIGHT_BLUE}https://www.youtube.com/@CryptoTesemnikov${NC}\n"
}

confirm() {
    local prompt="$1"
    show_bold "❓ $prompt [y/n, Enter = yes]: "
    read choice
    case "$choice" in
        ""|y|Y|yes|Yes)
            return 0
            ;;
        n|N|no|No)
            return 1
            ;;
        *)
            show_war '⚠️ Please enter y or n.'
            confirm "$prompt"
            ;;
    esac
}

show_name() {
   echo ""
   show_gold '░░░░░░░█▀▀█░▀█▀░▀█▀░█░░█░█▀▀█░█░░░░░░░░░█▄░░█░█▀▀█░█▀▀▄░█▀▀▀░░░░░░░'
   show_gold '░░░░░░░█▄▄▀░░█░░░█░░█░░█░█▀▀█░█░░░░░░░░░█░█░█░█░░█░█░░█░█▀▀▀░░░░░░░'
   show_gold '░░░░░░░█░░█░▄█▄░░█░░▀▄▄▀░█░░█░█▄▄█░░░░░░█░░▀█░█▄▄█░█▄▄▀░█▄▄▄░░░░░░░'
   echo ""
}

show_menu() {
    show_logotip
    show_name
    show_bold 'Select an action: '
    echo ''
    actions=(
        "1. Install Ritual node"
        "2. Change basic settings"
        "3. Replace RPC"
        "4. View container status"
        "5. View node logs"
        "6. Restart containers (disk cleanup)"
        "9. Delete node"
        "0. Exit"
    )
    for action in "${actions[@]}"; do
        show "$action"
    done
}

if [ "$EUID" -ne 0 ]; then
  show_war "⚠️ Please run the script as root."
  exit 1
fi

install_dependencies() {
    show 'Installing required packages and dependencies...'
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y make build-essential unzip lz4 gcc git jq ncdu \
    cmake clang pkg-config libssl-dev python3-pip protobuf-compiler bc curl screen
    show "Downloading required image..."
    docker pull ritualnetwork/hello-world-infernet:latest
}

CONFIG_PATH="/root/infernet-container-starter/deploy/config.json"
HELLO_CONFIG_PATH="/root/infernet-container-starter/projects/hello-world/container/config.json"
DEPLOY_SCRIPT_PATH="/root/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol"
MAKEFILE_PATH="/root/infernet-container-starter/projects/hello-world/contracts/Makefile"
DOCKER_COMPOSE_PATH="/root/infernet-container-starter/deploy/docker-compose.yaml"
DOCKER_IMAGE_VERSION="1.4.0"
export PATH=$PATH:/root/.foundry/bin

is_port_in_use() {
    local port=$1
    netstat -tuln | grep -q ":$port"
}

find_free_port() {
    local start_port=$1
    for port in $(seq $start_port 65535); do
        if ! is_port_in_use "$port"; then
            echo "$port"
            return
        fi
    done
    show_war "❌ No free port found."
    echo ""
    exit 1
}

check_and_replace_port() {
    local current_port=$1
    local start_search_port=$2
    local config_file=$3
    local docker_compose_file=$4
    local key_pattern=$5

    if is_port_in_use "$current_port"; then
        show "⚠️ Port $current_port is in use. Searching for a free port..."
        free_port=$(find_free_port "$start_search_port")
        show "✅ Found free port: $free_port"
        if [[ -n "$config_file" && -n "$key_pattern" ]]; then
            sed -i "s|$key_pattern $current_port|$key_pattern $free_port|" "$config_file"
        fi
        if [[ -n "$docker_compose_file" ]]; then
            sed -i "s|$current_port:|$free_port:|" "$docker_compose_file"
        fi
    else
        show "✅ Port $current_port is free."
    fi
}

change_ports() {
        if is_port_in_use 3000; then
            show "⚠️ Port 3000 is in use. Searching for a free port..."
            free_port=$(find_free_port 3001)
            show "✅ Found free port: $free_port"
            sed -i "s|\"3000\"|\"$free_port\"|" "$HELLO_CONFIG_PATH"
        else
            show "✅ Port 3000 is free."
            echo ""
        fi
        if is_port_in_use 4000; then
            show "⚠️ Port 4000 is in use. Searching for a free port..."
            free_port=$(find_free_port 4001)
            show "✅ Found free port: $free_port"
            sed -i "s|4000,|$free_port,|" "$HELLO_CONFIG_PATH"
            sed -i "s|4000:|$free_port:|" "$DOCKER_COMPOSE_PATH"
        else
            show "✅ Port 4000 is free."
            echo ""
        fi
        if is_port_in_use 6379; then
            show "⚠️ Port 6379 is in use. Searching for a free port..."
            free_port=$(find_free_port 6380)
            show "✅ Found free port: $free_port"
            sed -i "s|"port": 6379|"port": $free_port|" "$HELLO_CONFIG_PATH"
        else
            show "✅ Port 6379 is free."
            echo ""
        fi
        if is_port_in_use 8545; then
            show "⚠️ Port 8545 is in use. Searching for a free port..."
            free_port=$(find_free_port 8546)
            show "✅ Found free port: $free_port"
            sed -i "s|8545:|$free_port:|" "$DOCKER_COMPOSE_PATH"
        else
            show "✅ Port 8545 is free."
            echo ""
        fi
}

clone_repository() {
    local repo_url="https://github.com/ritual-net/infernet-container-starter"
    local destination="/root/infernet-container-starter"
    if [[ -d "$destination" && -n "$(ls -A "$destination")" ]]; then
        show_war "⚠️ Directory '$destination' already exists and is not empty."
        if confirm "Delete existing directory and clone again?"; then
            echo ""
            show "Deleting existing directory..."
            rm -rf "$destination" || { show_war "❌ Failed to delete directory $destination."; return 1; }
        else
            show_war "⚠️ Cloning skipped."
            echo ""
            return 1
        fi
    fi
    show "Cloning infernet-container-starter repository..."
    git clone "$repo_url" "$destination" || { show_war "❌ Error: Failed to clone repository."; return 1; }
    if cd "$destination"; then
        show "Successfully entered directory $destination."
    else
        show_war "❌ Error: Failed to enter directory $destination."
        echo ""
        return 1
    fi
}

ensure_file_exists() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        show_war "❌ File $file not found."
        echo ""
        exit 1
    fi
}

change_settings() {
    read -p "$(show_bold 'Enter value for sleep [3]: ')" SLEEP
    SLEEP=${SLEEP:-3}
    read -p "$(show_bold 'Enter value for trail_head_blocks [1]: ')" TRAIL_HEAD_BLOCKS
    TRAIL_HEAD_BLOCKS=${TRAIL_HEAD_BLOCKS:-1}
    read -p "$(show_bold 'Enter value for batch_size [1800]: ')" BATCH_SIZE
    BATCH_SIZE=${BATCH_SIZE:-1800}
    read -p "$(show_bold 'Enter value for starting_sub_id [205000]: ')" STARTING_SUB_ID
    STARTING_SUB_ID=${STARTING_SUB_ID:-205000}
    ensure_file_exists "$HELLO_CONFIG_PATH"
    sed -i "s|\"sleep\":.*|\"sleep\": $SLEEP,|" "$HELLO_CONFIG_PATH" || { show_war "❌ Error changing sleep."; return 1; }
    sed -i "s|\"batch_size\":.*|\"batch_size\": $BATCH_SIZE,|" "$HELLO_CONFIG_PATH" || { show_war "❌ Error changing batch_size."; return 1; }
    sed -i "s|\"starting_sub_id\":.*|\"starting_sub_id\": $STARTING_SUB_ID,|" "$HELLO_CONFIG_PATH" || { show_war "❌ Error changing starting_sub_id."; return 1; }
    sed -i "s|\"trail_head_blocks\":.*|\"trail_head_blocks\": $TRAIL_HEAD_BLOCKS,|" "$HELLO_CONFIG_PATH" || { show_war "❌ Error changing trail_head_blocks."; return 1; }
    echo ""
    show "✅ Values updated: sleep=$SLEEP, trail_head_blocks=$TRAIL_HEAD_BLOCKS, batch_size=$BATCH_SIZE, starting_sub_id=$STARTING_SUB_ID"
    echo ""
}

configure_files() {
    show "Configuring files..."
    cp "$HELLO_CONFIG_PATH" "${HELLO_CONFIG_PATH}.bak"
    cp "$DEPLOY_SCRIPT_PATH" "${DEPLOY_SCRIPT_PATH}.bak"
    cp "$MAKEFILE_PATH" "${MAKEFILE_PATH}.bak"
    cp "$DOCKER_COMPOSE_PATH" "${DOCKER_COMPOSE_PATH}.bak"
    read -p "$(show_bold 'Enter your private_key (with 0x): ')" PRIVATE_KEY
    if [[ -z "$PRIVATE_KEY" ]]; then
        show_war "❌ Private key cannot be empty."
        return 1
    fi
    read -p "$(show_bold 'Enter RPC address [https://mainnet.base.org]: ')" RPC_URL
    RPC_URL=${RPC_URL:-https://mainnet.base.org}
    change_settings
    sed -i "s|\"registry_address\":.*|\"registry_address\": \"0x3B1554f346DFe5c482Bb4BA31b880c1C18412170\",|" "$HELLO_CONFIG_PATH"
    sed -i "s|\"private_key\":.*|\"private_key\": \"$PRIVATE_KEY\",|" "$HELLO_CONFIG_PATH"
    sed -i "s|\"rpc_url\":.*|\"rpc_url\": \"$RPC_URL\",|" "$HELLO_CONFIG_PATH"
    sed -i "s|address registry =.*|address registry = 0x3B1554f346DFe5c482Bb4BA31b880c1C18412170;|" "$DEPLOY_SCRIPT_PATH"
    sed -i "s|sender :=.*|sender := $PRIVATE_KEY|" "$MAKEFILE_PATH"
    sed -i "s|RPC_URL :=.*|RPC_URL := $RPC_URL|" "$MAKEFILE_PATH"
    sed -i "s|ritualnetwork/infernet-node:.*|ritualnetwork/infernet-node:$DOCKER_IMAGE_VERSION|" "$DOCKER_COMPOSE_PATH"
    change_ports
    echo ''
    show_bold "✅ File configuration completed."
    echo ''
}

start_screen_session() {
    if screen -list | grep -q "ritual"; then
        show_war "⚠️ Previous 'ritual' session found. Removing..."
        screen -S ritual -X quit
    fi
    show "Starting screen session 'ritual'..."
    screen -S ritual -d -m bash -c "project=hello-world make deploy-container; bash"
    if screen -list | grep -q "ritual"; then
        show_bold "✅ Screen session ritual started successfully."
        echo ''
    else
        show_war "❌ Error: Failed to start screen session."
    fi
    echo ''
}

restart_node() {
        show "Restarting containers..."
        docker compose -f $DOCKER_COMPOSE_PATH down
        docker compose -f $DOCKER_COMPOSE_PATH up -d 
}

run_foundryup() {
    if ! command -v foundryup &> /dev/null; then
        show_war "⚠️ Foundry is not installed. Please install first."
        echo ''
        return 1
    fi
    if ! grep -q 'foundryup' ~/.bashrc; then
        show_war "⚠️ Foundry path not found in .bashrc. Adding..."
        echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
    fi
    show "Running foundryup..."
    foundryup
}

install_foundry() {
    if command -v foundryup &> /dev/null; then
        show "Foundry is already installed."
        echo ''
    else
        show "Installing Foundry..."
        curl -L https://foundry.paradigm.xyz | bash
    fi
    run_foundryup
}

install_project_dependencies() {
        show "Installing dependencies for hello-world project..."
        cd /root/infernet-container-starter/projects/hello-world/contracts || exit
        forge install --no-commit foundry-rs/forge-std || { echo "⚠️ Error installing forge-std. Fixing..."; rm -rf lib/forge-std && forge install --no-commit foundry-rs/forge-std; }
        forge install --no-commit ritual-net/infernet-sdk || { echo "⚠️ Error installing infernet-sdk. Fixing..."; rm -rf lib/infernet-sdk && forge install --no-commit ritual-net/infernet-sdk; }
}

call_contract() {
    if confirm "Deploy contract?"; then
        show "Deploying contract..."
        cd /root/infernet-container-starter || { show_war "❌ Project directory not found."; return 1; }
        DEPLOY_OUTPUT=$(project=hello-world make deploy-contracts 2>&1 | tee deploy.log)
        echo "===== DEPLOY_OUTPUT ====="
        echo "$DEPLOY_OUTPUT"
        echo "========================="
        CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | awk '/Deployed SaysHello:/ {print $3}')
        if [[ -z "$CONTRACT_ADDRESS" ]]; then
            show_war "❌ Error: Failed to extract contract address."
            echo ''
            return 1
        else
            echo ''
            show "✅ Contract address: $CONTRACT_ADDRESS"
            echo ''
        fi
        local contract_file="/root/infernet-container-starter/projects/hello-world/contracts/script/CallContract.s.sol"
        if [[ ! -f "$contract_file" ]]; then
            show_war "❌ File $contract_file not found."
            echo ''
            return 1
        fi
        show "Writing contract address to $contract_file..."
        if sed -i "s|SaysGM(.*)|SaysGM($CONTRACT_ADDRESS)|" "$contract_file"; then
            show_bold "✅ Contract address written successfully."
            echo ''
        else
            show_war "❌ Error writing contract address."
            echo ''
            return 1
        fi
        show "Calling contract..."
        if ! project=hello-world make call-contract 2>&1 | tee call_contract.log; then
            show_war "❌ Error calling contract. See 'call_contract.log' for details."
            echo ''
            return 1
        fi
        echo ''
        show_bold "✅ Contract called successfully."
        echo ""
    else
        echo ''
        show_bold "⚠️ Contract deployment cancelled."
        echo ''
    fi
}

replace_rpc_url() {
    if confirm "Replace RPC URL?"; then
        read -p "$(show_bold 'Enter new RPC URL [https://mainnet.base.org]: ') " NEW_RPC_URL
        NEW_RPC_URL=${NEW_RPC_URL:-https://mainnet.base.org}
        CONFIG_PATHS=(
            "/root/infernet-container-starter/projects/hello-world/container/config.json"
            "/root/infernet-container-starter/deploy/config.json"
            "/root/infernet-container-starter/projects/hello-world/contracts/Makefile"
        )
        files_found=false
        for config_path in "${CONFIG_PATHS[@]}"; do
            if [[ -f "$config_path" ]]; then
                sed -i "s|\"rpc_url\": \".*\"|\"rpc_url\": \"$NEW_RPC_URL\"|g" "$config_path"
                show "RPC URL replaced in $config_path"
                files_found=true
            else
                show_war "⚠️ File $config_path not found, skipping..."
                echo ''
            fi
        done
        if ! $files_found; then
            show_war "❌ No configuration file found to replace RPC URL."
            echo ''
            return
        fi
        restart_node
        show_bold "✅ Containers restarted after RPC URL replacement."
        echo ''
    else
        show "⚠️ RPC URL replacement cancelled."
        echo ''
    fi
}

delete_node() {
    if confirm "Delete node and clean files?"; then
        cd ~
        show "Stopping and removing containers..."
        docker compose -f $DOCKER_COMPOSE_PATH down
        docker rm infernet-node
        docker rm hello-world
        docker rm infernet-fluentbit
        docker rm infernet-anvil
        docker rm infernet-redis
        if screen -list | grep -q "ritual"; then
            show "Terminating screen session 'ritual'..."
            screen -S ritual -X quit
        fi
        show "Deleting project directory..."
        rm -rf ~/infernet-container-starter
        echo ''
        show_bold "✅ Node deleted and files cleaned."
        echo ''
    else
        show "⚠️ Node deletion cancelled."
        echo ''
    fi
}

menu() {
    if [[ -z "$1" ]]; then
        show_war "⚠️ Please select a menu item."
        return
    fi
    case $1 in
        1)
            install_dependencies
            clone_repository
            configure_files
            start_screen_session
            install_foundry
            install_project_dependencies
            call_contract
            ;;
        2)
            change_settings
            cp "$HELLO_CONFIG_PATH" "$CONFIG_PATH"
            restart_node
            ;;
        3)
            replace_rpc_url
            ;;
        4)
            docker ps -a | grep infernet
            ;;
        5)
            docker logs -f --tail 20 infernet-node
            ;;
        6)
            show "Restarting containers..."
            restart_node
            ;;
        9)
            delete_node
            ;;
        0)
            final_message
            exit 0
            ;;
        *)
            show_war "⚠️ Invalid choice, try again."
            ;;
    esac
}

while true; do
    show_menu
    show_bold 'Your choice: '
    read choice
    menu "$choice"
done
