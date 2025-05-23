#!/bin/bash
set -e

LOG_FILE="$HOME/k8s-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== Iniciando configuração Kubernetes ====="

USERNAME=$(whoami)
HOME_DIR="/home/$USERNAME"
IPV4=$(hostname -I | awk '{print $1}')

cd "$HOME_DIR"

# Detecta a versão do Ubuntu
UBUNTU_VERSION=$(lsb_release -rs | cut -d. -f1)
echo "🧭 Detectando versão do Ubuntu... Encontrada: $(lsb_release -rs)"
if [[ "$UBUNTU_VERSION" -eq 24 ]]; then
  echo "📌 Ubuntu 24.04 detectado."
elif [[ "$UBUNTU_VERSION" -eq 25 ]]; then
  echo "📌 Ubuntu 25.04 detectado."
else
  echo "⚠️ Versão do Ubuntu não testada. Continuando mesmo assim..."
fi

ajustar_hora() {
  echo "🕒 Instalando ntpdate ignorando validade de release..."
  sudo apt-get install -o Acquire::Check-Valid-Until=false -y ntpdate || {
    echo "❌ Falha crítica ao instalar ntpdate. Abortando."
    exit 1
  }

  echo "🕒 Sincronizando relógio com pool.ntp.org..."
  sudo systemctl stop systemd-timesyncd || true
  sudo ntpdate -u pool.ntp.org || echo "⚠️ Falha ao sincronizar com pool.ntp.org"
  sudo systemctl start systemd-timesyncd || true

  echo "⏱️ Habilitando sincronização NTP..."
  sudo timedatectl set-ntp true >/dev/null 2>&1 || sudo dbus-send --system \
    --print-reply --dest=org.freedesktop.timedate1 \
    /org/freedesktop/timedate1 org.freedesktop.timedate1.SetNTP boolean:true

  timedatectl show -p NTPSynchronized --value | grep -q "yes" &&
    echo "✅ NTP sincronizado com sucesso." || echo "⚠️ NTP ainda não sincronizado. Continuando..."

  echo "⬆️ Atualizando pacotes com hora já corrigida..."
  sudo apt update || true
}

configurar_rede() {
  echo "📡 Configurando rede e kernel..."
  sudo grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
  sudo grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p

  echo "💾 Desativando swap..."
  sudo sed -i '/swap/d' /etc/fstab
  sudo swapoff -a

  sudo apt install -y apt-transport-https ca-certificates curl jq gnupg lsb-release
}

instalar_containerd() {
  echo "📦 Instalando containerd..."
  sudo apt install -y containerd
  sudo mkdir -p /etc/containerd
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
}

instalar_kubernetes() {
  echo "☸️ Instalando ferramentas do Kubernetes..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  sudo apt update
  sudo apt install -y kubelet kubeadm kubectl
  sudo kubeadm config images pull
}

limpar_instalacao_anterior() {
  echo "🧹 Limpando instalação anterior (se houver)..."
  sudo kubeadm reset -f || true
  sudo systemctl stop kubelet || true
  sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni /opt/cni
  sudo ip link delete cni0 || true
  sudo ip link delete flannel.1 || true
  sudo systemctl restart containerd
  kubectl delete ns kube-flannel --ignore-not-found || true
  echo "✅ Limpeza concluída."
  echo "♻️ Reiniciando kubelet para garantir que encontre os plugins CNI..."
  sudo systemctl restart kubelet
  echo "♻️ Restart kubelet paconcluido..."

}

instalar_plugins_cni() {
  echo "🔌 Instalando plugins CNI (com loopback)..."
  sudo mkdir -p /opt/cni/bin
  curl -L https://github.com/containernetworking/plugins/releases/download/v1.4.1/cni-plugins-linux-amd64-v1.4.1.tgz \
    | sudo tar -C /opt/cni/bin -xz
  sudo chmod +x /opt/cni/bin/*
  sudo chown root:root /opt/cni/bin/*
  echo "✅ Plugins CNI instalados em /opt/cni/bin"
}

configurar_kubernetes() {
  echo "📝 Criando kubeadm-config.yaml..."
  cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/16
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$IPV4"
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    node-ip: "$IPV4"
EOF

  echo "🚀 Inicializando cluster..."
  sudo kubeadm init --config=kubeadm-config.yaml

  echo "🔧 Configurando kubectl para o usuário atual..."
  mkdir -p "$HOME_DIR/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME_DIR/.kube/config"
  sudo chown "$USERNAME:$USERNAME" "$HOME_DIR/.kube/config"
  chmod 600 "$HOME_DIR/.kube/config"
}

criar_pastas() {
  echo "📁 Criando diretórios de volumes..."
  mkdir -p "$HOME_DIR/Documentos/Yaml"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Zabbix/zabbix-conf"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Postgres/postgres-data"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Homeassistant/Config"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Homeassistant/localtime"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Homeassistant/dbus"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Grafana"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Jellyfin/Config"
  mkdir -p "$HOME_DIR/Documentos/Server/Volumes/Jellyfin/FilmesSeries"
  sudo chmod -R 777 "$HOME_DIR/Documentos"
}

aplicar_yamls() {
  echo "⬇️ Baixando YAMLs..."
  cd "$HOME_DIR/Documentos/Yaml"
  for file in zabbix-db.yaml zabbix-frontend.yaml zabbix-server.yaml grafana.yaml jellyfin.yaml homeassistant.yaml pihole.yaml; do
    wget -q "https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/Yaml/$file"
  done

  echo "🚫 Removendo taints do control-plane..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

  echo "📦 Aplicando serviços..."
  for yaml in *.yaml; do
    kubectl apply -f "$yaml" --validate=false
  done
}

aguardar_cluster() {
  echo "⏳ Aguardando o Kubernetes ficar pronto..."
  for i in {1..30}; do
    if kubectl get nodes --no-headers 2>/dev/null | grep "$HOSTNAME" | grep -q " Ready"; then
      echo "✅ Cluster pronto!"
      return 0
    fi
    echo "⏳ Esperando node se tornar Ready... ($i/30)"
    sleep 5
  done
  echo "⚠️ Node ainda está NotReady. Verifique o status com: kubectl describe node"
  kubectl get pods -A || true
}

# === Execução principal ===
ajustar_hora
configurar_rede
instalar_containerd
instalar_plugins_cni
instalar_kubernetes
limpar_instalacao_anterior
configurar_kubernetes
criar_pastas
kubectl apply -f https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/kube-flannel.yml --validate=false
aguardar_cluster
aplicar_yamls

echo "✅ Kubernetes instalado com sucesso e serviços aplicados."
echo "📜 Logs salvos em: $LOG_FILE"

read -p "Deseja acompanhar os pods em tempo real? (s/n): " RESPOSTA
if [[ "$RESPOSTA" =~ ^[sS]$ ]]; then
  watch kubectl get pods -A
fi
