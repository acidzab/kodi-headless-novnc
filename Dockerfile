ARG BASE_IMAGE="ubuntu:26.04"
ARG EASY_NOVNC_IMAGE="fhriley/easy-novnc:1.6.0"

FROM $EASY_NOVNC_IMAGE AS easy-novnc

# ============================================================================
# Python built by Kodi's own tools/depends (the exact version Kodi pins,
# static libpython). Only the python3 target is built here: every other
# library is built by Kodi's cmake (ENABLE_INTERNAL_*) or comes from apt.
# ============================================================================
FROM $BASE_IMAGE AS python-depends

ARG DEBIAN_FRONTEND="noninteractive"
ARG KODI_BRANCH="master"
ARG PYTHON_VERSION=3.14
ARG DEPENDS_PREFIX="/opt/kodi-deps"
ARG CFLAGS=
ARG CXXFLAGS=

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    autopoint \
    nasm \
    autotools-dev \
    bzip2 \
    ca-certificates \
    cmake \
    curl \
    g++ \
    gawk \
    gcc \
    gettext \
    git \
    gzip \
    libtool \
    m4 \
    make \
    patch \
    perl \
    pkg-config \
    tar \
    xz-utils \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --branch ${KODI_BRANCH} https://github.com/xbmc/xbmc.git /tmp/xbmc

# Native build of the host triplet; the layout is
# ${DEPENDS_PREFIX}/<triplet>-release (target) and <triplet>-native (tools).
RUN cd /tmp/xbmc/tools/depends \
 && ./bootstrap \
 && ./configure \
      --prefix=${DEPENDS_PREFIX} \
      --host=$(gcc -dumpmachine) \
      --with-toolchain=/usr \
      --with-rendersystem=gl \
      --with-tarballs=/tmp/tarballs \
      --with-target-cflags="${CFLAGS}" \
      --with-target-cxxflags="${CXXFLAGS}" \
      --disable-debug

# depends invokes <native>/bin/cmake for expat, xz and libxml2: reuse the apt
# cmake instead of compiling a native one. If this ever fails, drop the
# symlink and add "cmake" to the native targets below.
RUN N=$(ls -d ${DEPENDS_PREFIX}/*-native) \
 && mkdir -p ${N}/bin \
 && ln -sf "$(command -v cmake)" ${N}/bin/cmake

# Native: build-python + automake (provides share/automake-*/config.sub that
# many target Makefiles copy). automake/libtool are built first and serially,
# otherwise parallel native expat/libpng race on the missing config.sub.
RUN cd /tmp/xbmc/tools/depends \
 && make -C native libtool \
 && make -j $(nproc) -C native python3

# depends' generated Toolchain.cmake (used by cmake-based deps: zlib, expat,
# xz, libxml2) REQUIRES these tools inside <native>/bin. The ones depends did
# not build are taken from apt (ln -s without -f never overwrites built ones).
RUN N=$(ls -d ${DEPENDS_PREFIX}/*-native) \
 && for t in nasm autoconf aclocal autoheader automake autom4te autopoint autoreconf libtool libtoolize; do \
      [ -e ${N}/bin/$t ] || ln -s "$(command -v $t)" ${N}/bin/$t; \
    done \
 && ls ${N}/bin

# Target: python3 and what it depends on (expat gettext libxml2 sqlite3
# openssl libffi bzip2 xz).
RUN cd /tmp/xbmc/tools/depends && make -j $(nproc) -C target python3

# Collect only what the next stages need:
#   /out/include  python headers          -> build stage
#   /out/lib      libpython + its static deps -> build stage
#   /out/pylib    stdlib (opt-1 .pyc, Kodi runs with PYTHONOPTIMIZE) -> runtime
RUN P=$(ls -d ${DEPENDS_PREFIX}/*-release) \
 && N=$(ls -d ${DEPENDS_PREFIX}/*-native) \
 && for f in libpython${PYTHON_VERSION}.a libexpat.a libffi.a liblzma.a libbz2.a; do \
      test -f "${P}/lib/${f}" || { echo "missing ${P}/lib/${f}"; exit 1; }; \
    done \
 && mkdir -p /out/include /out/lib \
 && cp -a ${P}/include/python${PYTHON_VERSION} /out/include/ \
 && cp -a ${P}/lib/libpython${PYTHON_VERSION}.a ${P}/lib/libexpat.a ${P}/lib/libffi.a \
          ${P}/lib/liblzma.a ${P}/lib/libbz2.a /out/lib/ \
 && L=${P}/lib/python${PYTHON_VERSION} \
 && rm -rf ${L}/test ${L}/idlelib ${L}/turtledemo ${L}/tkinter ${L}/ensurepip \
 && (${N}/bin/python3 -O -m compileall -q ${L} || true) \
 && cp -a ${L} /out/pylib

FROM $BASE_IMAGE AS build

ARG DEBIAN_FRONTEND="noninteractive"
ARG PYTHON_VERSION=3.14

# Install Kodi build dependencies
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    autopoint \
    autotools-dev \
    bison \
    ca-certificates \
    cmake \
    cpp \
    curl \
    debhelper \
    default-jre \
    g++ \
    gawk \
    gcc  \
    gdc \
    gettext \
    git \
    gperf \
    libasound2-dev \
    libbz2-dev \
    libcdio-dev \
    libcdio++-dev \
    libcwiid-dev \
    libdrm-dev \
    libegl1-mesa-dev \
    libenca-dev \
    libflac-dev \
    libfontconfig-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libgbm-dev \
    libgcrypt-dev \
    libharfbuzz-dev \
    libgif-dev  \
    libgl1-mesa-dev \
    libglew-dev \
    libglu1-mesa-dev \
    libgnutls28-dev \
    libgpg-error-dev \
    libinput-dev \
    libiso9660++-dev \
    libiso9660-dev \
    libjpeg-dev \
    liblzo2-dev \
    libltdl-dev \
    libogg-dev \
    libp8-platform-dev \
    libpcre2-dev \
    libplist-dev \
    libpng-dev \
    libsmbclient-dev \
    libsqlite3-dev \
    libssh-dev \
    libssl-dev \
    libtiff5-dev \
    libtinyxml-dev \
    libtool \
    libunistring-dev \
    libvorbis-dev \
    libxml2-dev \
    libxkbcommon-dev \
    libxmu-dev \
    libxrandr-dev \
    libxt-dev \
    lsb-release \
    make \
    meson \
    nasm \
    ninja-build \
    patch \
    pkg-config \
    unzip \
    uuid-dev \
    yasm \
    zip \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

# Python (static libpython + headers) and its static deps, built by Kodi's own
# tools/depends in the python-depends stage: no apt Python, no second libpython.
COPY --from=python-depends /out/include/ /opt/kodi-deps/include/
COPY --from=python-depends /out/lib/ /opt/kodi-deps/lib/

ARG KODI_BRANCH="master"

# Clone Kodi source
RUN cd /tmp \
 && git clone --depth=1 --branch ${KODI_BRANCH} https://github.com/xbmc/xbmc.git

# Apply AudioLibrary Api Patch
COPY patches/ /patches/
RUN cd /tmp/xbmc \
 && git apply --ignore-whitespace /patches/*.patch

ARG CFLAGS=
ARG CXXFLAGS=
ARG WITH_CPU=

# Build Kodi
# USE_INTERNAL_LIBS=ON makes every ENABLE_INTERNAL_* "dependent_option" default
# to ON (ASS, CURL(+brotli, nghttp2), DAV1D, EXIV2, FLATBUFFERS, FMT, SPDLOG,
# LIBDVD, LIBMICROHTTPD, LZO2, MARIADBCLIENT, NFS, NLOHMANNJSON, PCRE2, SWIG,
# TAGLIB(+utfcpp), UDFREAD, XSLT); CROSSGUID is ON by default and
# FSTRCMP is built internally on Linux; FFMPEG and TINYXML2 (only declared as
# dependent_option for depends/Windows builds, so USE_INTERNAL_LIBS does not
# reach it on Linux) are set explicitly. FFMPEG is a plain option, hence the
# explicit flag. Kodi downloads and builds them with ExternalProject and links
# them statically into kodi.bin, so no RPATH / LD_LIBRARY_PATH is needed.
# Only libs Kodi cannot build itself stay on apt: OpenSSL, zlib, sqlite3,
# freetype, fribidi, harfbuzz, fontconfig, libxml2, tinyxml (v1), smbclient,
# libplist, libcdio, gnutls (libmicrohttpd https), X11/GL/ALSA.
# Python is the depends-built static libpython from /opt/kodi-deps. Its static
# modules (expat, ffi, lzma, bz2, ssl, sqlite3, zlib) are not pulled in by
# FindPython.cmake outside a depends build, so they are appended to the end of
# the link line through CMAKE_CXX_STANDARD_LIBRARIES (static archives must come
# after libpython.a). -lgnutls is for the static libmicrohttpd (built with HTTPS;
# Kodi's FindMicroHttpd has a "Todo: gnutls" and does not add it to the link).
# Build notes:
# - liblzo2-dev (and libpng/libgif/libjpeg): Kodi's internal TexturePacker is a
#   *host* tool configured by its own sub-project, which does not see the
#   internal lzo2 and needs the system one.
# - MAKEFLAGS ACLOCAL/AUTOMAKE/AUTOCONF/AUTOHEADER=: the libmicrohttpd tarball
#   is extracted with mtimes that make automake think it must regenerate
#   aclocal.m4; its Makefile then asks for aclocal-1.17 while Ubuntu 26.04 ships
#   1.18. The shipped autotools output is consistent, so regeneration is
#   disabled. It is applied ONLY to the build-libmicrohttpd target: MAKEFLAGS
#   leaks into the environment, and libass runs a real autoreconf that breaks
#   if AUTOCONF/ACLOCAL are ":".
RUN mkdir -p /tmp/xbmc/build \
  && cd /tmp/xbmc/build \
  && CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" cmake ../. \
    ${WITH_CPU} \
    -DCMAKE_INSTALL_LIBDIR=/usr/lib \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DUSE_INTERNAL_LIBS=ON \
    -DENABLE_INTERNAL_FFMPEG=ON \
    -DENABLE_INTERNAL_TINYXML2=ON \
    -DAPP_RENDER_SYSTEM=gl \
    -DCORE_PLATFORM_NAME=x11 \
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
    -DENABLE_PULSEAUDIO=OFF \
    -DENABLE_SNDIO=OFF \
    -DENABLE_TESTING=OFF \
    -DENABLE_UDEV=OFF \
    -DENABLE_UPNP=OFF \
    -DENABLE_VAAPI=OFF \
    -DENABLE_VDPAU=OFF \
    -DPYTHON_PATH=/opt/kodi-deps \
    -DPYTHON_VER=${PYTHON_VERSION} \
    -DPython3_USE_STATIC_LIBS=ON \
    -DCMAKE_CXX_STANDARD_LIBRARIES="/opt/kodi-deps/lib/libexpat.a /opt/kodi-deps/lib/libffi.a /opt/kodi-deps/lib/liblzma.a /opt/kodi-deps/lib/libbz2.a -lssl -lcrypto -lsqlite3 -lgnutls -lz -ldl -lpthread -lutil -lrt -lm" \
 && MAKEFLAGS="ACLOCAL=: AUTOMAKE=: AUTOCONF=: AUTOHEADER=:" make -j $(nproc) build-libmicrohttpd \
 && make -j $(nproc) \
 && make DESTDIR=/tmp/kodi-build install

# Install kodi-send and xbmcclient
RUN install -Dm755 \
	/tmp/xbmc/tools/EventClients/Clients/KodiSend/kodi-send.py \
	/tmp/kodi-build/usr/bin/kodi-send \
 && install -Dm644 \
	/tmp/xbmc/tools/EventClients/lib/python/xbmcclient.py \
	/tmp/kodi-build/usr/lib/python${PYTHON_VERSION}/xbmcclient.py

# ============================================================================
# Final runtime image
# ============================================================================
FROM $BASE_IMAGE

ARG DEBIAN_FRONTEND="noninteractive"
ARG PYTHON_VERSION=3.14

# Install runtime dependencies
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    alsa-base \
    ca-certificates \
    curl \
    gosu \
    libasound2t64 \
    libegl1 \
    libfontconfig1 \
    libfreetype6 \
    libfribidi0 \
    libgnutls30t64 \
    libharfbuzz0b \
    libgl1 \
    libssl3t64 \
    libiso9660-12 \
    libplist-2.0-4 \
    libsqlite3-0 \
    libsmbclient0 \
    libudf0t64 \
    libxrandr2 \
    libxslt1.1 \
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
COPY --from=python-depends /out/pylib /opt/kodi-python/lib/python${PYTHON_VERSION}

# Copy Kodi from build stage
COPY --from=build /tmp/kodi-build/usr/ /usr/

# Fail the build if Kodi's binaries need a shared lib that is not in this image
# (internal deps are static; whatever is left comes from the apt list above).
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