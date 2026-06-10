#include "vpn_core.h"
#include "mihomo_adapter.h"

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <arpa/inet.h>
#include <fstream>
#include <mutex>
#include <poll.h>
#include <string>
#include <thread>
#include <unistd.h>

namespace harmony_vpn_poc {
namespace {
constexpr int kBufferSize = 32767;
constexpr int kPollTimeoutMs = 250;

int g_tun_fd = -1;
std::atomic<bool> g_started(false);
std::atomic<bool> g_stop_requested(false);
std::atomic<unsigned long long> g_packet_count(0);
std::atomic<unsigned long long> g_byte_count(0);
std::atomic<unsigned long long> g_ipv4_count(0);
std::atomic<unsigned long long> g_tcp_count(0);
std::atomic<unsigned long long> g_udp_count(0);
std::atomic<unsigned long long> g_icmp_count(0);
std::atomic<unsigned long long> g_dns_count(0);
std::atomic<unsigned long long> g_other_count(0);
std::thread g_worker;
std::thread g_mihomo_start_worker;
std::mutex g_state_mutex;
std::string g_config;
std::string g_core_mode = "mihomo";
std::string g_mihomo_config_path;
std::string g_stats_file;
std::string g_last_error;
std::string g_last_packet;
std::string g_stats_cache;
MihomoAdapter g_mihomo_adapter;

void SetLastError(const std::string& message)
{
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_last_error = message;
}

std::string BuildStatsLocked()
{
    return "started=" + std::string(g_started.load() ? "true" : "false") +
        "; tunFd=" + std::to_string(g_tun_fd) +
        "; packets=" + std::to_string(g_packet_count.load()) +
        "; bytes=" + std::to_string(g_byte_count.load()) +
        "; ipv4=" + std::to_string(g_ipv4_count.load()) +
        "; tcp=" + std::to_string(g_tcp_count.load()) +
        "; udp=" + std::to_string(g_udp_count.load()) +
        "; icmp=" + std::to_string(g_icmp_count.load()) +
        "; dns=" + std::to_string(g_dns_count.load()) +
        "; other=" + std::to_string(g_other_count.load()) +
        "; lastPacket=" + g_last_packet +
        "; configBytes=" + std::to_string(g_config.size()) +
        "; coreMode=" + g_core_mode +
        "; mihomoConfigPath=" + g_mihomo_config_path +
        "; " + g_mihomo_adapter.Stats() +
        "; statsFile=" + g_stats_file +
        "; lastError=" + g_last_error;
}

void WriteStatsFile()
{
    std::string path;
    std::string stats;
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        path = g_stats_file;
        stats = BuildStatsLocked();
    }
    if (path.empty()) {
        return;
    }
    std::ofstream output(path, std::ios::out | std::ios::trunc);
    if (!output.is_open()) {
        SetLastError("write stats file failed");
        return;
    }
    output << stats;
}

uint16_t ReadU16(const char* data)
{
    uint16_t value = 0;
    std::memcpy(&value, data, sizeof(value));
    return ntohs(value);
}

std::string FormatIpv4(const char* data)
{
    char output[INET_ADDRSTRLEN] = {0};
    in_addr address {
        .s_addr = 0
    };
    std::memcpy(&address.s_addr, data, sizeof(address.s_addr));
    const char* result = inet_ntop(AF_INET, &address, output, sizeof(output));
    return result == nullptr ? "-" : std::string(result);
}

void SetLastPacket(const std::string& packet)
{
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_last_packet = packet;
}

bool InspectIpv4AtOffset(const char* buffer, ssize_t length, ssize_t offset)
{
    if (length < offset + 20) {
        return false;
    }

    const char* packet = buffer + offset;
    ssize_t packet_length = length - offset;
    uint8_t version = static_cast<uint8_t>((packet[0] >> 4) & 0x0F);
    if (version != 4) {
        return false;
    }

    uint8_t ihl = static_cast<uint8_t>(packet[0] & 0x0F);
    uint8_t header_length = static_cast<uint8_t>(ihl * 4);
    if (ihl < 5 || packet_length < header_length) {
        return false;
    }

    g_ipv4_count.fetch_add(1);
    uint8_t protocol = static_cast<uint8_t>(packet[9]);
    std::string source = FormatIpv4(packet + 12);
    std::string destination = FormatIpv4(packet + 16);
    std::string protocol_name = "OTHER";
    std::string port_info = "";

    if (protocol == 6) {
        g_tcp_count.fetch_add(1);
        protocol_name = "TCP";
        if (packet_length >= header_length + 4) {
            uint16_t source_port = ReadU16(packet + header_length);
            uint16_t destination_port = ReadU16(packet + header_length + 2);
            port_info = ":" + std::to_string(source_port) + " -> :" + std::to_string(destination_port);
            if (source_port == 53 || destination_port == 53) {
                g_dns_count.fetch_add(1);
            }
        }
    } else if (protocol == 17) {
        g_udp_count.fetch_add(1);
        protocol_name = "UDP";
        if (packet_length >= header_length + 4) {
            uint16_t source_port = ReadU16(packet + header_length);
            uint16_t destination_port = ReadU16(packet + header_length + 2);
            port_info = ":" + std::to_string(source_port) + " -> :" + std::to_string(destination_port);
            if (source_port == 53 || destination_port == 53) {
                g_dns_count.fetch_add(1);
            }
        }
    } else if (protocol == 1) {
        g_icmp_count.fetch_add(1);
        protocol_name = "ICMP";
    } else {
        g_other_count.fetch_add(1);
        protocol_name = "P" + std::to_string(protocol);
    }

    SetLastPacket(protocol_name + " " + source + port_info + " -> " + destination + " len=" + std::to_string(packet_length) + " offset=" + std::to_string(offset));
    return true;
}

void InspectIpv4Packet(const char* buffer, ssize_t length)
{
    if (InspectIpv4AtOffset(buffer, length, 0)) {
        return;
    }
    if (InspectIpv4AtOffset(buffer, length, 4)) {
        return;
    }
    g_other_count.fetch_add(1);
}

void PacketLoop()
{
    char buffer[kBufferSize];
    auto last_stats_write = std::chrono::steady_clock::now();
    WriteStatsFile();
    while (!g_stop_requested.load()) {
        int fd = -1;
        {
            std::lock_guard<std::mutex> lock(g_state_mutex);
            fd = g_tun_fd;
        }

        if (fd < 0) {
            SetLastError("tun fd is invalid");
            break;
        }

        pollfd item {
            .fd = fd,
            .events = POLLIN,
            .revents = 0
        };
        int poll_result = poll(&item, 1, kPollTimeoutMs);
        if (poll_result < 0) {
            if (errno == EINTR) {
                continue;
            }
            SetLastError(std::string("poll failed: ") + strerror(errno));
            break;
        }
        if (poll_result == 0) {
            auto now = std::chrono::steady_clock::now();
            if (std::chrono::duration_cast<std::chrono::seconds>(now - last_stats_write).count() >= 1) {
                WriteStatsFile();
                last_stats_write = now;
            }
            continue;
        }
        if ((item.revents & POLLIN) == 0) {
            continue;
        }

        ssize_t read_count = read(fd, buffer, sizeof(buffer));
        if (read_count > 0) {
            g_packet_count.fetch_add(1);
            g_byte_count.fetch_add(static_cast<unsigned long long>(read_count));
            InspectIpv4Packet(buffer, read_count);
            auto now = std::chrono::steady_clock::now();
            if (std::chrono::duration_cast<std::chrono::seconds>(now - last_stats_write).count() >= 1) {
                WriteStatsFile();
                last_stats_write = now;
            }
            continue;
        }
        if (read_count == 0) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            continue;
        }
        SetLastError(std::string("read failed: ") + strerror(errno));
        break;
    }
    g_started.store(false);
    WriteStatsFile();
}
} // namespace

int StartCore()
{
    if (g_started.load()) {
        return 1;
    }
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_tun_fd < 0) {
            g_last_error = "startCore failed: tun fd is invalid";
            return -1;
        }
        g_last_error.clear();
    }
    if (g_core_mode == "mihomo") {
        if (g_mihomo_start_worker.joinable()) {
            return 1;
        }
        g_started.store(true);
        WriteStatsFile();
        const std::string config_path = g_mihomo_config_path;
        const int tun_fd = g_tun_fd;
        g_mihomo_start_worker = std::thread([config_path, tun_fd]() {
            int start_result = g_mihomo_adapter.Start(config_path, tun_fd);
            if (start_result == 0 || start_result == 1) {
                SetLastError("");
            } else {
                g_started.store(false);
                SetLastError("mihomo adapter start failed: " + std::to_string(start_result));
            }
            WriteStatsFile();
        });
        g_mihomo_start_worker.detach();
        WriteStatsFile();
        return 0;
    }

    if (g_worker.joinable()) {
        g_worker.join();
    }
    g_stop_requested.store(false);
    g_packet_count.store(0);
    g_byte_count.store(0);
    g_ipv4_count.store(0);
    g_tcp_count.store(0);
    g_udp_count.store(0);
    g_icmp_count.store(0);
    g_dns_count.store(0);
    g_other_count.store(0);
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        g_last_packet.clear();
    }
    g_started.store(true);
    g_worker = std::thread(PacketLoop);
    return 0;
}

int StopCore()
{
    g_stop_requested.store(true);
    if (g_worker.joinable()) {
        g_worker.join();
    }
    int mihomo_stop_result = g_mihomo_adapter.Stop();
    g_started.store(false);
    WriteStatsFile();
    return mihomo_stop_result;
}

int SetTunFd(int fd)
{
    // TODO: Duplicate or take ownership of the TUN fd according to the final core design.
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_tun_fd = fd;
    return g_tun_fd;
}

int SetConfig(const char* config)
{
    // TODO: Parse and apply mihomo-compatible runtime config before starting packet processing.
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_config = config == nullptr ? "" : config;
    g_stats_file.clear();
    g_core_mode = "mihomo";
    g_mihomo_config_path.clear();

    auto read_value = [](const std::string& config_text, const std::string& key) -> std::string {
        size_t key_index = config_text.find(key);
        if (key_index == std::string::npos) {
            return "";
        }
        size_t value_start = key_index + key.size();
        size_t value_end = config_text.find('\n', value_start);
        return config_text.substr(value_start, value_end == std::string::npos ? std::string::npos : value_end - value_start);
    };

    std::string core_mode = read_value(g_config, "coreMode=");
    if (!core_mode.empty()) {
        g_core_mode = core_mode;
    }
    g_mihomo_config_path = read_value(g_config, "mihomoConfigPath=");
    g_stats_file = read_value(g_config, "statsFile=");
    std::string native_library_dir = read_value(g_config, "nativeLibraryDir=");
    if (!native_library_dir.empty()) {
        g_mihomo_adapter.SetNativeLibraryDir(native_library_dir);
    }
    return static_cast<int>(g_config.size());
}

const char* GetStats()
{
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_stats_cache = BuildStatsLocked();
    return g_stats_cache.c_str();
}

} // namespace harmony_vpn_poc
