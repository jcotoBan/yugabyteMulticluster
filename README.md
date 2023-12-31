Running Multicluster-Multiregion Databases with LKE and Yugabyte.

LKE is a linode container’s orchestration solution, which combines linode simple pricing and the ease of use.

Yugabyte is an open-source distributed SQL database designed for high-performance, fault-tolerant, 
and scalable applications. It aims to provide a unified database platform that combines the benefits 
of traditional relational databases with the scale and flexibility of NoSQL databases.

![](images/yugabytedb-lke.png)

In this setup, we will show how you can run a distributed database on Linodes platform that will provide:

→ Scalability
→ High Availability
→ Fault Tolerance
→ Data Locality and Performance
→ Elasticity
→ Flexibility in Data Models
→ Resilience and Disaster Recovery
→ Simplified Operations

Requirements: 

Terraform
Linode account access with pat token enabled to create LKE clusters and Linodes.

1-First pull this repo:

```bash
git pull test
```

2-Then go inside folder managementInstance→instanceworkdir

In this step we will create a vm with minimum specs in order to manage the cluster and the yugabyte setup.

Make sure you edit terraform.tfvars.template to terraform.tfvars and add both a pat token and a root pass for the instance.

Also, there is a folder managementInstance/ssh-keys. Make sure you create a pair of ssh keys named as lab_ssh_key and lab_ssh_key.pub, they will be required to access your management box.

Run command 

```bash
terraform init –-auto-apply
```

This will create the management instance, and in turn, from that instance the cluster creation will be triggered.

This setup created a cluster in the USA, another in Europe and one in Asia.

To manage the clusters with kubectl from that machine, the contexts will be renamed as us-west, eu-west and ap-north.

One last thing the script does is to install istio.


3-Once the terraform script has finished successfully, logging through ssh using your keys to that instance. Verify all three clusters were created correctly.

Use k8s_admin user, since root login is disabled, then switch to root and make sure you are on root’s home dir.

![](images/ssh-admin.jpg)
![](images/ssh-root.jpg)


Istio Setup

4-Make sure you have build libraries

```bash
apt-get install build-essential -y
```
cd to your istio folder, it should be something like istio-1.x.x, 

![](images/istio-folder.jpg)

and run the following bash segment:

```bash
{
  mkdir -p certs
  pushd certs
  make -f ../tools/certs/Makefile.selfsigned.mk root-ca

  for ctx in us-west eu-west ap-north; do
    echo -e "Creating and applying CA certs for ${ctx} .........\n"
    make -f ../tools/certs/Makefile.selfsigned.mk ${ctx}-cacerts || break
    kubectl create namespace istio-system --context ${ctx} || break
    kubectl create secret generic cacerts -n istio-system \
      --from-file=${ctx}/ca-cert.pem \
      --from-file=${ctx}/ca-key.pem \
      --from-file=${ctx}/root-cert.pem \
      --from-file=${ctx}/cert-chain.pem \
      --context=${ctx} || break
    echo -e "-------------\n"
  done

  popd
}
```

This will create required certificates for each of the istio instances on each cluster and create the namespaces required as well. Notice they are self-signed, but you can bring your own certificates.

5- Create the service mesh setup by using istio components. The service mesh is basically the network fabric that will allow inter cluster communication.

Run export PATH=$PWD/bin:$PATH, inside istio folder, and then:

```bash
{
  mkdir multi-cluster
  for ctx in us-west eu-west ap-north; do

    echo -e "Set the default network for ${ctx}-cluster .........\n"
    kubectl --context ${ctx} get namespace istio-system && \
      kubectl --context="${ctx}" label namespace istio-system topology.istio.io/network=${ctx}-network
    echo -e "-------------\n"
 
    echo -e "Configure ${ctx}-cluster as a primary .........\n"
    cat <<EOF > multi-cluster/${ctx}-cluster.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_DNS_AUTO_ALLOCATE: "true"
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: ${ctx}-cluster
      network: ${ctx}-network
EOF
istioctl install --context ${ctx} -y -f multi-cluster/${ctx}-cluster.yaml
    echo -e "-------------\n"
 
    echo -e "Install the east-west gateway in ${ctx}-cluster .........\n"
    ./samples/multicluster/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster ${ctx}-cluster --network ${ctx}-network | \
    istioctl --context="${ctx}" install -y -f -
    echo -e "-------------\n"
 
    echo -e "Expose services in ${ctx}-cluster .........\n"
    kubectl --context ${ctx} apply -n istio-system -f \
    samples/multicluster/expose-services.yaml
    echo -e "-------------\n"
 
  done
}
```

![](images/service-mesh.jpg)

6-Create cross cluster secrets required for the setup:

```bash
{
  for r1 in us-west eu-west ap-north; do
    for r2 in us-west eu-west ap-north; do
      if [[ "${r1}" == "${r2}" ]]; then continue; fi
      echo -e "Create remote secret of ${r1} in ${r2} .........\n"
      istioctl x create-remote-secret \
    --context ${r1} \
    --name ${r1}-cluster \
    --namespace istio-system | \
    kubectl apply -f - --context ${r2}
      echo -e "-------------\n"
    done
  done
}
```

7-Verify everything is running by running the following bash code segment:

```bash
{
  for ctx in us-west eu-west ap-north; do
    echo -e "Pods in istio-system from ${ctx} .........\n"
    kubectl get pods --namespace istio-system --context ${ctx} -o wide
    echo -e "-------------\n"
  done
}
```

![](images/pods-istio.jpg)

All istio pods should show up. Some node balancers are created as well:

![](images/nodebalancers.jpg)

Yugabyte setup

8-Create the required namespace (ybdb) on each of the cluster, with istio sidecar enabled:

```bash
{
  for ctx in us-west eu-west ap-north; do
    echo -e "Create ybdb namespace in ${ctx} .........\n"
    kubectl create namespace ybdb --context=${ctx}
    # Enable the automatic istio-proxy sidecar injection
    kubectl label namespace ybdb istio-injection=enabled --context=${ctx}
    echo -e "-------------\n"
  done
}
```

9-Download the required helm chart:

```bash
git clone https://github.com/yugabyte/charts.git
```

10- Then, install the helm charts with each of the values provided on yugabyte folder, 

```bash
helm install us-west charts/stable/yugabyte/ --namespace ybdb --values ~/yugabyte/us_west-values.yaml --kube-context us-west
helm install eu-west charts/stable/yugabyte/ --namespace ybdb --values ~/yugabyte/eu_west-values.yaml --kube-context eu-west
helm install ap-north charts/stable/yugabyte/ --namespace ybdb --values ~/yugabyte/ap_north-values.yaml --kube-context ap-north
```

11-Verify that yugabyte is running:

```bash
{
  for ctx in us-west eu-west ap-north; do
    echo -e "Pods in ybdb from ${ctx} .........\n"
    kubectl get pods --namespace ybdb --context ${ctx}
    echo -e "-------------\n"
  done
}
```

![](images/pods-yugabyte.jpg)

Nodebalancers pointing to port 7000 should be created for each region for the yugabyte db.

12-You need to specify the db cluster distribution, and replication factor of yugabyte db, for that you will need to execute some commands on the yugabyte containers:

```bash
$ kubectl exec -it us-west-yugabyte-yb-master-0 \
  -n ybdb -c yb-master --context us-west -- bash
```

![](images/yuga-exec.jpg)

Then, inside the container, set the placement factor:

```bash
yb-admin --master_addresses us-west-yugabyte-yb-master-0.ybdb.svc.cluster.local,eu-west-yugabyte-yb-master-0.ybdb.svc.cluster.local,ap-north-yugabyte-yb-master-0.ybdb.svc.cluster.local \
  modify_placement_info  \
  linode.us-west,linode.eu-west,linode.ap-north 3
```

![](images/yuga-command.jpg)

And finally, verify the placement info was set correctly. 

```bash
yb-admin --master_addresses us-west-yugabyte-yb-master-0.ybdb.svc.cluster.local,eu-west-yugabyte-yb-master-0.ybdb.svc.cluster.local,ap-north-yugabyte-yb-master-0.ybdb.svc.cluster.local \
  get_universe_config
```

![](images/placement-info.jpg)

If you go to the yugabyte UI, which is one the regions node balancers ips on port 7000, you will see this setup:

![](images/yuga-ui.jpg)

Now you have a database that is resilient and fault tolerant on any region, which means, if you lose one of the regions, the data will still be available.

Yugabyte offers other architecture configurations you can explore: https://docs.yugabyte.com/preview/explore/
