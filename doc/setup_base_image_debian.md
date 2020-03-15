# Setup Base Image (Debian)

1. Setup Base OS

   Install Debian 10.1.0 Net-install via CD

   URL: [https://www.debian.org/CD/netinst/](https://www.debian.org/CD/netinst/)

   Follow instructions:

     - Graphical Install
     - English, US, American English
     - Hostname: myNode
     - Domain Name: <LEAVE_EMPTY>
     - Root Password: bolt
     - Full Name: myNode
     - Username: mynode
     - Password: bolt
     - Timezone: Central
     - Partition: Guided Use Entire Disk, Continue, Continue, Continue, Yes
     - CDs and Packages: No, Next, Next
     - Software Selection: No GUI, No Print Server, Add SSH Server
     - Install Grub: Yes, /dev/sda
     - Install Complete: Continue

2. Login as root / bolt

3. Install basic Software

   ```sh
   apt-get -y install sudo
   useradd -p $(openssl passwd -1 bolt) -m -s /bin/bash admin
   adduser admin sudo
   ```

4. Delete mynode user

   ```sh
   deluser mynode
   rm -rf /home/mynode
   exit
   ```

5. Login as admin / bolt

6. Delete root password

   ```sh
   sudo passwd -d root
   ```

7. Update packages

   ```sh
   sudo apt-get -y update
   sudo apt-get -y upgrade
   ```

8. Install some basics

   ```sh
   sudo apt-get -y install tmux
   ```

9. Sync

   ```sh
   sync
   ```

10. Make image now (if imaging)
