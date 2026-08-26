cmake_minimum_required(VERSION 3.22.1)
project(ffm_local_model_bridge)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Vendor source is pinned in the repository. A caller may override this path
# for local smoke builds, but released/CI builds never depend on an absolute
# workstation path.
set(LLAMA_SRC "${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/llama.cpp" CACHE PATH "Pinned llama.cpp source directory")
get_filename_component(LLAMA_SRC "${LLAMA_SRC}" ABSOLUTE)
if(NOT EXISTS "${LLAMA_SRC}/CMakeLists.txt")
    message(FATAL_ERROR "Pinned llama.cpp source not found: ${LLAMA_SRC}")
endif()

# Android CPU fallback. GPU backends and network helpers are intentionally off.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_RPC OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_MTMD OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory("${LLAMA_SRC}" llama-build EXCLUDE_FROM_ALL)

add_library(ffm_local_model_bridge SHARED ffm_local_model_bridge.cpp)

target_include_directories(ffm_local_model_bridge PRIVATE
    "${LLAMA_SRC}/include"
    "${LLAMA_SRC}/ggml/include"
)

target_link_libraries(ffm_local_model_bridge
    llama
    log
)
