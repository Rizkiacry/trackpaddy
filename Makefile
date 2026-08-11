LIBS=-F/System/Library/PrivateFrameworks -framework MultitouchSupport \
	 -framework CoreFoundation \
	 -framework Carbon

BUILD_DIR=build
SOURCE_DIR=src
UTIL=driver
TARGET=trackpaddy
APP=trackpaddy.app

SWIFT_SOURCES=$(wildcard ${SOURCE_DIR}/*.swift)
UTIL_BIN=${BUILD_DIR}/bin/${UTIL}
APP_BIN=${BUILD_DIR}/bin/${TARGET}
ARCH=$(shell uname -m)
DEPLOYMENT_TARGET?=26.0
SWIFT_FLAGS=-target ${ARCH}-apple-macosx${DEPLOYMENT_TARGET}

.PHONY: all release dev bundle install install_util_update dirs

all: dirs ${UTIL_BIN} ${APP_BIN} bundle

release: dirs ${UTIL_BIN}_release ${APP_BIN}_release bundle

dev: all
	${BUILD_DIR}/${APP}/Contents/MacOS/${TARGET}

dirs:
	@mkdir -p ${BUILD_DIR}/bin

${UTIL_BIN}: ${SOURCE_DIR}/${UTIL}.c | dirs
	gcc ${LIBS} $< -o $@ -g

${UTIL_BIN}_release: ${SOURCE_DIR}/${UTIL}.c | dirs
	gcc ${LIBS} $< -o ${UTIL_BIN} -O3

${APP_BIN}: ${SWIFT_SOURCES} | dirs
	swiftc ${SWIFT_FLAGS} ${SWIFT_SOURCES} -o $@ -g -j$(shell sysctl -n hw.ncpu)

${APP_BIN}_release: ${SWIFT_SOURCES} | dirs
	swiftc ${SWIFT_FLAGS} ${SWIFT_SOURCES} -o ${APP_BIN} -O

bundle: ${UTIL_BIN} ${APP_BIN}
	@mkdir -p ${BUILD_DIR}/${APP}/Contents/MacOS
	@mkdir -p ${BUILD_DIR}/${APP}/Contents/Resources
	@cp -R Resources/* ${BUILD_DIR}/${APP}/Contents/Resources/
	@cp Info.plist ${BUILD_DIR}/${APP}/Contents
	@cp ${UTIL_BIN} ${BUILD_DIR}/${APP}/Contents/MacOS
	@cp ${APP_BIN} ${BUILD_DIR}/${APP}/Contents/MacOS

install:
	cp -R ${BUILD_DIR}/${APP} /Applications

install_util_update:
	cp ${BUILD_DIR}/bin/${UTIL} /Applications/${APP}/Contents/MacOS
