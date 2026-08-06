{
  description = "mvm microVM — Slack webhook bot template";

  inputs = {
    mvm.url = "github:tinylabscom/mvm?dir=nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { mvm, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system}.default = mvm.lib.${system}.mkGuest {
        name = "slack-vm";

        packages = [ pkgs.curl ];

        services.app = {
          command = "${pkgs.curl}/bin/curl --version";
          env = {
            SLACK_WEBHOOK_URL = "";
          };
        };
      };
    };
}
