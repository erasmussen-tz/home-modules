build:
	home-manager build --flake ./tests#everything

update:
	nix flake update

check lint:
	nix flake check

format fmt:
	nix fmt
