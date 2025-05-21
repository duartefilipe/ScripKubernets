# 🚀 ScripKubernets

Automação completa da instalação de um cluster Kubernetes em uma máquina com **Ubuntu Server 25.04**, configurando serviços essenciais para um ambiente de monitoramento e mídia.

---

## 📦 Serviços implantados automaticamente

Após a execução do script, os seguintes serviços são configurados e executados como pods no cluster Kubernetes:

- [x] **Zabbix** – Monitoramento de infraestrutura
- [x] **Grafana** – Visualização de métricas
- [x] **Home Assistant** – Automação residencial
- [x] **Jellyfin** – Servidor de mídia local
- [x] **Pihole** – Servidor DNS

---

## ⚙️ Requisitos

- Ubuntu Server **25.04**
- Acesso root (ou `sudo`)
- Conexão com a internet

---

## 🧪 Funcionalidades do script

- Corrige automaticamente a data/hora com `ntpdate`
- Desativa o `swap`
- Ativa o encaminhamento de pacotes IPv4 e IPv6
- Instala e configura:
  - `containerd`
  - `kubelet`, `kubeadm`, `kubectl`
  - Plugins de rede com **Flannel**
- Cria volumes persistentes para os serviços
- Aplica arquivos YAML dos serviços listados

---

## 🚀 Como executar

```bash
cd /home/$USER && wget -qO- https://raw.githubusercontent.com/duartefilipe/ScripKubernets/main/setup_kubernetes.sh | bash
