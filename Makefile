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
	@python3 -m http.server --directory ./out


# Download base Linux images
out/linux_base_images/raspi.zip:
	@mkdir -p out/linux_base_images/
	@wget http://downloads.raspberrypi.org/raspbian/images/raspbian-2019-04-09/2019-04-08-raspbian-stretch.zip -O out/linux_base_images/raspi.zip
out/linux_base_images/rock64_armbian.7z:
	@mkdir -p out/linux_base_images/
	@wget https://dl.armbian.com/rock64/Debian_stretch_default.7z -O out/linux_base_images/rock64_armbian.7z
download_linux_base_images: out/linux_base_images/raspi.zip out/linux_base_images/rock64_armbian.7z


# Download latest nyNode images
out/mynode_images/raspi_standard_final.img.gz:
	@mkdir -p out/mynode_images/
	@wget http://mynodebtc.com/device/mynode_images/raspi_standard_final.img.gz -O out/mynode_images/raspi_standard_final.img.gz
out/mynode_images/rock64_standard_final.img.gz:
	@mkdir -p out/mynode_images/
	@wget http://mynodebtc.com/device/mynode_images/rock64_standard_final.img.gz -O out/mynode_images/rock64_standard_final.img.gz
download_mynode_images: out/mynode_images/raspi_standard_final.img.gz out/mynode_images/rock64_standard_final.img.gz


# TODO: Make images programmatically
.PHONY: images
images: rootfs
	@echo "TODO"


# Clone repo to get release tools
release.sh:
	@git clone git@github.com:mynodebtc/mynode_release_tool.git out/mynode_release_tool
	@cp out/mynode_release_tool/release.sh ./release.sh

# Release package to server
.PHONY: release
release: rootfs release.sh
	@sh release.sh


# Clean build files
.PHONY: clean
clean:
	@rm -rf out/
	@rm -rf out/
	@rm -rf release.sh