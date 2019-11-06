#!/bin/bash
# this script is called to initialize bastion host when it is created
source ./env.sh

# install kubectl
sudo snap install kubectl --classic

# setup working files
mkdir -p .kube
if [ -f "config.yaml" ]; then
  mv config.yaml .kube/config
fi
mkdir -p .azure
echo "STORAGE_ACCT=${STORAGE_ACCT}" > .azure/store-secret
echo "STORAGE_KEY=${STORAGE_KEY}" >> .azure/store-secret

mnt_point=mnt/share

# download fabric operation project
git clone https://github.com/yxuco/fabric-operation.git
sed -i -e "s|^AZ_MOUNT_POINT=.*|AZ_MOUNT_POINT=${mnt_point}|" ./fabric-operation/config/setup.sh
sed -i -e "s|^AZ_STORAGE_SHARE=.*|AZ_STORAGE_SHARE=${STORAGE_SHARE}|" ./fabric-operation/config/setup.sh

# mount Azure file
sudo mkdir -p /${mnt_point}

sudo mkdir -p /etc/smbcredentials
cred=/etc/smbcredentials/${STORAGE_ACCT}.cred
echo "username=${STORAGE_ACCT}" | sudo tee ${cred} > /dev/null
echo "password=${STORAGE_KEY}" | sudo tee -a ${cred} > /dev/null
sudo chmod 600 ${cred}
check=$(grep "${SMB_PATH} /${mnt_point}" /etc/fstab)
if [ ! -z "${check}" ]; then
  echo "skip update of /etc/fstab to avoid mount conflict"
else
  echo "${SMB_PATH} /${mnt_point} cifs nofail,vers=3.0,credentials=${cred},serverino" | sudo tee -a /etc/fstab > /dev/null
fi
sudo mount -a
