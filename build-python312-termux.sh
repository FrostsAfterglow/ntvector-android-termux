#!/usr/bin/env bash
# ============================================================
# build-python312-termux.sh
# 在 Termux (Android aarch64) 原生编译 CPython 3.12.2，
# 产出 libpython3.12.so 供 Vector (NTvector) 内嵌运行时链接。
#
# 为什么不用 Termux 自带的 python？
#   Vector 的原生模块是按 CPython 3.12 ABI + pybind11 编译的，
#   且链接方式要求动态库 libpython3.12.so（Py_ENABLE_SHARED）。
#   自己编译可精确锁定 3.12.2，避免版本漂移导致 ABI 不匹配。
#
# 用法：
#   chmod +x build-python312-termux.sh
#   ./build-python312-termux.sh
# 完成后安装前缀默认为 $HOME/py312（可用环境变量 PY312_PREFIX 覆盖）。
# ============================================================
set -euo pipefail

PY_VER="3.12.2"
PY_SHORT="3.12"
PREFIX="${PY312_PREFIX:-$HOME/py312}"
SRC_DIR="${HOME}/cpython-${PY_VER}"
TAR="Python-${PY_VER}.tgz"
JOBS="$(nproc)"
LOG="${HOME}/py312-build.log"

echo "==> Python ${PY_VER}  |  安装前缀: ${PREFIX}  |  并行: ${JOBS}"
mkdir -p "$HOME" && cd "$HOME"

# ---------- 1. 依赖 ----------
echo "==> [1/6] 安装编译依赖"
pkg update -y >/dev/null 2>&1 || true
pkg install -y clang make perl pkg-config \
    libffi openssl zlib libsqlite libexpat bzip2 xz-utils \
    libcrypt libandroid-support libandroid-posix-semaphore \
    wget patchelf || { echo "依赖安装失败，请检查网络/源"; exit 1; }

# ---------- 2. 源码 ----------
echo "==> [2/6] 下载源码"
if [ ! -f "$TAR" ]; then
    wget -O "$TAR" "https://www.python.org/ftp/python/${PY_VER}/${TAR}"
fi
rm -rf "$SRC_DIR"
tar xzf "$TAR"
mv "Python-${PY_VER}" "$SRC_DIR"
cd "$SRC_DIR"

# ---------- 3. 环境 ----------
echo "==> [3/6] 设置编译环境"
export CC=clang
export CXX=clang++
export CPPFLAGS="-D__ANDROID_API__=24 -Wno-implicit-function-declaration -I${PREFIX}/include"
export CFLAGS="-Wno-implicit-function-declaration -Wno-int-conversion -fPIC"
export CXXFLAGS="-Wno-implicit-function-declaration -fPIC"
# Termux 特有库：posix 信号量 / support；--enable-shared 需要 rpath 指向安装后的 lib
export LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib -landroid-posix-semaphore -landroid-support -Wl,--as-needed"
export LIBCRYPT_LIBS="-lcrypt"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"

# ---------- 4. configure ----------
# 参数来源：Termux 社区 termux-python 移植（已在 Android 验证），
# 关键新增 --enable-shared，因为 Vector 以 Py_ENABLE_SHARED 方式链接。
echo "==> [4/6] configure（日志: ${LOG}）"
./configure \
    --prefix="${PREFIX}" \
    --enable-shared \
    --with-system-ffi \
    --with-system-expat \
    --without-ensurepip \
    --enable-loadable-sqlite-extensions \
    ac_cv_file__dev_ptmx=yes \
    ac_cv_file__dev_ptc=no \
    ac_cv_func_wcsftime=no \
    ac_cv_func_ftime=no \
    ac_cv_func_faccessat=no \
    ac_cv_func_linkat=no \
    ac_cv_buggy_getaddrinfo=no \
    ac_cv_little_endian_double=yes \
    ac_cv_posix_semaphores_enabled=yes \
    ac_cv_func_sem_open=yes \
    ac_cv_func_sem_timedwait=yes \
    ac_cv_func_sem_getvalue=yes \
    ac_cv_func_sem_unlink=yes \
    ac_cv_func_shm_open=yes \
    ac_cv_func_shm_unlink=yes \
    ac_cv_func_getloadavg=no \
    ac_cv_func_setpwent=no \
    ac_cv_func_getpwent=no \
    ac_cv_func_forkpty=no \
    ac_cv_func_openpty=no \
    2>&1 | tee "$LOG"

# ---------- 5. 编译安装 ----------
echo "==> [5/6] make -j${JOBS}（首次约 15-40 分钟，手机请确保插电+散热）"
# [FIX] Android/Termux 的文件系统通常不支持硬链接，CPython 构建 libpython3.12.so
# 时会用 ln 创建硬链接并报 "Permission denied"。改为软链接可绕过（已在真机验证）：
#   1) 把 Makefile 里的 LN 默认命令改为 ln -s
#   2) 预创建 libpython3.12.so 软链接，避免链接规则触发硬链接
#   3) make 时再用 LN="ln -s" 覆盖一次，双保险
sed -i 's/^LN[[:space:]]*=.*/LN = ln -s/' Makefile 2>/dev/null || true
rm -f "libpython${PY_SHORT}.so"
ln -s "libpython${PY_SHORT}.so.1.0" "libpython${PY_SHORT}.so" 2>/dev/null || true
make LN="ln -s" -j"${JOBS}" 2>&1 | tee -a "$LOG"
make install 2>&1 | tee -a "$LOG"

# ---------- 6. 校验 ----------
echo "==> [6/6] 校验产物"
"${PREFIX}/bin/python${PY_SHORT}" -V
ls -l "${PREFIX}/lib/libpython${PY_SHORT}.so"* \
    || { echo "!! 未找到 libpython${PY_SHORT}.so，--enable-shared 可能未生效"; exit 1; }
test -f "${PREFIX}/include/python${PY_SHORT}/Python.h" \
    || { echo "!! 未找到 Python.h"; exit 1; }

echo ""
echo "============================================================"
echo "完成。CPython ${PY_VER} 已安装到 ${PREFIX}"
echo ""
echo "下一步（编译 Vector）："
echo "  cp application_CMakeLists.txt  <NTvector>/application/CMakeLists.txt"
echo "  cd <NTvector>"
echo "  cmake -B build -DPLATFORM_ANDROID=ON -DPY312_ANDROID_ROOT=${PREFIX}"
echo "  cmake --build build -j\$(nproc)"
echo ""
echo "运行时若报找不到 libpython，执行："
echo "  export LD_LIBRARY_PATH=${PREFIX}/lib:\$LD_LIBRARY_PATH"
echo "============================================================"
