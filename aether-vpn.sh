#!/bin/bash

export LANG=en_US.UTF-8

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "amazon linux" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "apk del -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Please run this script as root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Current OS is not supported. Please use Debian, Ubuntu, CentOS, Fedora, or Alpine." && exit 1

os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

[[ $SYSTEM == "CentOS" && ${os_version} -lt 7 ]] && echo -e "Please use CentOS 7 or higher!" && exit 1
[[ $SYSTEM == "Fedora" && ${os_version} -lt 29 ]] && echo -e "Please use Fedora 29 or higher!" && exit 1
[[ $SYSTEM == "Ubuntu" && ${os_version} -lt 16 ]] && echo -e "Please use Ubuntu 16 or higher!" && exit 1
[[ $SYSTEM == "Debian" && ${os_version} -lt 9 ]] && echo -e "Please use Debian 9 or higher!" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "Unsupported CPU architecture!" && exit 1 ;;
    esac
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [default $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Restart the Aether VPN panel and XRay service?" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${YELLOW}Press Enter key to return to main menu: ${PLAIN}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/xoxod33p/aether-panel/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    read -rp "This will update Aether VPN to the latest release without data loss. Continue? [Y/N]: " yn
    if [[ $yn =~ "Y"|"y" ]]; then
        systemctl stop aether-vpn 2>/dev/null
        if [[ -e /usr/local/aether-vpn/ ]]; then
            cd
            rm -rf /usr/local/aether-vpn/
        fi
        
        last_version=$(curl -Ls "https://api.github.com/repos/xoxod33p/aether-panel/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || last_version=$(curl -sm8 https://raw.githubusercontent.com/xoxod33p/aether-panel/main/config/version)
        last_version=$(echo "$last_version" | tr -d ' \r\n')
        if [[ -z "$last_version" ]]; then
            red "Detecting the Aether VPN version failed, please make sure your server can connect to the GitHub API"
            exit 1
        fi
        
        yellow "The latest version of Aether VPN is: ${last_version}, starting update..."
        wget -N --no-check-certificate -O /usr/local/aether-vpn-linux-$(archAffix).tar.gz https://github.com/xoxod33p/aether-panel/releases/download/${last_version}/aether-vpn-linux-$(archAffix).tar.gz
        if [[ $? -ne 0 ]]; then
            red "Download failure, please make sure your server can connect and download files from GitHub"
            exit 1
        fi
        
        cd /usr/local/
        tar zxvf aether-vpn-linux-$(archAffix).tar.gz
        rm -f aether-vpn-linux-$(archAffix).tar.gz
        
        cd aether-vpn
        chmod +x aether-vpn bin/xray-linux-$(archAffix)
        cp -f aether-vpn.service /etc/systemd/system/
        
        wget -N --no-check-certificate https://raw.githubusercontent.com/xoxod33p/aether-panel/main/aether-vpn.sh -O /usr/bin/aether-vpn
        chmod +x /usr/local/aether-vpn/aether-vpn.sh 2>/dev/null
        chmod +x /usr/bin/aether-vpn
        
        systemctl daemon-reload
        systemctl enable aether-vpn 2>/dev/null
        systemctl restart aether-vpn 2>/dev/null
        
        green "Update completed successfully. Aether VPN has been restarted."
        exit 1
    else
        red "Aether VPN update has been cancelled."
        exit 1
    fi
}

uninstall() {
    confirm "Are you sure you want to uninstall Aether VPN and remove XRay?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop aether-vpn 2>/dev/null
    systemctl disable aether-vpn 2>/dev/null
    rm -f /etc/systemd/system/aether-vpn.service
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf /etc/aether-vpn/
    rm -rf /usr/local/aether-vpn/
    rm -f /usr/bin/aether-vpn
    green "Aether VPN panel has been completely uninstalled."
}

reset_user() {
    confirm "Reset admin username and password?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "Please set login username [default: random]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set login password [default: random]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/aether-vpn/aether-vpn setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    echo -e "Panel login username: ${GREEN}${config_account}${PLAIN}"
    echo -e "Panel login password: ${GREEN}${config_password}${PLAIN}"
    green "Credentials updated. Please store them securely."
    confirm_restart
}

reset_config() {
    confirm "Reset all panel configurations to default? (Account data will remain intact)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/aether-vpn/aether-vpn setting -reset >/dev/null 2>&1
    echo -e "All configurations have been reset to defaults. Default port: ${GREEN}54321${PLAIN}"
    confirm_restart
}

set_port() {
    echo && echo -n -e "Enter new web panel port [1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        red "Port cannot be empty."
        before_show_menu
    fi
    until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
            yellow "Port $port is already occupied. Please enter another port:"
            read -rp "Enter new web panel port [1-65535]: " port
        fi
    done
    /usr/local/aether-vpn/aether-vpn setting -port ${port} >/dev/null 2>&1
    echo -e "Panel port updated to: ${GREEN}${port}${PLAIN}"
    confirm_restart
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        green "Aether VPN is already running."
    else
        systemctl start aether-vpn 2>/dev/null
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            green "Aether VPN started successfully."
        else
            red "Failed to start Aether VPN. Check logs with 'aether-vpn log'."
        fi
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        green "Aether VPN is already stopped."
    else
        systemctl stop aether-vpn 2>/dev/null
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            green "Aether VPN and XRay stopped successfully."
        else
            red "Failed to stop Aether VPN."
        fi
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart aether-vpn 2>/dev/null
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        green "Aether VPN restarted successfully."
    else
        red "Failed to restart Aether VPN. Check logs with 'aether-vpn log'."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status aether-vpn 2>/dev/null -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable_aether() {
    systemctl enable aether-vpn 2>/dev/null
    if [[ $? == 0 ]]; then
        green "Aether VPN set to auto-start on boot."
    else
        red "Failed to enable auto-start."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable_aether() {
    systemctl disable aether-vpn 2>/dev/null
    if [[ $? == 0 ]]; then
        green "Aether VPN auto-start on boot disabled."
    else
        red "Failed to disable auto-start."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u aether-vpn.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

migrate_v2_ui() {
    /usr/local/aether-vpn/aether-vpn v2-ui
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/teddysun/across/raw/master/bbr.sh)
    if [[ $? == 0 ]]; then
        green "BBR installed successfully."
    else
        red "Failed to install BBR."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/aether-vpn -N --no-check-certificate https://raw.githubusercontent.com/xoxod33p/aether-panel/main/aether-vpn.sh
    if [[ $? != 0 ]]; then
        echo ""
        red "Failed to download update script. Check server network."
        before_show_menu
    else
        chmod +x /usr/bin/aether-vpn
        green "Management script updated successfully. Run 'aether-vpn' to launch."
        exit 0
    fi
}

check_status() {
    if [[ ! -f /etc/systemd/system/aether-vpn.service ]]; then
        return 2
    fi
    if systemctl is-active --quiet aether-vpn 2>/dev/null; then
        return 0
    fi
    temp=$(systemctl status aether-vpn 2>/dev/null | grep -i "Active:" | awk '{print $3}' | tr -d '()')
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    if systemctl is-enabled --quiet aether-vpn 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        yellow "Aether VPN is already installed."
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        yellow "Aether VPN is not installed yet. Please install it first."
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Aether VPN status: ${GREEN}Running${PLAIN}"
            show_enable_status
            show_xray_status
            ;;
        1)
            echo -e "Aether VPN status: ${YELLOW}Not running${PLAIN}"
            show_enable_status
            show_xray_status
            ;;
        2)
            echo -e "Aether VPN status: ${RED}Not installed${PLAIN}"
            ;;
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Auto-start on boot: ${GREEN}Enabled${PLAIN}"
    else
        echo -e "Auto-start on boot: ${RED}Disabled${PLAIN}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "XRay Core status: ${GREEN}Running${PLAIN}"
    else
        echo -e "XRay Core status: ${RED}Not running${PLAIN}"
    fi
}

open_ports(){
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    green "All server network firewall ports have been opened."
    before_show_menu
}

update_geo(){
    systemctl stop aether-vpn 2>/dev/null
    cd /usr/local/aether-vpn/bin
    rm -f geoip.dat geosite.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
    systemctl start aether-vpn 2>/dev/null
    green "Geosite and GeoIP databases updated successfully."
}

check_login_info(){
    yellow "Checking server network and credentials..."
    
    WgcfIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfIPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $WgcfIPv4Status =~ "on"|"plus" ]] || [[ $WgcfIPv6Status =~ "on"|"plus" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        v6=$(curl -s6m8 ip.gs -k)
        v4=$(curl -s4m8 ip.gs -k)
        wg-quick up wgcf >/dev/null 2>&1
    else
        v6=$(curl -s6m8 ip.gs -k)
        v4=$(curl -s4m8 ip.gs -k)
    fi
    
    config_port=$(/usr/local/aether-vpn/aether-vpn setting -show 2>/dev/null | grep -i "port:" | awk '{print $2}')
    if [[ -z "$config_port" ]]; then
        config_port=$(ss -ntlp 2>/dev/null | grep aether-vpn | awk '{print $4}' | awk -F: '{print $NF}')
    fi
    if [[ -z "$config_port" ]]; then
        config_port="54321"
    fi
}

show_usage() {
    green "Aether VPN Installation Complete. Dashboard is active."
    echo -e ""
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e "${GREEN}     _    _____ _____ _   _ _____ ____    __     ______  _   _         ${PLAIN}"
    echo -e "${GREEN}    / \  | ____|_   _| | | | ____|  _ \   \ \   / /  _ \| \ | |        ${PLAIN}"
    echo -e "${GREEN}   / _ \ |  _|   | | | |_| |  _| | |_) |   \ \ / /| |_) |  \| |        ${PLAIN}"
    echo -e "${GREEN}  / ___ \| |___  | | |  _  | |___|  _ <     \ V / |  __/| |\  |        ${PLAIN}"
    echo -e "${GREEN} /_/   \_\_____| |_| |_| |_|_____|_| \_\     \_/  |_|   |_| \_|        ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e ""
    echo -e "------------------------------------------------------------------------------"
    echo -e "AETHER VPN CLI COMMANDS: "
    echo -e "------------------------------------------------------------------------------"
    echo -e "aether-vpn              - Open interactive management menu"
    echo -e "aether-vpn start        - Start Aether VPN daemon"
    echo -e "aether-vpn stop         - Stop Aether VPN daemon"
    echo -e "aether-vpn restart      - Restart Aether VPN daemon"
    echo -e "aether-vpn status       - View service status"
    echo -e "aether-vpn enable       - Enable boot auto-start"
    echo -e "aether-vpn disable      - Disable boot auto-start"
    echo -e "aether-vpn log          - View live system logs"
    echo -e "aether-vpn v2-ui        - Migrate database from v2-ui"
    echo -e "aether-vpn update       - Update Aether VPN to latest release"
    echo -e "aether-vpn install      - Install Aether VPN"
    echo -e "aether-vpn uninstall    - Uninstall Aether VPN"
    echo -e "------------------------------------------------------------------------------"
    echo -e ""
}

show_menu() {
    echo -e "
--------------------------------------------------------------------------------
  ${GREEN}     _    _____ _____ _   _ _____ ____    __     ______  _   _         ${PLAIN}
  ${GREEN}    / \  | ____|_   _| | | | ____|  _ \   \ \   / /  _ \| \ | |        ${PLAIN}
  ${GREEN}   / _ \ |  _|   | | | |_| |  _| | |_) |   \ \ / /| |_) |  \| |        ${PLAIN}
  ${GREEN}  / ___ \| |___  | | |  _  | |___|  _ <     \ V / |  __/| |\  |        ${PLAIN}
  ${GREEN} /_/   \_\_____| |_| |_| |_|_____|_| \_\     \_/  |_|   |_| \_|        ${PLAIN}
--------------------------------------------------------------------------------
  ${GREEN}AETHER VPN PANEL MANAGEMENT CONSOLE (xoxod33p) ${PLAIN}
--------------------------------------------------------------------------------
  ${GREEN}0.${PLAIN} Exit Console
--------------------------------------------------------------------------------
  ${GREEN}1.${PLAIN} Install Aether VPN
  ${GREEN}2.${PLAIN} Update Aether VPN
  ${GREEN}3.${PLAIN} Uninstall Aether VPN
--------------------------------------------------------------------------------
  ${GREEN}4.${PLAIN} Reset Admin Credentials
  ${GREEN}5.${PLAIN} Reset Panel Settings to Default
  ${GREEN}6.${PLAIN} Set Web Access Port
--------------------------------------------------------------------------------
  ${GREEN}7.${PLAIN} Start Aether VPN
  ${GREEN}8.${PLAIN} Stop Aether VPN
  ${GREEN}9.${PLAIN} Restart Aether VPN
 ${GREEN}10.${PLAIN} Check Aether VPN Status
 ${GREEN}11.${PLAIN} View Live Logs
---------------------------------------------------------------------------------
 ${GREEN}12.${PLAIN} Enable Auto-start on Boot
 ${GREEN}13.${PLAIN} Disable Auto-start on Boot
---------------------------------------------------------------------------------
 ${GREEN}14.${PLAIN} Update Geosite and GeoIP Rules
 ${GREEN}15.${PLAIN} Install TCP BBR Acceleration
 ${GREEN}16.${PLAIN} Issue SSL Certificate via Certbot
 ${GREEN}17.${PLAIN} Open All Firewall Ports
 ${GREEN}18.${PLAIN} Install & Configure Cloudflare WARP
 --------------------------------------------------------------------------------   "
    show_status
    echo ""
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "Web Panel IPv4 Address: ${GREEN}http://$v4:$config_port ${PLAIN}"
    elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "Web Panel IPv6 Address: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "Web Panel IPv4 Address: ${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "Web Panel IPv6 Address: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo && read -rp "Please enter option [0-18]: " num
    
    case "${num}" in
        0) exit 1 ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && reset_user ;;
        5) check_install && reset_config ;;
        6) check_install && set_port ;;
        7) check_install && start ;;
        8) check_install && stop ;;
        9) check_install && restart ;;
        10) check_install && status ;;
        11) check_install && show_log ;;
        12) check_install && enable_aether ;;
        13) check_install && disable_aether ;;
        14) update_geo ;;
        15) install_bbr ;;
        16) if [[ -f /usr/local/aether-vpn/certbot.sh ]]; then bash /usr/local/aether-vpn/certbot.sh; else wget -N --no-check-certificate https://raw.githubusercontent.com/xoxod33p/aether-panel/main/certbot.sh && bash certbot.sh; fi && before_show_menu ;;
        17) open_ports ;;
        18) wget -N --no-check-certificate https://raw.githubusercontent.com/taffychan/warp/main/warp.sh && bash warp.sh && before_show_menu ;;
        *) red "Please enter a valid option [0-18]" ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable_aether 0 ;;
        "disable") check_install 0 && disable_aether 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "v2-ui") check_install 0 && migrate_v2_ui 0 ;;
        "update") check_install 0 && update ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        *) show_usage ;;
    esac
else
    check_login_info && show_menu
fi
