ifeq ($(BR2_PACKAGE_COG_PLATFORM_FDO),y)
COG_CONF_OPTS := $(filter-out -Dwayland_weston_direct_display=%,$(COG_CONF_OPTS)) -Dwayland_weston_direct_display=false
endif
