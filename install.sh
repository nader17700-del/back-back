#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# Paths
BIN_PATH="/usr/local/bin/backhaul"
CONFIG_DIR="/etc/backhaul"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/backhaul.service"

# GitHub Info
DOWNLOAD_URL="https://github.com/nader17700-del/back-back/raw/main/backhaul_linux_amd64"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${BLUE}Installing dependencies...${PLAIN}"
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y curl wget nano
    elif command -v yum &> /dev/null; then
        yum install -y curl wget nano
    fi
}

install_backhaul() {
    echo -e "${BLUE}Installing Backhaul...${PLAIN}"
    
    # Create config dir
    mkdir -p "$CONFIG_DIR"

    # Install Binary
    # If running from local folder and binary exists, use it. Otherwise download.
    if [[ -f "backhaul_linux_amd64" ]]; then
        echo -e "${GREEN}Found local binary, installing...${PLAIN}"
        cp backhaul_linux_amd64 "$BIN_PATH"
    else
        echo -e "${YELLOW}Downloading binary from GitHub...${PLAIN}"
        wget -O "$BIN_PATH" "$DOWNLOAD_URL"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Download failed! Please check DOWNLOAD_URL in script.${PLAIN}"
            exit 1
        fi
    fi

    chmod +x "$BIN_PATH"
    echo -e "${GREEN}Backhaul installed successfully!${PLAIN}"
}

create_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Backhaul Tunnel Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable backhaul
    echo -e "${GREEN}Systemd service created.${PLAIN}"
}

configure_backhaul() {
    echo -e "${YELLOW}--- Configuration Wizard ---${PLAIN}"
    echo "1. Server (Iran/Bridge)"
    echo "2. Client (Kharej/Upstream)"
    read -p "Select mode [1]: " mode
    mode=${mode:-1}

    if [[ "$mode" == "1" ]]; then
        # Server Mode
        read -p "Tunnel Port (e.g. 3000): " t_port
        read -p "Token (password): " token
        read -p "Web/Sniffer Port (e.g. 8080): " w_port
        
        cat > "$CONFIG_FILE" <<EOF
[server]
bind_addr = "0.0.0.0:$t_port"
transport = "tcpmux"
token = "$token"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $w_port
sniffer_log = "/var/log/backhaul.json"
ip_limit = true
# ports = ["80", "443"] # Example: Ports to forward
EOF
        echo -e "${GREEN}Server config created! Please edit $CONFIG_FILE to add ports.${PLAIN}"

    else
        # Client Mode
        read -p "Remote Server IP: " r_ip
        read -p "Remote Tunnel Port: " r_port
        read -p "Token: " token
        
        cat > "$CONFIG_FILE" <<EOF
[client]
remote_addr = "$r_ip:$r_port"
transport = "tcpmux"
token = "$token"
keepalive_period = 75
nodelay = true
retry_interval = 3
connection_pool = 8
mux_session = 1
aggressive_pool = true
EOF
        echo -e "${GREEN}Client config created!${PLAIN}"
    fi
}

start_backhaul() {
    systemctl restart backhaul
    systemctl status backhaul --no-pager
}

show_menu() {
    clear
    echo -e "${BLUE}Backhaul Installer Manager${PLAIN}"
    echo -e "${YELLOW}--------------------------${PLAIN}"
    echo "1. Install Backhaul"
    echo "2. Configure (Re-run wizard)"
    echo "3. Start/Restart Service"
    echo "4. Stop Service"
    echo "5. View Logs"
    echo "6. Uninstall"
    echo "0. Exit"
    echo -e "${YELLOW}--------------------------${PLAIN}"
    read -p "Choose an option: " choice

    case $choice in
        1)
            check_root
            install_dependencies
            install_backhaul
            create_service
            configure_backhaul
            start_backhaul
            ;;
        2)
            configure_backhaul
            start_backhaul
            ;;
        3)
            systemctl restart backhaul
            echo -e "${GREEN}Restarted.${PLAIN}"
            ;;
        4)
            systemctl stop backhaul
            echo -e "${RED}Stopped.${PLAIN}"
            ;;
        5)
            journalctl -u backhaul -f -n 50
            ;;
        6)
            systemctl stop backhaul
            systemctl disable backhaul
            rm -f "$BIN_PATH"
            rm -f "$SERVICE_FILE"
            rm -rf "$CONFIG_DIR"
            systemctl daemon-reload
            echo -e "${RED}Uninstalled.${PLAIN}"
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
        install)
            check_root
            install_dependencies
            install_backhaul
            create_service
            configure_backhaul
            start_backhaul
            ;;
        *)
            show_menu
            ;;
    esac
else
    show_menu
fi
