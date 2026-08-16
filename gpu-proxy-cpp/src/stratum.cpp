#include "stratum.hpp"
#include <sstream>
#include <algorithm>

namespace gpu_proxy {

StratumRequest StratumRequest::parse(const std::string& line) {
    StratumRequest req;

    try {
        nlohmann::json j = nlohmann::json::parse(line);

        if (j.contains("id")) j["id"].get_to(req.id);
        else req.id = 0;  // Notifications have no id

        if (j.contains("method")) {
            std::string method_str;
            j["method"].get_to(method_str);

            if (method_str == "mining.subscribe") req.method = StratumMethod::SUBSCRIBE;
            else if (method_str == "mining.authorize") req.method = StratumMethod::AUTHORIZE;
            else if (method_str == "mining.submit") req.method = StratumMethod::SUBMIT;
            else if (method_str == "mining.notify") req.method = StratumMethod::NOTIFY;
            else if (method_str == "mining.set_difficulty") req.method = StratumMethod::SET_DIFFICULTY;
            // Monero Stratum protocol methods
            else if (method_str == "login") req.method = StratumMethod::LOGIN;
            else if (method_str == "job") req.method = StratumMethod::JOB;
            else if (method_str == "submit") req.method = StratumMethod::MONERO_SUBMIT;
            else req.method = StratumMethod::UNKNOWN;
        } else {
            req.method = StratumMethod::UNKNOWN;
        }

        if (j.contains("params")) {
            j["params"].get_to(req.params);
        }

    } catch (const nlohmann::json::exception& e) {
        req.method = StratumMethod::UNKNOWN;
    }

    return req;
}

std::string StratumResponse::to_json() const {
    nlohmann::json j;
    j["id"] = id;
    j["result"] = result;
    j["error"] = error;
    return j.dump();
}

Job Job::from_notify(const nlohmann::json& params) {
    Job job;
    job.height = 0;
    job.clean_jobs = false;

    if (!params.is_array() || params.size() < 4) {
        return job;
    }

    // Pools differ on whether job_id/height are strings or numbers. Coerce
    // both so a type mismatch never throws (which would drop the whole job).
    auto as_str = [](const nlohmann::json& j) -> std::string {
        if (j.is_string()) return j.get<std::string>();
        if (j.is_number()) return j.dump();
        return "";
    };
    auto as_u64 = [](const nlohmann::json& j) -> uint64_t {
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
    };

    job.job_id = as_str(params[0]);
    job.blob = as_str(params[1]);  // Extra nonce2
    job.target = as_str(params[2]);
    job.difficulty = as_str(params[3]);

    if (params.size() >= 5) job.height = as_u64(params[4]);
    if (params.size() >= 6 && params[5].is_boolean()) {
        job.clean_jobs = params[5].get<bool>();
    }

    return job;
}

} // namespace gpu_proxy
