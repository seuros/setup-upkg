# setup-upkg

GitHub Action to install [upkg](https://github.com/seuros/upkg), the universal package manager.

Works on GitHub Actions and Gitea Actions.

## Usage

```yaml
steps:
  - uses: seuros/setup-upkg@master

  - run: upkg install imagemagick
```

### Pin the upkg version

```yaml
- uses: seuros/setup-upkg@master
  with:
    version: '0.15.0'
```

### In a VM (FreeBSD with vmactions)

A VM the job starts runs no actions, only commands. Install upkg on the
host to resolve the version, then run the same `setup.sh` inside the VM,
pinned to it: a pinned install only downloads release assets, so FreeBSD's
`fetch` needs no token. Outside a runner, upkg is linked into
`/usr/local/bin`.

```yaml
steps:
  - uses: actions/checkout@v6
  - uses: seuros/setup-upkg@master
    id: upkg
    with:
      update: 'false'
  - uses: actions/checkout@v6
    with:
      repository: seuros/setup-upkg
      path: .setup-upkg
  - uses: vmactions/freebsd-vm@v1
    env:
      INPUT_VERSION: ${{ steps.upkg.outputs.version }}
    with:
      envs: INPUT_VERSION
      run: |
        sh .setup-upkg/setup.sh
        upkg install ruby40
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | Version to install (e.g. `0.15.0`) | `latest` |
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
| FreeBSD (runner or VM) | x64 |
| Windows | x64 |

Also runs inside job containers (`container:`), including Alpine: the
installer is POSIX `sh`, downloads with curl or wget, and runs package
manager commands as root directly when there is no sudo. The static musl
build is used on musl systems, and on glibc systems too old for the glibc
build. GitHub runs JavaScript actions such as `actions/checkout` in Alpine
containers on x64 runners only.
