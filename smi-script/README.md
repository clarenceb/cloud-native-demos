SMI Demo
========

Demo using [SMI](https://smi-spec.io/) + [Linkerd](https://linkerd.io/2/overview/) to [shift traffic](https://github.com/deislabs/smi-spec/blob/master/traffic-split.md) from one or more services to another (canary) version.

Pre-requsities
--------------

* Recent Kubernetes cluster created with `kubectl` CLI installed - [Steps](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough)
* Helm (v2) - client and Tiller setup in Kubernetes with RBAC role binding configured - [Steps](https://docs.microsoft.com/en-us/azure/aks/kubernetes-helm)
* Linkerd 2.4+ installed - client and server components (control plane) - [Steps](https://linkerd.io/2/tasks/install/)
* Locally cloned `bookinfo` sample app - Steps: `git clone git@github.com:clarenceb/bookinfo.git; cd bookinfo/`

Demo Script
-----------

### Linkerd dashboard

Display the Linkerd dashboard:

```sh
# On WSL2, get the VM eth0 interface IP (as localhost not reoutable from Windows yet)
WSLHOST=`ip route get 1.2.3.4 | head -1 | awk '{print $7}'`

linkerd dashboard --address $WSLHOST &
```

Visit: `http://$WSLHOST:50750` in your browser.

### Bookinfo app

Deploy the initial `bookinfo` sample app, meshed with Linkerd:

```sh
linkerd inject ./platform/kube/bookinfo.yaml | kubectl apply -f -

watch kubectl get pod
kubectl get svc

kubectl port-forward --address $WSLHOST svc/productpage 9080:9080 &
```

View the app: `http://$WSLHOST:9080`

Click 'Test user' to see reviews (`http://$WSLHOST:9080/productpage?u=test`)

Reload the page several times: You should see the reviews cycle through 3 versions of ratings (v1 - no stars, v2 - red stars, v3 - black stars)

### Linkerd traffic telemetry

In Linkerd dashboard, you can vist the `default` namespace to see the connection graph (at top) and list of deployments.

You can see there are 3 versions of the revierw service already deployed:

* `reviews-1`
* `reviews-2`
* `reviews-3`

Click the `productpage-v1` deployment (`http://$WSLHOST:50750/namespaces/default/deployments/productpage-v1`).

Here you can see the call graph with success rates, RPS, etc.  You can also see  **Live Calls** which shows the outbound connections to downstream services.

Try `Tap` on one of the outbound calls.

Currently, there are no **Traffic Splits** defined (http://$WSLHOST:50750/namespaces/default/trafficsplits).

### SMI Traffic Split

Service `reviews` currently routes to all 3 review deployments:

```sh
kubectl describe svc/reviews
# Selector:          app=reviews
```

Each deployment has the `app=reviews` label plus a `version` label:

```sh
kubectl describe deploy reviews-v{1,2,3} | grep -A1 ^Labels
```

Create two new services for SMI traffic split to route to only `reviews-v2` and `reviews-v3`:

```sh
kubectl apply -f platform/kube/bookinfo-reviews-v2v3.yaml
kubectl get svc
```

Now create the the SMI `TrafficSplit` object to split traffic 50/50 between reviews v2 and v3:

```sh
kubectl apply -f platform/kube/smi-traffic-split-reviews-50v250v3.yaml
kubectl describe trafficsplit.split.smi-spec.io/reviews-rollout
```

Back in the `bookinfo` app, if you reload the page you'll only get black and red star ratings.

If you check the Linkerd **Traffic Split** page (`http://$WSLHOST:50750/namespaces/default/trafficsplits`) you'll see the split is 50/50.

Click the `reviews-rollout` traffic split object (`http://$WSLHOST:50750:50750/namespaces/default/trafficsplits/reviews-rollout`) to see this in more detail.


After a while, you'll see that no traffic goes to `reviews-1` (http://$WSLHOST:50750/namespaces/default/deployments/productpage-v1).

Finally, shift 100% of traffic to `reviews-3`:

```sh
kubectl apply -f platform/kube/smi-traffic-split-reviews-100v3.yaml
kubectl describe trafficsplit.split.smi-spec.io/reviews-rollout
```

Reload the `bookinfo` app (`http://$WSLHOST:9080/productpage?u=test`) -- only red stars ratings should appear and only `review-3` should be getting traffic (`http://$WSLHOST:50750/namespaces/default/deployments/productpage-v1`)

To fianlise the rollout, you would:

* Update the traffic split to only list `reviews-v3` as a backend with `100` weight
* Delete the `review-v2` service
* Delete the `reviews-v1` and `reviews-v2` deployments

### Demo Extensions

* Use Flagger to automatically shift traffic
* Deploy Istio mesh to another namespace and deploy `bookinfo` there - show traffic split works with both Linkerd and Istio (requires an adapter)

Cleanup / Reset Demo
--------------------

```sh
cd bookinfo/
kubectl delete -f ./platform/kube/bookinfo.yaml
kubectl delete -f ./platform/kube/smi-traffic-split-reviews-100v3.yaml
kubectl delete -f ./platform/kube/bookinfo-reviews-v2v3.yaml
kubectl get all

pkill linkerd # dashboard
pkill kubectl # port-forward
```

Resources
---------

* [SMI spec](https://smi-spec.io/)
* [SMI Traffic Split](https://github.com/deislabs/smi-spec/blob/master/traffic-split.md)
* [Linkerd 2](https://linkerd.io/2/overview/)
* [Annoucement for Linkerd 2 support for SMI Traffic Split](https://linkerd.io/2019/07/11/announcing-linkerd-2.4/)
* [Original Bookinfo sample](https://github.com/istio/istio/tree/master/samples/bookinfo)

Credits
-------

* This demo is based on this post: https://www.tarunpothulapati.com/posts/traffic-splitting-linkerd/