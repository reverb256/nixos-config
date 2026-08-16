#pragma once
#include <string>
#include <cstdint>
#include <nlohmann/json.hpp>

namespace gpu_proxy {

// Escape a string so it can be safely embedded inside a JSON string literal.
// Protocol fields (worker ids, nonces, blobs) are interpolated into raw JSON
// frames in several places; this prevents a field containing `"` or `\` from
// corrupting the frame or injecting extra JSON members.
inline std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    static const char* hex = "0123456789abcdef";
                    out += "\\u00";
                    out += hex[(c >> 4) & 0xf];
                    out += hex[c & 0xf];
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

// Coerce a JSON value to a string (handles string or number payloads).
inline std::string json_as_string(const nlohmann::json& j) {
    if (j.is_string()) return j.get<std::string>();
    if (j.is_number()) return j.dump();
    return "";
}

// Coerce a JSON value to an unsigned 64-bit integer (handles number or
// numeric-string payloads). Returns 0 when the value cannot be parsed.
inline uint64_t json_as_u64(const nlohmann::json& j) {
    if (j.is_number_unsigned()) return j.get<uint64_t>();
    if (j.is_number_integer()) {
        return static_cast<uint64_t>(j.get<int64_t>());
    }
    if (j.is_string()) {
        try {
            return std::stoull(j.get<std::string>());
        } catch (...) {
            return 0;
        }
    }
    return 0;
}

enum class StratumMethod {
    SUBSCRIBE,
    AUTHORIZE,
    SUBMIT,
    NOTIFY,
    SET_DIFFICULTY,
    // Monero Stratum protocol methods
    LOGIN,
    JOB,
    MONERO_SUBMIT,
    UNKNOWN
};

struct StratumRequest {
    int id;
    StratumMethod method;
    nlohmann::json params;

    static StratumRequest parse(const std::string& line);
};

struct StratumResponse {
    int id;
    nlohmann::json result;
    nlohmann::json error;

    std::string to_json() const;
};

struct Job {
    std::string job_id;
    std::string blob;
    std::string target;
    std::string difficulty;
    uint64_t height;
    bool clean_jobs;

    static Job from_notify(const nlohmann::json& params);
};

} // namespace gpu_proxy
