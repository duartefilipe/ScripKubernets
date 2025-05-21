#!/bin/bash
set -e

echo "===== Iniciando configuração Kubernetes ====="

USERNAME=$(whoami)
HOME_DIR="/home/$USERNAME"
IPV4=$(hostname -I | awk '{print $1}')
IPV6=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | head -n 1)

cd "$HOME_DIR"

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

  if timedatectl show -p NTPSynchronized --value | grep -q "yes"; then
    echo "✅ NTP sincronizado com sucesso."
  else
    echo "⚠️ NTP ainda não sincronizado. Continuando mesmo assim..."
  fi

  echo "⬆️ Atualizando pacotes com hora já corrigida..."
  sudo apt update
}

configurar_rede() {
  echo "📡 Configurando rede e kernel..."
  [ -f /etc/sysctl.conf ] || sudo touch /etc/sysctl.conf

  sudo grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
  sudo grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p

  echo "💾 Desativando swap..."
  sudo sed -i '/swap/d' /etc/fstab
  sudo swapoff -a

  echo "⬆️ Atualizando pacotes..."
  sudo apt update
  sudo apt install -y apt-transport-https ca-certificates curl jq gnupg lsb-release
}

instalar_containerd() {
  echo "📦 Instalando containerd..."
  sudo apt install -y containerd
  sudo mkdir -p /etc/containerd
  sudo containerd config default | sudo tee /etc/containerd/config.toml
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
  echo "✅ Limpeza concluída."
}

configurar_kubernetes() {
  echo "📝 Criando kubeadm-config.yaml..."
  cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16,fc00:10:244::/56
  serviceSubnet: 10.96.0.0/16,fc00:10:96::/108
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$IPV4"
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    node-ip: "$IPV4,$IPV6"
EOF

  echo "🚀 Inicializando cluster..."
  if ! sudo kubeadm init --config=kubeadm-config.yaml; then
    echo "❌ Erro ao inicializar o Kubernetes. Abortando."
    exit 1
  fi

  echo "🔧 Configurando kubectl para o usuário atual..."
  mkdir -p "$HOME_DIR/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME_DIR/.kube/config"
  sudo chown "$USERNAME:$USERNAME" "$HOME_DIR/.kube/config"
  chmod 600 "$HOME_DIR/.kube/config"
  export KUBECONFIG="$HOME_DIR/.kube/config"
}

aguardar_cluster() {
  echo "⏳ Aguardando o Kubernetes ficar pronto..."
  for i in {1..30}; do
    if kubectl get nodes &>/dev/null; then
      echo "✅ Cluster pronto!"
      return 0
    fi
    echo "⏳ Tentativa $i: aguardando kube-apiserver..."
    sleep 5
  done

  echo "❌ Timeout: Kubernetes não ficou pronto a tempo."
  exit 1
}


criar_pastas() {
  echo "📁 Criando diretórios de volumes..."
  mkdir -p $HOME_DIR/Documentos/Yaml
  mkdir -p $HOME_DIR/Documentos/Server/Volumes/Zabbix/zabbix-conf
  mkdir -p $HOME_DIR/Documentos/Server/Volumes/Postgres/postgres-data
  mkdir -p $HOME_DIR/Documentos/Server/Volumes/Homeassistant/{Config,localtime,dbus}
  mkdir -p $HOME_DIR/Documentos/Server/Volumes/Grafana
  mkdir -p $HOME_DIR/Documentos/Server/Volumes/Jellyfin/{Config,FilmesSeries}
  sudo chmod -R 777 "$HOME_DIR/Documentos"
}

aplicar_yamls() {
  echo "⬇️ Baixando YAMLs..."
  cd "$HOME_DIR/Documentos/Yaml"
  for file in zabbix-db.yaml zabbix-frontend.yaml zabbix-server.yaml grafana.yaml jellyfin.yaml homeassistant.yaml pihole.yaml; do
    wget -q "https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/Yaml/$file"
  done
  wget -q "https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/kube-flannel.yml"

  echo "✅ Aplicando flannel..."
  kubectl apply -f kube-flannel.yml || true
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

  echo "📦 Aplicando serviços..."
  for yaml in *.yaml; do
    kubectl apply -f "$yaml" --validate=false
  done
}

### 🧭 Execução
ajustar_hora
configurar_rede
instalar_containerd
instalar_kubernetes
limpar_instalacao_anterior
configurar_kubernetes
aguardar_cluster
criar_pastas
aplicar_yamls

echo "✅ Kubernetes instalado e todos os serviços (Zabbix, Grafana, Jellyfin, Home Assistant, Pi-hole) aplicados com sucesso!"
