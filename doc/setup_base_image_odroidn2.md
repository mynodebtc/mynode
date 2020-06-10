# Setup Base Image (ODROID-N2)

1. After Armbian Flash

   - Login with root / 1234
   - Change root password to something longish like boltbolt
   - Create admin user with password bolt

2. Login as admin

3. Delete root password

   ```sh
   sudo passwd -d root
   ```

4. Set hostname

   ```sh
   echo "myNode" | sudo tee /etc/hostname
   sudo sed -i 's/odroidn2/myNode/g' /etc/hosts
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
   ```

8. Make image now (if imaging)
