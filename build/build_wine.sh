#!/usr/bin/env bash

########################################################################
##
## A script for Wine compilation.
## By default it uses a 64-bit Ubuntu bootstrap, which it enters
## with bubblewrap (root rights are not required).
##
## This script requires: git, wget, autoconf, xz, bubblewrap
##
## You can change the environment variables below to your desired values.
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
	echo "Do not run this script as root!"
	echo
	echo "If you really need to run it as root and you know what you are doing,"
	echo "set the ALLOW_ROOT environment variable."

	exit 1
fi

# Wine version to compile.
# You can set it to "latest" to compile the latest available version.
# You can also set it to "git" to compile the latest git revision.
#
# This variable affects only vanilla and staging branches. Other branches
# use their own versions.
export WINE_VERSION="${WINE_VERSION:-latest}"

# Available branches: vanilla, staging, proton, staging-tkg, staging-tkg-fsync
export WINE_BRANCH="${WINE_BRANCH:-staging}"

# Available proton branches: proton_3.7, proton_3.16, proton_4.2, proton_4.11
# proton_5.0, proton_5.13, experimental_5.13, proton_6.3, experimental_6.3
# proton_7.0, experimental_7.0, proton_8.0, experimental_8.0, experimental_9.0
# bleeding-edge
# Leave empty to use the default branch.
export PROTON_BRANCH="${PROTON_BRANCH:-proton_11.0}"

# Sometimes Wine and Staging versions don't match (for example, 5.15.2).
# Leave this empty to use Staging version that matches the Wine version.
export STAGING_VERSION="${STAGING_VERSION:-}"

# Specify custom arguments for the Staging's patchinstall.sh script.
# For example, if you want to disable ntdll-NtAlertThreadByThreadId
# patchset, but apply all other patches, then set this variable to
# "--all -W ntdll-NtAlertThreadByThreadId"
# Leave empty to apply all Staging patches
export STAGING_ARGS="${STAGING_ARGS:-}"

# Make 64-bit Wine builds with the new WoW64 mode (32-on-64)
export EXPERIMENTAL_WOW64="${EXPERIMENTAL_WOW64:-true}"

# Set this to a path to your Wine source code (for example, /home/username/wine-custom-src).
# This is useful if you already have the Wine source code somewhere on your
# storage and you want to compile it.
#
# You can also set this to a GitHub clone url instead of a local path.
#
# If you don't want to compile a custom Wine source code, then just leave this
# variable empty.
export CUSTOM_SRC_PATH="${CUSTOM_SRC_PATH:-}"

# Branch (or tag) to check out when CUSTOM_SRC_PATH is a git URL. Empty = default branch.
export CUSTOM_SRC_BRANCH="${CUSTOM_SRC_BRANCH:-}"

# Optional label appended to the build name of custom builds, e.g. "cef-share"
# gives wine-10.13-custom-cef-share-amd64.tar.xz
export CUSTOM_BUILD_LABEL="${CUSTOM_BUILD_LABEL:-}"

# Set to true to download and prepare the source code, but do not compile it.
# If this variable is set to true, root rights are not required.
export DO_NOT_COMPILE="false"

# Set to true to use ccache to speed up subsequent compilations.
# First compilation will be a little longer, but subsequent compilations
# will be significantly faster (especially if you use a fast storage like SSD).
#
# Note that ccache requires additional storage space.
# By default it has a 5 GB limit for its cache size.
#
# Make sure that ccache is installed before enabling this.
export USE_CCACHE="${USE_CCACHE:-false}"

# NASM=false: bionic's nasm (2.13) can't build Wine's bundled PE FFmpeg (its -I paths
# need a trailing slash), so build that without assembly, as before nasm was installed.
export WINE_BUILD_OPTIONS="--without-oss --disable-winemenubuilder --disable-tests --enable-archs=x86_64,i386 NASM=false"

# A temporary directory where the Wine source code will be stored.
# Do not set this variable to an existing non-empty directory!
# This directory is removed and recreated on each script run.
export BUILD_DIR="${HOME}"/build_wine

# Change this path to where your Ubuntu bootstrap resides
export BOOTSTRAP_X64=/opt/chroots/bionic64_chroot

export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

export CC="gcc-15"
export CXX="g++-15"

export CROSSCC_X32="i686-w64-mingw32-gcc"
export CROSSCXX_X32="i686-w64-mingw32-g++"
export CROSSCC_X64="x86_64-w64-mingw32-gcc"
export CROSSCXX_X64="x86_64-w64-mingw32-g++"

export CFLAGS_X32="-march=i686 -msse2 -mfpmath=sse -O3"
export CFLAGS_X64="-march=x86-64 -msse3 -mfpmath=sse -O3"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

export CROSSCFLAGS_X32="${CFLAGS_X32}"
export CROSSCFLAGS_X64="${CFLAGS_X64}"
export CROSSLDFLAGS="${LDFLAGS}"

if [ "$USE_CCACHE" = "true" ]; then
	export CC="ccache ${CC}"
	export CXX="ccache ${CXX}"

	export i386_CC="ccache ${CROSSCC_X32}"
	export x86_64_CC="ccache ${CROSSCC_X64}"

	export CROSSCC_X32="ccache ${CROSSCC_X32}"
	export CROSSCXX_X32="ccache ${CROSSCXX_X32}"
	export CROSSCC_X64="ccache ${CROSSCC_X64}"
	export CROSSCXX_X64="ccache ${CROSSCXX_X64}"

	if [ -z "${XDG_CACHE_HOME}" ]; then
		export XDG_CACHE_HOME="${HOME}"/.cache
	fi

	mkdir -p "${XDG_CACHE_HOME}"/ccache
	mkdir -p "${HOME}"/.ccache

	# Use one cache directory, and compare compilers by content: the bootstraps are
	# unpacked afresh for each CI run, so their timestamps always change.
	export CCACHE_DIR="${CCACHE_DIR:-${XDG_CACHE_HOME}/ccache}"
	export CCACHE_COMPILERCHECK=content
	export CCACHE_BASEDIR="${BUILD_DIR}"
	export CCACHE_NOHASHDIR=true
	export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-3G}"
fi

build_with_bwrap () {
    bwrap --ro-bind "${BOOTSTRAP_X64}" / --dev /dev --ro-bind /sys /sys \
		  --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
		  --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
		  --bind-try "${XDG_CACHE_HOME}"/ccache "${XDG_CACHE_HOME}"/ccache \
		  --bind-try "${HOME}"/.ccache "${HOME}"/.ccache \
		  --setenv PATH "/opt/mingw/x86_64/bin:/opt/mingw/i686/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin" \
			"$@"
}

if ! command -v git 1>/dev/null; then
	echo "Please install git and run the script again"
	exit 1
fi

if ! command -v autoconf 1>/dev/null; then
	echo "Please install autoconf and run the script again"
	exit 1
fi

if ! command -v wget 1>/dev/null; then
	echo "Please install wget and run the script again"
	exit 1
fi

if ! command -v xz 1>/dev/null; then
	echo "Please install xz and run the script again"
	exit 1
fi

# Replace the "latest" parameter with the actual latest Wine version
if [ "${WINE_VERSION}" = "latest" ] || [ -z "${WINE_VERSION}" ]; then
	WINE_VERSION="$(wget -q -O - "https://raw.githubusercontent.com/wine-mirror/wine/master/VERSION" | tail -c +14)"
fi

# Stable and Development versions have a different source code location
# Determine if the chosen version is stable or development
if [ "$(echo "$WINE_VERSION" | cut -d "." -f2 | cut -c1)" = "0" ]; then
	WINE_URL_VERSION=$(echo "$WINE_VERSION" | cut -d "." -f 1).0
else
	WINE_URL_VERSION=$(echo "$WINE_VERSION" | cut --d "." -f 1).x
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}" || exit 1

echo
echo "Downloading the source code and patches"
echo "Preparing Wine for compilation"
echo

if [ -n "${CUSTOM_SRC_PATH}" ]; then
	is_url="$(echo "${CUSTOM_SRC_PATH}" | head -c 6)"

	if [ "${is_url}" = "git://" ] || [ "${is_url}" = "https:" ]; then
		if [ -n "${CUSTOM_SRC_BRANCH}" ]; then
			git clone --depth 1 -b "${CUSTOM_SRC_BRANCH}" "${CUSTOM_SRC_PATH}" wine
		else
			git clone "${CUSTOM_SRC_PATH}" wine
		fi
	else
		if [ ! -f "${CUSTOM_SRC_PATH}"/configure ]; then
			echo "CUSTOM_SRC_PATH is set to an incorrect or non-existent directory!"
			echo "Please make sure to use a directory with the correct Wine source code."
			exit 1
		fi

		cp -r "${CUSTOM_SRC_PATH}" wine
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}"-custom"${CUSTOM_BUILD_LABEL:+-${CUSTOM_BUILD_LABEL}}"
elif [ "$WINE_BRANCH" = "staging-tkg" ] || [ "$WINE_BRANCH" = "staging-tkg-fsync" ]; then
	if [ "$WINE_BRANCH" = "staging-tkg" ]; then
		git clone https://github.com/Kron4ek/wine-tkg wine
	else
		git clone https://github.com/Kron4ek/wine-tkg wine -b fsync
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}"-"${WINE_BRANCH}"
elif [ "$WINE_BRANCH" = "proton" ]; then
	if [ -z "${PROTON_BRANCH}" ]; then
		git clone https://github.com/ValveSoftware/wine
	else
		git clone https://github.com/ValveSoftware/wine -b "${PROTON_BRANCH}"
	fi

 	patch -d wine -Np1 < "${scriptdir}"/fix-proton-compilation-and-version-output.patch

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)-$(git -C wine rev-parse --short HEAD | cut -c1-7)"
	if [[ "${PROTON_BRANCH}" == "experimental_"* ]] || [ "${PROTON_BRANCH}" = "bleeding-edge" ]; then
		BUILD_NAME=proton-exp-"${WINE_VERSION}"
	else
		BUILD_NAME=proton-"${WINE_VERSION}"
	fi
else
	if [ "${WINE_VERSION}" = "git" ]; then
		git clone https://gitlab.winehq.org/wine/wine.git wine
		BUILD_NAME="${WINE_VERSION}-$(git -C wine rev-parse --short HEAD)"
	else
		BUILD_NAME="${WINE_VERSION}"

		wget -q --show-progress "https://dl.winehq.org/wine/source/${WINE_URL_VERSION}/wine-${WINE_VERSION}.tar.xz"

		tar xf "wine-${WINE_VERSION}.tar.xz"
		mv "wine-${WINE_VERSION}" wine
	fi

	# patch -d wine -Np1 < "${scriptdir}"/ntsync-fix-32-bit-processes.patch && echo "Applied fix for 32-bit processes for NTSYNC"

	if [ "${WINE_BRANCH}" = "staging" ]; then
		if [ "${WINE_VERSION}" = "git" ]; then
			git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"

			upstream_commit="$(cat wine-staging-"${WINE_VERSION}"/staging/upstream-commit | head -c 7)"
			git -C wine checkout "${upstream_commit}"
			BUILD_NAME="${WINE_VERSION}-${upstream_commit}-staging"
		else
			if [ -n "${STAGING_VERSION}" ]; then
				WINE_VERSION="${STAGING_VERSION}"
			fi

			BUILD_NAME="${WINE_VERSION}"-staging

			wget -q --show-progress "https://github.com/wine-staging/wine-staging/archive/v${WINE_VERSION}.tar.gz"
			tar xf v"${WINE_VERSION}".tar.gz

			if [ ! -f v"${WINE_VERSION}".tar.gz ]; then
				git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"
			fi
		fi

		if [ -f wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh ]; then
			staging_patcher=("${BUILD_DIR}"/wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh
							DESTDIR="${BUILD_DIR}"/wine)
		else
			staging_patcher=("${BUILD_DIR}"/wine-staging-"${WINE_VERSION}"/staging/patchinstall.py)
		fi

		cd wine || exit 1
		if [ -n "${STAGING_ARGS}" ]; then
			"${staging_patcher[@]}" ${STAGING_ARGS}
		else
			"${staging_patcher[@]}" --all
		fi

		if [ $? -ne 0 ]; then
			echo
			echo "Wine-Staging patches were not applied correctly!"
			exit 1
		fi

		cd "${BUILD_DIR}" || exit 1
	fi
fi

if [ ! -d wine ]; then
	clear
	echo "No Wine source code found!"
	echo "Make sure that the correct Wine version is specified."
	exit 1
fi

cd wine || exit 1
dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
autoreconf -f
cd "${BUILD_DIR}" || exit 1

if [ "${DO_NOT_COMPILE}" = "true" ]; then
	clear
	echo "DO_NOT_COMPILE is set to true"
	echo "Force exiting"
	exit
fi

if ! command -v bwrap 1>/dev/null; then
	echo "Bubblewrap is not installed on your system!"
	echo "Please install it and run the script again"
	exit 1
fi

if [ ! -d "${BOOTSTRAP_X64}" ]; then
	clear
	echo "Bootstraps are required for compilation!"
	exit 1
fi

BWRAP64="build_with_bwrap"

export CROSSCC="${CROSSCC_X64}"
export CROSSCXX="${CROSSCXX_X64}"
export CFLAGS="${CFLAGS_X64}"
export CXXFLAGS="${CFLAGS_X64}"
export CROSSCFLAGS="${CROSSCFLAGS_X64}"
export CROSSCXXFLAGS="${CROSSCFLAGS_X64}"

# The bootstrap's GStreamer build ships an old FFmpeg in /usr/local/lib/x86_64-linux-gnu,
# whose pkg-config files are found first; make Wine use the FFmpeg we bundle instead.
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

# Hardware video decoding for winedmo. The bootstrap's FFmpeg is built without
# hardware decoders, so build our own here, with:
#   VA-API (Intel, AMD; NVIDIA with nvidia-vaapi-driver), linked to libva, which we
#     bundle. The host's VA driver must be built against a libva no newer than
#     ours, so keep LIBVA_VERSION at the latest release.
#   NVDEC (NVIDIA's driver): headers only, FFmpeg loads libcuda/libnvcuvid at run time.
#     The oldest headers FFmpeg accepts work with the widest range of drivers.
#   Vulkan Video: FFmpeg loads libvulkan at run time.
# libdrm is only built against; the host's must match its GPU drivers, so it isn't
# bundled. HWDEC=false keeps the bootstrap's software-only FFmpeg.
HWDEC="${HWDEC:-true}"
HWDEC_PREFIX="${BUILD_DIR}"/hwdec
FFMPEG_LIBDIR="${BOOTSTRAP_X64}"/usr/local/lib
FFMPEG_INCDIR="${BOOTSTRAP_X64}"/usr/local/include
if [ "${HWDEC}" = "true" ]; then
	FFMPEG_HW_VERSION=7.1.1
	LIBVA_VERSION=2.24.1
	LIBDRM_VERSION=2.4.124
	NVCODEC_VERSION=n12.0.16.1
	NASM_VERSION=2.16.03

	mkdir -p "${BUILD_DIR}"/hwdec-src
	cd "${BUILD_DIR}"/hwdec-src || exit 1
	wget -q -O ffmpeg.tar.xz "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_HW_VERSION}.tar.xz" &&
	echo "26f2bd7d20c6c616f31d7130c88d7250  ffmpeg.tar.xz" | md5sum -c - &&
	wget -q -O libva.tar.gz "https://github.com/intel/libva/archive/refs/tags/${LIBVA_VERSION}.tar.gz" &&
	wget -q -O libdrm.tar.xz "https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VERSION}.tar.xz" &&
	wget -q -O nv-codec-headers.tar.gz "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/${NVCODEC_VERSION}.tar.gz" &&
	wget -q -O nasm.tar.xz "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/nasm-${NASM_VERSION}.tar.xz" || {
		echo "Failed to download the hardware decoding sources"
		exit 1
	}
	for f in *.tar.*; do tar xf "$f"; done

	cat > build-hwdec.sh <<-HWEOF
	#!/bin/bash
	set -e
	export CC=gcc-12 CXX=g++-12 CFLAGS=-O2 CXXFLAGS=-O2
	export PATH="${HWDEC_PREFIX}/bin:\$PATH"
	export PKG_CONFIG_PATH="${HWDEC_PREFIX}/lib/pkgconfig:/usr/local/lib/pkgconfig"
	src="${BUILD_DIR}/hwdec-src"

	cd "\$src"/nasm-${NASM_VERSION}
	./configure --prefix="${HWDEC_PREFIX}"
	make -j\$(nproc) install

	cd "\$src"/nv-codec-headers-${NVCODEC_VERSION}
	make PREFIX="${HWDEC_PREFIX}" install

	cd "\$src"/libdrm-${LIBDRM_VERSION}
	meson setup build --prefix="${HWDEC_PREFIX}" --libdir=lib -Dintel=disabled -Dradeon=disabled \
		-Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Dfreedreno=disabled \
		-Dvc4=disabled -Detnaviv=disabled -Dexynos=disabled -Domap=disabled -Dtegra=disabled \
		-Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false
	meson install -C build

	# Look for VA drivers where distributions put them; LIBVA_DRIVERS_PATH still overrides.
	cd "\$src"/libva-${LIBVA_VERSION}
	meson setup build --prefix="${HWDEC_PREFIX}" --libdir=lib -Dwith_x11=no -Dwith_glx=no \
		-Dwith_wayland=no -Denable_docs=false \
		-Ddriverdir=/usr/lib/x86_64-linux-gnu/dri:/usr/lib64/dri:/usr/lib/dri:/usr/local/lib/x86_64-linux-gnu/dri:/usr/local/lib/dri
	meson install -C build

	# As the bootstrap's FFmpeg (see create_ubuntu_bootstraps.sh), plus hardware decoders.
	ffconf () {
		"\$src"/ffmpeg-${FFMPEG_HW_VERSION}/configure --prefix="${HWDEC_PREFIX}" --enable-shared --disable-static \
			--disable-programs --disable-doc --disable-debug --disable-autodetect --enable-zlib \
			--disable-avdevice --disable-avfilter --disable-swscale --disable-network \
			--disable-encoders --disable-muxers --disable-indevs --disable-outdevs \
			--enable-vaapi --enable-ffnvcodec --enable-nvdec "\$@"
	}
	rm -rf "\$src"/ffbuild; mkdir "\$src"/ffbuild; cd "\$src"/ffbuild
	if ! ffconf --enable-vulkan; then
		echo "FFmpeg doesn't configure with Vulkan here, building without Vulkan decoding"
		ffconf
	fi
	make -j\$(nproc) install
	grep -E "^#define CONFIG_(VAAPI|NVDEC|VULKAN|H264_VAAPI_HWACCEL|H264_NVDEC_HWACCEL|H264_VULKAN_HWACCEL) " config.h
	HWEOF
	chmod +x build-hwdec.sh
	if ! ${BWRAP64} "${BUILD_DIR}"/hwdec-src/build-hwdec.sh; then
		echo "Failed to build FFmpeg with hardware decoding"
		exit 1
	fi
	FFMPEG_LIBDIR="${HWDEC_PREFIX}"/lib
	FFMPEG_INCDIR="${HWDEC_PREFIX}"/include
	export PKG_CONFIG_PATH="${HWDEC_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
	# libavutil needs libva: let the linker find it when linking winedmo.so
	export LDFLAGS="-Wl,-rpath-link,${HWDEC_PREFIX}/lib${LDFLAGS:+ ${LDFLAGS}}"
fi

mkdir "${BUILD_DIR}"/build64
cd "${BUILD_DIR}"/build64 || exit
${BWRAP64} "${BUILD_DIR}"/wine/configure ${WINE_BUILD_OPTIONS} --prefix "${BUILD_DIR}"/wine-"${BUILD_NAME}"-amd64
${BWRAP64} make -j$(nproc) install


echo
echo "Compilation complete"
echo "Creating and compressing archives..."

cd "${BUILD_DIR}" || exit

if touch "${scriptdir}"/write_test; then
	rm -f "${scriptdir}"/write_test
	result_dir="${scriptdir}"
else
	result_dir="${HOME}"
fi

export XZ_OPT="-9 -T 0"


builds_list="wine-${BUILD_NAME}-amd64"

for build in ${builds_list}; do
	if [ -d "${build}" ]; then
		if [ -f wine/wine-tkg-config.txt ]; then
			cp wine/wine-tkg-config.txt "${build}"
		fi

		i686-w64-mingw32-strip --strip-unneeded "${build}"/lib/wine/i386-windows/*.dll
		x86_64-w64-mingw32-strip --strip-unneeded "${build}"/lib/wine/x86_64-windows/*.dll

		# remove include directory
		rm -rf "${build}"/include

		# remove wine static libs
		find ./"${build}"/lib/wine/ -type f -name '*.a'
		find ./"${build}"/lib/wine/ -type f -name '*.a' -delete

		# strip files
		strip ./"${build}"/bin/w*
		find ./"${build}"/lib/wine/*-unix -type f -name '*' -exec strip {} \;

		# winedmo (Wine's Media Foundation demuxer) links to FFmpeg. Bundle the bootstrap's
		# FFmpeg libraries next to it and point its RUNPATH there, so the build doesn't
		# depend on whichever FFmpeg (and soname) the host has.
		unixdir="${build}"/lib/wine/x86_64-unix
		if ls "${FFMPEG_LIBDIR}"/libavformat.so.* >/dev/null 2>&1; then
			if ! command -v patchelf >/dev/null; then
				echo "patchelf is required to bundle FFmpeg"
				exit 1
			fi
			if ! readelf -d "${unixdir}"/winedmo.so 2>/dev/null | grep -q 'libavformat'; then
				echo "FFmpeg is in the bootstrap but winedmo.so wasn't built with it"
				exit 1
			fi
			cp -a "${FFMPEG_LIBDIR}"/lib{avformat,avcodec,avutil,swresample}.so.* "${unixdir}"/ 2>/dev/null
			# libva for VA-API decoding (MIT); not libdrm, whose host copy must match the GPU drivers.
			if ls "${FFMPEG_LIBDIR}"/libva.so.* >/dev/null 2>&1; then
				cp -a "${FFMPEG_LIBDIR}"/libva{,-drm}.so.* "${unixdir}"/
				for f in "${unixdir}"/libva{,-drm}.so.*; do
					[ -f "$f" ] && [ ! -L "$f" ] && strip --strip-unneeded "$f" && patchelf --set-rpath '$ORIGIN' "$f"
				done
				echo "Bundled libva: $(cd "${unixdir}" && ls libva*.so.* | tr '\n' ' ')"
			fi
			# Every FFmpeg library winedmo.so needs must be one we bundle (same soname).
			for lib in $(readelf -d "${unixdir}"/winedmo.so | sed -n 's/.*Shared library: \[\(lib\(av\|sw\)[a-z]*\.so\.[0-9]*\)\]/\1/p'); do
				if [ ! -e "${unixdir}/${lib}" ]; then
					echo "winedmo.so needs ${lib}, which isn't the bundled FFmpeg"
					exit 1
				fi
			done
			for f in "${unixdir}"/lib{avformat,avcodec,avutil,swresample}.so.*; do
				[ -f "$f" ] && [ ! -L "$f" ] && strip --strip-unneeded "$f"
			done
			for f in "${unixdir}"/winedmo.so "${unixdir}"/lib{avformat,avcodec,avutil,swresample}.so.*; do
				[ -f "$f" ] && [ ! -L "$f" ] && patchelf --set-rpath '$ORIGIN' "$f"
			done
			ffver=$(sed -n 's/^#define FFMPEG_VERSION "\(.*\)"/\1/p' "${FFMPEG_INCDIR}"/libavutil/ffversion.h 2>/dev/null)
			cat > "${unixdir}"/FFMPEG-README.txt <<-FFEOF
			These libav* libraries are FFmpeg ${ffver:-unknown}, unmodified, built as shared libraries
			under the GNU LGPL 2.1 or later; the licence text is in COPYING.LGPL-2.1 here.
			Source: https://ffmpeg.org/releases/ffmpeg-${ffver}.tar.xz
			Build recipe: build/build_wine.sh (with hardware decoding) or
			build/create_ubuntu_bootstraps.sh in
			https://github.com/FaithLife-Community/wine-appimages
			FFEOF
			cp wine/COPYING.LIB "${unixdir}"/COPYING.LGPL-2.1
			echo "Bundled FFmpeg: $(cd "${unixdir}" && ls lib{avformat,avcodec,avutil,swresample}.so.* 2>/dev/null | tr '\n' ' ')"
		fi

		tar -Jcf "${build}".tar.xz "${build}"
		mv "${build}".tar.xz "${result_dir}"
	fi
done

rm -rf "${BUILD_DIR}"

echo
echo "Done"
echo "The builds should be in ${result_dir}"
