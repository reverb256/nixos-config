{ config, lib, pkgs, inputs, ... }:
let
  ctxSize = 262144;
  llama-cpp = inputs.llama-turboquant.packages.x86_64-linux.llama-cpp-turboquant;
  modelDir = "/home/j_kro/.lmstudio/models";

  startScript = pkgs.writeShellScriptBin "llama-3090" ''
    exec env -i \
      CUDA_VISIBLE_DEVICES=0 \
      LD_LIBRARY_PATH=${llama-cpp}/lib:/run/opengl-driver/lib \
      PATH=/run/current-system/sw/bin \
      HOME=/home/j_kro \
      ${llama-cpp}/bin/llama-server \
      --model ${modelDir}/mradermacher/Qwen3.6-35B-A3B-abliterated-i1-GGUF/Qwen3.6-35B-A3B-abliterated.i1-IQ3_M.gguf \
      --host 0.0.0.0 --port 1237 -ngl 99 -c ${toString ctxSize} -t 8 --fit off \
      --batch-size 1024 --ubatch-size 256 --flash-attn on --parallel 1 \
      --cache-type-k iq4_nl --cache-type-v iq4_nl \
      --temp 0.6 --top-k 20 --top-p 0.95 \
      --metrics
  '';
in {
  systemd.services.llama-server-3090 = {
    description = "llama.cpp server on RTX 3090 (Qwen3.6-35B-A3B)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe startScript;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
