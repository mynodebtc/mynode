# Setup Base Image (Rock Pi 4)

1. After Armbian Flash

   - Open Terminal (no login)
   - Change set root password to something like rootbolt
   - Create admin user with password adminbolt

2. Login as admin

3. Delete root password and set admin pass to bolt

   ```sh
   sudo passwd -d root
   sudo passwd admin
   ```

4. Set hostname

   ```sh
   echo "mynode" | sudo tee /etc/hostname
   sudo sed -i 's/rockpi4-b/mynode/g' /etc/hosts
   # OR armbian-config -> Personal -> Hostname
   ```

5. Update packages

   ```sh
   sudo apt-get update
   sudo apt-get -y upgrade
   ```

6. Install some necessary tools

   ```sh
   sudo apt-get -y install network-manager tmux
   ```

7. Sync

   ```sh
   sync
   sudo shutdown -h now
   ```

8. Make image now (if imaging)
