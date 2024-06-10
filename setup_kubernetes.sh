#!/bin/bash

# Obtendo o usuário não-root atual
USERNAME=$(whoami)
HOME_DIR="/home/$USERNAME"

# Obtendo o endereço IP da máquina
IPV4=$(hostname -I | awk '{print $1}')
IPV6=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | head -n 1)

cd $HOME_DIR

# Função para verificar e configurar rede
configurar_rede() {
    echo "Verificando informações do sistema..."
    lsb_release -a
    uname -a
    ip -br addr show

    echo "Verificando configuração de rede..."
    cat /etc/netplan/50-cloud-init.yaml

    echo "Aplicando configurações de rede..."
    echo "Descomentando net.ipv4.ip_forward e net.ipv6.conf.all.forwarding em /etc/sysctl.conf..."
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
    sysctl -p

    echo "Desativando swap..."
    sed -i '/swap/d' /etc/fstab
    swapoff -a
    free -m

    echo "Atualizando o sistema..."
    apt update && apt upgrade -y
    apt install -y apt-transport-https ca-certificates curl jq

    echo "Instalando Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Configurando containerd..."
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd

    echo "Instalando Kubernetes..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
    apt update
    apt install -y kubelet kubeadm kubectl

    echo "Puxando imagens do Kubernetes..."
    kubeadm config images pull

    echo "Configuração de rede concluída."
}

# Função para criar e aplicar a configuração do Kubernetes
configurar_kubernetes() {
    echo "Criando arquivo kubeadm-config.yaml..."
    cat <<EOF >kubeadm-config.yaml
---
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
    node-ip: $IPV4,$IPV6
EOF

    echo "Inicializando Kubernetes com kubeadm..."
    kubeadm init --config=kubeadm-config.yaml

    echo "Configurando kubectl..."
    mkdir -p $HOME_DIR/.kube
    cp -i /etc/kubernetes/admin.conf $HOME_DIR/.kube/config
    chown $(id -u):$(id -g) $HOME_DIR/.kube/config
    export KUBECONFIG="$HOME_DIR/.kube/config"


    echo "Baixando e configurando o Flannel..."
    curl -OL https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/kube-flannel.yml

    echo "Aplicando configuração do Flannel..."
    kubectl apply -f kube-flannel.yml

    echo "Removendo taint do nó mestre..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-

    echo "Configuração do Kubernetes concluída."
}

# Função para criar pastas e ajustar permissões
criar_pastas() {
    echo "Criando pastas para automação..."
    mkdir -p $HOME_DIR/Documentos/Yaml
    mkdir -p $HOME_DIR/Documentos/Server/Volumes/Zabbix/zabbix-conf
    mkdir -p $HOME_DIR/Documentos/Server/Volumes/Postgres/postgres-data
    mkdir -p $HOME_DIR/Documentos/Server/Volumes/Homeassistant/{Config,localtime,dbus}
    mkdir -p $HOME_DIR/Documentos/Server/Volumes/Grafana

    echo "Criação de pastas concluída."
}

# Executando funções
configurar_rede
configurar_kubernetes

echo "Script de configuração concluído."

echo "Criando pastas para automação..."
criar_pastas

echo "Script finalizado por completo"
