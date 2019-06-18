# Makefile

# Build rootfs
.PHONY: rootfs
rootfs:
	@./make_rootfs.sh

# Copy rootfs to device
.PHONY: copy_to_device
copy_to_device:
	@./scripts/copy_to_device.sh


# Download base images
out/base_images/raspi_standard_final.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/base_images/raspi_standard_final.img.gz -O out/base_images/raspi_standard_final.img.gz
out/base_images/rock64_standard_final.img.gz:
	@mkdir -p out/base_images/
	@wget http://mynodebtc.com/device/base_images/rock64_standard_final.img.gz -O out/base_images/rock64_standard_final.img.gz
download_base_images: out/base_images/raspi_standard_final.img.gz out/base_images/rock64_standard_final.img.gz


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