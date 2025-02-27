#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause

set -ex

echo "::group::Install action dependencies"

sudo add-apt-repository -y ppa:v-launchpad-jochen-sprickerhof-de/sbuild
echo "$DEB_REPOSITORY" | sudo tee /etc/apt/sources.list.d/1-custom-ros-deb-builder-repositories.list

sudo apt update

echo apt-cacher-ng apt-cacher-ng/tunnelenable boolean true | sudo debconf-set-selections

DEBIAN_FRONTEND=noninteractive sudo apt install -y \
  mmdebstrap \
  distro-info \
  debian-archive-keyring \
  ccache \
  curl \
  vcstool \
  python3-rosdep2 \
  sbuild \
  catkin \
  python3-bloom \
  apt-cacher-ng

if [ "$ACT" = "true" ]; then
  # autostarting services does not work in `act` due to systemd missing in docker
  service apt-cacher-ng start
fi

echo "::endgroup::"

echo "::group::Setup build environment"
mkdir -p ~/.cache/sbuild
mmdebstrap --variant=buildd --include=apt,ccache,ca-certificates \
  --customize-hook='chroot "$1" update-ccache-symlinks' \
  "$DEB_DISTRO" "$HOME/.cache/sbuild/$DEB_DISTRO-amd64.tar" "deb http://127.0.0.1:3142/azure.archive.ubuntu.com/ubuntu $DEB_DISTRO main universe"

ccache --zero-stats --max-size=10.0G

# allow ccache access from sbuild
chmod a+rwX ~
chmod -R a+rwX ~/.cache/ccache

cat << "EOF" > ~/.sbuildrc
$build_environment = { 'CCACHE_DIR' => '/build/ccache' };
$path = '/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games';
$build_path = "/build/package/";
$dsc_dir = "package";
$unshare_bind_mounts = [ { directory => '/home/runner/.cache/ccache', mountpoint => '/build/ccache' } ];
$verbose = 1;
EOF
echo "$SBUILD_CONF" >> ~/.sbuildrc

cat ~/.sbuildrc

echo "::endgroup::"

echo "::group::Checkout workspace from $REPOS_FILE"

mkdir src
vcs import --recursive --input  "$REPOS_FILE" src
echo "::endgroup::"
