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

echo "==> [3/3] 验证"
echo "--- 残留 SLikeNet/ include（应为空）:"
grep -rn 'SLikeNet/' application --include='*.h' --include='*.cpp' 2>/dev/null | head || true
echo "--- ScrollLog 函数体（应无 RedrawLogPane 调用）:"
sed -n '/^void ScrollLog/,/^}/p' application/Core/VectorConsole.cpp
echo "==> 完成。现在执行: cmake --build build -j\$(nproc)"
