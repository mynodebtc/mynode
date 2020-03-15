# Setup Base Image (Other)

1. Login as administrator

2. Set hostname

   ```sh
   hostname myNode
   ```

3. Add admin user

   ```sh
   sudo useradd -p $(openssl passwd -1 bolt) -m -s /bin/bash admin
   sudo adduser admin sudo
   ```

4. Update OS

   ```sh
   sudo apt-get update
   sudo apt-get -y upgrade
   ```

5. Install some basics

   ```sh
   sudo apt-get -y install tmux
   ```

6. Reboot

   ```sh
   sudo reboot
   ```

7. Log back in as admin

8. Delete default users for your specific device (if any)

   ```sh
   # For example:
   # sudo deluser pi
   # sudo rm -rf /home/pi
   ```

9. Sync

   ```sh
   sync
   ```

10. Make image now (if imaging)

    Final results:

     - Image with SSH access
     - Root user disabled
     - Default user admin with password bolt
