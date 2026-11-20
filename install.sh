#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora", "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "apk del -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "This script must be run as root user!" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Script doesn't support your system. Please use a supported one" && exit 1

cur_dir=$(pwd)
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
        * ) red "Unsupported CPU architecture! " && rm -f install.sh && exit 1 ;;
    esac
}

info_bar(){
    clear
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e "${GREEN}      _         _   _               __     ______  _   _               ${PLAIN}"
    echo -e "${GREEN}     / \   ___ | |_| |__   ___ _ __ \ \   / /  _ \| \ | |              ${PLAIN}"
    echo -e "${GREEN}    / _ \ / _ \| __| '_ \ / _ \ '__| \ \ / /| |_) |  \| |              ${PLAIN}"
    echo -e "${GREEN}   / ___ \  __/| |_| | | |  __/ |     \ V / |  __/| |\  |              ${PLAIN}"
    echo -e "${GREEN}  /_/   \_\___| \__|_| |_|\___|_|      \_/  |_|   |_| \_|              ${PLAIN}"
    echo -e "${GREEN}                        AETHER VPN MANAGEMENT PANEL                     ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo ""
    echo -e "OS: ${GREEN} ${CMD} ${PLAIN}"
    echo ""
    sleep 2
}

check_status(){
    yellow "Checking the IP configuration environment of the server. Please wait..." && sleep 1
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
        if [[ -z $v4 && -n $v6 ]]; then
            yellow "IPv6 only is detected. Adding DNS64 parsing server automatically..."
            echo -e "nameserver 2606:4700:4700::1111" > /etc/resolv.conf
        fi
    fi
    sleep 1
}

install_base(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    if [[ -z $(type -P curl) ]]; then
        ${PACKAGE_INSTALL[int]} curl
    fi
    if [[ -z $(type -P tar) ]]; then
        ${PACKAGE_INSTALL[int]} tar
    fi   
    check_status
}

download_aether_vpn(){
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/xoxod33p/aether-vpn-panel/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || last_version=$(curl -sm8 https://raw.githubusercontent.com/xoxod33p/aether-vpn-panel/main/config/version 2>/dev/null)
        if [[ -z "$last_version" ]]; then
            red "Detecting the Aether VPN version failed, please make sure your server can connect to GitHub API"
            rm -f install.sh
            exit 1
        fi
        yellow "Latest version of Aether VPN detected: ${last_version}, starting installation..."
        wget -N --no-check-certificate -O /usr/local/aether-vpn-linux-$(archAffix).tar.gz https://github.com/xoxod33p/aether-vpn-panel/releases/download/${last_version}/aether-vpn-linux-$(archAffix).tar.gz
        if [[ $? -ne 0 ]]; then
            red "Download failure, please make sure your server can connect and download files from GitHub"
            rm -f install.sh
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/xoxod33p/aether-vpn-panel/releases/download/${last_version}/aether-vpn-linux-$(archAffix).tar.gz"
        yellow "Starting installation Aether VPN $1"
        wget -N --no-check-certificate -O /usr/local/aether-vpn-linux-$(archAffix).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            red "Download Aether VPN v$1 Failure, please make sure this version exists"
            rm -f install.sh
            exit 1
        fi
    fi
    
    cd /usr/local/
    tar zxvf aether-vpn-linux-$(archAffix).tar.gz
    rm -f aether-vpn-linux-$(archAffix).tar.gz
    
    cd aether-vpn
    chmod +x aether-vpn bin/xray-linux-$(archAffix)
    cp -f aether-vpn.service /etc/systemd/system/
    
    wget -N --no-check-certificate https://raw.githubusercontent.com/xoxod33p/aether-vpn-panel/main/aether-vpn.sh -O /usr/bin/aether-vpn
    chmod +x /usr/local/aether-vpn/aether-vpn.sh 2>/dev/null
    chmod +x /usr/bin/aether-vpn
}

panel_config() {
    yellow "For security reasons, after the installation/update, please set your credentials:"
    read -rp "Please set login username [default: random]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set login password [default: random]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set panel port [default: random]: " config_port
    [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$config_port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$config_port") ]]; then
            yellow "Port $config_port is already in use, please choose another port:"
            read -rp "Please set panel port [default: random]: " config_port
            [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
        fi
    done
    /usr/local/aether-vpn/aether-vpn setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/aether-vpn/aether-vpn setting -port ${config_port} >/dev/null 2>&1
}

install_aether_vpn() {
    info_bar
    
    if [[ -e /usr/local/aether-vpn/ ]]; then
        yellow "Aether VPN panel is already installed. Confirm update without data loss."
        read -rp "Please enter option [y/n, default n]: " yn
        if [[ $yn =~ "Y"|"y" ]]; then
            cd
            [[ -f /etc/aether-vpn/aether-vpn.db ]] && cp /etc/aether-vpn/aether-vpn.db /etc/aether-vpn.db.bak
            systemctl stop aether-vpn >/dev/null 2>&1
            systemctl disable aether-vpn >/dev/null 2>&1
            rm /etc/systemd/system/aether-vpn.service -f 2>/dev/null
            systemctl daemon-reload
            systemctl reset-failed 
            rm /etc/aether-vpn/ -rf 2>/dev/null
            rm /usr/local/aether-vpn/ -rf 2>/dev/null
            rm /usr/bin/aether-vpn -f 2>/dev/null
        else
            red "Cancelled. Exiting script."
            exit 1
        fi
    fi
    
    systemctl stop aether-vpn >/dev/null 2>&1
    
    install_base
    download_aether_vpn $1
    
    cd
    if [[ -f /etc/aether-vpn.db.bak ]]; then
        mkdir -p /etc/aether-vpn
        cp /etc/aether-vpn.db.bak /etc/aether-vpn/aether-vpn.db
    fi
    
    panel_config
    
    systemctl daemon-reload
    systemctl enable aether-vpn >/dev/null 2>&1
    systemctl start aether-vpn 
    systemctl restart aether-vpn
    
    cd $cur_dir
    rm -f install.sh
    green "Aether VPN v${last_version} Installation / Upgrade Completed! Panel is running."
    echo -e ""
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e "${GREEN}      _         _   _               __     ______  _   _               ${PLAIN}"
    echo -e "${GREEN}     / \   ___ | |_| |__   ___ _ __ \ \   / /  _ \| \ | |              ${PLAIN}"
    echo -e "${GREEN}    / _ \ / _ \| __| '_ \ / _ \ '__| \ \ / /| |_) |  \| |              ${PLAIN}"
    echo -e "${GREEN}   / ___ \  __/| |_| | | |  __/ |     \ V / |  __/| |\  |              ${PLAIN}"
    echo -e "${GREEN}  /_/   \_\___| \__|_| |_|\___|_|      \_/  |_|   |_| \_|              ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e ""
    echo -e "------------------------------------------------------------------------------"
    echo -e "AETHER VPN MANAGEMENT COMMANDS: "
    echo -e "------------------------------------------------------------------------------"
    echo -e "aether-vpn             - Show the management menu"
    echo -e "aether-vpn start        - Start Aether VPN panel"
    echo -e "aether-vpn stop         - Stop Aether VPN panel"
    echo -e "aether-vpn restart      - Restart Aether VPN panel"
    echo -e "aether-vpn status       - View status"
    echo -e "aether-vpn enable       - Set boot self-start"
    echo -e "aether-vpn disable      - Cancel boot self-start"
    echo -e "aether-vpn log          - View logs"
    echo -e "aether-vpn update       - Update panel"
    echo -e "------------------------------------------------------------------------------"
    show_login_info
    echo -e ""
    yellow "(If you cannot access the web panel, run 'aether-vpn' in terminal and select option 17 to open firewall ports)"
}

show_login_info(){
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "Panel IPv4 login address: ${GREEN}http://$v4:$config_port ${PLAIN}"
    elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "Panel IPv6 login address: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "Panel IPv4 login address: ${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "Panel IPv6 login address: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo -e "Username: ${GREEN}$config_account ${PLAIN}"
    echo -e "Password: ${GREEN}$config_password ${PLAIN}"
}

install_aether_vpn $1
