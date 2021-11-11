# Makefile

# Build rootfs
.PHONY: rootfs
rootfs:
	@./make_rootfs.sh

.PHONY: rootfs_auto
rootfs_auto:
	@./make_rootfs_auto.sh

.PHONY: clean_rootfs
clean_rootfs:
	@rm -rf out/mynode_rootfs_*
	@rm -rf out/rootfs_*

# Start file server to allow downloads to devices
.PHONY: start_file_server
start_file_server:
	@/bin/bash scripts/start_http_server.sh
.PHONY: stop_file_server
stop_file_server:
	@/bin/bash scripts/stop_http_server.sh


# Download Linux images
out/linux_images/raspi_raspbian.zip:
	@mkdir -p out/linux_images/
	@wget https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip -O out/linux_images/raspi_raspbian.zip
out/linux_images/raspi_raspbian64.zip:
	@mkdir -p out/linux_images/
	@wget https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2021-05-28/2021-05-07-raspios-buster-arm64-lite.zip -O out/linux_images/raspi_raspbian.zip
out/linux_images/rock64_debian.7z:
	@mkdir -p out/linux_images/
	@wget https://dl.armbian.com/rock64/Debian_buster_default.7z -O out/linux_images/rock64_debian.7z
download_linux_images: out/linux_images/raspi_raspbian.zip out/linux_images/raspi_raspbian64.zip out/linux_images/rock64_debian.7z


# Download base myNode images
out/base_images/raspi3_base.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/raspi3_base.img.gz -O out/base_images/raspi3_base.img.gz
out/base_images/raspi4_base.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/raspi4_base.img.gz -O out/base_images/raspi4_base.img.gz
out/base_images/rock64_base.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/rock64_base.img.gz -O out/base_images/rock64_base.img.gz
out/base_images/rockpro64_base.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/rockpro64_base.img.gz -O out/base_images/rockpro64_base.img.gz
out/base_images/debian_base.ova:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/vm_base.ova -O out/base_images/debian_base.ova



# Setup of New Device
.PHONY: setup_new_rock64
setup_new_rock64: start_file_server out/base_images/rock64_base.img.gz rootfs
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_rock64.sh

.PHONY: setup_new_rockpro64
setup_new_rockpro64: start_file_server out/base_images/rockpro64_base.img.gz rootfs
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_rockpro64.sh

.PHONY: setup_new_raspi3
setup_new_raspi3: start_file_server out/base_images/raspi3_base.img.gz rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi3.sh

.PHONY: setup_new_raspi4
setup_new_raspi4: start_file_server out/base_images/raspi4_base.img.gz rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi4.sh

.PHONY: setup_new_debian
setup_new_debian: start_file_server out/base_images/debian_base.ova rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_debian.sh


# Clone repo to get release tools
release.sh:
	@rm -rf out/mynode_release_tool
	@git clone git@github.com:mynodebtc/mynode_release_tool.git out/mynode_release_tool
	@cp out/mynode_release_tool/release.sh ./release.sh

# Release package to server
.PHONY: release
release: clean_rootfs rootfs release.sh
	@sh release.sh

.PHONY: beta
beta: clean_rootfs release.sh
	@sh release.sh beta


# Clean build files
.PHONY: clean
clean: stop_file_server
	@rm -rf out/
	@rm -rf release.sh