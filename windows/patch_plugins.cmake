# Source patches for pinned Windows plugin versions that predate MSVC 14.51+
# (the toolchain on windows-latest / Visual Studio 2026). Newer MSVC releases
# promoted several constructs these plugins rely on from warnings to hard
# errors.
#
# flutter_inappwebview_windows (0.6.0, the current release):
#
#   C4596  member declarations inside a class body qualified with the class
#          name (`bool Rect::operator==(...)` inside `class Rect`), now an
#          error in conformance mode
#   C3861  `always_false_v<T>` in utils/util.h, a variable template the plugin
#          uses but never defines; it used to survive because the discarded
#          `if constexpr` branch was never parsed under the old lookup rules
#   C2065  `return s2;` left in the void `to_uppercase` template in
#          utils/string.h (it belongs to to_uppercase_copy)
#   C2664  the join helper's std::accumulate lambda takes `auto&`; the C++20
#          standard library passes the accumulator as an rvalue, which cannot
#          bind to a non-const lvalue reference. The lambda only reads its
#          arguments, so take them by const reference.
#
# Upstream has not released a fixed version: 0.6.0 and 0.7.0-beta.3 both still
# contain all of these.
#
# flutter_local_notifications_windows (3.1.1, pulled by
# flutter_local_notifications 22.x):
#
#   C++20  plugin.cpp copy-initializes std::string from CW2A, which is
#          ambiguous in C++20. 4.0.0 fixed this and raised the standard to
#          C++20; CMakeLists.txt raises the standard for the 3.1.1 target and
#          this script applies the same two-line constructor change. The
#          target also needs C++20 so C++/WinRT uses <coroutine> instead of the
#          removed <experimental/coroutine> header (STL1011).
#
# Patch the pub-cache copies in place at CMake configure time. Every
# replacement is a no-op once applied, so reconfiguring is safe.
#
# Remove this file and its include in CMakeLists.txt once both plugins are
# upgraded to releases that support MSVC 14.51.

if(NOT DEFINED FLUTTER_INAPPWEBVIEW_WINDOWS_DIR)
  set(FLUTTER_INAPPWEBVIEW_WINDOWS_DIR "${CMAKE_CURRENT_LIST_DIR}/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows")
endif()

if(NOT DEFINED FLUTTER_LOCAL_NOTIFICATIONS_WINDOWS_DIR)
  set(FLUTTER_LOCAL_NOTIFICATIONS_WINDOWS_DIR "${CMAKE_CURRENT_LIST_DIR}/flutter/ephemeral/.plugin_symlinks/flutter_local_notifications_windows/src")
endif()

if(NOT EXISTS "${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}")
  message(WARNING
    "flutter_inappwebview_windows is not in the Windows plugin symlinks yet; "
    "run `flutter pub get` before configuring the Windows build.")
endif()

# Read a file with LF line endings so the replacements below match regardless
# of how the pub cache was extracted on this machine.
function(read_plugin_file path out_var)
  file(READ "${path}" contents)
  string(REPLACE "\r\n" "\n" contents "${contents}")
  set(${out_var} "${contents}" PARENT_SCOPE)
endfunction()

if(EXISTS "${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}")
# Drop the redundant `Class::` qualifier from member declarations inside the
# class body. Definitions in the .cpp files keep their qualifiers.
foreach(header rect.h size_2d.h permission_response.h)
  read_plugin_file("${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/types/${header}" contents)
  if(header STREQUAL "rect.h")
    string(REPLACE "bool Rect::operator==" "bool operator==" contents "${contents}")
    string(REPLACE "bool Rect::operator!=" "bool operator!=" contents "${contents}")
  elseif(header STREQUAL "size_2d.h")
    string(REPLACE "bool Size2D::operator==" "bool operator==" contents "${contents}")
    string(REPLACE "bool Size2D::operator!=" "bool operator!=" contents "${contents}")
  else()
    string(REPLACE "bool PermissionResponse::operator==" "bool operator==" contents "${contents}")
    string(REPLACE "bool PermissionResponse::operator!=" "bool operator!=" contents "${contents}")
  endif()
  file(WRITE "${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/types/${header}" "${contents}")
endforeach()

read_plugin_file("${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/types/web_resource_response.h" contents)
string(REPLACE
  "ICoreWebView2WebResourceResponse* WebResourceResponse::toWebView2Response"
  "ICoreWebView2WebResourceResponse* toWebView2Response"
  contents "${contents}")
file(WRITE "${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/types/web_resource_response.h" "${contents}")

# A dependent expression that is always false, without relying on an undefined
# helper template.
read_plugin_file("${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/utils/util.h" contents)
string(REPLACE "always_false_v<T>" "(sizeof(T) == 0)" contents "${contents}")
file(WRITE "${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/utils/util.h" "${contents}")

# to_uppercase returns void; the trailing `return s2;` was copied from
# to_uppercase_copy and is invalid. Match through the next declaration so only
# the stray statement inside to_uppercase is removed.
read_plugin_file("${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/utils/string.h" contents)
string(REPLACE
  "    return s2;\n  }\n\n  template <typename T>\n  std::basic_string<T> to_uppercase_copy("
  "  }\n\n  template <typename T>\n  std::basic_string<T> to_uppercase_copy("
  contents "${contents}")
string(REPLACE
  "[delim](auto& a, auto& b) { return a + delim + b; }"
  "[delim](const auto& a, const auto& b) { return a + delim + b; }"
  contents "${contents}")
file(WRITE "${FLUTTER_INAPPWEBVIEW_WINDOWS_DIR}/utils/string.h" "${contents}")
endif()

# flutter_local_notifications_windows 3.1.1: std::string's range constructor
# makes `const std::string s = CW2A(...)` ambiguous under C++20. Construct the
# string explicitly, matching the change upstream shipped in 4.0.0.
if(EXISTS "${FLUTTER_LOCAL_NOTIFICATIONS_WINDOWS_DIR}/plugin.cpp")
  read_plugin_file("${FLUTTER_LOCAL_NOTIFICATIONS_WINDOWS_DIR}/plugin.cpp" contents)
  string(REPLACE
    "const std::string key = CW2A(item.Key, CP_UTF8);"
    "const std::string key(CW2A(item.Key, CP_UTF8));"
    contents "${contents}")
  string(REPLACE
    "const std::string value = CW2A(item.Value, CP_UTF8);"
    "const std::string value(CW2A(item.Value, CP_UTF8));"
    contents "${contents}")
  file(WRITE "${FLUTTER_LOCAL_NOTIFICATIONS_WINDOWS_DIR}/plugin.cpp" "${contents}")
endif()
