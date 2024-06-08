#!/bin/bash
cd /home/anakin
sudo su
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
  advertiseAddress: "192.168.100.44"
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    node-ip: 192.168.100.44,2804:d51:4d5b:ef00:f81c:1dff:fed8:2b19
EOF

    echo "Inicializando Kubernetes com kubeadm..."
    kubeadm init --config=kubeadm-config.yaml

    echo "Configurando kubectl..."
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    echo "Baixando e configurando o Flannel..."
    #curl -OL https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    curl -OL https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/kube-flannel.yml

    #echo "Editando kube-flannel.yml para suporte a IPv6..."
    #sed -i '/"Backend": {/a \ \ \ \ "EnableIPv6": true,\n\ \ \ \ "IPv6Network": "fc00:10:244::/56"' kube-flannel.yml

    echo "Aplicando configuração do Flannel..."
    kubectl apply -f kube-flannel.yml

    echo "Removendo taint do nó mestre..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-

    echo "Configuração do Kubernetes concluída."
}

# Executando funções
configurar_rede
configurar_kubernetes

echo "Script de configuração concluído."


echo "Criando pastas para automação."
mkdir -p /home/$USER/Documentos
mkdir -p /home/$USER/Documentos/Yaml
mkdir -p /home/$USER/Documentos/Server
mkdir -p /home/$USER/Documentos/Server/Volumes
mkdir -p /home/$USER/Documentos/Server/Volumes/Zabbix
mkdir -p /home/$USER/Documentos/Server/Volumes/Zabbix/zabbix-conf
mkdir -p /home/$USER/Documentos/Server/Volumes/Postgres
mkdir -p /home/$USER/Documentos/Server/Volumes/Postgres/postgres-data
mkdir -p /home/$USER/Documentos/Server/Volumes/Homeassistant
mkdir -p /home/$USER/Documentos/Server/Volumes/Homeassistant/Config
mkdir -p /home/$USER/Documentos/Server/Volumes/Homeassistant/localtime
mkdir -p /home/$USER/Documentos/Server/Volumes/Homeassistant/dbus
mkdir -p /home/$USER/Documentos/Server/Volumes/Grafana

# Sair do modo sudo
exit

echo "Criando diretório .kube no diretório home do usuário atual..."
mkdir -p /home/$USER/.kube

echo "Copiando o arquivo de configuração do Kubernetes para o diretório .kube..."
mkdir -p /home/$USER/.kube/config
cp -i /etc/kubernetes/admin.conf /home/$USER/.kube/config

echo "Mudando a propriedade do arquivo de configuração para o usuário atual..."
chown $USER:$USER /home/$USER/.kube/config

# Exportar KUBECONFIG
echo "Exportando KUBECONFIG..."
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "Script finalizado por completo"

echo "export KUBECONFIG"
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "Script finalizado por completo"

