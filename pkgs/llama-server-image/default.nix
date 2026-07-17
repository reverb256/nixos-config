{
  pkgs,
  system,
  config,
  ...
}: {
  name = "llama-server";
  tag = "latest";
  config = {
    pkgs,
    config,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      llama-cpp
    ];
    users.users.llama-server = {
      isNormalUser = true;
      group = "llama-server";
    };
    users.groups.llama-server = {};
    systemd.services.llama-server = {
      enable = true;
      description = "llama.cpp LLM inference server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        User = "llama-server";
        Group = "llama-server";
        ExecStart = "${pkgs.llama-cpp}/bin/llama-server \
          --model=/models/Qwen3.5-0.8B.Q8_0.gguf \
          --host=0.0.0.0 \
          --port=8080 \
          --ctx-size=16384 \
          --threads=16 \
          --metrics";
        Environment = "CUDA_VISIBLE_DEVICES=";
        Restart = "on-failure";
      };
    };
  };
}
