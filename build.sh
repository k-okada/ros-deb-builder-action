#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause

echo "::group::Prepare build"

set -ex

if debian-distro-info --all | grep -q "$DEB_DISTRO"; then
  DISTRIBUTION=debian
elif ubuntu-distro-info --all | grep -q "$DEB_DISTRO"; then
  DISTRIBUTION=ubuntu
else
  echo "Unknown DEB_DISTRO: $DEB_DISTRO"
  exit 1
fi

case $ROS_DISTRO in
  one)
    # ros one is handled on top of basic debian packages,
    # but has its own ros-one-* package prefix and installs to /opt/ros
    BLOOM=ros
    ROS_DEB="$ROS_DISTRO-"
    ROS_DISTRO=debian
    ;;
  debian)
    ;;
  boxturtle|cturtle|diamondback|electric|fuerte|groovy|hydro|indigo|jade|kinetic|lunar)
    echo "Unsupported ROS 1 version: $ROS_DISTRO"
    exit 1
    ;;
  melodic|noetic)
    BLOOM=ros
    ROS_DEB="$ROS_DISTRO-"
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o $HOME/ros-archive-keyring.gpg
    set -- --extra-repository="deb http://packages.ros.org/ros/ubuntu $DEB_DISTRO main" --extra-repository-key=$HOME/ros-archive-keyring.gpg "$@"
    ;;
  *)
    # assume ROS 2 so we don't have to list versions
    BLOOM=ros
    ROS_DEB="$ROS_DISTRO-"
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o $HOME/ros-archive-keyring.gpg
    set -- --extra-repository="deb http://packages.ros.org/ros2/ubuntu $DEB_DISTRO main" --extra-repository-key=$HOME/ros-archive-keyring.gpg "$@"
    ;;
esac

# make output directory
mkdir -p $HOME/apt_repo

echo "::group::Add unreleased packages to rosdep"

for PKG in $(catkin_topological_order --only-names); do
  printf "%s:\n  %s:\n  - %s\n" "$PKG" "$DISTRIBUTION" "ros-one-$(printf '%s' "$PKG" | tr '_' '-')" >> $HOME/apt_repo/local.yaml
done
echo "yaml file://$HOME/apt_repo/local.yaml $ROS_DISTRO" | sudo tee /etc/ros/rosdep/sources.list.d/1-local.list
echo $ROSDEP_SOURCE | while read source; do
  [ ! -f $GITHUB_WORKSPACE/$source ] || source="file://$GITHUB_WORKSPACE/$source"
  printf "yaml %s $ROS_DISTRO\n" "$source" | sudo tee /etc/ros/rosdep/sources.list.d/2-remote.list
done

rosdep update

echo "::endgroup::"

echo "Run sbuild"

# Don't build tests
export DEB_BUILD_OPTIONS=nocheck

TOTAL="$(catkin_topological_order --only-names | wc -l)"
COUNT=1

EXTRA_DEPENDS=""

cd src

echo "::endgroup::"

# TODO: use colcon list -tp in future
for PKG_PATH in setup_files ros_environment $(catkin_topological_order --only-folders | grep -v 'setup_files\|ros_environment'); do
  echo "::group::Building $COUNT/$TOTAL: $PKG_PATH"
  test -f "$PKG_PATH/CATKIN_IGNORE" && echo "Skipped" && continue
  test -f "$PKG_PATH/COLCON_IGNORE" && echo "Skipped" && continue
  #(
  cd "$PKG_PATH"

  if ! bloom-generate "${BLOOM}debian" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO"; then
    echo "- bloom-generate of $(basename "$PKG_PATH")" >> $HOME/apt_repo/Failed.md
    exit 1
  fi
  # because bloom needs to see the ROS distro as "debian" to resolve rosdep keys the generated files
  # all use the "debian" term, but we want this distribution to be called "one" instead
  sed -i 's@ros-debian-@ros-one-@' $(grep -rl 'ros-debian-' debian/)
  sed -i 's@/opt/ros/debian@/opt/ros/one@g' debian/rules

  # Set the version based on the checked out git state
  # git tags like release/noetic/package/1.2.3 and v1.2.3 are reduced to their pure version number 1.2.3
  description=`( git describe --tag 2>/dev/null || echo 0 ) | sed -E 's@.*/@@; s@^v@@'`
  sed -i "1 s@([^)]*)@($description-$(date +%Y.%m.%d.%H.%M))@" debian/changelog

  # https://github.com/ros-infrastructure/bloom/pull/643
  echo 11 > debian/compat

  # dpkg-source-opts: no need for upstream.tar.gz
  if ! sbuild --chroot-mode=unshare --no-clean-source --no-run-lintian \
    --dpkg-source-opts="-Zgzip -z1 --format=1.0 -sn" --build-dir=$HOME/apt_repo \
    --extra-package=$HOME/apt_repo \
    $EXTRA_DEPENDS \
    "$@"; then
    echo "- [$(catkin_topological_order --only-names)](https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$DEB_DISTRO-one/$(basename $HOME/apt_repo/$(head -n1 debian/changelog | cut -d' ' -f1)_*-*T*.build))" >> $HOME/apt_repo/Failed.md
    exit 1
  fi

  if [ $PKG_PATH = setup_files ]; then
    EXTRA_DEPENDS="$EXTRA_DEPENDS --add-depends=ros-one-setup-files"
  fi
  if [ $PKG_PATH = ros_environment ]; then
    EXTRA_DEPENDS="$EXTRA_DEPENDS --add-depends=ros-one-ros-environment"
  fi
  #)
  cd -
  COUNT=$((COUNT+1))
  ccache -sv
  echo "::endgroup::"
done
