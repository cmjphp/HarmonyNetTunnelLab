cmake_minimum_required(VERSION 3.16)
project(HarmonyVpnMihomoPoc)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH "arm64-v8a")
endif()
option(BUILD_BUNDLED_MIHOMO_STUB "Build the placeholder mihomo adapter stub" OFF)

add_library(vpn_core SHARED
    napi_init.cpp
    native/mihomo_adapter.cpp
    native/vpn_core.cpp
)

set(MIHOMO_PREBUILT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmihomo_adapter.so")
set(MIHOMO_PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}")
if(EXISTS "${MIHOMO_PREBUILT_PATH}")
    message(STATUS "Using prebuilt mihomo adapter (RUNTIME DLOPEN): ${MIHOMO_PREBUILT_PATH}")
    set(HAS_MIHOMO_PREBUILT TRUE)
elseif(BUILD_BUNDLED_MIHOMO_STUB)
    message(STATUS "No prebuilt mihomo adapter found, building stub adapter")
    add_library(mihomo_adapter SHARED
        mihomo_adapter/mihomo_adapter_stub.cpp
    )

    target_include_directories(mihomo_adapter PRIVATE
        ${NATIVERENDER_ROOT_PATH}/mihomo_adapter
    )
else()
    message(STATUS "No prebuilt mihomo adapter found and bundled stub is disabled")
endif()

target_include_directories(vpn_core PRIVATE
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/native
)

set_target_properties(vpn_core PROPERTIES
    SKIP_BUILD_RPATH TRUE
    BUILD_WITH_INSTALL_RPATH FALSE
    INSTALL_RPATH ""
)

target_link_libraries(vpn_core PUBLIC libace_napi.z.so libhilog_ndk.z.so)

if(BUILD_BUNDLED_MIHOMO_STUB)
    target_link_libraries(vpn_core PUBLIC mihomo_adapter)
endif()
