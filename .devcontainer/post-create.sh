#!/bin/bash
set -e

echo "Installing system packages..."
sudo apt-get update && sudo apt-get install -y netcat-traditional iputils-ping

echo "Installing Ansible..."
pip install --user ansible ansible-lint

echo "Installing Ansible collections..."
cd /workspaces/pseudo-code-spaces-sakura/ansible
ansible-galaxy collection install -r requirements.yml
cd -

echo "Verifying installations..."
terraform --version
ansible --version
git --version
git lfs --version
node --version
npm --version
docker --version
docker compose version

echo "Setting up Git configuration..."
git config --global core.autocrlf input

echo "Post-create setup completed successfully!"
