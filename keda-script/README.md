KEDA demo
=========

Pre-requisites
--------------

* Install [Azure Function Core Tools](https://github.com/Azure/azure-functions-core-tools) version 2.7.1149+
* Install `jq` for JSON parsing/querying
* Recent Kubernetes cluster created with `kubectl` CLI installed - [Steps](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough)
* Helm (v2) - client and Tiller setup in Kubernetes with RBAC role binding configured - [Steps](https://docs.microsoft.com/en-us/azure/aks/kubernetes-helm)
* Demo 2 requires an [Azure Subscription]( https://azure.com/free) for creating a Storage Queue and a Docker Hub account and login.

Create an AKS cluster
---------------------

```sh
RGROUP=kedademo
LOCATION=australiaeast
CLUSTER_NAME=kedademo
AKS_VERSION=1.14.7
AKS_NODE_SIZE=Standard_DS2_v2
#AKS_NODE_SIZE=Standard_D4s_v3
az group create -n ${RGROUP} -l ${LOCATION}
az ad sp create-for-rbac --skip-assignment -n "https://keda-demo-sp" > keda-cluster-sp.json
chmod 0400 keda-cluster-sp.json

APP_ID=$(cat keda-cluster-sp.json | jq -r .appId)
CLIENT_SECRET=$(cat keda-cluster-sp.json | jq -r .password)

az aks create -n ${CLUSTER_NAME} -g ${RGROUP} -k ${AKS_VERSION} --service-principal ${APP_ID} --client-secret ${CLIENT_SECRET} --load-balancer-sku standard --vm-set-type VirtualMachineScaleSets -l ${LOCATION} --node-count 3 --generate-ssh-keys --node-vm-size ${AKS_NODE_SIZE}

sudo az aks install-cli
az aks get-credentials -n ${CLUSTER_NAME} -g ${RGROUP}

kubectl get nodes
```

Install and setup Helm
----------------------

```sh
curl -L https://git.io/get_helm.sh | bash

cat << EOF > helm-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
EOF

kubectl apply -f helm-rbac.yaml

helm init --history-max 200 --service-account tiller --node-selectors "beta.kubernetes.io/os=linux"
```

Install Keda components
-----------------------

```sh
#helm repo add kedacore https://kedacore.azureedge.net/helm
#helm repo update
#helm install kedacore/keda-edge --devel --set logLevel=debug --namespace keda --name keda
# TODO remove after keda issue 83 is solved
git clone https://github.com/kedacore/keda.git
git -C keda checkout 6ee8f18
helm install --name keda --namespace keda ./keda/chart/keda/ -f ./keda/chart/keda/values.yaml
```

Demo Script
-----------

### Demo 1 - RabbitMQ consumer and sender using Go

**This example shows that any code can work with KEDA -- not only Azure Functions.**

Create a namespace for the demo:

```sh
kubectl create ns keda-demo1
```

Clone the sample code:

```sh
git clone https://github.com/kedacore/sample-go-rabbitmq
cd sample-go-rabbitmq
```

Edit the file: `deploy/deploy-consumer.yaml`

* Change `namespace` to `namespace: keda-demo1`
* Change connection string to: `amqp://user:PASSWORD@rabbitmq.keda-demo1.svc.cluster.local:5672`

Edit the file: `deploy/deploy-publisher-job.yaml`

* Change the `command` to `command: ["send",  "amqp://user:PASSWORD@rabbitmq.keda-demo1.svc.cluster.local:5672", "300"]`

Install RabbitMQ using Helm:

```sh
helm install --name rabbitmq --set rabbitmq.username=user,rabbitmq.password=PASSWORD stable/rabbitmq --namespace keda-demo1

# Wait until deployed
kubectl get po -n keda-demo1
```

Deploy the consumer:

```sh
kubectl apply -f deploy/deploy-consumer.yaml -n keda-demo1
kubectl get deploy -n keda-demo1
# No pods active as there currently aren't any queue messages. It is scale to zero.
kubectl describe ScaledObject -n keda-demo1
```

Deploy the publisher to push messages onto the queue:

```sh
# The following job will publish 300 messages to the "hello" queue the deployment is listening to.
kubectl apply -f deploy/deploy-publisher-job.yaml -n keda-demo1

# Validate deployment scales

# In one window
watch kubectl get deploy -n keda-demo1
watch kubectl get po -n keda-demo1

# In another window
watch kubectl get hpa -n keda-demo1
```

### Demo 2 - Azure Function triggering on Azure Storage Queue messages

Create the function app:

```sh
mkdir hello-keda
cd hello-keda
func init . --docker --worker-runtime node --language javascript
func new
# Select 10 (Azure Queue Storage trigger), `QueueTrigger` as function name
``

Create the Azure Storage Queue:

```sh
az group create -n kedademo -l australiaeast
az storage account create --sku Standard_LRS --location australiaeast -g kedademo -n jsqueueitemscbx
CONNECTION_STRING=$(az storage account show-connection-string --name jsqueueitemscbx --query connectionString)
az storage queue create -n jsqueueitemscbxx --connection-string $CONNECTION_STRING
```

Update the function metadata with the storage account info:

**local.settings.json**

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;EndpointSuffix=core.windows.net;AccountName=mystorageaccount;AccountKey=shhhh==="
  }

}
```

**function.json**

```json
{
  "bindings": [
    {
      "name": "myQueueItem",
      "type": "queueTrigger",
      "direction": "in",
      "queueName": "js-queue-items",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
```

Enable the storage queue bundle on the function runtime:

**host.json**

```json
{
    "version": "2.0",
    "extensionBundle": {
        "id": "Microsoft.Azure.Functions.ExtensionBundle",
        "version": "[1.*, 2.0.0)"
    }
}
```

Test the function locally:

* `func start`
* From the Azure portal, go to the storage account and open **Storage Explorer**
* Add a test message to the queue `jsqueueitemscbxx`
* Observe the message is retrieved

Login to Docker hub (or your own private registry):

```sh
docker login
# enter your username and password
```

If using WSL2:

* Use Docker Desktop version 2.1.4.0 or greater
* Enable **WSL 2 Technical Preview** to use Docker from within WSL2

See the Kubernetes manaifest generated by the Azure Function Core Tools:

Deploy function using 1) first time; 2) reuse existing image:

1 - Build and push Docker image for function and deploy the function to KEDA

```sh
#func kubernetes deploy --name hello-keda --registry  <docker-user-id>

# See the generated Kubernetes deployment
func kubernetes deploy --name hello-keda --registry clarenceb --dry-run

# Build and push Docker image, then deploy to KEDA in Kubernetes
func kubernetes deploy --name hello-keda --registry clarenceb --namespace keda-demo2 --polling-interval 30 --cooldown-period 300 --min-replicas 0 --max-replicas 10
```

**Note:** You can use Kubernetes Secrets instead of inline connection strings.

2 - Deploy using pre-existing Docker image for function to KEDA

```sh
# Dry-run
func kubernetes deploy --name  hello-keda --image-name hello-keda --registry clarenceb --namespace keda-demo2 --no-docker --polling-interval 5 --cooldown-period 30 --min-replicas 0 --max-replicas 30 --dry-run

# Deploy
func kubernetes deploy --name  hello-keda --image-name hello-keda --registry clarenceb --namespace keda-demo2 --no-docker --polling-interval 5 --cooldown-period 30 --min-replicas 0 --max-replicas 30
```

Validate there are no pods as the queue is empty:

```sh
kubectl get deploy -n keda-demo2
```

From the portal, Storage Explorer, add a queue message to validate function app scales with KEDA:

```sh
watch kubectl get pods -n keda-demo2
```

See all the objects, including HPA:

```sh
kubectl get all -n keda-demo2
```

Only 1 pod will be created unless more than 5 messages are in the queue waiitng for processing.

### Demo 3 - Azure Function triggering on HTTP with Osiris

You can install [Osiris](https://github.com/deislabs/osiris#installation) manually or via the Azure Functions Core Tools.

If KEDA was installed previously with Helm, remove it:

```sh
cd demo-scripts/
./cleanup.sh
```

Here we install KEDA and Osiris together via the core tools:

```sh
func kubernetes install --namespace keda
# Wait until keda and osiris are deployed
watch kubectl get all -n keda
```

Create a functions project (C# this time):

```sh
mkdir hello-keda-osiris
cd hello-keda-osiris
func init . --docker
func new
# Select 2 (HttpTrigger), `helloosiris` as function name
```

Deploy the function 1) first time, 2) reuse Docker image:

Create namespace:

```sh
kubectl create ns keda-demo3
```

**1) First time**

```sh
func kubernetes deploy --name hello-keda-osiris --registry clarenceb --namespace keda-demo3 --dry-run > func-deploy.yaml
```

**2) Reuse Docker image**

```sh
func kubernetes deploy --name hello-keda-osiris --image-name hello-keda-osiris --registry clarenceb --namespace keda-demo3 --no-docker --dry-run > func-deploy.yaml
```

To control Osiris further, you'll need to adjust the annotations on the Kubernetes objects (deployment, service), as discussed [here](https://github.com/deislabs/osiris#configuration).

Check Kubernetes objects:

```sh
kubectl apply -f func-deploy.yaml -n keda-demo3
kubectl get all -n keda-demo3
```


Cleanup / Reset Demo
--------------------

```sh
# Remove keda-demo1
kubectl delete job rabbitmq-publish -n keda-demo1
kubectl delete ScaledObject rabbitmq-consumer -n keda-demo1
kubectl delete deploy rabbitmq-consumer -n keda-demo1
helm delete rabbitmq --namespace keda-demo1
kubectl delete ns keda-demo1

# Remove keda-demo2
kubectl delete deploy hello-keda -n keda-demo2
kubectl delete ScaledObject hello-keda -n keda-demo2
kubectl delete Secret hello-keda -n keda-demo2

# Optional - Demo2, remove storage account
az storage account delete --name jsqueueitemscbx

# Remove KEDA components (keda-demo1/keda-demo2)
./cleanup.sh

# Remove keda-demo3
kubectl delete -f func-deploy.yaml
kubectl delete ns keda-demo3
func kubernetes remove --namespace keda
```

Resources
---------

* [KEDA on GitHub](https://github.com/kedacore/keda)
* [KEDA Specifications](https://github.com/kedacore/keda/tree/master/spec)
* [Original RabbitMQ consumer and sender code](https://github.com/kedacore/sample-go-rabbitmq)
* [Using Azure Functions with Keda and Osiris](https://github.com/kedacore/keda/wiki/Using-Azure-Functions-with-Keda-and-Osiris)
* [Osiris configuation](https://github.com/deislabs/osiris#configuration)
