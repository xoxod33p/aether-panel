#!/bin/bash

export LANG=en_US.UTF-8

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
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

cyan() {
    echo -e "\033[36m\033[01m$1\033[0m"
}

[[ $EUID -ne 0 ]] && red "Please run this script as root user." && exit 1

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "amazon linux" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Current OS is not supported." && exit 1

back2menu() {
    echo ""
    echo -n -e "${YELLOW}Press Enter key to return to certificate menu: ${PLAIN}" && read temp
    menu
}

install_certbot() {
    if command -v certbot &>/dev/null; then
        green "Certbot is already installed."
        return 0
    fi

    yellow "Installing Certbot..."
    if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
        apt-get update -y
        apt-get install -y certbot python3-certbot-dns-cloudflare curl socat
    elif [[ $SYSTEM == "CentOS" ]]; then
        yum install -y epel-release
        yum install -y certbot python3-certbot-dns-cloudflare curl socat
    elif [[ $SYSTEM == "Fedora" ]]; then
        dnf install -y certbot python3-certbot-dns-cloudflare curl socat
    elif [[ $SYSTEM == "Alpine" ]]; then
        apk update
        apk add certbot py3-certbot-dns-cloudflare curl socat
    fi

    if ! command -v certbot &>/dev/null; then
        red "Certbot installation failed. Please check network/package repositories."
        exit 1
    fi
    green "Certbot installed successfully."
}

check_port_80() {
    if ! command -v lsof &>/dev/null; then
        if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
            apt-get install -y lsof 2>/dev/null
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
            yum install -y lsof 2>/dev/null
        fi
    fi

    if command -v lsof &>/dev/null; then
        if lsof -i :80 | grep -iq "listen"; then
            yellow "Port 80 is currently in use by another service:"
            lsof -i :80
            read -rp "Do you want to stop the service using port 80? [y/N]: " kill_yn
            if [[ $kill_yn =~ ^[Yy]$ ]]; then
                lsof -i :80 | awk '{print $2}' | grep -v "PID" | xargs kill -9 2>/dev/null
                sleep 1
            else
                red "Port 80 must be available for Certbot standalone mode. Aborting."
                back2menu
            fi
        fi
    fi
}

apply_cert_to_panel() {
    local domain=$1
    local cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local key_file="/etc/letsencrypt/live/${domain}/privkey.pem"

    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        red "Certificate files not found at /etc/letsencrypt/live/${domain}/"
        return 1
    fi

    yellow "Configuring certificate into Aether VPN panel..."

    # Ensure permissions allow root service reading
    chmod 755 /etc/letsencrypt/live
    chmod 755 /etc/letsencrypt/archive
    chmod 644 "$cert_file"
    chmod 600 "$key_file"

    # Setup automatic renewal deploy hook
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/aether-vpn.sh
#!/bin/bash
systemctl restart aether-vpn 2>/dev/null
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/aether-vpn.sh

    # Setup timer / cron for auto-renewal
    if command -v systemctl &>/dev/null; then
        systemctl enable certbot.timer 2>/dev/null
        systemctl start certbot.timer 2>/dev/null
    fi
    if ! grep -q "certbot renew" /etc/crontab 2>/dev/null; then
        echo "0 3 * * * root certbot renew --quiet --deploy-hook 'systemctl restart aether-vpn' >/dev/null 2>&1" >> /etc/crontab
    fi

    # Update Panel Setting in database using CLI
    if [[ -x /usr/local/aether-vpn/aether-vpn ]]; then
        /usr/local/aether-vpn/aether-vpn setting -cert "$cert_file" -key "$key_file"
    fi

    # Restart Aether VPN to apply HTTPS
    if command -v systemctl &>/dev/null; then
        systemctl restart aether-vpn 2>/dev/null
    fi

    local port=$(/usr/local/aether-vpn/aether-vpn setting -show 2>/dev/null | grep -i "port:" | awk '{print $2}')
    [[ -z "$port" ]] && port="54321"

    echo ""
    green "=================================================================="
    green " SSL Certificate successfully applied to Aether VPN Dashboard! "
    green "=================================================================="
    cyan  " Certificate Path : $cert_file"
    cyan  " Private Key Path : $key_file"
    echo ""
    green " Panel is now secured with HTTPS at:"
    green " https://${domain}:${port}"
    green "=================================================================="
    echo ""
}

issue_standalone() {
    install_certbot
    check_port_80

    echo ""
    read -rp "Please enter your domain name (e.g. vpn.example.com): " domain
    domain=$(echo "$domain" | tr -d ' ')
    if [[ -z "$domain" ]]; then
        red "Domain name cannot be empty."
        back2menu
    fi

    read -rp "Please enter your email for Let's Encrypt alerts [optional]: " email
    email=$(echo "$email" | tr -d ' ')

    local email_args
    if [[ -z "$email" ]]; then
        email_args="--register-unsafely-without-email"
    else
        email_args="--email $email"
    fi

    yellow "Requesting certificate from Let's Encrypt via Certbot standalone..."
    certbot certonly --standalone \
        --agree-tos \
        --non-interactive \
        $email_args \
        -d "$domain"

    if [[ $? -eq 0 && -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        green "Certificate issued successfully for $domain!"
        apply_cert_to_panel "$domain"
    else
        red "Certificate issuance failed."
        yellow "Please ensure:"
        yellow "1. Domain DNS A/AAAA record points to this server's public IP."
        yellow "2. Port 80 is accessible from the internet and firewall is open."
        yellow "3. Cloudflare proxy is turned off (DNS only) during verification."
    fi
    back2menu
}

issue_cloudflare() {
    install_certbot

    echo ""
    read -rp "Please enter your domain or wildcard domain (e.g. *.example.com or vpn.example.com): " domain
    domain=$(echo "$domain" | tr -d ' ')
    if [[ -z "$domain" ]]; then
        red "Domain name cannot be empty."
        back2menu
    fi

    echo ""
    yellow "Choose Cloudflare Authentication:"
    echo " 1. Cloudflare API Token (Recommended with Zone:DNS:Edit permission)"
    echo " 2. Cloudflare Global API Key"
    read -rp "Select [1-2]: " cf_auth_choice

    mkdir -p /root/.secrets/certbot
    local cf_creds="/root/.secrets/certbot/cloudflare.ini"

    if [[ "$cf_auth_choice" == "2" ]]; then
        read -rp "Enter Cloudflare registered email: " cf_email
        read -rp "Enter Cloudflare Global API Key: " cf_key
        cat << EOF > "$cf_creds"
dns_cloudflare_email = $cf_email
dns_cloudflare_api_key = $cf_key
EOF
    else
        read -rp "Enter Cloudflare API Token: " cf_token
        cat << EOF > "$cf_creds"
dns_cloudflare_api_token = $cf_token
EOF
    fi
    chmod 600 "$cf_creds"

    read -rp "Please enter your email for Let's Encrypt alerts [optional]: " email
    email=$(echo "$email" | tr -d ' ')

    local email_args
    if [[ -z "$email" ]]; then
        email_args="--register-unsafely-without-email"
    else
        email_args="--email $email"
    fi

    yellow "Requesting certificate from Let's Encrypt via Cloudflare DNS..."
    certbot certonly --dns-cloudflare \
        --dns-cloudflare-credentials "$cf_creds" \
        --dns-cloudflare-propagation-seconds 30 \
        --agree-tos \
        --non-interactive \
        $email_args \
        -d "$domain"

    local base_domain=$(echo "$domain" | sed 's/\*\.//')
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        apply_cert_to_panel "$domain"
    elif [[ -f "/etc/letsencrypt/live/${base_domain}/fullchain.pem" ]]; then
        apply_cert_to_panel "$base_domain"
    else
        red "Cloudflare DNS certificate issuance failed. Please check your API credentials."
    fi
    back2menu
}

check_certificates() {
    install_certbot
    echo ""
    certbot certificates
    back2menu
}

renew_certificates() {
    install_certbot
    yellow "Attempting renewal of all Let's Encrypt certificates..."
    certbot renew --deploy-hook "systemctl restart aether-vpn 2>/dev/null"
    if [[ $? -eq 0 ]]; then
        green "Renewal completed successfully."
    else
        red "Certificate renewal encountered an error."
    fi
    back2menu
}

revoke_certificate() {
    install_certbot
    echo ""
    certbot certificates
    echo ""
    read -rp "Enter the certificate name/domain to delete from above list: " cert_name
    if [[ -n "$cert_name" ]]; then
        certbot delete --cert-name "$cert_name"
        green "Certificate $cert_name has been deleted."
    fi
    back2menu
}

set_existing_cert() {
    echo ""
    read -rp "Enter the domain name configured under /etc/letsencrypt/live/: " domain
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        apply_cert_to_panel "$domain"
    else
        red "Certificate files not found for ${domain}."
    fi
    back2menu
}

menu() {
    clear
    echo -e "
--------------------------------------------------------------------------------
   ${GREEN}AETHER VPN - SSL CERTIFICATE MANAGER (CERTBOT)${PLAIN}
--------------------------------------------------------------------------------
   ${GREEN}1.${PLAIN} Issue SSL Certificate via Standalone (Port 80) & Apply to Panel
   ${GREEN}2.${PLAIN} Issue SSL Certificate via Cloudflare DNS API & Apply to Panel
--------------------------------------------------------------------------------
   ${GREEN}3.${PLAIN} View Existing Certificates
   ${GREEN}4.${PLAIN} Force Renew All Certificates
   ${GREEN}5.${PLAIN} Revoke & Delete Certificate
   ${GREEN}6.${PLAIN} Re-apply Existing Let's Encrypt Certificate to Panel
--------------------------------------------------------------------------------
   ${GREEN}0.${PLAIN} Exit
--------------------------------------------------------------------------------"
    echo && read -rp "Please enter option [0-6]: " opt
    case "$opt" in
        1) issue_standalone ;;
        2) issue_cloudflare ;;
        3) check_certificates ;;
        4) renew_certificates ;;
        5) revoke_certificate ;;
        6) set_existing_cert ;;
        0) exit 0 ;;
        *) red "Please enter a valid option [0-6]" && sleep 1 && menu ;;
    esac
}

menu
