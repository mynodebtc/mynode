# Setup Base Image (ROCK64)

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
   sudo sed -i 's/rock64/myNode/g' /etc/hosts
   # OR armbian-config -> Personal -> Hostname
   ```

5. Overclock

   ```sh
   sudo sed -i "s/MAX_SPEED=.*/MAX_SPEED=1510000/" /etc/default/cpufrequtils
   sudo systemctl restart cpufrequtils
   ```

6. Update packages

   ```sh
   sudo apt-get update
   sudo apt-get -y upgrade
   ```

7. Install some necessary tools

   ```sh
   sudo apt-get -y install network-manager tmux
   ```

8. Regenerate MAC Address for Rock64

   ```sh
   . /usr/lib/armbian/armbian-common
   CONNECTION="$(nmcli -f UUID,ACTIVE,DEVICE,TYPE connection show --active | tail -n1)"
   UUID=$(awk -F" " '/ethernet/ {print $1}' <<< "${CONNECTION}")
   get_random_mac
   nmcli connection modify $UUID ethernet.cloned-mac-address $MACADDR
   nmcli connection modify $UUID -ethernet.mac-address ""
   ```

9. Sync

   ```sh
   sync
   ```

10. Make image now (if imaging)
