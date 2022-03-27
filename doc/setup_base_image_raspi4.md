# Setup Base Image (Raspberry Pi 4)

1. After Raspi Flash `touch` ssh file on rootfs

2. Login as pi / raspberry

3. Run `sudo raspi-config`

   - Update 8: Get latest configuration tool
   - Network Options 2: Hostname -> myNode
   - Boot Options 3: Choose Desktop / CLI -> Console
   - Boot Options 3: Wait for Network at Boot
   - Localisation 4: I2 -> US -> Central
   - Localisation 4: I4 -> US
   - Advanced 7: Expand Filesystem
   - Advanced 7: Memory Split -> 16
   - Exit by selecting <Finish>, and <No> as no reboot is necessary

4. Add admin user

   ```sh
   sudo useradd -p $(openssl passwd -1 bolt) -m -s /bin/bash admin
   sudo adduser admin sudo
   ```

5. Update OS

   ```sh
   sudo apt-get update
   sudo apt-get -y upgrade
   ```

6. Install some basics

   ```sh
   sudo apt-get -y install tmux
   ```

7. Reboot

   ```sh
   sudo reboot
   ```

8. Log back in as admin

9. Delete pi user

   ```sh
   sudo deluser pi
   sudo rm -rf /home/pi
   ```

10. Install Log2Ram (Armbian has own solution)

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

11. Sync

   ```sh
   sync
   sudo shutdown -h now
   ```

12. Make image now (if imaging)

    Final results:

     - Image with SSH access
     - Root user disabled
     - Default user admin with password bolt
