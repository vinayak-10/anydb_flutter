# CMake Toolchain file for Cross-Compiling targeting Windows x64 using LLVM on Linux
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Compiler checks enabled

# Set compilers and linker using the local wrapper symlinks
set(CMAKE_C_COMPILER "/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/bin/clang-cl")
set(CMAKE_CXX_COMPILER "/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/bin/clang-cl")
set(CMAKE_LINKER "/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/bin/lld-link" CACHE FILEPATH "Linker")
set(CMAKE_RC_COMPILER "/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/bin/llvm-rc" CACHE FILEPATH "RC Compiler")
set(CMAKE_MT "/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/bin/llvm-mt" CACHE FILEPATH "Manifest Tool")

# Define target triple for compilation and linking
set(triple x86_64-pc-windows-msvc)
set(CMAKE_C_COMPILER_TARGET ${triple})
set(CMAKE_CXX_COMPILER_TARGET ${triple})

# Define SDK and CRT directories from xwin
set(XWIN_DIR "/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/xwin")
set(CRT_INC "${XWIN_DIR}/crt/include")
set(SDK_INC "${XWIN_DIR}/sdk/include")
set(CRT_LIB "${XWIN_DIR}/crt/lib/x86_64")
set(SDK_LIB "${XWIN_DIR}/sdk/lib")

# Add system include directories using /imsvc to treat them as system headers
set(sys_includes
  "/imsvc${CRT_INC}"
  "/imsvc${SDK_INC}/ucrt"
  "/imsvc${SDK_INC}/shared"
  "/imsvc${SDK_INC}/um"
  "/imsvc${SDK_INC}/winrt"
)
string(REPLACE ";" " " sys_includes_str "${sys_includes}")

# Add linker search paths using /libpath: to feed to lld-link
set(sys_libpaths
  "/libpath:${CRT_LIB}"
  "/libpath:${SDK_LIB}/ucrt/x86_64"
  "/libpath:${SDK_LIB}/um/x86_64"
)
string(REPLACE ";" " " sys_libpaths_str "${sys_libpaths}")

# Inject headers globally into compiler flags
set(CMAKE_C_FLAGS "${sys_includes_str} /MD /D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH /FI/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/preinclude.h -Wno-unused-parameter -Wno-unused -Wno-microsoft-extra-qualification -Wno-extra-qualification" CACHE STRING "C compiler flags" FORCE)
set(CMAKE_CXX_FLAGS "${sys_includes_str} /MD /D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH /FI/home/ruggedcoder/softwares/fresh/anydb_flutter/xyz.maya/preinclude.h -Wno-unused-parameter -Wno-unused -Wno-microsoft-extra-qualification -Wno-extra-qualification" CACHE STRING "C++ compiler flags" FORCE)

# Override Debug flags to use /MD (Release CRT) to prevent linking against missing debug CRT libraries and avoid requiring debug dlls on user machines
set(CMAKE_C_FLAGS_DEBUG "/MD /Zi /Ob0 /Od /D_ITERATOR_DEBUG_LEVEL=0" CACHE STRING "C compiler flags for Debug" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG "/MD /Zi /Ob0 /Od /D_ITERATOR_DEBUG_LEVEL=0" CACHE STRING "C++ compiler flags for Debug" FORCE)

# Inject resource compiler includes
set(sys_rc_includes "-I${CRT_INC} -I${SDK_INC}/ucrt -I${SDK_INC}/shared -I${SDK_INC}/um -I${SDK_INC}/winrt")
set(CMAKE_RC_FLAGS "${sys_rc_includes}" CACHE STRING "RC compiler flags" FORCE)

# Inject library search paths globally into linker flags
set(CMAKE_EXE_LINKER_FLAGS "${sys_libpaths_str} /nodefaultlib:msvcrtd.lib msvcrt.lib vcruntime.lib ucrt.lib /alternatename:__guard_eh_cont_table=memset /alternatename:__guard_eh_cont_count=memset" CACHE STRING "Executable linker flags" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${sys_libpaths_str} /nodefaultlib:msvcrtd.lib msvcrt.lib vcruntime.lib ucrt.lib /alternatename:__guard_eh_cont_table=memset /alternatename:__guard_eh_cont_count=memset" CACHE STRING "Shared library linker flags" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "${sys_libpaths_str} /nodefaultlib:msvcrtd.lib msvcrt.lib vcruntime.lib ucrt.lib /alternatename:__guard_eh_cont_table=memset /alternatename:__guard_eh_cont_count=memset" CACHE STRING "Module linker flags" FORCE)

# Set runtime library to Release DLL by default
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "MSVC runtime library")
