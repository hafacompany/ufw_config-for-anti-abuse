#!/bin/bash

# UFW Configuration Script for Ubuntu

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "UFW is not installed. Installing ufw..."
    apt update && apt install -y ufw || { echo "Failed to install UFW. Exiting."; exit 1; }
else
    echo "UFW is already installed."
fi

# Get SSH port
ssh_port=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')
ssh_port=${ssh_port:-22}
echo "SSH Port: $ssh_port"

# Ask SSH protocol
read -p "Is the SSH port TCP or UDP? [tcp/udp] (default: tcp): " port_type
port_type=${port_type:-tcp}
port_type=$(echo "$port_type" | tr '[:upper:]' '[:lower:]')
[[ "$port_type" != "tcp" && "$port_type" != "udp" ]] && port_type="tcp"

ufw allow $ssh_port/$port_type
read -p "Do you want to limit the number of SSH connections? [y/n] (default: n): " limit_ssh
limit_ssh=${limit_ssh:-n}
[[ "$limit_ssh" =~ ^[Yy]$ ]] && ufw limit $ssh_port/$port_type

# Block outbound private IP ranges
echo "Adding outbound blocking rules..."
private_ips=(
  "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10"
  "198.18.0.0/15" "169.254.0.0/16" "141.101.78.0/23" "173.245.48.0/20"
  "0.0.0.0/8" "127.0.0.0/8" "127.0.53.53" "192.0.0.0/24" "192.0.2.0/24"
  "192.88.99.0/24" "198.51.100.0/24" "203.0.113.0/24" "224.0.0.0/3"
  "240.0.0.0/4" "255.255.255.255" "102.230.9.0/24" "102.233.71.0/24" "102.236.0.0/16"
)

for ip in "${private_ips[@]}"; do
    ufw deny out from any to $ip
done

# 🔍 Detect and display open ports
echo -e "\nDetecting currently listening ports..."

mapfile -t open_ports < <(ss -tuln | awk 'NR>1 {split($5,a,":"); if(a[2]!="") print a[2] "/" ($1=="tcp"?"tcp":"udp")}' | sort -u)

if [ ${#open_ports[@]} -eq 0 ]; then
    echo "No open ports detected."
else
    echo -e "\nThe following ports are currently in use:\n"
    printf "%-10s %-10s %-20s\n" "Port" "Protocol" "Service"
    echo "-----------------------------------------------"
    for entry in "${open_ports[@]}"; do
        port="${entry%%/*}"
        proto="${entry##*/}"
        service=$(getent services "$port/$proto" | awk '{print $1}' | head -n1)
        service=${service:-unknown}
        printf "%-10s %-10s %-20s\n" "$port" "$proto" "$service"
    done

    echo -e "\nDo you want to allow these ports through UFW? [y/n]: "
    read allow_ports
    if [[ "$allow_ports" =~ ^[Yy]$ ]]; then
        echo "Allowing detected ports..."
        for entry in "${open_ports[@]}"; do
            ufw allow "$entry"
        done
    else
        echo "Skipping opening detected ports."
    fi
fi

# Allow additional manual ports
echo "Do you want to open additional ports? (y/n)"
read answer
while [[ "$answer" =~ ^[Yy]$ ]]; do
    read -p "Enter port number (1-65535): " port
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        read -p "Protocol for port $port [tcp/udp] (default: tcp): " ptype
        ptype=${ptype:-tcp}
        [[ "$ptype" != "tcp" && "$ptype" != "udp" ]] && ptype="tcp"
        ufw allow "$port/$ptype"
    else
        echo "Invalid port."
    fi
    echo "Do you want to open another port? (y/n)"
    read answer
done

# Enable firewall
echo "Enabling UFW firewall..."
ufw --force enable

# Show status
echo "Current UFW rules:"
ufw status verbose

echo "Script completed successfully."
