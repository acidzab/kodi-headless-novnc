ARG BASE_IMAGE="ubuntu:22.04"
ARG EASY_NOVNC_IMAGE="fhriley/easy-novnc:1.3.0"

FROM $EASY_NOVNC_IMAGE as easy-novnc
FROM $BASE_IMAGE as build

ARG DEBIAN_FRONTEND="noninteractive"

RUN apt-get update -y \
  && apt purge kodi* \
  && apt-get update -y \
  && apt-get install -y \
    autoconf \
    automake \
    autopoint \
    autotools-dev \
    cmake \
    cpp  \
    curl \
    default-jre \
    default-libmysqlclient-dev \
    flatbuffers-compiler \
    flatbuffers-compiler-dev \
    g++  \
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
    libcdio++-dev \
    libcdio-dev \
    libcrossguid-dev \
    libcurl4-openssl-dev \
    libcwiid-dev \
    libdav1d-dev \
    libdrm-dev \
    libegl1-mesa-dev \
    libenca-dev \
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
    libkissfft-dev \
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
    python3-dev \
    python3-pil \
    rapidjson-dev \
    swig \
    unzip \
    uuid-dev \
    yasm \
    zip \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists

ARG KODI_BRANCH="master"

RUN cd /tmp \
 && git clone --depth=1 --branch ${KODI_BRANCH} https://github.com/xbmc/xbmc.git

# Apply AudioLibrary Api Patch
COPY patches/ /patches/
RUN \
 cd /tmp/xbmc && \
 git apply --ignore-whitespace /patches/*.patch

ARG CFLAGS=
ARG CXXFLAGS=
ARG WITH_CPU=

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
    -DENABLE_INTERNAL_CROSSGUID=OFF \
    -DENABLE_INTERNAL_KISSFFT=OFF \
    -DENABLE_INTERNAL_RapidJSON=OFF \
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
    -DENABLE_UPNP=ON \
    -DENABLE_VAAPI=OFF \
    -DENABLE_VDPAU=OFF \
 && make -j $(nproc) \
 && make DESTDIR=/tmp/kodi-build install

ARG PYTHON_VERSION=3.10

RUN install -Dm755 \
	/tmp/xbmc/tools/EventClients/Clients/KodiSend/kodi-send.py \
	/tmp/kodi-build/usr/bin/kodi-send \
 && install -Dm644 \
	/tmp/xbmc/tools/EventClients/lib/python/xbmcclient.py \
	/tmp/kodi-build/usr/lib/python${PYTHON_VERSION}/xbmcclient.py


FROM $BASE_IMAGE

ARG DEBIAN_FRONTEND="noninteractive"
ARG PYTHON_VERSION=3.10

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
    alsa-base \
    ca-certificates \
    curl \
    gosu \
    libasound2 \
    libass9 \
    libbluray2 \
    libcrossguid0 \
    libcurl4 \
    libdav1d5 \
    libegl1 \
    libfmt8 \
    libfstrcmp0 \
    libgl1 \
    libiso9660-11 \
    libkissfft-float131 \
    liblzo2-2 \
    libmicrohttpd12 \
    libmysqlclient21 \
    libnfs13 \
    libpcrecpp0v5 \
    libplist3 \
    libpython${PYTHON_VERSION} \
    libsmbclient \
    libspdlog1 \
    libtag1v5 \
    libtinyxml2.6.2v5 \
    libtinyxml2-9 \
    libudf0 \
    libudfread0 \
    libxrandr2 \
    libxslt1.1 \
    python3-minimal \
    samba-common-bin \
    supervisor \
    tigervnc-standalone-server \
    tigervnc-tools \
    tzdata \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* \
  && echo 'pcm.!default = null;' > /etc/asound.conf

COPY --from=build /tmp/kodi-build/usr/ /usr/
COPY --from=easy-novnc /usr/local/bin/easy-novnc /usr/local/bin/easy-novnc

COPY supervisord.conf /etc/
COPY advancedsettings.xml /usr/share/kodi/
COPY docker-entrypoint.sh /

VOLUME /data

CMD ["/docker-entrypoint.sh"]

# VNC
EXPOSE 5900/tcp

# HTTP (noVNC)
EXPOSE 8001/tcp

# Kodi HTTP API
EXPOSE 8080/tcp

# Websockets
EXPOSE 9090/tcp

# EventServer
EXPOSE 9777/udp

VOLUME /data

RUN groupadd --gid 2000 app && \
  useradd --home-dir /data --shell /bin/bash --uid 2000 --gid 2000 app

ENV KODI_UID=2000
ENV KODI_GID=2000
ENV KODI_DB_HOST=mysql
ENV KODI_DB_PORT=3306
ENV KODI_DB_USER=kodi
ENV KODI_DB_PASS=kodi
ENV KODI_UMASK=002
ENV KODI_NOVNC_PORT=8001

HEALTHCHECK --start-period=5s --interval=30s --retries=1 --timeout=5s \
  CMD /usr/bin/supervisorctl status all >/dev/null || exit 1

