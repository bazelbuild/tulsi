
# default
default_xcode_version=12.5.1
default_unzip_dir=${HOME}/Applications
default_bazel_path=bazel

# configuration
_unzip_dir=$(if $(install_path),$(install_path),$(default_unzip_dir))
_bazel_path=$(if $(bazel_path),$(bazel_path),$(default_bazel_path))
_xcode_version:= $(if $(xcode),$(xcode),$(default_xcode_version))
_workspace_path:=$(shell ${_bazel_path} info workspace)
_bazel_bin=${_workspace_path}/bazel-bin

clean:
#remove previous
	@rm -f $(_bazel_bin)/tulsi.zip
	@rm -f $(_bazel_bin)/Tulsi++.zip
	@rm -rf $(_bazel_bin)/Tulsi++.app

build: clean
	@$(_bazel_path) build //:tulsi -s \
	--use_top_level_targets_for_symlinks \
	--apple_platform_type=macos \
	--cpu=darwin \
	--compilation_mode=opt \
	--xcode_version=${_xcode_version}
	
	@unzip -oq $(_bazel_bin)/tulsi.zip -d "${_bazel_bin}"

#fix compiled version of bazel, change executable on `Sparkle.framework`
	@rm -rf $(_bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework
	@unzip -oq ${_workspace_path}/src/Sparkle/Sparkle.framework.zip -d $(_bazel_bin)/Tulsi++.app/Contents/Frameworks
	
# remove bazel's codesign, it's invalid codesign, apple notorization server unable to read the codesign
	@codesign --remove-signature --deep $(_bazel_bin)/Tulsi++.app
	@codesign --remove-signature --deep $(_bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework

install: build
	@rm -rf ${_unzip_dir}/Tulsi++.app
	@cp -R $(_bazel_bin)/Tulsi++.app ${_unzip_dir}/Tulsi++.app
	@open "${_unzip_dir}/Tulsi++.app"

.PHONY: build install