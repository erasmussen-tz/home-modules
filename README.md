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
{ pkgs, ... }:
{
  tz.javascript.extraPackages = [ pkgs.ripgrep ];
}
```

`pkgs` is the package set, and it arrives through the `{ pkgs, ... }:` line, so a block that names a package needs that line at the top.

Search [search.nixos.org/packages](https://search.nixos.org/packages) for a tool's name.
A name that does not exist fails the build with `attribute 'ripgrepp' missing` rather than installing nothing.

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

## Working on the modules

```sh
make fmt    # format
make check  # build a configuration with every module turned on
```

`make check` is the one that matters.
It builds a real Home Manager configuration with `tz.enable = true`, so a module that fails to evaluate fails here rather than on someone's laptop.
CI runs the same command.

### The shape of a module

Every file under `modules/` looks like this:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.tz.javascript;
in
{
  options.tz.javascript = {
    # what can be set
  };

  config = lib.mkIf cfg.enable {
    # what happens when it is
  };
}
```

The first line takes what the module needs: `config` is every setting in the final configuration, `lib` is the standard library, `pkgs` is the package set.
`let ... in` names things for use below, the way a block of `const` declarations would.
`cfg` is always shorthand for this module's own settings.

### The whole vocabulary

This table is every library function and operator used anywhere under `modules/`.
There is no `with`, no `inherit`, no `builtins.` and no `rec` in this repo, and keeping it that way is deliberate.
To check after a change:

```sh
grep -rohE '\blib\.[a-zA-Z.]+|\bbuiltins\.[a-zA-Z]+|\binherit\b|\bwith [a-zA-Z.]+;|\brec \{|\+\+' modules/ | sort -u
```

| Spelling | Means |
| --- | --- |
| `lib.mkOption { type = ...; default = ...; }` | Declare a setting. `type` is checked, so a typo fails the build with the option's name in the message. |
| `lib.mkEnableOption "..."` | Shorthand for an on/off setting that starts off. |
| `lib.mkIf condition { ... }` | Apply this block only when the condition holds. Wraps the whole `config` half of a module. |
| `lib.mkDefault value` | A value any consumer can override without a fight. Use it for anything you are guessing at on their behalf. |
| `lib.optionalAttrs condition { ... }` | The block, or `{ }` when the condition is false. |
| `lib.optionalString condition "..."` | The string, or `""`. |
| `lib.optional condition value` | A one-item list, or `[ ]`. Note the missing `s`; `lib.optionals` takes a list instead. |
| `lib.types.str`, `.bool`, `.int`, `.path`, `.package` | Setting types. `lib.types.listOf X` is a list of them, `lib.types.nullOr X` allows null. |
| `lib.literalExpression "..."` | Shows that text as the default or example in the generated docs, instead of the evaluated value. Documentation only. |
| `lib.hasPrefix`, `lib.removePrefix` | Ordinary string helpers, same as any language's. |
| `a ++ b` | Join two lists. |
| `a // b` | Merge two sets, `b` winning. Shallow, so `{ x.y = 1; } // { x.z = 2; }` loses `x.y`. |
| `''...''` | A multi-line string. `${foo}` inside it inserts the value of `foo`. |

Two of those bite:

**`//` is shallow.**
Merging `{ tz.enable = true; }` with `{ tz.javascript.url = "..."; }` gives you only the second.
Use a list of modules and let the module system merge them, which is deep.

**`${` always belongs to Nix.**
To put a literal `${VAR}` into a generated file, build it by joining pieces, as `envReference` in `modules/javascript/default.nix` does.

### Generating config files

Prefer a generator over writing the file out by hand:

```nix
yaml = pkgs.formats.yaml { };
# ...
home.file.".yarnrc.yml".source = yaml.generate "yarnrc.yml" {
  npmAlwaysAuth = true;
  npmMinimalAgeGate = 11520;
};
```

You write a plain object and get correct quoting and escaping for free.
`pkgs.formats` also has `json`, `toml` and `ini`.
Hand-written text is worth it only for a format none of those covers, like `.npmrc`.

### Adding a module

1. Create `modules/yourthing/default.nix` using the shape above.
2. Add `./yourthing` to the `imports` list in `modules/default.nix`.
3. Give it `enable = lib.mkOption { type = lib.types.bool; default = config.tz.enable; ... }`, so `tz.enable` picks it up.
4. Add a row to the module table above.
5. Run `make check`.

Step 3 is the only one easy to get wrong.
Using `lib.mkEnableOption` there instead would leave the module off under `tz.enable = true`.
