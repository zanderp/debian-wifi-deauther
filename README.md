# Wifi Deauthenticator

*On Debian/Ubuntu/Kali/other debian based distributions for PC you don't need modprobe and monstart/monstop commands*
*For raspberry pi zero, 1,2,3 and 4 ( excluding the 5 you can run the below commands after you've patched the wireless firmware and the kernel )

## Usage

### Make sure you make the scripts executable:

```bash
sudo chmod +x wifi_deauth.sh
sudo chmod +x monstart
sudo chmod +x monstop
```

### After device is booted run:

```bash 
sudo modprobe brcmfmac
```

### To switch on the monitor mode:

```bash
sudo ./monstart
```

### To stop the monitor mode:

```bash
sudo ./monstop
```

### To execute

```bash
sudo ./wifi_deauth.sh rpi
```
*run without rpi argument for Debian/Ubuntu/Kali or other debian based distributions for Desktop*
