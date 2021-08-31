
unzip_dir=${HOME}/Applications
bazel_path=bazel
xcode_version="12.5.1"
workspace_path:=$(shell ${bazel_path} info workspace)
bazel_bin=${workspace_path}/bazel-bin

build:
	src/tools/codesign.sh
	${bazel_path} build //:tulsi --use_top_level_targets_for_symlinks --xcode_version=${xcode_version}

install: build
	unzip -oq $(bazel_bin)/tulsi.zip -d "${bazel_bin}"

	# fix compiled version of bazel, change executable on `Sparkle.framework`
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Autoupdate
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Versions/A/Autoupdate
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Updater.app/Contents/MacOS/Updater
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Versions/A/Updater.app/Contents/MacOS/Updater

	rm -rf ${unzip_dir}/Tulsi++.app
	cp -R $(bazel_bin)/Tulsi++.app ${unzip_dir}/Tulsi++.app
	open "${unzip_dir}/Tulsi++.app"

release:
	src/tools/codesign.sh

	rm -f $(bazel_bin)/tulsi.zip
	rm -f $(bazel_bin)/Tulsi++.zip
	rm -rf $(bazel_bin)/Tulsi++.app

	${bazel_path} build //:tulsi --use_top_level_targets_for_symlinks --xcode_version=${xcode_version}
	unzip -oq $(bazel_bin)/tulsi.zip -d "${bazel_bin}"
	rm -f $(bazel_bin)/tulsi.zip

	# fix compiled version of bazel, change executable on `Sparkle.framework`
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Autoupdate
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Versions/A/Autoupdate
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Updater.app/Contents/MacOS/Updater
	chmod +x $(bazel_bin)/Tulsi++.app/Contents/Frameworks/Sparkle.framework/Versions/A/Updater.app/Contents/MacOS/Updater

	# create zip
	ditto -c -k --keepParent "$(bazel_bin)/Tulsi++.app" "$(bazel_bin)/Tulsi++.zip"
	src/tools/sparkle/sign_update -s $(SPARKLE_PRIVATE_KEY) "${bazel_bin}/Tulsi++.zip"
	
	# create dmg
	src/tools/BuildTools/create_dmg.sh $(bazel_bin)/Tulsi++.app -o $(bazel_bin)/Tulsi++.dmg

install_release: release
	unzip -oq $(bazel_bin)/Tulsi++.zip -d "${unzip_dir}"

.PHONY: build install release install_release