#!/bin/bash
# this script is called to initialize bastion host when it is created
source ./env.sh

# install kubectl
sudo snap install kubectl --classic

# download fabric operation project
git clone https://github.com/yxuco/fabric-operation.git

# mount Azure file
sudo mkdir /mnt/share

sudo mkdir /etc/smbcredentials
cred=/etc/smbcredentials/${STORAGE_ACCT}.cred
echo "username=${STORAGE_ACCT}" | sudo tee ${cred} > /dev/null
echo "password=${STORAGE_KEY}" | sudo tee -a ${cred} > /dev/null
sudo chmod 600 ${cred}
check=$(grep "//${STORAGE_ACCT}.file.core.windows.net/${STORAGE_SHARE} /mnt/share" /etc/fstab)
if [ -z "${check}" ]; then
  echo "skip update of /etc/fstab to avoid mount conflict"
else
  echo "//${STORAGE_ACCT}.file.core.windows.net/${STORAGE_SHARE} /mnt/share cifs nofail,vers=3.0,credentials=${cred},serverino" | sudo tee -a /etc/fstab > /dev/null
fi
sudo mount -a
