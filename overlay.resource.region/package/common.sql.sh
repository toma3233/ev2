#!/bin/bash
set -ex

if [ ${CLOUDENV} == "ex" ] || [ ${CLOUDENV} == "rx" ];
then
  exit 0
fi

function apt_install {
  echo "Install $@"
  sudo DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y apt-get -qq --no-install-recommends install $@ > /dev/null
}

export UBUNTU_VERSION="$(lsb_release -rs)"
echo "UBUNTU VERSION IS ${UBUNTU_VERSION}"
# hack because sqlcmd isn't in the 18.04 repo but it is just a go binary so it should work the same
# //TODO: remove once 18.04 agents are removed
if [ "${UBUNTU_VERSION}" = "18.04" ];
then
  export UBUNTU_VERSION="20.04"
fi

if [ $(dpkg-query -W -f='${Status}' sqlcmd 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  sudo bash -c "curl https://packages.microsoft.com/config/ubuntu/"${UBUNTU_VERSION}"/prod.list > /etc/apt/sources.list.d/mssql-release.list"
  sudo apt-get update -y
  apt_install unixodbc unixodbc-dev
  apt_install sqlcmd gettext msodbcsql17
fi
