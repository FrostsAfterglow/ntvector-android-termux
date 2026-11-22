#!/bin/bash
# Vector (NTvector) Android/Termux 源码适配补丁
# 修复上游 Py3 迁移遗留的、仅在大小写敏感文件系统 / 非 Windows 平台暴露的编译问题。
# 用法：在 NTvector 源码根目录执行  bash fix_android_sources.sh
set -e
cd "$(dirname "$0")"

echo "==> [1/3] 修复 <SLikeNet/xxx.h> include 路径（Android 大小写敏感）"
grep -rl 'SLikeNet/' application --include='*.h' --include='*.cpp' 2>/dev/null | \
  xargs -r sed -i 's|<SLikeNet/|<|g'

echo "==> [2/3] 修复 ScrollLog() 在非 Windows 下调用未定义的 RedrawLogPane()"
# RedrawLogPane 定义在 #ifdef _WIN32 块内，但 ScrollLog() 无条件调用它。
# 只在 ScrollLog 函数体内删除该调用（其余被 #ifdef 保护的调用保留）。
if grep -q '^void ScrollLog' application/Core/VectorConsole.cpp 2>/dev/null; then
  sed -i '/^void ScrollLog/,/^}/ { /RedrawLogPane();/d; }' application/Core/VectorConsole.cpp
fi

echo "==> [3/4] 修复 PythonRuntime.cpp 未加平台保护的 #include <windows.h>"
# 其它文件都用 #ifdef _WIN32 包了 windows.h，唯独此处漏包，Android 下无此头文件。
if grep -q '^#include <windows.h>' application/Python/PythonRuntime.cpp 2>/dev/null; then
  sed -i 's|^#include <windows.h>|#ifdef _WIN32\n#include <windows.h>\n#endif|' application/Python/PythonRuntime.cpp
fi

echo "==> [4/5] 修复非 Windows 下 Py_SetPythonHome 硬编码为 '.' 导致找不到标准库"
# 原逻辑: #else 分支写死 Py_SetPythonHome(L".")，运行目录无 stdlib 时
# 报 ModuleNotFoundError: No module named 'encodings'。
# 改为: 若设置了 PYTHONHOME 则用环境变量指定的路径，否则回退 '.'。
python3 - <<'PYEOF'
p = 'application/Python/PythonRuntime.cpp'
s = open(p, encoding='utf-8').read()
old = '''#else
    Py_SetPythonHome(L".");
#endif
}'''
new = '''#else
    // Android/Termux: do NOT override here. Let CPython honor the PYTHONHOME
    // environment variable (pointing at the bundled stdlib), falling back to
    // its compiled-in default when the variable is absent.
#endif
}'''
if old in s and 'do NOT override here' not in s:
    s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('   已移除 Py_SetPythonHome(".") 硬编码')
else:
    print('   跳过（已修复或未匹配）')
PYEOF

echo "==> [5/5] 验证"
echo "--- 残留 SLikeNet/ include（应为空）:"
grep -rn 'SLikeNet/' application --include='*.h' --include='*.cpp' 2>/dev/null | head || true
echo "--- ScrollLog 函数体（应无 RedrawLogPane 调用）:"
sed -n '/^void ScrollLog/,/^}/p' application/Core/VectorConsole.cpp
echo "--- PythonRuntime.cpp 头部（windows.h 应被 #ifdef _WIN32 包裹）:"
sed -n '1,8p' application/Python/PythonRuntime.cpp
echo "--- SetPythonHome #else 分支（应读取 PYTHONHOME）:"
sed -n '/^#else/,/^}/p' application/Python/PythonRuntime.cpp | grep -A9 -m1 'Py_SetPythonHome' || true
echo "==> 完成。现在执行: cmake --build build -j\$(nproc)"
