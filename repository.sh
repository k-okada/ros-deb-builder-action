#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause

set -ex

echo "::group::Setup deb repository"

vcs export src --exact-with-tags > $HOME/apt_repo/sources.repos

cd $HOME/apt_repo
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release

REPOSITORY="$(printf "%s" "$GITHUB_REPOSITORY" | tr / _)"
echo '```bash' > README.md
echo "echo \"deb [trusted=yes] https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$DEB_DISTRO-$ROS_DISTRO/ ./\" | sudo tee /etc/apt/sources.list.d/$REPOSITORY.list" >> README.md
echo "sudo apt update" >> README.md
echo "sudo apt install python3-rosdep2" >> README.md
echo "echo \"yaml https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$DEB_DISTRO-$ROS_DISTRO/local.yaml debian\" | sudo tee /etc/ros/rosdep/sources.list.d/1-$REPOSITORY.list" >> README.md
echo "rosdep update" >> README.md
echo '```' >> README.md

echo "::endgroup::"
