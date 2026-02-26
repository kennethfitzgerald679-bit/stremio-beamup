
#!/usr/bin/env bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please use sudo." >&2
	exit 1
fi


set -euo pipefail

apt-get update && apt-get install -y gnupg software-properties-common



echo 'Adding repositories ...'

# Install HashiCorp's GPG key.

wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# Verify the GPG key's fingerprint.

gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint

# The gpg command reports the key fingerprint:

# /usr/share/keyrings/hashicorp-archive-keyring.gpg
# -------------------------------------------------
# pub   rsa4096 XXXX-XX-XX [SC]
# AAAA AAAA AAAA AAAA
# uid         [ unknown] HashiCorp Security (HashiCorp Package Signing) <security+packaging@hashicorp.com>
# sub   rsa4096 XXXX-XX-XX [E]

# Add the official HashiCorp repository to your system.

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list


# Add Ansible PPA
add-apt-repository --yes --update ppa:ansible/ansible



# Update apt to download the package information from the HashiCorp repository.

apt update


# Install Terraform from the new repository.

echo 'Installing dependencies ...'

apt-get install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils mkisofs terraform ansible dnsmasq -y



# Adding current user to libvirt
usermod -a -G libvirt $(whoami)



# Setting up default libvirt storage pool
DEFAULT_POOL_EXISTS=$(virsh pool-list --all | awk '{print $1}' | grep -wq default && echo yes || echo no)
DEFAULT_POOL_TARGET=$(virsh pool-dumpxml default 2>/dev/null | grep '<path>' | sed -E 's/.*<path>(.*)<\/path>.*/\1/')

if [[ "$DEFAULT_POOL_EXISTS" == "yes" && "$DEFAULT_POOL_TARGET" == "/var/lib/libvirt/images" ]]; then
	echo "Default libvirt pool already exists and is configured correctly."
else
	# Remove if exists but misconfigured
	if [[ "$DEFAULT_POOL_EXISTS" == "yes" ]]; then
		echo "Default libvirt pool exists but is misconfigured. Removing..."
		virsh pool-destroy default || true
		virsh pool-undefine default || true
	fi
	echo "Creating default libvirt pool..."
	virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
	virsh pool-build default
	virsh pool-start default
	virsh pool-autostart default
fi


# Set libvirt security_driver to 'none'
echo 'Setting libvirt security_driver to "none" in /etc/libvirt/qemu.conf ...'
sed -i '/^security_driver\s*=\s*\"none\"/d' /etc/libvirt/qemu.conf
sed -i '/^security_driver/d' /etc/libvirt/qemu.conf
echo 'security_driver = "none"' | tee -a /etc/libvirt/qemu.conf
systemctl restart libvirtd

# install ansible dependencies

ansible-galaxy install -r ../ansible/requirements.yml --force
ansible-galaxy collection install -r ../ansible/requirements.yml --force

echo "Local setup complete."
echo "After terraform apply, run ./local-deployment/dns-init.sh"
