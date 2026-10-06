# setup-upkg

GitHub Action to install [upkg](https://github.com/seuros/upkg), the universal package manager.

Works on GitHub Actions and Gitea Actions.

## Usage

```yaml
steps:
  - uses: seuros/setup-upkg@v0.9.1

  - run: upkg install imagemagick
```

### Pin to a specific version

```yaml
- uses: seuros/setup-upkg@v0.9.1
  with:
    version: '0.9.1'
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | Version to install (e.g. `0.9.1`) | `latest` |
| `token` | GitHub token for API requests | `${{ github.token }}` |
| `update` | Refresh native package metadata after installing upkg | `true` |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | The installed version of upkg |

## Supported platforms

| OS | Architecture |
|----|-------------|
| Linux (glibc and musl) | x64, ARM64 |
| macOS | x64, ARM64 |
| FreeBSD | x64 |
| Windows | x64 |

Also runs inside job containers (`container:`), including Alpine: the
installer is POSIX `sh`, downloads with curl or wget, and runs package
manager commands as root directly when there is no sudo. The static musl
build is used on musl systems, and on glibc systems too old for the glibc
build. GitHub runs JavaScript actions such as `actions/checkout` in Alpine
containers on x64 runners only.
