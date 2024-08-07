# Wifi Deauthenticator

*On Debian/Ubuntu/Kali/other debian based distributions for PC you don't need modprobe and monstart/monstop commands, also when using external wifi cards on a Raspberry Pi device*

*For raspberry pi zero w, zero 2 w, 3 and 4 ( excluding the 5 you can run the below commands after you've patched the wireless firmware and the kernel, aplicable only for the internal wifi card )

## Usage

### Make sure you make the scripts executable:

```bash
sudo chmod +x wifi_deauth.sh
sudo chmod +x monstart
sudo chmod +x monstop
```

### After device is booted run (rpi only):

```bash 
sudo modprobe brcmfmac
```

### To switch on the monitor mode (rpi only):

```bash
sudo ./monstart
```

### To stop the monitor mode (rpi only):

```bash
sudo ./monstop
```

### To execute

```bash
sudo ./wifi_deauth.sh rpi
```
*run without rpi argument for Debian/Ubuntu/Kali or other debian based distributions for Desktop or Raspberry Pi devices with an external wifi card*

# DISCLAIMER

Run this tool on your own networks, this is an educational tool, not intended for doing any harm. I will not be responsable for any misuse of the tool.
