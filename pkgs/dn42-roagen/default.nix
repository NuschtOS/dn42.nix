{ pkgs }:

pkgs.rustPlatform.buildRustPackage {
  pname = "dn42-roagen";
  version = "0.2.2";

  src = pkgs.fetchFromGitLab {
    owner = "bauen1";
    repo = "dn42-roagen";
    rev = "2862b6e48865412648fb93e09517edb6320f02b0";
    hash = "sha256-+YrvwL845qkr4v5ad897034rgI8H4rIWi4HnoSKGgFs=";
  };

  patches = [
    ./0001-Update-dependencies.patch
  ];

  cargoLock.lockFile = ./Cargo.lock;

  meta.mainProgram = "dn42-roagen";
}
