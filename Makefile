# Makefile

# Build rootfs
.PHONY: rootfs
rootfs:
	@./make_rootfs.sh

.PHONY: rootfs_auto
rootfs_auto: start_file_server
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



# Download base MyNode images
out/base_images/raspi3_base.img.gz:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/raspi3_base.img.gz -O out/base_images/raspi3_base.img.gz
out/base_images/raspi4_base.img.gz:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/raspi45_base_arm64_deb12.img.gz -O out/base_images/raspi4_base.img.gz
out/base_images/raspi5_base.img.gz:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/raspi45_base_arm64_deb12.img.gz -O out/base_images/raspi5_base.img.gz
out/base_images/rock64_base.img.gz:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/rock64_base.img.gz -O out/base_images/rock64_base.img.gz
out/base_images/rockpro64_base.img.gz:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/rockpro64_base.img.gz -O out/base_images/rockpro64_base.img.gz
out/base_images/rockpi4_base.img.gz:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/rockpi4_base.img.gz -O out/base_images/rockpi4_base.img.gz
out/base_images/debian_base.ova:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/vm_base.ova -O out/base_images/debian_base.ova
out/base_images/amd64_base_uefi_deb12.img:
	@mkdir -p out/base_images/
	@wget https://mynodebtc.com/device/mynode_images/amd64_base_uefi_deb12.img.gz -O out/base_images/amd64_base_uefi_deb12.img.gz



# Setup of New Device
.PHONY: setup_new_rock64
setup_new_rock64: start_file_server out/base_images/rock64_base.img.gz rootfs
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_rock64.sh

.PHONY: setup_new_rockpro64
setup_new_rockpro64: start_file_server out/base_images/rockpro64_base.img.gz rootfs
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_rockpro64.sh

.PHONY: setup_new_rockpi4
setup_new_rockpi4: start_file_server out/base_images/rockpi4_base.img.gz rootfs
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_rockpi4.sh

.PHONY: setup_new_raspi3
setup_new_raspi3: start_file_server out/base_images/raspi3_base.img.gz rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi3.sh

.PHONY: setup_new_raspi4
setup_new_raspi4: start_file_server out/base_images/raspi4_base.img.gz rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi4.sh

.PHONY: setup_new_raspi5
setup_new_raspi5: start_file_server rootfs 
	@cp -f setup/setup_device.sh out/setup_device.sh 
	@/bin/bash scripts/setup_new_raspi5.sh

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
beta: clean_rootfs rootfs release.sh
	@sh release.sh beta


# Clean build files
.PHONY: clean
clean: stop_file_server
	@rm -rf out/
	@rm -rf release.sh