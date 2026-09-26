#!/usr/bin/env bash
# รันบน VPS โดยตรง (paste ทั้งไฟล์นี้ในเทอร์มินัล SSH) — ลง Docker Engine + Compose plugin
# อ้างอิงตามวิธีติดตั้งทางการของ Docker สำหรับ Ubuntu
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ให้ user ubuntu รัน docker โดยไม่ต้อง sudo ทุกครั้ง (ต้อง logout/login ใหม่ถึงจะมีผล)
sudo usermod -aG docker ubuntu

docker --version
docker compose version
