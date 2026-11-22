# Vector Android/Termux 补丁包（1+2）

本目录包含两份产物，对应你要的「CMake 补丁」+「CPython 3.12.2 编译脚本」。

| 文件 | 用途 |
|---|---|
| `application_CMakeLists.txt` | 替换仓库的 `application/CMakeLists.txt`，修复 Python 链接 |
| `build-python312-termux.sh` | 在 Termux 编译 CPython 3.12.2，产出 `libpython3.12.so` |

> 调研结论：仓库的 `cmake/BuildOpenSSL.cmake` **已内置 aarch64 分支**，`cmake/Platform.cmake` 已处理 Bionic 链接，**都不用改**。真正断掉的只有 `application/CMakeLists.txt` 第 3–11 行硬编码的 Windows Python 路径。

---

## 完整操作步骤

### 第 1 步：编译 CPython 3.12.2

```bash
pkg update -y && pkg upgrade -y
# F-Droid 版 Termux；Play 商店版已停止维护
chmod +x build-python312-termux.sh
./build-python312-termux.sh
```

- 默认安装到 `$HOME/py312`，可用 `PY312_PREFIX=/自定义路径 ./...` 覆盖。
- 脚本已加 `--enable-shared`（**关键**：Vector 用 `Py_ENABLE_SHARED` 宏 + 动态链接 `libpython3.12.so`）。
- 若某步失败，看 `$HOME/py312-build.log` 最后几十行；configure 阶段失败多为缺依赖，make 阶段失败多为 Android 特有符号，把报错贴给我。
- 备选：若自编译卡住，可直接用社区现成的 3.12 版（第三种选择，见文末）。

### 第 2 步：应用 CMake 补丁

```bash
git clone https://github.com/lurete-cn/NTvector.git
cd NTvector
cp /path/to/application_CMakeLists.txt ./application/CMakeLists.txt
```

> 这是**完整文件替换**，不是 git patch。原文件只剩 Python 链接段被改成平台分支，其余 170+ 行与上游一致（含 `PLATFORM_ANDROID` 分支只链 `dl m`）。

### 第 3 步：配置与编译

```bash
cmake -B build \
  -DPLATFORM_ANDROID=ON \
  -DPY312_ANDROID_ROOT="$HOME/py312"
cmake --build build -j$(nproc)
```

- 平台会被 `cmake/Platform.cmake` 自动识别（检测到 Bionic 即设 `PLATFORM_ANDROID=TRUE`），手动指定更稳妥。
- OpenSSL 在 configure 期从源码编译（aarch64 目标，约 5–10 分钟，缓存在 `build/_deps/`）。
- 产物：`build/Program`。

### 第 4 步：部署运行

把运行时文件放到 `Program` 同目录：

```
Vector/
├── Program
├── libpython3.12.so        ← 从 $HOME/py312/lib/ 拷贝（或靠 rpath/LD_LIBRARY_PATH）
├── python3.12/             ← 标准库 + site-packages
├── source/                 ← 框架脚本（init.py / proton.py / redirect.py）
├── scripts/                ← 你的插件
└── mc.cfg / client_cfg.json / skin_data.json
```

```bash
export LD_LIBRARY_PATH="$HOME/py312/lib:$LD_LIBRARY_PATH"
./Program --config mc.cfg --logger
```

看到 `log.txt` 里 `PlayStatus value: 3`（PlayerSpawn）即成功进服。

---

## 已知风险与排障

| 现象 | 原因 / 处理 |
|---|---|
| `configure` 报缺头文件 | 回到第 1 步补 `pkg install`（libffi/openssl/zlib/libsqlite/libexpat） |
| `make` 报 `HAVE_CLOSE_RANGE` / `getlogin_r` 相关符号 | Termux 上部分 syscall 是 stub，需在 `pyconfig.h` 里把对应 `#define HAVE_xxx 1` 注释掉或 `#undef`；把报错贴我 |
| 链接报 `undefined reference to Py_...` | `libpython3.12.so` 没链上：确认 `-DPY312_ANDROID_ROOT` 路径正确、`.so` 存在 |
| 运行报 `libpython3.12.so: cannot open` | 设 `LD_LIBRARY_PATH` 或确认脚本里 rpath 已生效 |
| `cxa` 符号缺失 | `Platform.cmake` 注释说由 `application/platform/cxa_stub.cpp` 提供弱符号，确认它参与了编译（源码在即自动 GLOB 进来） |
| 目录大小写 / 找不到头文件 | Bionic 大小写敏感，`SLikeNet-master` 目录名必须与 `#include` 完全一致，别改名 |

---

## 第三种选择（更省事，但需验证 ABI）

社区已有编译好的 **Python 3.12 for Termux**（带 `termux.patch`）：
- `https://github.com/csh1258/termux-python-12`（3.12.1）
- `https://github.com/Wenceslausstar/termux-python`（3.12.5）

思路：直接用它们的产物替换 `$HOME/py312`。**但要注意**：这些包默认可能不含 `libpython3.12.so`（多为静态链接），而 Vector 必须要动态库。用之前先 `find <prefix> -name 'libpython*.so'` 确认。若没有，仍需走本脚本的 `--enable-shared` 路线。

---

## 仍需你验证的部分

我在沙箱里**没有 Android 环境**，以下无法替你实测：
1. CPython 3.12.2 在 Termux 上 `--enable-shared` 的完整编译是否一遍过（configure 参数已按社区验证版整理，但 Android 版本差异可能导致个别 syscall 开关需微调）。
2. pybind11 编译的 19 个原生模块与自编译 `libpython3.12.so` 的 ABI 是否完全对齐（同为 3.12.2 理论上没问题）。
3. 四种网络后端（尤其 WebRTC/RakNet）在移动网络下的实际稳定性。

遇到任何报错，把 `py312-build.log` 或 cmake/make 的输出贴给我，我按错误逐条修。
