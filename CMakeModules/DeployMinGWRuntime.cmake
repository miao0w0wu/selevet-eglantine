# SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copies the non-system DLLs a MinGW-built executable depends on next to it.
#
# windeployqt only handles Qt's own libraries. A MinGW build also needs its toolchain runtime
# (libstdc++-6.dll, libgcc_s_seh-1.dll, libwinpthread-1.dll) plus everything the other imported
# DLLs pull in. When those are missing the Qt platform plugin cannot be loaded, and the program
# aborts at startup with "no Qt platform plugin could be initialized" instead of naming the DLL.
#
# Usage:
#   cmake -DEXE=<executable> -DDEST=<output dir> -DPREFIX=<mingw prefix> -P DeployMinGWRuntime.cmake

if(NOT EXE OR NOT DEST OR NOT PREFIX)
    message(FATAL_ERROR "DeployMinGWRuntime: EXE, DEST and PREFIX are required")
endif()
if(NOT EXISTS "${EXE}")
    message(FATAL_ERROR "DeployMinGWRuntime: '${EXE}' does not exist")
endif()

find_program(OBJDUMP_EXECUTABLE NAMES objdump HINTS "${PREFIX}/bin")
if(NOT OBJDUMP_EXECUTABLE)
    message(WARNING "DeployMinGWRuntime: objdump not found in ${PREFIX}/bin, skipping runtime deploy")
    return()
endif()

# Windows' own libraries and the UCRT API sets are always present; never copy them.
set(SYSTEM_PREFIXES
    api-ms- ext-ms-
    advapi32 authz avrt bcrypt cfgmgr32 comctl32 comdlg32 crypt32 dbghelp
    d3d9 d3d11 d3d12 d3dcompiler dcomp dnsapi dwmapi dwrite dxcore dxgi dxva2
    gdi32 gdiplus hid imagehlp imm32 iphlpapi kernel32 ksuser mfplat mpr mscms msimg32
    msvcrt mswsock netapi32 ncrypt ntdll normaliz ole32 oleacc oleaut32 opengl32
    pdh powrprof propsys psapi quartz rpcrt4 secur32 sensorsapi setupapi shcore shell32
    shlwapi tdh urlmon user32 userenv usp10 uxtheme version wevtapi winhttp wininet winmm
    winspool winsta wintrust wlanapi wldap32 ws2_32 wtsapi32 xinput
)

set(_queue "${EXE}")
set(_seen "")
set(_copied 0)

while(_queue)
    list(POP_FRONT _queue _current)
    get_filename_component(_current_name "${_current}" NAME)
    string(TOLOWER "${_current_name}" _current_key)
    if(_current_key IN_LIST _seen)
        continue()
    endif()
    list(APPEND _seen "${_current_key}")

    execute_process(COMMAND "${OBJDUMP_EXECUTABLE}" -p "${_current}"
        OUTPUT_VARIABLE _dump ERROR_QUIET)

    # "DLL Name: foo.dll" one per import.
    string(REGEX MATCHALL "DLL Name: [^\r\n]+" _matches "${_dump}")

    foreach(_m IN LISTS _matches)
        string(REGEX REPLACE "^DLL Name: *" "" _dep_name "${_m}")
        string(STRIP "${_dep_name}" _dep_name)
        if(NOT _dep_name)
            continue()
        endif()
        string(TOLOWER "${_dep_name}" _dep_lower)

        set(_is_system FALSE)
        foreach(_prefix IN LISTS SYSTEM_PREFIXES)
            string(FIND "${_dep_lower}" "${_prefix}" _pos)
            if(_pos EQUAL 0)
                set(_is_system TRUE)
                break()
            endif()
        endforeach()
        if(_is_system)
            continue()
        endif()

        # Already deployed (by windeployqt or a previous pass): recurse into it, do not overwrite.
        if(EXISTS "${DEST}/${_dep_name}")
            list(APPEND _queue "${DEST}/${_dep_name}")
            continue()
        endif()

        if(EXISTS "${PREFIX}/bin/${_dep_name}")
            execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                "${PREFIX}/bin/${_dep_name}" "${DEST}/${_dep_name}")
            math(EXPR _copied "${_copied} + 1")
            list(APPEND _queue "${DEST}/${_dep_name}")
        endif()
    endforeach()
endwhile()

message(STATUS "DeployMinGWRuntime: copied ${_copied} DLL(s) to ${DEST}")
