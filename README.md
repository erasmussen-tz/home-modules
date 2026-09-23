# home-modules

Home Manager modules for TractorZoom development machines.

Turning one on installs the tools a group of TractorZoom repos expects and writes the configuration files they need, so a checkout builds without any manual setup.

Using these does not require knowing Nix.
Copy the flake below, change the username, run one command.

## Setup

Create `flake.nix` in a directory of your own:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-modules.url = "github:erasmussen-tz/home-modules";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, home-modules, ... }:
    {
      homeConfigurations."yourname" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;

        modules = [
          home-modules.homeModules.tz

          {
            home.username = "yourname";
            home.homeDirectory = "/Users/yourname";
            home.stateVersion = "26.05";

            # Everything below this line is the part you edit.
            tz.enable = true;
            tz.javascript.registry.tokenSopsFile = ./secrets/npm.yaml;
          }
        ];
      };
    };
}
```

Apply it:

```sh
nix run nixpkgs#home-manager -- switch --flake .#yourname
```

Open a new terminal afterwards.
Anything that sets an environment variable, such as the npm token, only reaches shells started after the switch.

### If you already use sops-nix

Add one line to `inputs`, or the build fails with `The option 'sops.secrets' ... is already declared`:

```nix
home-modules = {
  url = "github:erasmussen-tz/home-modules";
  inputs.sops-nix.follows = "sops-nix";
};
```

These modules bring their own copy of sops-nix so that secret decryption works without extra wiring.
Two copies of it declare the same options, which the module system rejects.
`follows` points both at one copy.

## The npm token

Private `@tractorzoom` packages need a read token.
It is held in a sops-encrypted file rather than written into the flake, because anything written into a flake is readable by every account on the machine.

Create the file once:

```sh
nix run nixpkgs#sops -- secrets/npm.yaml
```

Give it a single entry, then save and close:

```yaml
npm_private_read: npm_yourtokenhere
```

Point the module at it with `tz.javascript.registry.tokenSopsFile`, as in the flake above.
`NPM_PRIVATE_READ` is exported in every new shell from then on, which is the variable the checked-in `.npmrc` and `.yarnrc.yml` in each repo already read.

Editing the file later is the same command.

## Everyday changes

Turn everything on:

```nix
tz.enable = true;
```

Turn one piece back off:

```nix
tz.enable = true;
tz.salesforce.enable = false;
```

Add a tool for yourself, on top of what the module installs:

```nix
tz.javascript.extraPackages = with pkgs; [ ripgrep ];
```

That needs `pkgs` in scope, so write the module as a function:

```nix
{ pkgs, ... }:
{
  tz.javascript.extraPackages = with pkgs; [ ripgrep ];
}
```

Search [search.nixos.org/packages](https://search.nixos.org/packages) for a tool's name.
A name that does not exist fails the build with `attribute 'foo' missing` rather than installing nothing.

## Modules

| Option | What it sets up |
| --- | --- |
| `tz.enable` | Every module below at once. Each one's own `enable` defaults to this. |
| `tz.javascript.enable` | biome, commitlint, fnm, lefthook and yarn, plus `~/.npmrc` and `~/.yarnrc.yml` pointed at the private registry. |

Node is deliberately not installed.
Each repo pins a version in `.nvmrc` and `fnm` supplies that one, so a system-wide Node would only shadow the pin.

Every option carries a description.
To read them all, once your own configuration is in place:

```sh
nix run nixpkgs#home-manager -- option --recursive tz
```

## Troubleshooting

**`No key source configured for sops`**

Your age key is missing.
It belongs at `~/.config/sops/age/keys.txt`, and the file you are decrypting has to list that key as a recipient.

**`The option 'sops.secrets' ... is already declared`**

Two copies of sops-nix.
Add the `follows` line from [If you already use sops-nix](#if-you-already-use-sops-nix).

**A private `@tractorzoom` package fails to install with a 401**

The token is not in your shell.
Check with `echo $NPM_PRIVATE_READ`.
An empty result means either the switch has not run since you set `tokenSopsFile`, or this terminal predates it.

**A package installs an older version than you expect**

`npmMinimalAgeGate` holds new releases back for eight days as a supply chain delay.
A repo that needs a newer internal release lists it in its own `npmPreapprovedPackages`.

## Working on this repo

```sh
make fmt    # format
make check  # evaluate everything
```
