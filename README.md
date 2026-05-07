# Indimo Examples

Here are some examples of invariants.

> **Note:** I use `nix` to manage the packages for these examples. See the section [below](#using-nix-shellnix).

## Examples

### Go

- [FindAll](go/findall/README.md) (from proposal)

### Erlang

- [Parametric Rate-based Invariant](erlang/rates/README.md)

#### Other

- Crude AI-translation of [Go **FindAll** example](erlang/findall/README.md)

## Using Nix (`shell.nix`)

If you have `nix` installed on your system, it should be as simple as running:

```shell
nix-shell
```

and it will download the necessary packages for you to be able to run the examples in this repo.

### Using `direnv`

The `.envrc` file is used by `direnv` to automatically run the `nix-shell` command once your terminal enters this directory. 

> **Note:** You see a `direnv` error instructing you need to run `direnv allow` in this directory. Do that and it'll work. You may need to start a fresh terminal or re-enter the directory for it to take effect.
