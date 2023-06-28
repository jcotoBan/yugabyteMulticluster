#!/bin/bash
#General setup for the  user (ssh hardening)
useradd -m k8s_admin -s /bin/bash
echo -e "H57yUL8h\nH57yUL8h" | passwd k8s_admin #random password for k8s_admin wont be required since login will be through key and user will be able to sudo without password
mkdir /home/k8s_admin/.ssh
cp /root/.ssh/authorized_keys /home/k8s_admin/.ssh/authorized_keys
chmod 600 /home/k8s_admin/.ssh/authorized_keys
chmod 700 /home/k8s_admin/.ssh
chown -R k8s_admin:k8s_admin /home/k8s_admin/.ssh
echo $'#k8s_admin entry\nk8s_admin ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd


#jq install
apt install jq -y

#make
apt-get install build-essential -y

#Git Install
apt-get update
apt-get install git -y

#Install terraform
apt-get update &&  apt-get install -y gnupg software-properties-common
apt-get install wget -y
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor |  tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |  tee /etc/apt/sources.list.d/hashicorp.list
apt update && apt-get install terraform

#Install kubectl 
apt-get update && apt-get install -y ca-certificates curl
curl -sS https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update && apt-get install -y kubectl

#install kubectx
sudo apt-get -y install kubectx

#install helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update -y
apt-get install helm -y

#Terraform Setup
terraform -chdir=LKE/clusters/clustersworkdir init
terraform -chdir=LKE/clusters/clustersworkdir plan
terraform -chdir=LKE/clusters/clustersworkdir apply -auto-approve

 
#Kubernetes clusters setup
echo 'export KUBE_VAR="$(terraform output -state=./LKE/clusters/clustersworkdir/terraform.tfstate kubeconfig_us)"' >> .bashrc && source .bashrc && echo $KUBE_VAR | base64 -di > kubeconfig_us.yaml
echo 'export KUBE_VAR="$(terraform output -state=./LKE/clusters/clustersworkdir/terraform.tfstate kubeconfig_eu)"' >> .bashrc && source .bashrc && echo $KUBE_VAR | base64 -di > kubeconfig_eu.yaml
echo 'export KUBE_VAR="$(terraform output -state=./LKE/clusters/clustersworkdir/terraform.tfstate kubeconfig_ap)"' >> .bashrc && source .bashrc && echo $KUBE_VAR | base64 -di > kubeconfig_ap.yaml
echo 'alias k=kubectl' >> .bashrc
echo 'export KUBECONFIG=~/kubeconfig_us.yaml:~/kubeconfig_eu.yaml:~/kubeconfig_ap.yaml' >> .bashrc
source .bashrc

chmod 600 kubeconfig_*

kubectl config rename-context $(kubectl config current-context --kubeconfig=kubeconfig_us.yaml) us-west
kubectl config rename-context $(kubectl config current-context --kubeconfig=kubeconfig_eu.yaml) eu-west
kubectl config rename-context $(kubectl config current-context --kubeconfig=kubeconfig_ap.yaml) ap-north

#Istio setup

curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
cd ..
istioctl install --set profile=default -y







