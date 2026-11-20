ARG BASE_IMAGE="ubuntu:26.04"
ARG EASY_NOVNC_IMAGE="fhriley/easy-novnc:1.6.0"

FROM $EASY_NOVNC_IMAGE AS easy-novnc

# ============================================================================
# Every library Kodi links is built here by Kodi's own tools/depends, the way
# the Linux Jenkins job does it (configure-depends + make-depends), so the
# Kodi stage only compiles Kodi. Layers go from the least to the most often
# changed, so a patch only rebuilds what comes after it:
#   patches/depends/*.patch  version bumps of depends  -> everything
#   patches/ffmpeg/*.patch   ffmpeg only               -> ffmpeg + Kodi
#   patches/*.patch          Kodi only                 -> Kodi
# Layout: ${DEPENDS_PREFIX}/<triplet>-release (target libs, static) and
# ${DEPENDS_PREFIX}/<triplet>-native (build tools).
# ============================================================================
FROM $BASE_IMAGE AS depends

ARG DEBIAN_FRONTEND="noninteractive"
ARG KODI_BRANCH="master"
ARG DEPENDS_PREFIX="/opt/kodi-deps"
ARG CFLAGS=
ARG CXXFLAGS=

# An armv7 container on an arm64 host gets "aarch64" from uname -m, so
# config.guess and OpenSSL's ./config pick 64-bit targets for a 32-bit gcc
# (native OpenSSL came out as linux-aarch64 and failed every signature check).
# With a 32-bit userland every RUN of this stage, and of the stages built
# FROM it, runs under the linux32 personality (uname -m: armv8l); elsewhere
# the wrapper only execs its arguments.
RUN printf '%s\n' '#!/bin/sh' \
      'if [ "$(getconf LONG_BIT)" = 32 ]; then exec setarch linux32 "$@"; fi' \
      'exec "$@"' > /usr/local/bin/native-arch \
 && chmod 755 /usr/local/bin/native-arch
SHELL ["/usr/local/bin/native-arch", "/bin/sh", "-c"]

# Host toolchain to bootstrap depends (it builds its own autotools, cmake,
# meson, ninja, pkg-config, python3, swig, ...), plus the X11/GL development
# files: depends does not build them, its linux-system-x11-libs and
# linux-system-gl-libs targets link the system .pc files into the prefix.
# default-jre-headless runs groovy for the Python bindings in the Kodi stage.
# Host packages the native tools expect, as on the Jenkins builders:
# libcurl4-openssl-dev for native cmake (bootstrapped with --system-curl),
# python3 for native heimdal's configure.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    curl \
    default-jre-headless \
    flex \
    g++ \
    gawk \
    gcc \
    git \
    gperf \
    gzip \
    libcurl4-openssl-dev \
    libegl-dev \
    libgbm-dev \
    libgl-dev \
    libglu1-mesa-dev \
    libx11-dev \
    libx11-xcb-dev \
    libxcb-dri2-0-dev \
    libxcb-dri3-dev \
    libxcb-glx0-dev \
    libxcb-present-dev \
    libxcb-randr0-dev \
    libxcb-render0-dev \
    libxcb-shape0-dev \
    libxcb-sync-dev \
    libxcb-xfixes0-dev \
    libxcb1-dev \
    libxdamage-dev \
    libxext-dev \
    libxfixes-dev \
    libxmu-dev \
    libxrandr-dev \
    libxrender-dev \
    libxshmfence-dev \
    libxt-dev \
    libxxf86vm-dev \
    make \
    patch \
    perl \
    python3 \
    tar \
    unzip \
    x11proto-dev \
    xz-utils \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --branch ${KODI_BRANCH} https://github.com/xbmc/xbmc.git /tmp/xbmc

# They touch the same files, so they are applied one at a time, in name order.
COPY patches/depends/ /patches/depends/
RUN cd /tmp/xbmc \
 && for p in /patches/depends/*.patch; do \
      git apply --ignore-whitespace "$p" || exit 1; \
    done

# Same as tools/buildsteps/linux/configure-depends. There is no x11-only
# platform (x86 gets "x11 wayland gbm", ARM "wayland gbm"): the target list
# below is explicit, so nothing wayland/gbm is built, and the Kodi stage sets
# CORE_PLATFORM_NAME=x11. VAAPI/VDPAU are off in Kodi, so ffmpeg does not need
# them either (on x86 they are depends' ffmpeg default).
# --build too, so depends never thinks it is cross compiling (see the
# native-arch wrapper above).
RUN cd /tmp/xbmc/tools/depends \
 && ./bootstrap \
 && ./configure \
      --prefix=${DEPENDS_PREFIX} \
      --build=$(gcc -dumpmachine) \
      --host=$(gcc -dumpmachine) \
      --with-toolchain=/usr \
      --with-rendersystem=gl \
      --with-tarballs=/tmp/tarballs \
      --with-target-cflags="${CFLAGS}" \
      --with-target-cxxflags="${CXXFLAGS}" \
      --with-ffmpeg-options="--disable-vaapi --disable-vdpau" \
      --disable-debug

# Native tools, all of them as in tools/buildsteps/linux/make-native-depends.
# Like Jenkins, a serial retry gets past the rare parallel race.
RUN cd /tmp/xbmc/tools/depends \
 && (make -j $(nproc) -C native || make -C native)

# Target libraries of depends' own linux list (tools/depends/target/Makefile)
# that this build uses; their order comes from the Makefile's dependency rules.
# Left out: dbus, libinput/libevdev/mtdev/libudev, libusb, libshairplay,
# pipewire, libcdio, libva (features disabled in Kodi), wayland/gbm, and
# ffmpeg, which has its own layer.
RUN cd /tmp/xbmc/tools/depends \
 && T="linux-system-x11-libs linux-system-gl-libs \
       alsa-lib bzip2 dav1d expat fontconfig freetype2 freetype2-noharfbuzz \
       fribidi fstrcmp gettext gmp gnutls harfbuzz libdrm libffi libgcrypt \
       libgpg-error libjpeg-turbo libplist libpng libuuid libxml2 nettle \
       openssl python3 pythonmodule-pil pythonmodule-pycryptodome samba \
       sqlite3 tinyxml xz" \
 && (make -j $(nproc) -C target ${T} || make -C target ${T})

# What Kodi's cmake would otherwise build itself with ExternalProject
# (ENABLE_INTERNAL_*), Jenkins included. Their depends Makefiles have no
# dependency rules in target/Makefile, so they are built one by one, in an
# order that has each library after the ones it needs.
RUN cd /tmp/xbmc/tools/depends \
 && for t in brotli nghttp2 curl crossguid fmt spdlog flatbuffers nlohmann_json \
             pcre2 exiv2 libass liblzo2 libmicrohttpd libnfs mariadb udfread \
             libdvdread libdvdnav libxslt utfcpp taglib tinyxml2; do \
      make -j $(nproc) -C target/${t} || exit 1; \
    done

# Collect what the runtime image needs from Python:
#   /out/python-version "X.Y" read from Kodi's own PYTHON3-VERSION, so a Python
#                       minor bump in Kodi needs no change here
#   /out/kodi-python    stdlib + Pillow/PyCryptodome (opt-1 .pyc, Kodi runs
#                       with PYTHONOPTIMIZE) laid out as lib/pythonX.Y
RUN PYTHON_VERSION=$(sed -n 's/^VERSION=\([0-9]*\.[0-9]*\)\..*/\1/p' /tmp/xbmc/tools/depends/target/python3/PYTHON3-VERSION) \
 && test -n "${PYTHON_VERSION}" \
 && P=$(ls -d ${DEPENDS_PREFIX}/*-release) \
 && N=$(ls -d ${DEPENDS_PREFIX}/*-native) \
 && mkdir -p /out/kodi-python/lib \
 && echo "${PYTHON_VERSION}" > /out/python-version \
 && L=${P}/lib/python${PYTHON_VERSION} \
 && rm -rf ${L}/test ${L}/idlelib ${L}/turtledemo ${L}/tkinter ${L}/ensurepip \
 && (${N}/bin/python3 -O -m compileall -q ${L} || true) \
 && cp -a ${L} /out/kodi-python/lib/python${PYTHON_VERSION}

# ffmpeg last: its patches change more often than the rest. Built from its
# own directory, so target/Makefile does not pull libva in on x86.
COPY patches/ffmpeg/ /patches/ffmpeg/
RUN cd /tmp/xbmc \
 && for p in /patches/ffmpeg/*.patch; do \
      git apply --ignore-whitespace "$p" || exit 1; \
    done \
 && make -j $(nproc) -C tools/depends/target/ffmpeg

# ============================================================================
# Kodi itself, against the depends prefix (tools/buildsteps/linux/
# configure-xbmc + make-xbmc). Same source tree as the depends stage.
# ============================================================================
FROM depends AS build

ARG CFLAGS=
ARG CXXFLAGS=
ARG WITH_CPU=

# Kodi-only patches (none of depends/ or ffmpeg/), one at a time, in name order.
COPY patches/ /patches/
RUN cd /tmp/xbmc \
 && for p in /patches/*.patch; do \
      [ -e "$p" ] || continue; \
      git apply --ignore-whitespace "$p" || exit 1; \
    done

# cmakebuildsys runs the native cmake with depends' Toolchain.cmake
# (KODI_DEPENDSBUILD): libraries, pkg-config and the static Python and its
# dependencies all come from the prefix. USE_INTERNAL_LIBS=OFF turns every
# ENABLE_INTERNAL_* dependent_option off, so nothing is rebuilt here;
# CROSSGUID and FFMPEG are plain options and are turned off explicitly
# (cmakebuildsys passes ENABLE_INTERNAL_CROSSGUID=ON before the extra args).
RUN make -C /tmp/xbmc/tools/depends/target/cmakebuildsys \
      BUILD_DIR=/tmp/xbmc/build \
      CMAKE_EXTRA_ARGUMENTS="${WITH_CPU} \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=/usr/lib \
        -DCORE_PLATFORM_NAME=x11 \
        -DAPP_RENDER_SYSTEM=gl \
        -DUSE_INTERNAL_LIBS=OFF \
        -DENABLE_INTERNAL_CROSSGUID=OFF \
        -DENABLE_INTERNAL_FFMPEG=OFF \
        -DENABLE_AIRTUNES=OFF \
        -DENABLE_ALSA=ON \
        -DENABLE_AVAHI=OFF \
        -DENABLE_BLUETOOTH=OFF \
        -DENABLE_BLURAY=OFF \
        -DENABLE_CAP=OFF \
        -DENABLE_CEC=OFF \
        -DENABLE_DBUS=OFF \
        -DENABLE_DVDCSS=OFF \
        -DENABLE_MARIADBCLIENT=ON \
        -DENABLE_MYSQLCLIENT=OFF \
        -DENABLE_EVENTCLIENTS=OFF \
        -DENABLE_GLX=ON \
        -DENABLE_LCMS2=OFF \
        -DENABLE_LIBUSB=OFF \
        -DENABLE_LIRCCLIENT=OFF \
        -DENABLE_NFS=ON \
        -DENABLE_OPTICAL=OFF \
        -DENABLE_PIPEWIRE=OFF \
        -DENABLE_PULSEAUDIO=OFF \
        -DENABLE_SNDIO=OFF \
        -DENABLE_TESTING=OFF \
        -DENABLE_UDEV=OFF \
        -DENABLE_UPNP=OFF \
        -DENABLE_VAAPI=OFF \
        -DENABLE_VDPAU=OFF"

RUN (make -j $(nproc) -C /tmp/xbmc/build || make -C /tmp/xbmc/build) \
 && make -C /tmp/xbmc/build DESTDIR=/tmp/kodi-build install

# Install kodi-send and xbmcclient
RUN install -Dm755 \
	/tmp/xbmc/tools/EventClients/Clients/KodiSend/kodi-send.py \
	/tmp/kodi-build/usr/bin/kodi-send \
 && install -Dm644 \
	/tmp/xbmc/tools/EventClients/lib/python/xbmcclient.py \
	/tmp/kodi-build/usr/lib/python$(cat /out/python-version)/xbmcclient.py

# ============================================================================
# Final runtime image
# ============================================================================
FROM $BASE_IMAGE

ARG DEBIAN_FRONTEND="noninteractive"

# Install runtime dependencies. The depends libraries are static inside
# kodi.bin except alsa-lib and libdrm (shared in depends too, their sonames
# resolve to the packages below); X11/GL always come from the system.
# fontconfig-config: depends' fontconfig looks for its config under the depends
# prefix, so supervisord.conf points FONTCONFIG_FILE at /etc/fonts.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    alsa-base \
    ca-certificates \
    curl \
    fontconfig-config \
    gosu \
    libasound2t64 \
    libdrm2 \
    libegl1 \
    libgl1 \
    libxrandr2 \
    samba-common-bin \
    supervisor \
    tigervnc-standalone-server \
    tigervnc-tools \
    tzdata \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* \
  && echo 'pcm.!default = null;' > /etc/asound.conf

# Python stdlib for Kodi's embedded (static) interpreter. It lives outside
# /usr/lib so it never mixes with the system Python used by supervisor;
# supervisord.conf points PYTHONHOME of the kodi process here.
COPY --from=depends /out/kodi-python /opt/kodi-python

# Copy Kodi from build stage
COPY --from=build /tmp/kodi-build/usr/ /usr/

# Fail the build if Kodi's binaries need a shared lib that is not in this image
# (depends libs are static; whatever is left comes from the apt list above).
RUN for b in /usr/lib/kodi/kodi-*; do \
      if ldd "$b" 2>/dev/null | grep -q "not found"; then \
        ldd "$b" | grep "not found"; exit 1; \
      fi; \
    done

# Copy easy-novnc
COPY --from=easy-novnc /usr/local/bin/easy-novnc /usr/local/bin/easy-novnc

# Copy configuration files
COPY supervisord.conf /etc/
COPY advancedsettings.xml /usr/share/kodi/
COPY docker-entrypoint.sh /

# Create app user and group
RUN groupadd --gid 2000 app \
  && useradd --home-dir /data --shell /bin/bash --uid 2000 --gid 2000 app

# Environment variables
ENV KODI_UID=2000 \
    KODI_GID=2000 \
    KODI_DB_HOST=mysql \
    KODI_DB_PORT=3306 \
    KODI_DB_USER=kodi \
    KODI_DB_PASS=kodi \
    KODI_UMASK=002 \
    KODI_NOVNC_PORT=8001 \
    MALLOC_ARENA_MAX=1 \
    MALLOC_MMAP_THRESHOLD_=8192

VOLUME /data

# Expose ports
EXPOSE 5900/tcp 8001/tcp 8080/tcp 9090/tcp 9777/udp

# Health check
HEALTHCHECK --start-period=5s --interval=30s --retries=1 --timeout=5s \
  CMD /usr/bin/supervisorctl status all >/dev/null || exit 1

CMD ["/docker-entrypoint.sh"]
