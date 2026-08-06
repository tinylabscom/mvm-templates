{
  description = "mvm microVM — git/SSH clone template";

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
        name = "git-vm";

        packages = [ pkgs.git pkgs.openssh ];

        services.app = {
          command = "${pkgs.git}/bin/git --version";
        };
      };
    };
}
