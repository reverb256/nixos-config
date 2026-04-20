{ config, lib, pkgs, inputs, ... }:
let
  llama-cpp = inputs.llama-turboquant.packages.x86_64-linux.llama-cpp;
  modelDir = "/home/j_kro/.lmstudio/models";
in {
  systemd.services.llama-server-3060ti = {
    description = "llama.cpp server on RTX 3060 Ti (Qwen3.5-9B)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      CUDA_VISIBLE_DEVICES = "0";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe llama-cpp} --model ${modelDir}/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF/Qwen3.5-9B.Q4_K_M.gguf --host 0.0.0.0 --port 1236 -ngl 99 -c 32768 -t 4 --fit off --batch-size 32 --ubatch-size 16 --flash-attn on --parallel 1 --cache-type-k iq4_nl --cache-type-v iq4_nl --temp 0.6 --top-k 20 --top-p 0.95 --reasoning-format deepseek --chat-template-file ${modelDir}/qwen3-thinking-template.jinja --jinja --metrics";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
