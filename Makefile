# FAQ
# 1. How to add a new component to ev2 release: https://dev.azure.com/msazure/CloudNativeCompute/_wiki/wikis/CloudNativeCompute.wiki/73268/Build-and-release
# 2. Why do we need 'append_cse_pkg': https://dev.azure.com/msazure/CloudNativeCompute/_wiki/wikis/CloudNativeCompute.wiki/72591/2-stage-image-package-logic-for-CDPX
# Quick guide on adding *.image:
# 1. If component.image contains only single image, and the image is with same name of component, then there is no need to add a '$(EV2AB_SOURCE)/component.image target. It can fallback to default target.
# 2. If component.image contains multiple images, follow 'cxunderlay.image' in 'cse_pkg.yaml' file to update images

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)

ifneq (,$(EV2AB_SUITE)$(EV2AB_DIRFILTER))
EV2AB_DIRS := $(shell $(PROJECT_ROOT)/scripts/building/map-suite.pl name '$(EV2AB_SUITE)' '$(EV2AB_DIRFILTER)')
endif

include ../makefiles/ev2ab.mk

IMAGES_SOURCE ?= $(PROJECT_ROOT)/build/images
TARGET_PACKAGE ?= ''
comma =,

define copy_artifacts
	mkdir -p $(1) && cd ../ && BUILDDROP=$(1) ./scripts/vs/official_build/copy_artifacts
endef

# need three parameters, the third parameter is the path to the deployer folder
define prepare_deployer_release
	cp ../deployer/scripts/call_me_to_cleanup_resource.sh $(1)
	$(shell chmod -R +x ../scripts/vs/official_build/generate_deployer_component_configuration.sh)
	mkdir -p $(2) && cd ../ && BUILDDROP=$(2) ./scripts/vs/official_build/generate_deployer_component_configuration.sh "$(EV2_BUILDVERSION)" $(3)
	mkdir -p $(2)/build/ev2/tools/release
	cp "$(PROJECT_ROOT)/build/ev2/tools/release/release-via-deployer" $(2)/build/ev2/tools/release
endef

# i.e: "TARGET_PACKAGE=autoupgrader.image make -C ev2 pack"
# avoids knowing the EV2AB_SOURCE path to call a specific target
# IN_CONTAINER allows to build locally when not on linux, or without dotnet installed
# i.e.: "IN_CONTAINER=y TARGET_PACKAGE=autoupgrader.image make -C ev2 pack"
pack: $(EV2AB_SOURCE)/$(TARGET_PACKAGE)
	$(shell chmod -R +x $(PROJECT_ROOT)/build/ev2/tools/ev2ab)
ifdef IN_CONTAINER
	docker run --rm \
	-v $(PROJECT_ROOT)/build/ev2/tools/ev2ab:/tools \
	-v $(EV2AB_SOURCE)/$(TARGET_PACKAGE):/ev2/$(TARGET_PACKAGE) \
	-v $(OUTPUT_DIR):/output \
	mcr.microsoft.com/dotnet/core/runtime:3.1 \
	/tools/ev2ab.sh /ev2 /output
else
ifeq ($(EV2_BUILDVERSION),)
	$(info EV2_BUILDVERSION $(EV2_BUILDVERSION))
	$(error EV2_BUILDVERSION must be set)
endif
	$(info EV2_BUILDVERSION=$(EV2_BUILDVERSION))
	export EV2_BUILDVERSION && bash $(EV2AB) $(EV2AB_SOURCE) $(OUTPUT_DIR)
endif

$(EV2AB_SOURCE)/%.health.gate.2: $(EV2AB_SOURCE)/health.gate.2
	mkdir -p $(@D)
	cp -aT $< $@
	cp $(@F)/ev2ab.yaml $@/

$(EV2AB_SOURCE)/%.health.image: $(EV2AB_SOURCE)/health.image
	mkdir -p $(@D)
	cp -aT $< $@
	cp $(@F)/ev2ab.yaml $@/

$(EV2AB_SOURCE)/%.health.icm-checker: $(EV2AB_SOURCE)/health.icm-checker
	mkdir -p $(@D)
	cp -aT $< $@
	cp $(@F)/ev2ab.yaml $@/

# fallback target for image base
$(EV2AB_SOURCE)/%.image: %.image
	mkdir -p $(@D)
	cp -a $< $(@D)
ifeq ($(BUILD_PIPELINE),CDPX)
	cp ../makefiles/cdpx/publish.mk $@/package
else
	cp ../makefiles/publish.mk $@/package
endif

$(EV2AB_SOURCE)/%.image/source/postbuild_run:
	$(call append_cse_pkg,$@,$(shell $(PROJECT_ROOT)/scripts/building/map.pl package $(patsubst $(EV2AB_SOURCE)/%,%,$(patsubst %/source/postbuild_run,%,$@))))

$(EV2AB_SOURCE)/aro.resource.region: aro.resource.region
	mkdir -p $(@D)
	cp -a $^ $(@D)
	$(call copy_artifacts,$@/package/common)

$(EV2AB_SOURCE)/az-cli-aksbin.sync: az-cli-aksbin.sync
	mkdir -p $(@D)
	cp -a $< $(@D)

$(EV2AB_SOURCE)/health.gate.common: health.gate.common
	mkdir -p $(@D)
	cp -a $< $(@D)

$(EV2AB_SOURCE)/health.gate.2: health.gate.2
	mkdir -p $(@D)
	cp -a $< $(@D)

$(EV2AB_SOURCE)/health.icm-checker: health.icm-checker
	mkdir -p $(@D)
	cp -a $< $(@D)
	cp $(PROJECT_ROOT)/scripts/util/parse-suite.pl $@/package/

$(EV2AB_SOURCE)/health.image: health.image
	mkdir -p $(@D)
	cp -a $< $(@D)
	cp ../test/dev-fundamental-cluster/scripts/prepare-azure-cli.sh $@/package/prepare-azure-cli.sh
	cp ../test/dev-fundamental-cluster/scripts/prepare-box.sh $@/package/prepare-box.sh
ifeq ($(BUILD_PIPELINE),CDPX)
	cp ../makefiles/cdpx/publish.mk $@/package
else
	cp ../makefiles/publish.mk $@/package
endif

$(EV2AB_SOURCE)/jumpbox.runtime: jumpbox.runtime
	mkdir -p $(@D)
	cp -a $< $(@D)

$(EV2AB_SOURCE)/overlay.resource.app: overlay.resource.app
	mkdir -p $(@D)
	cp -a $< $(@D)
	$(call copy_artifacts,$@/package/common)

$(EV2AB_SOURCE)/overlay.resource.deployenv: overlay.resource.deployenv
	mkdir -p $(@D)
	cp -a $^ $(@D)

$(EV2AB_SOURCE)/overlay.resource.region: overlay.resource.region
	mkdir -p $(@D)
	cp -a $^ $(@D)
	mkdir -p $@/package/common/scripts && cd ../ && cp scripts/assign-msi.sh $@/package/common/scripts  && cp -a --parents scripts/infraapi $@/package/common

$(EV2AB_SOURCE)/overlay.resource.region.bl: overlay.resource.region.bl
	mkdir -p $(@D)
	cp -a $^ $(@D)

$(EV2AB_SOURCE)/security.trustedaccess.service: security.trustedaccess.service
	mkdir -p $(@D)
	cp -a $< $(@D)

	$(MAKE) -C $(PROJECT_ROOT)/security/trustedaccess pack OUTPUT_DIR=$@/package

$(EV2AB_SOURCE)/vhd: vhd
	mkdir -p $(@D)
	cp -a $^ $(@D)

$(EV2AB_SOURCE)/vhdpool: vhdpool
	mkdir -p $(@D)
	cp -a $^ $(@D)

$(EV2AB_SOURCE)/vhdreducer: vhdreducer
	mkdir -p $(@D)
	cp -a $^ $(@D)
