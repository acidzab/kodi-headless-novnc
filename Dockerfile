ARG BASE_IMAGE="ubuntu:24.04"
ARG EASY_NOVNC_IMAGE="fhriley/easy-novnc:1.6.0"

FROM $EASY_NOVNC_IMAGE AS easy-novnc
FROM $BASE_IMAGE AS build

ARG DEBIAN_FRONTEND="noninteractive"
ARG PYTHON_VERSION=3.12

# Install Kodi build dependencies
RUN apt-get update -y \
    && apt-get install --no-install-recommends -y software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    autopoint \
    autotools-dev \
    cmake \
    cpp \
    curl \
    debhelper \
    default-jre \
    default-libmysqlclient-dev \
    g++ \
    gawk \
    gcc  \
    gdc \
    gettext \
    git \
    gperf \
    libasound2-dev \
    libass-dev  \
    libbluray-dev \
    libbz2-dev \
    libcdio-dev \
    libcdio++-dev \
    libcrossguid-dev \
    libcurl4-openssl-dev \
    libcwiid-dev \
    libdav1d-dev \
    libdrm-dev \
    libegl1-mesa-dev \
    libenca-dev \
    libexiv2-dev \
    libflac-dev \
    libflatbuffers-dev \
    libfmt-dev  \
    libfontconfig-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libfstrcmp-dev \
    libgbm-dev \
    libgcrypt-dev \
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
    libltdl-dev \
    liblzo2-dev \
    libmicrohttpd-dev \
    libnfs-dev \
    libogg-dev \
    libomxil-bellagio-dev \
    libp8-platform-dev \
    libpcre3-dev \
    libplist-dev \
    libpng-dev \
    libsmbclient-dev \
    libspdlog-dev  \
    libsqlite3-dev \
    libssh-dev \
    libssl-dev \
    libtag1-dev \
    libtiff5-dev \
    libtinyxml-dev \
    libtinyxml2-dev \
    libtool \
    libunistring-dev \
    libvorbis-dev \
    libxkbcommon-dev \
    libxmu-dev \
    libxrandr-dev \
    libxslt1-dev \
    libxt-dev \
    lsb-release \
    meson \
    nasm \
    ninja-build \
    nlohmann-json3-dev \
    python${PYTHON_VERSION}-dev \
    swig \
    unzip \
    uuid-dev \
    yasm \
    zip \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

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

# Build Kodi with Python 3.13
RUN mkdir -p /tmp/xbmc/build \
  && cd /tmp/xbmc/build \
  && CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" cmake ../. \
    ${WITH_CPU} \
    -DCMAKE_INSTALL_LIBDIR=/usr/lib \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DAPP_RENDER_SYSTEM=gl \
    -DCORE_PLATFORM_NAME=x11 \
    -DENABLE_AIRTUNES=OFF \
    -DENABLE_ALSA=ON \
    -DENABLE_AVAHI=OFF \
    -DENABLE_BLUETOOTH=OFF \
    -DENABLE_BLURAY=ON \
    -DENABLE_CAP=OFF \
    -DENABLE_CEC=OFF \
    -DENABLE_DBUS=OFF \
    -DENABLE_DVDCSS=OFF \
    -DENABLE_INTERNAL_FFMPEG=ON \
    -DENABLE_INTERNAL_NLOHMANNJSON=OFF \
    -DENABLE_EVENTCLIENTS=OFF \
    -DENABLE_GLX=ON \
    -DENABLE_LCMS2=OFF \
    -DENABLE_LIBUSB=OFF \
    -DENABLE_LIRCCLIENT=OFF \
    -DENABLE_NFS=ON \
    -DENABLE_OPTICAL=OFF \
    -DENABLE_PULSEAUDIO=OFF \
    -DPYTHON_VER=${PYTHON_VERSION} \
    -DENABLE_SNDIO=OFF \
    -DENABLE_TESTING=OFF \
    -DENABLE_UDEV=OFF \
    -DENABLE_UPNP=ON \
    -DENABLE_VAAPI=OFF \
    -DENABLE_VDPAU=OFF \
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
ARG PYTHON_VERSION=3.12

# Install runtime dependencies
RUN apt-get update -y \
    && apt-get install --no-install-recommends -y software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    alsa-base \
    ca-certificates \
    curl \
    gosu \
    libasound2t64 \
    libass9 \
    libbluray2 \
    libcrossguid0 \
    libcurl4t64 \
    libdav1d7 \
    libegl1 \
    libexiv2-27 \
    libfmt9 \
    libfstrcmp0 \
    libgl1 \
    libiso9660-11t64 \
    liblzo2-2 \
    libmicrohttpd12t64 \
    libmysqlclient21 \
    libnfs14 \
    libpcrecpp0v5 \
    libplist-2.0-4 \
    libpython${PYTHON_VERSION} \
    libsmbclient0 \
    libspdlog1.12 \
    libtag1v5 \
    libtinyxml2.6.2v5 \
    libtinyxml2-10 \
    libudf0t64 \
    libudfread0 \
    libxrandr2 \
    libxslt1.1 \
    python${PYTHON_VERSION} \
    samba-common-bin \
    supervisor \
    tigervnc-standalone-server \
    tigervnc-tools \
    tzdata \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* \
  && echo 'pcm.!default = null;' > /etc/asound.conf

# Set PYTHON_VERSION as the default Python interpreter
RUN update-alternatives --install /usr/bin/python3 python /usr/bin/python$PYTHON_VERSION 1
RUN update-alternatives --set python /usr/bin/python$PYTHON_VERSION

# Copy Kodi from build stage
COPY --from=build /tmp/kodi-build/usr/ /usr/

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
    KODI_NOVNC_PORT=8001

VOLUME /data

# Expose ports
EXPOSE 5900/tcp 8001/tcp 8080/tcp 9090/tcp 9777/udp

# Health check
HEALTHCHECK --start-period=5s --interval=30s --retries=1 --timeout=5s \
  CMD /usr/bin/supervisorctl status all >/dev/null || exit 1

CMD ["/docker-entrypoint.sh"]