# HarmonyNetTunnelLab

<div align="center">

**HarmonyOS NEXT Network Tunnel and Protocol Stack Research Project**

A research-oriented project for validating Network Extension, virtual network interfaces, multi-language Native bridging, and protocol stack adaptation on HarmonyOS NEXT.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-NEXT-orange)](https://developer.harmonyos.com/)
[![Language](https://img.shields.io/badge/Lang-ArkTS%20%7C%20C%2B%2B%20%7C%20Go-blue)]()

</div>

---

## Overview

HarmonyNetTunnelLab is a network protocol research project for **HarmonyOS NEXT**. It is designed to validate the engineering feasibility of HarmonyOS NEXT Network Extension capabilities, virtual network interface data paths, and a mixed-language architecture based on ArkTS, NAPI, C++ Native, and Go c-shared components.

This project focuses on the following technical areas:

* Lifecycle management of HarmonyOS NEXT Network Extension capabilities, including startup, authorization, execution, and resource cleanup
* ArkTS → NAPI → C++ Native → Go c-shared multi-language invocation chain
* Cross-compiling Go-based network protocol components into HarmonyOS arm64 shared libraries
* Virtual interface data flow, protocol parsing, runtime statistics, and diagnostics
* Engineering validation for mobile network management, enterprise internal network access, and network protocol development/debugging scenarios

---

## Technical Goals

This project is primarily a PoC and engineering validation project. It aims to verify:

1. The practical capability boundaries of Network Extension on HarmonyOS NEXT;
2. The bridge design between the ArkTS application layer and the Native C++ layer;
3. Native-layer management of virtual interface file descriptors, lifecycle handling, and data reading;
4. The feasibility of integrating Go components into HarmonyOS native applications through `c-shared`;
5. Local runtime configuration, protocol statistics, diagnostics, and error recovery mechanisms;
6. Stability and maintainability of a mixed-language architecture on real HarmonyOS NEXT devices.

---

## Upstream and Third-party Projects

This project may reference or optionally integrate the following open-source projects:

| Project                                                            | Description                                                                                          | License                             |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ----------------------------------- |
| [mihomo](https://github.com/metacubex/mihomo)                      | Optional rule engine and network protocol component for engineering adaptation research              | MIT                                 |
| [ohos_golang_go](https://gitee.com/openharmony-sig/ohos_golang_go) | Go toolchain adaptation maintained by OpenHarmony SIG for `GOOS=ohos` experiments                    | BSD-style                           |
| OpenHarmony / HarmonyOS SDK                                        | HarmonyOS NEXT application framework, Network Extension capabilities, and Native development support | Subject to the official SDK license |

If this repository includes third-party source code, patches, dynamic libraries, or build artifacts, their source, version, license, modifications, and distribution method should be documented in `THIRD_PARTY_NOTICES.md`.

---

## Go Component Adaptation

This project optionally explores cross-compiling Go-based network protocol components into HarmonyOS arm64 shared libraries and loading them in a HarmonyOS native application through a C ABI adaptation layer.

This direction is used to validate the following engineering questions:

* Whether Go projects can be cross-compiled for HarmonyOS NEXT;
* Whether `.so` shared libraries generated with `c-shared` are usable in this environment;
* How ArkTS, NAPI, C++, and Go can exchange data;
* How Native components cooperate with the lifecycle of a Network Extension;
* How local configuration, runtime state, statistics, and diagnostics can be bridged across layers.

Example C ABI design:

```c
int AdapterSetConfigPath(const char *path);
int AdapterSetRuntimeMode(const char *mode);
int AdapterSetInterfaceFd(int fd);
int AdapterStart(void);
int AdapterStop(void);
const char *AdapterGetStats(void);
const char *AdapterGetDiagnostics(void);
```

The above interfaces are for engineering research only. The actual implementation should be based on the project source code.

---

## About ohos_golang_go

The official Go toolchain does not currently provide a standard `ohos/arm64` mobile application target.

`ohos_golang_go` is a Go toolchain adaptation project maintained by OpenHarmony SIG. It explores how the Go compiler and runtime can be adapted for OpenHarmony / HarmonyOS-related environments. With this toolchain, it is possible to experiment with building HarmonyOS arm64 shared libraries using parameters such as:

```bash
CGO_ENABLED=1
GOOS=ohos
GOARCH=arm64
-buildmode=c-shared
```

This project uses that toolchain to study how Go components can be integrated into HarmonyOS native applications:

```text
Go source code
  ↓
ohos_golang_go toolchain
  ↓
OHOS Clang / CMake / NDK cross-compilation toolchain
  ↓
libxxx_adapter.so
  ↓
HarmonyOS NEXT HAP packaging
  ↓
NAPI / C++ Native dynamic loading
```

---

## System Architecture

```text
┌─────────────────────────────────────────────────────┐
│                  ArkTS Application Layer             │
│  ┌────────────┐ ┌────────────┐ ┌──────────────────┐ │
│  │ Status View │ │ Config Mgmt │ │ Control / Diag   │ │
│  └────────────┘ └────────────┘ └──────────────────┘ │
├─────────────────────────────────────────────────────┤
│              Network Extension Layer                 │
│  • Creates a virtual network interface                │
│  • Manages extension lifecycle                         │
│  • Maintains runtime status and error information      │
│  • Coordinates system authorization and start/stop flow │
├─────────────────────────────────────────────────────┤
│              NAPI Bridge (C++)                        │
│  • startCore / stopCore / setInterfaceFd / setConfig  │
│  • getStats / getDiagnostics                          │
│  • Bridges data between ArkTS and Native layers         │
├─────────────────────────────────────────────────────┤
│              Native Core (C++ / CMake)                │
│  • fd management                                       │
│  • Data read/write loop                                │
│  • Basic IPv4 / TCP / UDP / DNS parsing                │
│  • Dynamic library loading and ABI adaptation           │
├─────────────────────────────────────────────────────┤
│         Optional Go Adapter (.so / c-shared)          │
│  • Optional Go-based network protocol component         │
│  • C ABI: Start / Stop / SetFd / GetStats              │
│  • Used to validate Go ecosystem adaptation on HarmonyOS │
└─────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Layer               | Technology                                              | Description                                                                 |
| ------------------- | ------------------------------------------------------- | --------------------------------------------------------------------------- |
| UI Layer            | ArkTS / ArkUI                                           | HarmonyOS declarative UI and status presentation                            |
| System Capability   | Network Extension / VpnExtensionAbility / VpnConnection | Network extension, virtual interface, and lifecycle management              |
| Bridge Layer        | NAPI / C++                                              | Bidirectional calls between ArkTS and Native components                     |
| Native Layer        | C++ / CMake                                             | fd management, data reading, protocol parsing, dynamic loading, diagnostics |
| Optional Core Layer | Go c-shared `.so`                                       | Go protocol components exposed through C ABI                                |
| Build Support       | ohos_golang_go / Docker                                 | Go component cross-compilation and isolated build environment               |

---

## Current Capabilities

This project is mainly used for PoC validation. Planned or implemented capabilities include:

* Network Extension startup, authorization, and stop-flow validation
* Virtual network interface creation and parameter configuration
* ArkTS pages for runtime status, logs, and diagnostics
* NAPI / C++ Native bridge validation
* Native-layer fd reception and lifecycle management
* Basic IPv4 / TCP / UDP / DNS statistics
* Local YAML configuration loading and runtime parameter generation
* Network endpoint configuration structure parsing and presentation
* Routing policy structure parsing and presentation
* Connectivity check interface reservation
* Optional Go c-shared dynamic library loading and ABI invocation validation
* Native Core diagnostics, including:

  * uninitialized
  * stub mode
  * missing dynamic library
  * ABI mismatch
  * running
  * startup failure

---

## Multi-language Cross-compilation Flow

```text
Go source / Go Adapter
    │
    ▼
ohos_golang_go
    │
    ├─ CGO_ENABLED=1
    ├─ GOOS=ohos
    ├─ GOARCH=arm64
    └─ -buildmode=c-shared
    │
    ▼
OHOS Clang / CMake / NDK
    │
    ▼
libxxx_adapter.so
    │
    ▼
entry/libs/arm64-v8a/
    │
    ▼
HAP packaging
    │
    ▼
HarmonyOS NEXT device
    │
    ▼
NAPI / C++ Native dlopen loading
```

---

## Project Structure

```text
HarmonyNetTunnelLab/
├── AppScope/                  # Application metadata and icons
├── entry/
│   └── src/main/
│       ├── ets/               # ArkTS application layer
│       │   ├── api/           # Local API / diagnostics wrappers
│       │   ├── common/        # Constants / utility functions
│       │   ├── components/    # UI components
│       │   ├── core/          # Config / diagnostics / statistics storage
│       │   ├── model/         # Data models
│       │   ├── native/        # NAPI Bridge call wrappers
│       │   ├── pages/         # Pages
│       │   ├── store/         # Global state management
│       │   ├── extension/     # Network Extension Ability / Service
│       │   └── entryability/  # Application entry Ability
│       ├── cpp/               # Native C++ layer
│       │   ├── native/        # fd handling / dynamic library loading
│       │   ├── adapter/       # C ABI headers / stub
│       │   └── CMakeLists.txt
│       ├── resources/         # Resources
│       └── module.json5       # Module declaration
├── tools/                     # Build scripts and helper tools
│   ├── adapter-go/            # Go c-shared adapter sample source
│   ├── build-adapter.sh
│   ├── verify-adapter.sh
│   └── docker-build-adapter.sh
├── docker/                    # Docker build environment
├── docs/                      # Development documentation
├── third_party/               # Third-party licenses and notices
├── build-profile.json5        # Build configuration
├── oh-package.json5           # Package metadata
├── THIRD_PARTY_NOTICES.md     # Third-party notices
├── LICENSE
└── README.md
```

---

## UI Naming Guidelines

To keep the project aligned with its engineering validation scope, neutral technical naming is recommended for internal pages and actions:

| Page / Feature             | Recommended Name              |
| -------------------------- | ----------------------------- |
| Home                       | Overview                      |
| Control Page               | Runtime Control               |
| Configuration Page         | Configuration Management      |
| Policy Page                | Routing Policy                |
| Connection Statistics Page | Session Statistics            |
| Log Page                   | Runtime Logs                  |
| Diagnostics Page           | Diagnostics                   |
| Start Button               | Start Network Extension       |
| Stop Button                | Stop Network Extension        |
| Test Button                | Connectivity Check            |
| Core Status                | Core Status                   |
| Dynamic Library Status     | Adapter Status                |
| Configuration Item         | Local Config / Runtime Config |
| Remote Configuration       | Config Source                 |
| Node-like Object           | Endpoint                      |
| Rule-like Object           | Routing Policy                |
| Proxy-like Object          | Network Channel               |

---

## Requirements

* DevEco Studio
* HarmonyOS NEXT SDK
* HarmonyOS NEXT device
* CMake / OHOS Native build environment
* Go 1.23+, only required when building the optional Go adapter
* ohos_golang_go, only required for `GOOS=ohos` experiments
* Docker, optional, for isolated cross-compilation environments

> Network Extension-related capabilities may depend on SDK version, device system version, signing permissions, application type, and system policy.
> If build-time or runtime errors occur, check DevEco Studio, HarmonyOS SDK, device firmware, and application permission configuration first.

---

## Build

### 1. Build the Application with DevEco Studio

```bash
git clone <your-repo-url>
cd HarmonyNetTunnelLab
```

Open the project with DevEco Studio:

```text
File → Open → Select the HarmonyNetTunnelLab project directory
```

Check the following:

* HarmonyOS NEXT SDK is installed;
* The project API version matches the local SDK;
* Developer mode is enabled on the test device;
* Signing configuration is available;
* `module.json5` contains the required Network Extension declarations;
* The Native build environment is available.

Connect the device and run:

```text
Run → Run 'entry'
```

---

### 2. Build the Optional Go Adapter

To validate the Go c-shared component, run:

```bash
OHOS_SDK_HOME=/path/to/ohos-sdk \
GO_TARGET_OS=ohos \
GO_TARGET_ARCH=arm64 \
./tools/build-adapter.sh
```

After a successful build, the shared library should be generated under a path similar to:

```text
entry/libs/arm64-v8a/libnet_adapter.so
```

Verify the shared library:

```bash
./tools/verify-adapter.sh entry/libs/arm64-v8a/libnet_adapter.so
```

---

### 3. Docker Build, Optional

```bash
OHOS_SDK_DIR=/path/to/ohos-sdk \
./tools/docker-build-adapter.sh
```

---

## Initial Validation

### Extension Lifecycle Validation

1. Open the project with DevEco Studio;
2. Connect a HarmonyOS NEXT test device;
3. Install and run the application;
4. Start the network extension from the `Runtime Control` page;
5. Complete the system authorization flow if prompted;
6. Check the in-app logs and confirm that extension lifecycle callbacks are triggered correctly;
7. Stop the network extension and confirm that resources are released properly.

### Native Bridge Validation

1. Open the `Diagnostics` page;
2. Run Native initialization;
3. Check ABI, dynamic library loading, and runtime status diagnostics;
4. Confirm that ArkTS-to-Native calls work as expected.

### Data Path Validation

1. Start test mode;
2. Trigger a small amount of system network activity;
3. Check protocol counters in the statistics panel;
4. Stop test mode and confirm that the statistics thread exits properly.

---

## Local Runtime Configuration Example

This project can use a local test configuration to validate parsing and runtime parameter generation.

Example:

```yaml
runtime:
  mode: diagnostics
  virtualInterface:
    address: 10.0.0.2
    prefixLength: 32

diagnostics:
  enableLifecycleLog: true
  enableNativeBridgeCheck: true
  enablePacketCounter: true
  enableAdapterCheck: true

adapter:
  enabled: false
  libraryName: libnet_adapter.so
  startMode: manual
```

This configuration is only a local validation example. Actual fields should follow the model definitions in the project source code.

For more complete runtime configuration details, maintain documentation in `docs/runtime-config.md`.

---

## License and Third-party Notices

This project is licensed under the [Apache License 2.0](LICENSE).

Third-party project licenses are subject to their upstream repositories. If this project includes third-party source code, patches, dynamic libraries, or build artifacts, make sure to:

* Preserve upstream copyright notices;
* Preserve upstream LICENSE files;
* Document source, version, and usage in `THIRD_PARTY_NOTICES.md`;
* Document modifications and patch locations if applicable;
* Comply with the distribution requirements of the corresponding licenses.

Recommended directory layout:

```text
third_party/
├── mihomo/
│   └── LICENSE
├── ohos_golang_go/
│   └── LICENSE
└── README.md
```

---

## Roadmap

Recommended development phases:

| Phase   | Goal                            | Key Work                                                                    |
| ------- | ------------------------------- | --------------------------------------------------------------------------- |
| Phase 1 | Extension capability validation | Startup, authorization, virtual interface creation, stop flow               |
| Phase 2 | Native Bridge                   | ArkTS / NAPI / C++ invocation chain                                         |
| Phase 3 | Data Path                       | fd injection, read/write loop, lifecycle management                         |
| Phase 4 | Protocol Statistics             | Basic IPv4 / TCP / UDP / DNS parsing and statistics                         |
| Phase 5 | Go Adapter                      | Go c-shared dynamic library build, loading, and ABI invocation              |
| Phase 6 | Policy Engine Research          | Optional rule engine integration, config parsing, routing policy validation |
| Phase 7 | Stability Validation            | Background behavior, error recovery, diagnostics, compatibility testing     |

---

## Contributing

Contributions are welcome in the following areas:

* HarmonyOS NEXT Network Extension compatibility validation
* ArkTS / NAPI / C++ mixed-architecture improvements
* Native-layer stability fixes
* Go c-shared cross-compilation workflow improvements
* Documentation, test cases, and diagnostic tooling
* Compatibility feedback across different HarmonyOS NEXT devices and SDK versions

Before submitting a PR, please make sure that:

* Newly added third-party code includes the corresponding LICENSE and NOTICE files;
* New functionality remains aligned with the research and engineering validation scope;
* Example configurations do not contain personal sensitive information or production credentials;
* Code and documentation use neutral, clear, and engineering-oriented terminology where possible.

---

## FAQ

### Why use ArkTS instead of only using Cangjie?

ArkTS / ArkUI is currently the more mature application-layer development path for HarmonyOS NEXT. It is suitable for UI, Ability lifecycle, state management, and system API calls. Cangjie may be explored later for business logic or lower-level modules, but this project currently prioritizes buildability, runtime validation, and debuggability.

### Why are NAPI and C++ needed?

Network extension handling, virtual interface data paths, dynamic library loading, and protocol parsing are better suited for the Native layer. ArkTS handles UI, state presentation, and lifecycle orchestration, while C++ handles the lower-level data path and adaptation work.

### Can any third-party application use Network Extension capabilities?

Not necessarily. Related capabilities may be limited by SDK version, device system version, signing permissions, application type, and system policy. One goal of this project is to validate the practical capability boundary in real environments.

### Why explore Go c-shared adaptation?

Many network protocol components have mature Go implementations. Integrating Go components into HarmonyOS native applications through `c-shared` helps evaluate reuse paths for the Go ecosystem on HarmonyOS NEXT, including performance, stability, and maintenance cost.

---

## Disclaimer

This project is published as a HarmonyOS NEXT network protocol and Network Extension capability research project.

When using, modifying, or distributing this project, please comply with applicable laws and regulations, network service terms, organizational security policies, and relevant open-source license requirements.

---

<div align="center">

**HarmonyNetTunnelLab** · HarmonyOS NEXT Network Tunnel Research

</div>
