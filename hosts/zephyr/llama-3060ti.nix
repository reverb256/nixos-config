{ config, lib, pkgs, inputs, ... }:
let
  llama-cpp = inputs.llama-turboquant.packages.x86_64-linux.llama-cpp-turboquant;
  modelDir = "/home/j_kro/.lmstudio/models";
  startScript = pkgs.writeShellScriptBin "llama-3060ti" ''
    exec env -i \
      CUDA_VISIBLE_DEVICES=1 \
      LD_LIBRARY_PATH=${llama-cpp}/lib:/run/opengl-driver/lib \
      PATH=/run/current-system/sw/bin \
      HOME=/home/j_kro \
      ${llama-cpp}/bin/llama-server \
      --model ${modelDir}/Abiray/supergemma4-e4b-abliterated-GGUF/supergemma4-Q5_K_M.gguf \
      --host 0.0.0.0 --port 1236 -ngl 99 -c 32768 -t 4 --fit off \
      --batch-size 512 --ubatch-size 128 --flash-attn on --parallel 1 \
      --cache-type-k iq4_nl --cache-type-v iq4_nl \
      --temp 0.6 --top-k 20 --top-p 0.95 \
      --metrics
  '';
in {
  systemd.services.llama-server-3060ti = {
    description = "llama.cpp server on RTX 3060 Ti (Supergemma4 E4B)";
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
