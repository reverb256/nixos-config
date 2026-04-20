{ config, lib, pkgs, ... }:
let
  llama-cpp = /nix/store/d7f6imkyiv8rsd00za8kln0hjij4nns5-llama-cpp-turboquant-1.6.0/bin/llama-server;
  model = "/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUF/Qwen3.5-9B.Q4_K_M.gguf";
  template = "/home/j_kro/.lmstudio/models/qwen3-thinking-template.jinja";
in {
  systemd.services.llama-server-3060ti = {
    description = "llama.cpp server on RTX 3060 Ti";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      CUDA_VISIBLE_DEVICES = "0";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${llama-cpp} --model ${model} --host 0.0.0.0 --port 1236 -ngl 99 -c 32768 -t 4 --fit off --batch-size 32 --ubatch-size 16 --flash-attn on --parallel 1 --cache-type-k iq4_nl --cache-type-v iq4_nl --temp 0.6 --top-k 20 --top-p 0.95 --reasoning-format deepseek --chat-template-file ${template} --jinja --metrics";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
