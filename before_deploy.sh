#!/usr/bin/env bash
# Building and packaging for release

set -ex

build() {
    cargo build --target "$TARGET" --release --verbose
}

metadata() {
    local json
    local key
    local result

    # Parse argument.
    key="$1"
    if [ -z "$key" ]; then
        echo "metadata requires an argument"
        return 1
    fi

    # Extract Cargo.toml as JSON.
    json=$(cargo metadata --no-deps --format-version 1)

    # Try a top-level key.
    result=$(echo "$json" | jq --raw-output --exit-status ".packages[0] | .$key")
    if [ ! $? -eq 0 ]; then
        # Fallback to a metadata key.
        result=$(echo "$json" | jq --raw-output --exit-status ".packages[0].metadata | .$key")
        return $?
    fi

    echo "$result"
}

pack() {
    local tempdir
    local out_dir
    local project_name
    local package_name
    local gcc_prefix

    tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t tmp)
    out_dir=$(pwd)
    project_name=$(metadata name)
    package_name="$project_name-$TRAVIS_TAG-$TARGET"

    if [[ $TARGET == arm-unknown-linux-* ]]; then
        gcc_prefix="arm-linux-gnueabihf-"
    else
        gcc_prefix=""
    fi

    # create a "staging" directory
    mkdir "$tempdir/$package_name"
    mkdir "$tempdir/$package_name/autocomplete"

    # copying the main binary
    cp "target/$TARGET/release/$project_name" "$tempdir/$package_name/"
    "${gcc_prefix}"strip "$tempdir/$package_name/$project_name"

    # manpage, readme and license
    [ -f "doc/$project_name.1" ] && cp "doc/$project_name.1" "$tempdir/$package_name"
    cp README.md "$tempdir/$package_name"
    cp ci/LICENSE-MIT "$tempdir/$package_name"
    cp ci/LICENSE-APACHE "$tempdir/$package_name"
    cp ci/LICENSE-UNLICENSE "$tempdir/$package_name"

    # shell completions
    # these files are generated by the `build.rs` script
    cp target/"$TARGET"/release/build/"$project_name"-*/out/"$project_name".bash "$tempdir/$package_name/autocomplete/${project_name}.bash-completion"
    cp target/"$TARGET"/release/build/"$project_name"-*/out/"$project_name".elvish "$tempdir/$package_name/autocomplete"
    cp target/"$TARGET"/release/build/"$project_name"-*/out/"$project_name".fish "$tempdir/$package_name/autocomplete"
    cp target/"$TARGET"/release/build/"$project_name"-*/out/"$project_name".ps1 "$tempdir/$package_name/autocomplete"
    cp target/"$TARGET"/release/build/"$project_name"-*/out/_"$project_name" "$tempdir/$package_name/autocomplete"

    # archiving
    pushd "$tempdir"
    tar czf "$out_dir/$package_name.tar.gz" "$package_name"/*
    popd
    rm -r "$tempdir"
}

make_deb() {
    local tempdir
    local architecture
    local version
    local dpkgname
    local conflictname
    local homepage
    local maintainers
    local gcc_prefix
    local project_name

    project_name="$(metadata name)"
    homepage="$(metadata repository)"
    maintainers="$(metadata authors)"

    case $TARGET in
        x86_64*)
            architecture=amd64
            gcc_prefix=""
            ;;
        i686*)
            architecture=i386
            gcc_prefix=""
            ;;
        arm*hf)
            architecture=armhf
            gcc_prefix="arm-linux-gnueabihf-"
            ;;
        *)
            echo "make_deb: skipping target '${TARGET}'" >&2
            return 0
            ;;
    esac
    version=${TRAVIS_TAG#v}
    if [[ $TARGET = *musl* ]]; then
      dpkgname=$project_name-musl
      conflictname=$project_name
    else
      dpkgname=$project_name
      conflictname=$project_name-musl
    fi

    tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t tmp)

    # copy the main binary
    install -Dm755 "target/$TARGET/release/$project_name" "$tempdir/usr/bin/$project_name"
    "${gcc_prefix}"strip "$tempdir/usr/bin/$project_name"

    # manpage
    if [ -f "doc/$project_name.1" ]; then
        install -Dm644 "doc/$project_name.1" "$tempdir/usr/share/man/man1/$project_name.1"
        gzip --best "$tempdir/usr/share/man/man1/$project_name.1"
    fi

    # readme and license
    install -Dm644 README.md "$tempdir/usr/share/doc/$project_name/README.md"
    install -Dm644 ci/LICENSE-MIT "$tempdir/usr/share/doc/$project_name/LICENSE-MIT"
    install -Dm644 ci/LICENSE-APACHE "$tempdir/usr/share/doc/$project_name/LICENSE-APACHE"
    install -Dm644 ci/LICENSE-UNLICENSE "$tempdir/usr/share/doc/$project_name/LICENSE-UNLICENSE"
    cat > "$tempdir/usr/share/doc/$project_name/copyright" <<EOF
Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $project_name
Source: $homepage

Files: *
Copyright: $maintainers
License: Apache-2.0, MIT or UNLICENSE

License: Apache-2.0
 On Debian systems, the complete text of the Apache-2.0 can be found in the
 file /usr/share/common-licenses/Apache-2.0.

License: MIT
 $(cat ci/LICENSE-MIT | sed 's/^/ /')

License: UNLICENSE
 $(cat ci/LICENSE-UNLICENSE | sed 's/^/ /')
EOF

    # completions
    install -Dm644 target/$TARGET/release/build/$project_name-*/out/$project_name.bash "$tempdir/usr/share/bash-completion/completions/${project_name}"
    install -Dm644 target/$TARGET/release/build/$project_name-*/out/$project_name.fish "$tempdir/usr/share/fish/completions/$project_name.fish"
    install -Dm644 target/$TARGET/release/build/$project_name-*/out/_$project_name "$tempdir/usr/share/zsh/vendor-completions/_$project_name"

    # Control file
    mkdir "$tempdir/DEBIAN"
    cat > "$tempdir/DEBIAN/control" <<EOF
Package: $dpkgname
Version: $version
Section: utils
Priority: optional
Maintainer: $maintainers
Architecture: $architecture
Provides: $project_name
Depends: $(metadata "depends")
Conflicts: $conflictname
Homepage: $homepage
Description: $(metadata "description")
EOF

    fakeroot dpkg-deb --build "$tempdir" "${dpkgname}_${version}_${architecture}.deb"
}


main() {
    build
    pack
    if [[ $TARGET = *linux* ]]; then
      make_deb
    fi
}

main
