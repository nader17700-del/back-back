#!/bin/bash

# ==========================================
# Backhaul Pro Installer / Manager
# Created based on user requirements for UI & Functionality
# ==========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# Paths
INSTALL_DIR="/root/backhaul-mine"
BIN_PATH="${INSTALL_DIR}/backhaul"
CONFIG_DIR="${INSTALL_DIR}"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/backhaul.service"

# GitHub Info
DOWNLOAD_URL="https://github.com/nader17700-del/back-back/raw/main/backhaul_linux_amd64"

# Functions
log_info() { echo -e "${BLUE}[INFO] ${PLAIN}$1"; }
log_success() { echo -e "${GREEN}[OK] ${PLAIN}$1"; }
log_error() { echo -e "${RED}[ERROR] ${PLAIN}$1"; }
log_ws() { echo -e "${YELLOW}[WARNING] ${PLAIN}$1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root!"
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y -q
        apt-get install -y -q curl wget nano net-tools jq tar
    elif command -v yum &> /dev/null; then
        yum install -y -q curl wget nano net-tools jq tar
    fi
}

get_server_ip() {
    local ip=""
    if command -v curl &> /dev/null; then
        ip=$(curl -s --max-time 2 https://api.ipify.org)
        [[ -z "$ip" ]] && ip=$(curl -s --max-time 2 https://icanhazip.com)
    elif command -v wget &> /dev/null; then
        ip=$(wget -qO- --timeout=2 https://api.ipify.org)
        [[ -z "$ip" ]] && ip=$(wget -qO- --timeout=2 https://icanhazip.com)
    fi
    
    if [[ -z "$ip" ]]; then
        ip="Unknown"
    fi
    echo "$ip"
}

show_logo() {
    clear
    echo -e "${CYAN}"
    echo "  ____   _    ____ _  __ _   _    _    _   _ _     "
    echo " | __ ) / \  / ___| |/ /| | | |  / \  | | | | |    "
    echo " |  _ \/ _ \| |   | ' / | |_| | / _ \ | | | | |    "
    echo " | |_) / ___ \ |___| . \ |  _  |/ ___ \| |_| | |___ "
    echo " |____/_/   \_\____|_|\_\|_| |_/_/   \_\___/|_____|"
    echo -e "${PLAIN}"
    echo -e "${PURPLE}  Backhaul User Friendly Manager${PLAIN}"
    echo -e "${PURPLE}  Install Path: ${INSTALL_DIR}${PLAIN}"
    echo -e "${PURPLE}  Server IP:    ${GREEN}${PUBLIC_IP}${PLAIN}"
    echo -e "--------------------------------------------------"
}

get_status() {
    if [[ -f "$BIN_PATH" ]]; then
        if systemctl is-active --quiet backhaul; then
            echo -e "Status: ${GREEN}Running${PLAIN}"
        else
            echo -e "Status: ${RED}Stopped${PLAIN}"
        fi
    else
        echo -e "Status: ${YELLOW}Not Installed${PLAIN}"
    fi
}

install_backhaul() {
    install_dependencies
    
    mkdir -p "$INSTALL_DIR"

    log_info "Downloading Backhaul binary..."
    
    if command -v curl &> /dev/null; then
        curl -sL -o "$BIN_PATH" "$DOWNLOAD_URL"
    else
        wget -qO "$BIN_PATH" "$DOWNLOAD_URL"
    fi

    if [[ ! -f "$BIN_PATH" ]]; then
        log_error "Download failed!"
        return 1
    fi

    chmod +x "$BIN_PATH"
    log_success "Backhaul installed successfully."
    
    # Create Service
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Backhaul Tunnel Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable backhaul
}

configure_wizard() {
    show_logo
    echo -e "${YELLOW}--- Configuration Wizard ---${PLAIN}"
    
    echo -e "${GREEN}1.${PLAIN} Server (Iran/Bridge)"
    echo -e "${GREEN}2.${PLAIN} Client (Kharej/Upstream)"
    read -p "Select Mode [1]: " mode
    mode=${mode:-1}

    # Protocol Selection
    echo -e "\n${YELLOW}--- Transport Protocol ---${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} tcpmux (Recommended)"
    echo -e "${GREEN}2.${PLAIN} tcp"
    echo -e "${GREEN}3.${PLAIN} ws (WebSocket)"
    echo -e "${GREEN}4.${PLAIN} wsmux"
    read -p "Select Protocol [1]: " proto_num
    
    case $proto_num in
        2) transport="tcp" ;;
        3) transport="ws" ;;
        4) transport="wsmux" ;;
        *) transport="tcpmux" ;;
    esac

    # Common Settings
    read -p "Tunnel Token (Password): " token
    
    if [[ "$mode" == "1" ]]; then
        # SERVER CONFIG
        echo -e "\n${YELLOW}--- Server Settings ---${PLAIN}"
        read -p "Tunnel Port to Listen (e.g. 3000): " t_port
        read -p "Web Sniffer Port (e.g. 8080): " w_port
        
        # IP Limit
        read -p "Enable IP Limit? (read from x-ui) [y/N]: " iplimit_yn
        if [[ "$iplimit_yn" =~ ^[Yy]$ ]]; then
            iplimit="true"
            read -p "X-UI DB Path [/etc/x-ui/x-ui.db]: " xui_path
            xui_path=${xui_path:-"/etc/x-ui/x-ui.db"}
        else
            iplimit="false"
            xui_path=""
        fi

        # Proxy Protocol
        read -p "Enable Proxy Protocol? (For behind CDN/Haproxy) [y/N]: " pp_yn
        if [[ "$pp_yn" =~ ^[Yy]$ ]]; then pp="true"; else pp="false"; fi

        log_info "Generating Server Config..."
        
        cat > "$CONFIG_FILE" <<EOF
[server]
bind_addr = "0.0.0.0:$t_port"
transport = "$transport"
token = "$token"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $w_port
sniffer_log = "${INSTALL_DIR}/backhaul.json"
ip_limit = $iplimit
xui_db_path = "$xui_path"
proxy_protocol = $pp
# ports = ["80", "443"] # Add your ports here manually if needed later
EOF

    else
        # CLIENT CONFIG
        echo -e "\n${YELLOW}--- Client Settings ---${PLAIN}"
        read -p "Remote Server IP: " r_ip
        read -p "Remote Tunnel Port: " r_port
        
        # Proxy Protocol (Client side usually doesn't need this setting as listener, but good to have logic if needed for upstream)
        # Usually client just connects. We keep it simple.
        
        log_info "Generating Client Config..."
        
        cat > "$CONFIG_FILE" <<EOF
[client]
remote_addr = "$r_ip:$r_port"
transport = "$transport"
token = "$token"
keepalive_period = 75
nodelay = true
retry_interval = 3
connection_pool = 8
mux_session = 1
aggressive_pool = true
sniffer = false
web_port = 0
EOF
    fi
    
    log_success "Configuration saved to $CONFIG_FILE"
}

start_service() {
    systemctl restart backhaul
    log_success "Backhaul Service Restarted"
    sleep 1
    if systemctl is-active --quiet backhaul; then
        echo -e "Status: ${GREEN}Active (Running)${PLAIN}"
    else
        echo -e "Status: ${RED}Failed to Start${PLAIN}"
        journalctl -u backhaul -n 10 --no-pager
    fi
}

check_ports() {
    echo -e "\n${YELLOW}--- Listening Ports ---${PLAIN}"
    netstat -tulpn | grep backhaul
    echo -e "${YELLOW}-----------------------${PLAIN}"
    read -n 1 -s -r -p "Press any key to continue..."
}

view_logs() {
    echo -e "\n${YELLOW}--- Last 50 Logs ---${PLAIN}"
    journalctl -u backhaul -n 50 --no-pager
    echo -e "\n${YELLOW}--- Live Log (Ctrl+C to exit) ---${PLAIN}"
    journalctl -u backhaul -f
}

# Main Menu Loop
main_menu() {
    while true; do
        show_logo
        get_status
        echo -e "--------------------------------------------------"
        echo -e "${GREEN}1.${PLAIN} Install / Update Backhaul"
        echo -e "${GREEN}2.${PLAIN} Configure (Re-run Wizard)"
        echo -e "${GREEN}3.${PLAIN} Edit Config Manually (nano)"
        echo -e "--------------------------------------------------"
        echo -e "${GREEN}4.${PLAIN} Start / Restart Service"
        echo -e "${GREEN}5.${PLAIN} Stop Service"
        echo -e "--------------------------------------------------"
        echo -e "${GREEN}6.${PLAIN} Check Ports & Status"
        echo -e "${GREEN}7.${PLAIN} View Logs"
        echo -e "${GREEN}8.${PLAIN} Uninstall"
        echo -e "--------------------------------------------------"
        echo -e "${RED}0.${PLAIN} Exit"
        echo -e ""
        read -p "Select Option: " choice

        case $choice in
            1)
                check_root
                install_backhaul
                configure_wizard
                start_service
                ;;
            2)
                check_root
                configure_wizard
                start_service
                ;;
            3)
                nano "$CONFIG_FILE"
                read -p "Restart service to apply changes? [y/N]: " res
                if [[ "$res" =~ ^[Yy]$ ]]; then start_service; fi
                ;;
            4)
                start_service
                read -n 1 -s -r -p "Press any key to continue..."
                ;;
            5)
                systemctl stop backhaul
                log_success "Service Stopped."
                sleep 1
                ;;
            6)
                check_ports
                ;;
            7)
                view_logs
                ;;
            8)
                read -p "Are you sure? [y/N]: " sure
                if [[ "$sure" =~ ^[Yy]$ ]]; then
                    systemctl stop backhaul
                    systemctl disable backhaul
                    rm -f "$BIN_PATH"
                    rm -f "$SERVICE_FILE"
                    rm -rf "$INSTALL_DIR"
                    systemctl daemon-reload
                    log_success "Backhaul Uninstalled."
                fi
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option!${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# Entry Point
# Helper variable
PUBLIC_IP=$(get_server_ip)

if [[ $# > 0 ]]; then
    # Command line mode (for fast install)
    if [[ $1 == "install" ]]; then
        check_root
        install_backhaul
        configure_wizard
        start_service
    else
        main_menu
    fi
else
    main_menu
fi
