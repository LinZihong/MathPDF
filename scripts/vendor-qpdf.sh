#!/bin/zsh

set -euo pipefail

readonly QPDF_TAG="v12.3.2"
readonly QPDF_COMMIT="a898bb3a7289d1d05789d6d3f0d5dd534943a8da"
readonly JPEG_TAG="3.2.0"
readonly JPEG_COMMIT="c85e6b905bf237038faa936dab160ebfc5da0344"
readonly DEPLOYMENT_TARGET="15.7"

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR:h}"
readonly DESTINATION="${PROJECT_DIR}/ThirdParty/qpdf"
readonly WORK_ROOT="$(mktemp -d /tmp/MathPDF-qpdf-vendor.XXXXXX)"

cleanup() {
    rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $1"
        exit 1
    fi
}

require_tool cmake
require_tool git
require_tool lipo

git clone --quiet --branch "${QPDF_TAG}" --depth 1 https://github.com/qpdf/qpdf.git "${WORK_ROOT}/qpdf"
git clone --quiet --branch "${JPEG_TAG}" --depth 1 https://github.com/libjpeg-turbo/libjpeg-turbo.git "${WORK_ROOT}/libjpeg-turbo"

[[ "$(git -C "${WORK_ROOT}/qpdf" rev-parse HEAD)" == "${QPDF_COMMIT}" ]]
[[ "$(git -C "${WORK_ROOT}/libjpeg-turbo" rev-parse HEAD)" == "${JPEG_COMMIT}" ]]

for arch in arm64 x86_64; do
    jpeg_build="${WORK_ROOT}/jpeg-build-${arch}"
    jpeg_install="${WORK_ROOT}/jpeg-install-${arch}"
    qpdf_build="${WORK_ROOT}/qpdf-build-${arch}"

    cmake -S "${WORK_ROOT}/libjpeg-turbo" -B "${jpeg_build}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
        -DCMAKE_INSTALL_PREFIX="${jpeg_install}" \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON \
        -DWITH_SIMD=OFF \
        -DWITH_TURBOJPEG=OFF \
        -DWITH_TOOLS=OFF \
        -DWITH_TESTS=OFF
    cmake --build "${jpeg_build}" --target install --parallel

    cmake -S "${WORK_ROOT}/qpdf" -B "${qpdf_build}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
        -DCMAKE_PREFIX_PATH="${jpeg_install}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DUSE_IMPLICIT_CRYPTO=OFF \
        -DREQUIRE_CRYPTO_NATIVE=ON \
        -DBUILD_DOC=OFF \
        -DINSTALL_EXAMPLES=OFF \
        -DINSTALL_MANUAL=OFF
    cmake --build "${qpdf_build}" --target libqpdf --parallel
done

mkdir -p "${DESTINATION}/include/qpdf" "${DESTINATION}/lib" "${DESTINATION}/licenses"
cp -R "${WORK_ROOT}/qpdf/include/qpdf/." "${DESTINATION}/include/qpdf/"
cp "${WORK_ROOT}/qpdf-build-arm64/libqpdf/qpdf/qpdf-config.h" "${DESTINATION}/include/qpdf/qpdf-config.h"

lipo -create \
    "${WORK_ROOT}/qpdf-build-arm64/libqpdf/libqpdf.a" \
    "${WORK_ROOT}/qpdf-build-x86_64/libqpdf/libqpdf.a" \
    -output "${DESTINATION}/lib/libqpdf.a"
lipo -create \
    "${WORK_ROOT}/jpeg-install-arm64/lib/libjpeg.a" \
    "${WORK_ROOT}/jpeg-install-x86_64/lib/libjpeg.a" \
    -output "${DESTINATION}/lib/libjpeg.a"

cp "${WORK_ROOT}/qpdf/LICENSE.txt" "${DESTINATION}/licenses/qpdf-LICENSE.txt"
cp "${WORK_ROOT}/qpdf/NOTICE.md" "${DESTINATION}/licenses/qpdf-NOTICE.md"
cp "${WORK_ROOT}/libjpeg-turbo/LICENSE.md" "${DESTINATION}/licenses/libjpeg-turbo-LICENSE.md"

lipo -info "${DESTINATION}/lib/libqpdf.a"
lipo -info "${DESTINATION}/lib/libjpeg.a"
