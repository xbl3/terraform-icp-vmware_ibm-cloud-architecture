#!/bin/bash
LOGFILE=/tmp/install-docker.log
exec  &> >(tee -a $LOGFILE)

usage() {
  echo "Usage $0 [-p <nfs/http>] [-d docker_disk]" 1>&2
  exit 1
}

while getopts ":p:d:" arg; do
    case "${arg}" in
      p)
        package_location=${OPTARG}
        ;;
      d)
        docker_disk=${OPTARG}
        ;;
    esac
done

#Find Linux Distro
if grep -q -i ubuntu /etc/*release
  then
    OSLEVEL=ubuntu
  else
    OSLEVEL=other
fi

echo "Operating System is $OSLEVEL"
echo "Package is at: ${package_location}"
echo "Docker block device is ${docker_disk}"

sourcedir=/tmp/icp-docker

# Figure out if we're asked to install at all
if [[ -z ${package_location} ]]
then
  echo "Not required to install ICP provided docker. Exiting"
  exit 0
fi

if docker --version
then
  echo "Docker already installed. Exiting"
fi

mkdir -p ${sourcedir}

# Decide which protocol to use
if [[ "${package_location:0:3}" == "nfs" ]]
then
  # Separate out the filename and path
  nfs_mount=$(dirname ${package_location:4})
  package_file="${sourcedir}/$(basename ${package_location})"
  # Mount
  sudo mount.nfs $nfs_mount $sourcedir
elif [[ "${package_location:0:4}" == "http" ]]
then
  # Figure out what we should name the file
  filename="icp-docker.bin"
  mkdir -p ${sourcedir}
  curl -o ${sourcedir}/${filename} "${package_location#http:}"
  package_file="${sourcedir}/${filename}"
fi

chmod a+x ${package_file}
sudo ${package_file} --install

# Make sure our user is added to the docker group if needed
# Some RHEL based installations may not have docker installed yet.
# Only aattempt to add user to group if docker is installed and the user is not root
if grep -q docker /etc/group
then
  iam=$(whoami)

  if [[ $iam != "root" ]]
  then
    sudo usermod -a -G docker $iam
  fi
fi

# if docker block device is not provided, make sure we use overlay2 storage driver
if [ -z "${docker_disk}" ]; then

  sudo systemctl stop docker

  if [ "${OSLEVEL}" -eq "ubuntu" ]; then
    cat > /tmp/daemon.json <<EOF
{
  "storage-driver": "devicemapper",
  "storage-opts": [
    "dm.directlvm_device=${docker_disk}"
  ]
}
EOF
  else
    # docker installer uses devicemapper already
    cat > /tmp/daemon.json <<EOF
{
  "storage-opts": [
    "dm.directlvm_device=${docker_disk}"
  ]
}
EOF
  fi

  sudo mv /tmp/daemon.json /etc/docker/daemon.json

  sudo systemctl start docker
fi
