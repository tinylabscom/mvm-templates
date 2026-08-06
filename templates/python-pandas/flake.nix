{
  description = "mvm microVM — Python data-science template";

  inputs = {
    mvm.url = "github:tinylabscom/mvm?dir=nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { mvm, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };

      python = pkgs.python3.withPackages (ps: [
        ps.pandas
        ps.numpy
        ps.requests
      ]);

      appSrc = pkgs.stdenv.mkDerivation {
        pname = "python-pandas-app";
        version = "0";
        src = ./app;
        installPhase = "cp -r . $out";
      };

    in {
      packages.${system}.default = mvm.lib.${system}.mkGuest {
        name = "python-pandas-vm";

        packages = [ python appSrc pkgs.curl ];

        services.app = {
          command = "${python}/bin/python3 ${appSrc}/main.py";
          env = {
            PORT = "8080";
            PYTHONUNBUFFERED = "1";
          };
        };

        healthChecks.app = {
          healthCmd = "${pkgs.curl}/bin/curl -sf http://localhost:8080/ >/dev/null";
          healthIntervalSecs = 5;
          healthTimeoutSecs = 3;
        };
      };
    };
}
