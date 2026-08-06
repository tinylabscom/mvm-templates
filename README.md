# mvm-templates

Remote template registry for [`mvmctl`](https://github.com/tinylabscom/mvm).

This repository holds richer, community-oriented microVM templates that are
fetched on demand by `mvmctl`'s template registry. A small core catalog
(`minimal`, `http`, `postgres`, `worker`, `python`) continues to ship inside
`mvmctl` itself so basic scaffolding works offline.

## Layout

```
index.json                 # registry manifest
templates/
  <name>/
    template.toml          # metadata: name, description, sizing, tags
    flake.nix              # guest definition using mvm.lib.<system>.mkGuest
```

## Adding a template

1. Create `templates/<name>/template.toml`:

```toml
name = "<name>"
description = "..."
default_vcpus = 1
default_memory_mib = 256
tags = ["..."]
```

2. Create `templates/<name>/flake.nix` using `mvm.lib.<system>.mkGuest`.
3. Add an entry to `index.json` with the matching `path` and an
   `mvm_version` constraint such as `">=0.18.0"`.
4. Open a PR.

## Local testing

Point `mvmctl` at this directory with a `file://` URL:

```bash
export MVM_TEMPLATE_REGISTRY="file:///path/to/mvm-templates"
mvmctl template list
mvmctl template info <name>
mvmctl generate template <name> ./my-project
```
