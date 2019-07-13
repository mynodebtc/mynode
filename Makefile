# Makefile

# Build rootfs
.PHONY: rootfs
rootfs:
	@./make_rootfs.sh

.PHONY: rootfs_auto
rootfs_auto:
	@./make_rootfs_auto.sh

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
	@wget https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-06-24/2019-06-20-raspbian-buster-lite.zip -O out/linux_images/raspi_raspbian.zip
out/linux_images/rock64_debian.7z:
	@mkdir -p out/linux_images/
	@wget https://dl.armbian.com/rock64/Debian_buster_default.7z -O out/linux_images/rock64_debian.7z
download_linux_images: out/linux_images/raspi_raspbian.zip out/linux_images/rock64_debian.7z


# Download base myNode images
out/base_images/raspi3_base.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/raspi3_base.img.gz -O out/base_images/raspi3_base.img.gz
#out/base_images/raspi4_base.img.gz:
#	@mkdir -p out/base_images/
#	@wget http://mynodebtc.com/device/mynode_images/raspi4_base.img.gz -O out/base_images/raspi4_base.img.gz
out/base_images/rock64_base.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/mynode_images/rock64_base.img.gz -O out/base_images/rock64_base.img.gz
download_base_images: download_linux_images out/base_images/raspi3_base.img.gz out/base_images/rock64_base.img.gz


# Download latest nyNode images
out/mynode_images/raspi3_standard_final.img.gz:
	@mkdir -p out/mynode_images/
	@wget http://mynodebtc.com/device/mynode_images/raspi3_standard_final.img.gz -O out/mynode_images/raspi3_standard_final.img.gz
#out/mynode_images/raspi4_standard_final.img.gz:
#	@mkdir -p out/mynode_images/
#	@wget http://mynodebtc.com/device/mynode_images/raspi4_standard_final.img.gz -O out/mynode_images/raspi4_standard_final.img.gz
out/mynode_images/rock64_standard_final.img.gz:
	@mkdir -p out/mynode_images/
	@wget http://mynodebtc.com/device/mynode_images/rock64_standard_final.img.gz -O out/mynode_images/rock64_standard_final.img.gz
download_mynode_images: download_base_images out/mynode_images/raspi3_standard_final.img.gz out/mynode_images/rock64_standard_final.img.gz


# Setup of New Device
.PHONY: setup_new_rock64
setup_new_rock64: start_file_server download_base_images rootfs
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_rock64.sh

.PHONY: setup_new_raspi3
setup_new_raspi3: start_file_server download_base_images rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi3.sh

.PHONY: setup_new_raspi4
setup_new_raspi4: start_file_server download_base_images rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi4.sh

# TODO: Make images programmatically
.PHONY: images
images: rootfs
	@echo "TODO"


# Clone repo to get release tools
release.sh:
	@rm -rf out/mynode_release_tool
	@git clone git@github.com:mynodebtc/mynode_release_tool.git out/mynode_release_tool
	@cp out/mynode_release_tool/release.sh ./release.sh

# Release package to server
.PHONY: release
release: rootfs release.sh
	@sh release.sh


# Clean build files
.PHONY: clean
clean: stop_file_server
	@rm -rf out/
	@rm -rf release.sh