SMI Demo
========

Demo using [SMI](https://smi-spec.io/) + [Linkerd](https://linkerd.io/2/overview/) to [shift traffic](https://github.com/servicemeshinterface/smi-spec/blob/master/traffic-split.md) from one or more services to another (canary) version.

Pre-requsities
--------------

* Recent Kubernetes cluster created with `kubectl` CLI installed - [Steps](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough)
* Helm (v2) - client and Tiller setup in Kubernetes with RBAC role binding configured - [Steps](https://docs.microsoft.com/en-us/azure/aks/kubernetes-helm)
* Linkerd 2.4+ installed - client and server components (control plane) - [Steps](https://linkerd.io/2/tasks/install/)
* Locally cloned `bookinfo` sample app - Steps: `git clone git@github.com:clarenceb/bookinfo.git; cd bookinfo/`

Demo Script
-----------

### View the Linkerd dashboard

Display the Linkerd dashboard:

```sh
linkerd dashboard &
```

Visit: [`http://localhost:50750`](http://localhost:50750) in your browser.

### Deploy the Bookinfo app

Deploy the initial `bookinfo` sample app, meshed with Linkerd:

```sh

linkerd inject ./platform/kube/bookinfo.yaml | kubectl apply -n bookinfo -f -

watch kubectl get pod -n bookinfo  # CTRL+C to exit
kubectl get svc -n bookinfo

kubectl port-forward -n bookinfo svc/productpage 9080:9080 &
```

View the app: [`http://localhost:9080`](http://localhost:9080)

Click 'Test user' to see reviews (`http://localhost:9080/productpage?u=test`)

Reload the page several times: You should see the reviews cycle through 3 versions of ratings (**v1** - no stars, **v2** - red stars, **v3** - black stars)

In Linkerd dashboard, you can vist the [`bookinfo` namespace](http://localhost:50750/namespaces/bookinfo) to see the connection graph (at top) and list of deployments.

### Linkerd traffic telemetry

You can see that there are 3 versions of the review service already deployed:

* `reviews-1`
* `reviews-2`
* `reviews-3`

Click the `productpage-v1` deployment (`http://localhost:50750/namespaces/bookinfo/deployments/productpage-v1`).

Here you can see the call graph with success rates, RPS, etc.  You can also see  **Live Calls** which shows the outbound connections to downstream services.

Try clicking the `Tap` link on one of the outbound calls and starting a tap on one of the routes.

Currently, there are no **Traffic Splits** defined (http://localhost:50750/namespaces/bookinfo/trafficsplits).

### Define SMI Traffic Splits

Service `reviews` currently routes to all 3 review deployments:

```sh
kubectl describe svc/reviews -n bookinfo
# Selector:          app=reviews
```

Each deployment has the `app=reviews` label plus a `version` label:

```sh
kubectl describe deploy reviews-v{1,2,3} -n bookinfo | grep -A1 ^Labels
```

Create two new services for SMI traffic split to route to only the services `reviews-v2` and `reviews-v3`:

```sh
kubectl apply -f platform/kube/bookinfo-reviews-v2v3.yaml -n bookinfo
kubectl get svc -n bookinfo
```

Now create the the SMI `TrafficSplit` object to split traffic 50/50 between reviews v2 and v3:

```sh
kubectl apply -f platform/kube/smi-traffic-split-reviews-50v250v3.yaml -n bookinfo
kubectl describe trafficsplit.split.smi-spec.io/reviews-rollout -n bookinfo
```

Back in the [`bookinfo`](http://localhost:9080/productpage?u=test) app, if you reload the page you'll only get black and red star ratings.

If you check the Linkerd **Traffic Split** page (`http://localhost:50750/namespaces/bookinfo/trafficsplits`) you'll see the split is 50/50.

Click the `reviews-rollout` traffic split object (`http://localhost:50750:50750/namespaces/bookinfo/trafficsplits/reviews-rollout`) to see this in more detail.

After a while of generating requests, you'll see that no traffic goes to [`reviews-1`](http://localhost:50750/namespaces/bookinfo/deployments/productpage-v1).

Finally, shift 100% of traffic to `reviews-3`:

```sh
kubectl apply -f platform/kube/smi-traffic-split-reviews-100v3.yaml -n bookinfo
kubectl describe trafficsplit.split.smi-spec.io/reviews-rollout -n bookinfo
```

Reload the `bookinfo` app (`http://localhost:9080/productpage?u=test`) -- only red stars ratings should appear and only `review-3` should be getting traffic (`http://localhost:50750/namespaces/bookinfo/deployments/productpage-v1`)

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
kubectl delete -f ./platform/kube/bookinfo.yaml -n bookinfo
kubectl delete -f ./platform/kube/smi-traffic-split-reviews-100v3.yaml -n bookinfo
kubectl delete -f ./platform/kube/bookinfo-reviews-v2v3.yaml -n bookinfo
kubectl get all -n bookinfo

pkill linkerd # dashboard
pkill kubectl # port-forward
```

Resources
---------

* [SMI spec](https://smi-spec.io/)
* [SMI Traffic Split](https://github.com/servicemeshinterface/smi-spec/blob/master/traffic-split.md)
* [Linkerd 2](https://linkerd.io/2/overview/)
* [Annoucement for Linkerd 2 support for SMI Traffic Split](https://linkerd.io/2019/07/11/announcing-linkerd-2.4/)
* [Original Bookinfo sample](https://github.com/istio/istio/tree/master/samples/bookinfo)

Credits
-------

* This demo is based on this post: https://www.tarunpothulapati.com/posts/traffic-splitting-linkerd/
