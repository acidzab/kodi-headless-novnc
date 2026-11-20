#!/bin/sh
# Configures Kodi in /tmp/xbmc/build. Used by both the internal-deps stage
# (first configure, then the ENABLE_INTERNAL_* libraries are built) and the
# build stage (reconfigure after the Kodi-only patches, then Kodi itself):
# the arguments MUST be the same in both, otherwise ExternalProject sees a
# changed configuration and rebuilds the libraries. Hence this single script.
# CFLAGS, CXXFLAGS and WITH_CPU come from the environment (the stage ARGs).
#
# USE_INTERNAL_LIBS=ON makes every ENABLE_INTERNAL_* "dependent_option" default
# to ON (ASS, CURL(+brotli, nghttp2), DAV1D, EXIV2, FLATBUFFERS, FMT, SPDLOG,
# LIBDVD, LIBMICROHTTPD, LZO2, MARIADBCLIENT, NFS, NLOHMANNJSON, PCRE2, SWIG,
# TAGLIB(+utfcpp), UDFREAD, XSLT); CROSSGUID is ON by default and
# FFMPEG, FSTRCMP (plain option, OFF by default) and TINYXML2 (only declared as
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
# after libpython.a). libintl.a: depends' python3 builds _locale against depends'
# GNU gettext (its libintl.h renames gettext() to libintl_gettext()).
# -lgnutls is for the static libmicrohttpd (built with HTTPS; Kodi's
# FindMicroHttpd has a "Todo: gnutls" and does not add it to the link).
set -e

mkdir -p /tmp/xbmc/build
cd /tmp/xbmc/build

# WITH_CPU is unquoted on purpose: empty means no argument at all.
CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" exec cmake ../. \
  ${WITH_CPU} \
  -DCMAKE_INSTALL_LIBDIR=/usr/lib \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DUSE_INTERNAL_LIBS=ON \
  -DENABLE_INTERNAL_FFMPEG=ON \
  -DENABLE_INTERNAL_TINYXML2=ON \
  -DENABLE_INTERNAL_FSTRCMP=ON \
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
  -DPYTHON_VER="$(cat /opt/kodi-deps/python-version)" \
  -DPython3_USE_STATIC_LIBS=ON \
  -DCMAKE_CXX_STANDARD_LIBRARIES="/opt/kodi-deps/lib/libexpat.a /opt/kodi-deps/lib/libffi.a /opt/kodi-deps/lib/liblzma.a /opt/kodi-deps/lib/libbz2.a /opt/kodi-deps/lib/libintl.a -lssl -lcrypto -lsqlite3 -lgnutls -lz -ldl -lpthread -lutil -lrt -lm"
