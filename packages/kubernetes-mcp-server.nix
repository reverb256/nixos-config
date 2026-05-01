{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:
buildGoModule rec {
  pname = "kubernetes-mcp-server";
  version = "0.0.51";

  src = fetchFromGitHub {
    owner = "containers";
    repo = "kubernetes-mcp-server";
    rev = "v${version}";
    hash = "sha256-b/KCD0SR7X6FyaG5sLiXopTaSKXM+P5or4nYUIgDSn8=";
  };

  vendorHash = "sha256-icObUYvIv8/a0e/8HwFA3V+KXE27I8VzIYxDGUbX5f4=";

  ldflags = [
    "-s"
    "-w"
  ];

  subPackages = ["cmd/kubernetes-mcp-server"];

  meta = with lib; {
    description = "MCP server for Kubernetes and OpenShift";
    homepage = "https://github.com/containers/kubernetes-mcp-server";
    license = licenses.asl20;
    mainProgram = "kubernetes-mcp-server";
  };
}
