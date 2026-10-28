##############################################################
#
# AESD-ASSIGNMENTS
#
##############################################################

# SITE must use the ssh (git@github.com:) form: the course autotest
# (assignment-autotest/test/shared/buildroot-common-build.sh) records a
# validation error and rewrites the file if this line starts with https.
# VERSION is the published assignment 9 commit (aesdchar llseek and AESDCHAR_IOCSEEKTO, aesdsocket seek command).
AESD_ASSIGNMENTS_VERSION = 37cf1018f72b0abe07f08b49e76521a2714a2d23
AESD_ASSIGNMENTS_SITE = git@github.com:cu-ecen-aeld/assignment-3-julian-werder.git
AESD_ASSIGNMENTS_SITE_METHOD = git
AESD_ASSIGNMENTS_GIT_SUBMODULES = YES
# Built and installed to /lib/modules/<release>/updates by the kernel-module infrastructure
AESD_ASSIGNMENTS_MODULE_SUBDIRS = aesd-char-driver

define AESD_ASSIGNMENTS_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)/finder-app all
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)/server all
endef

define AESD_ASSIGNMENTS_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/finder-app/conf
	for f in $(@D)/conf/*; do \
		[ -e "$$f" ] || continue; \
		$(INSTALL) -D -m 0755 "$$f" $(TARGET_DIR)/etc/finder-app/conf/$$(basename "$$f") || exit 1; \
	done
	$(INSTALL) -D -m 0755 $(@D)/finder-app/writer $(TARGET_DIR)/usr/bin/writer
	$(INSTALL) -D -m 0755 $(@D)/finder-app/finder.sh $(TARGET_DIR)/usr/bin/finder.sh
	for f in $(@D)/assignment-autotest/test/assignment4/*.sh; do \
		[ -e "$$f" ] || continue; \
		$(INSTALL) -D -m 0755 "$$f" $(TARGET_DIR)/usr/bin/$$(basename "$$f") || exit 1; \
	done
	$(INSTALL) -D -m 0755 $(AESD_ASSIGNMENTS_PKGDIR)/finder-test.sh $(TARGET_DIR)/usr/bin/finder-test.sh
	$(INSTALL) -D -m 0755 $(AESD_ASSIGNMENTS_PKGDIR)/finder.sh $(TARGET_DIR)/usr/bin/finder.sh
	$(INSTALL) -D -m 0755 $(@D)/server/aesdsocket $(TARGET_DIR)/usr/bin/aesdsocket
	$(INSTALL) -D -m 0755 $(@D)/server/aesdsocket-start-stop $(TARGET_DIR)/etc/init.d/S99aesdsocket
	$(INSTALL) -D -m 0755 $(@D)/aesd-char-driver/aesdchar_load $(TARGET_DIR)/usr/bin/aesdchar_load
	$(INSTALL) -D -m 0755 $(@D)/aesd-char-driver/aesdchar_unload $(TARGET_DIR)/usr/bin/aesdchar_unload
	$(INSTALL) -D -m 0755 $(AESD_ASSIGNMENTS_PKGDIR)/S97aesdchar $(TARGET_DIR)/etc/init.d/S97aesdchar
endef

$(eval $(kernel-module))
$(eval $(generic-package))
