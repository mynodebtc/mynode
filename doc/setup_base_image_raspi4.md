# Setup Base Image (Raspberry Pi 4)

**LATEST TESTED IMAGE (Debian 12 - Bookworm)**
2023-12-11-raspios-bookworm-arm64-lite.img

1. Flash Using Raspberry Pi Images
   
   Settings
   - Enable SSH
   - Hostname: mynode.local
   - Username: admin
   - Password: bolt

2. Login as admin / bolt

3. Run `sudo raspi-config`

   - Update 8: Get latest configuration tool
   - System Options 1: Hostname -> mynode
   - System Options 1- > Boot Options -> Console
   - Localisation 5: Timezone -> US -> Central
   - Localisation 5: Keyboard
   - Advanced 6: Expand Filesystem
   - Exit by selecting <Finish>, and <No> as no reboot is necessary

4. Update OS

   ```sh
   sudo apt-get update
   sudo apt-get -y upgrade
   ```

5. Install some basics

   ```sh
   sudo apt-get -y install tmux
   ```

6. Install Log2Ram (Armbian has own solution)

   ```sh
   cd /tmp
   wget https://github.com/azlux/log2ram/archive/v1.2.2.tar.gz -O log2ram.tar.gz
   tar -xvf log2ram.tar.gz
   mv log2ram-* log2ram
   cd log2ram
   chmod +x install.sh
   sudo ./install.sh
   cd ~
   ```

7. Sync

   ```sh
   sync
   sudo shutdown -h now
   ```

8. Make image now (if imaging)

    Final results:

     - Image with SSH access
     - Root user disabled
     - Default user admin with password bolt
