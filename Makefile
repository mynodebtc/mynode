



.PHONY: rootfs
rootfs:
	@sh make_rootfs.sh

.PHONY: images
images: rootfs
	@echo "TODO"

release.sh:
	@git clone git@github.com:mynodebtc/mynode_release_tool.git out/mynode_release_tool
	@cp out/mynode_release_tool/release.sh ./release.sh

.PHONY: release
release: rootfs release.sh
	@echo "Run release"

.PHONY: clean
clean:
	@rm -rf out/
	@rm -rf out/
	@rm -rf release.sh