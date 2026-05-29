#pragma once
#define _ALLOW_KEYWORD_MACROS
#ifdef __cplusplus
#define static_assert(...)
#endif

// Undefine _DEBUG to force standard CRT and STL headers to compile in Release mode,
// which prevents any references to _CrtDbgReport and avoids requiring debug DLLs on user machines.
#undef _DEBUG
