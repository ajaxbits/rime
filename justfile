# SPDX-FileCopyrightText: 2023 Christina Sørensen
# SPDX-FileContributor: Christina Sørensen
#
# SPDX-License-Identifier: AGPL-3.0-only

name := "rime"

genDemo:
    fish_prompt="> " fish_history="rime_history" vhs < docs/tapes/demo.tape
    librewolf docs/images/demo.gif

cropHeader:
    convert docs/images/Rimed_hexagonal_snow_crystal.TIF.jpg -crop 1024x325+0+380 docs/images/rime.jpg && kitty +icat docs/images/rime.jpg

buildContainer:
    nix build ./#container
    docker load -i ./result

# GitHub Container Registry
ghPushContainer VERSION:
    docker tag rime:latest ghcr.io/cafkafk/rime:{{VERSION}}
    -pass show rime/gh/deployment/persona-access-token | tail -n 1 | docker login ghcr.io -u cafkafk --password-stdin
    docker push ghcr.io/cafkafk/rime:{{VERSION}}

# Digital Ocean Container Registry
doPushContainer VERSION:
    docker tag rime:latest registry.digitalocean.com/rime/rime:{{VERSION}}
    -pass show rime/digitalocean/deployment/personal-access-token | tail -n 1 | docker login registry.digitalocean.com -u "$(pass show rime/digitalocean/deployment/personal-access-token | tail -n 1)" --password-stdin
    docker push registry.digitalocean.com/rime/rime:{{VERSION}}

pushLatestContainers:
    just ghPushContainer latest
    just doPushContainer latest

pushTaggedContainers VERSION:
    just ghPushContainer {{VERSION}}
    just doPushContainer {{VERSION}}

buildAndPushLatestContainers:
    just buildContainer
    just pushLatestContainers

buildAndPushTaggedContainers VERSION:
    git checkout {{VERSION}}
    just buildContainer
    just pushTaggedContainers {{VERSION}}

# Builds and pushes most recently tagged version
buildAndPushRecentContainers:
    #!/usr/bin/env bash
    set -euxo pipefail

    current_commit="$(git rev-parse HEAD)";
    version="v$(convco version)";

    git checkout $version;

    just buildContainer;
    just pushTaggedContainers $version;

    git checkout $current_commit;

#---------------#
#    release    #
#---------------#

new_version := "$(convco version --bump)"

# If you're not cafkafk and she isn't dead, don't run this!
release:
    cargo bump "{{new_version}}"
    git cliff -t "{{new_version}}" > CHANGELOG.md
    cargo check
    nix build -L ./#clippy
    git checkout -b "cafk-release-v{{new_version}}"
    git commit -asm "chore: release {{name}} v{{new_version}}"
    git push
    @echo "waiting 10 seconds for github to catch up..."
    sleep 10
    gh pr create --draft --title "chore: release v{{new_version}}" --body "This PR was auto-generated by our lovely just file" --reviewer cafkafk 
    @echo "Now go review that and come back and run gh-release"

@gh-release:
    git tag -d "v{{new_version}}" || echo "tag not found, creating";
    git tag --sign -a "v{{new_version}}" -m "auto generated by the justfile for {{name}} v$(convco version)"
    just cross
    mkdir -p ./target/"release-notes-$(convco version)"
    git cliff -t "v$(convco version)" --current > ./target/"release-notes-$(convco version)/RELEASE.md"
    -just checksum >> ./target/"release-notes-$(convco version)/RELEASE.md"

    git push origin "v{{new_version}}"
    gh release create "v$(convco version)" --target "$(git rev-parse HEAD)" --title "{{name}} v$(convco version)" -d -F ./target/"release-notes-$(convco version)/RELEASE.md" ./target/"bin-$(convco version)"/*

#----------------#
#    binaries    #
#----------------#

tar BINARY TARGET:
    tar czvf ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}.tar.gz -C ./target/{{TARGET}}/release/ ./{{BINARY}}

zip BINARY TARGET:
    zip -j ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}.zip ./target/{{TARGET}}/release/{{BINARY}}

tar_static BINARY TARGET:
    tar czvf ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}_static.tar.gz -C ./target/{{TARGET}}/release/ ./{{BINARY}}

zip_static BINARY TARGET:
    zip -j ./target/"bin-$(convco version)"/{{BINARY}}_{{TARGET}}_static.zip ./target/{{TARGET}}/release/{{BINARY}}

binary BINARY TARGET:
    rustup target add {{TARGET}}
    cross build --release --target {{TARGET}}
    just tar {{BINARY}} {{TARGET}}
    just zip {{BINARY}} {{TARGET}}

binary_static BINARY TARGET:
    rustup target add {{TARGET}}
    RUSTFLAGS='-C target-feature=+crt-static' cross build --release --target {{TARGET}}
    just tar_static {{BINARY}} {{TARGET}}
    just zip_static {{BINARY}} {{TARGET}}

checksum:
    @echo "# Checksums"
    @echo "## sha256sum"
    @echo '```'
    @sha256sum ./target/"bin-$(convco version)"/*
    @echo '```'
    @echo "## md5sum"
    @echo '```'
    @md5sum ./target/"bin-$(convco version)"/*
    @echo '```'

alias c := cross

# Generate release binaries
# 
# usage: cross
@cross: 
    # Setup Output Directory
    mkdir -p ./target/"bin-$(convco version)"

    # Install Toolchains/Targets
    rustup toolchain install stable

    ## Linux
    ### x86
    -just binary {{name}} x86_64-unknown-linux-gnu
    # just binary_static {{name}} x86_64-unknown-linux-gnu
    -just binary {{name}} x86_64-unknown-linux-musl
    -just binary_static {{name}} x86_64-unknown-linux-musl

    ### aarch
    -just binary {{name}} aarch64-unknown-linux-gnu
    # BUG: just binary_static {{name}} aarch64-unknown-linux-gnu

    ### arm
    -just binary {{name}} arm-unknown-linux-gnueabihf
    # just binary_static {{name}} arm-unknown-linux-gnueabihf

    ## MacOS
    # TODO: just binary {{name}} x86_64-apple-darwin

    ## Windows
    ### x86
    -just binary {{name}}.exe x86_64-pc-windows-gnu
    # just binary_static {{name}}.exe x86_64-pc-windows-gnu
    # TODO: just binary {{name}}.exe x86_64-pc-windows-gnullvm
    # TODO: just binary {{name}}.exe x86_64-pc-windows-msvc

    # Generate Checksums
    # TODO: moved to gh-release just checksum

testString := "The fault, dear Brutus, is not in our flakes, but in our governance, that we aren't moderators."

run_test TARGET:
    #!/usr/bin/env bash
    set -euxo pipefail
    test_dir=`mktemp -d -t "XXXXXXX-rime-itest"`
    nix run {{TARGET}} --refresh 2> $test_dir/nix-run.log 1> $test_dir/nix-run.out
    diff -U3 --color=auto <(cat $test_dir/nix-run.out) <(echo "{{testString}}")
    if grep -q 'warning: error:' $test_dir/nix-run.log; then
        cat $test_dir/nix-run.log;
        rm $test_dir -r
        echo "tests failed >_<"
        exit 1
    fi
    rm $test_dir -r

testStringPre := "The fault, dear pre-release-Brutus, is not in our flakes, but in our governance, that we aren't moderators."

run_test_pre TARGET:
    #!/usr/bin/env bash
    set -euxo pipefail
    test_dir=`mktemp -d -t "XXXXXXX-rime-itest"`
    nix run {{TARGET}} --refresh 2> $test_dir/nix-run.log 1> $test_dir/nix-run.out
    diff -U3 --color=auto <(cat $test_dir/nix-run.out) <(echo "{{testStringPre}}")
    if grep -q 'warning: error:' $test_dir/nix-run.log; then
        cat $test_dir/nix-run.log;
        rm $test_dir -r
        echo "tests failed >_<"
        exit 1
    fi
    rm $test_dir -r


# Integration Testing (requires Nix)
itest:
    # TODO: self hosted gitlab

    # Default Endpoints
    just run_test "http://localhost:3000/v1/codeberg/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/github/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/gitlab/gitlab.com/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/gitlab/gitlab.freedesktop.org/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/forgejo/next.forgejo.org/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/flakehub/cafkafk/hello.tar.gz"

    # Version Endpoints
    just run_test "http://localhost:3000/v1/flakehub/cafkafk/hello/v/v0.0.1.tar.gz"
    just run_test "http://localhost:3000/v1/sourcehut/git.sr.ht/cafkafk/hello/v/v0.0.1.tar.gz"

    # Branch Endpoints
    just run_test_pre "http://localhost:3000/v1/sourcehut/git.sr.ht/cafkafk/hello/b/main.tar.gz"

    # Tags Endpoints
    just run_test     "http://localhost:3000/v1/sourcehut/git.sr.ht/cafkafk/hello/t/v0.0.1.tar.gz"
    just run_test_pre "http://localhost:3000/v1/sourcehut/git.sr.ht/cafkafk/hello/t/main.tar.gz"

    # Autodiscovery
    just run_test "http://localhost:3000/v1/codeberg.org/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/github.com/cafkafk/hello.tar.gz"
    -just run_test "http://localhost:3000/v1/gitlab.com/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/next.forgejo.org/cafkafk/hello.tar.gz"
    just run_test "http://localhost:3000/v1/flakehub.com/cafkafk/hello/v/v0.0.1.tar.gz"

    # Filter pre-releases
    just run_test "http://localhost:3000/v1/codeberg/cafkafk/hello.tar.gz?include_prereleases=false"
    just run_test "http://localhost:3000/v1/github/cafkafk/hello.tar.gz?include_prereleases=false"
    just run_test "http://localhost:3000/v1/gitlab/gitlab.com/cafkafk/hello.tar.gz?include_prereleases=false"
    just run_test "http://localhost:3000/v1/forgejo/next.forgejo.org/cafkafk/hello.tar.gz?include_prereleases=false"

    # Don't filter pre-releases (gitlab doesn't support pre-releases)
    just run_test_pre "http://localhost:3000/v1/codeberg/cafkafk/hello.tar.gz?include_prereleases=true"
    just run_test_pre "http://localhost:3000/v1/github/cafkafk/hello.tar.gz?include_prereleases=true"
    just run_test     "http://localhost:3000/v1/gitlab/gitlab.com/cafkafk/hello.tar.gz?include_prereleases=true"
    just run_test_pre "http://localhost:3000/v1/forgejo/next.forgejo.org/cafkafk/hello.tar.gz?include_prereleases=true"

    # Test branches with questionable amount of slashes
    just run_test "http://localhost:3000/v1/codeberg/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://localhost:3000/v1/github/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://localhost:3000/v1/gitlab/gitlab.com/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://localhost:3000/v1/forgejo/next.forgejo.org/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://localhost:3000/v1/git.madhouse-project.org/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"

    # Test semantic versioning
    just run_test "http://localhost:3000/v1/github/cafkafk/hello/s/*.tar.gz"
    just run_test_pre "http://localhost:3000/v1/github/cafkafk/hello/s/0.0.2-pre.1.tar.gz"
    # ?version=>=0.0.1,<=0.0.2-pre.5
    just run_test_pre "http://localhost:3000/v1/github/cafkafk/hello/s/*.tar.gz?version=%3e%3d0.0.1%2c%3c%3d0.0.2-pre.5"
    just run_test "http://localhost:3000/v1/flakehub/cafkafk/hello/s/*.tar.gz"
    # ?version=>=0.0.1,<=0.0.2-pre.5
    just run_test_pre "http://localhost:3000/v1/flakehub/cafkafk/hello/s/*.tar.gz?version=%3e%3d0.0.1%2c%3c%3d0.0.2-pre.5"

    @echo "tests passsed :3"

# Integration Testing of rime.cx (requires Nix)
itest-live:
    # Default Endpoints
    just run_test "http://rime.cx/v1/codeberg/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/github/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/gitlab/gitlab.com/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/gitlab/gitlab.freedesktop.org/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/forgejo/next.forgejo.org/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/flakehub/cafkafk/hello.tar.gz"

    # Version Endpoints
    just run_test "http://rime.cx/v1/flakehub/cafkafk/hello/v/v0.0.1.tar.gz"
    just run_test "http://rime.cx/v1/sourcehut/git.sr.ht/cafkafk/hello/v/v0.0.1.tar.gz"

    # Branch Endpoints
    just run_test_pre "http://rime.cx/v1/sourcehut/git.sr.ht/cafkafk/hello/b/main.tar.gz"

    # Tags Endpoints
    just run_test     "http://rime.cx/v1/sourcehut/git.sr.ht/cafkafk/hello/t/v0.0.1.tar.gz"
    just run_test_pre "http://rime.cx/v1/sourcehut/git.sr.ht/cafkafk/hello/t/main.tar.gz"

    # Autodiscovery
    just run_test "http://rime.cx/v1/codeberg.org/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/github.com/cafkafk/hello.tar.gz"
    -just run_test "http://rime.cx/v1/gitlab.com/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/next.forgejo.org/cafkafk/hello.tar.gz"
    just run_test "http://rime.cx/v1/flakehub.com/cafkafk/hello/v/v0.0.1.tar.gz"

    # Filter pre-releases
    just run_test "http://rime.cx/v1/codeberg/cafkafk/hello.tar.gz?include_prereleases=false"
    just run_test "http://rime.cx/v1/github/cafkafk/hello.tar.gz?include_prereleases=false"
    just run_test "http://rime.cx/v1/gitlab/gitlab.com/cafkafk/hello.tar.gz?include_prereleases=false"
    just run_test "http://rime.cx/v1/forgejo/next.forgejo.org/cafkafk/hello.tar.gz?include_prereleases=false"

    # Don't filter pre-releases (gitlab doesn't support pre-releases)
    just run_test_pre "http://rime.cx/v1/codeberg/cafkafk/hello.tar.gz?include_prereleases=true"
    just run_test_pre "http://rime.cx/v1/github/cafkafk/hello.tar.gz?include_prereleases=true"
    just run_test     "http://rime.cx/v1/gitlab/gitlab.com/cafkafk/hello.tar.gz?include_prereleases=true"
    just run_test_pre "http://rime.cx/v1/forgejo/next.forgejo.org/cafkafk/hello.tar.gz?include_prereleases=true"

    # Test branches with questionable amount of slashes
    just run_test "http://rime.cx/v1/codeberg/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://rime.cx/v1/github/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://rime.cx/v1/gitlab/gitlab.com/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://rime.cx/v1/forgejo/next.forgejo.org/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"
    just run_test "http://rime.cx/v1/git.madhouse-project.org/cafkafk/hello/b/a-/t/e/s/t/i/n/g/b/r/a/n/c/h-th@t-should-be-/ha/rd/to/d/e/a/l/wi/th.tar.gz"

    # Test semantic versioning
    just run_test "http://rime.cx/v1/github/cafkafk/hello/s/*.tar.gz"
    just run_test_pre "http://rime.cx/v1/github/cafkafk/hello/s/0.0.2-pre.1.tar.gz"
    # ?version=>=0.0.1,<=0.0.2-pre.5
    just run_test_pre "http://rime.cx/v1/github/cafkafk/hello/s/*.tar.gz?version=%3e%3d0.0.1%2c%3c%3d0.0.2-pre.5"
    just run_test "http://rime.cx/v1/flakehub/cafkafk/hello/s/*.tar.gz"
    # ?version=>=0.0.1,<=0.0.2-pre.5
    just run_test_pre "http://rime.cx/v1/flakehub/cafkafk/hello/s/*.tar.gz?version=%3e%3d0.0.1%2c%3c%3d0.0.2-pre.5"

    @echo "tests passsed :3"
