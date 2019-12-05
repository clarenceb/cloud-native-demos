#!/bin/bash

helm del --purge keda
kubectl delete ns/keda
kubectl delete clusterrolebindings.rbac.authorization.k8s.io/keda-keda-edge
kubectl delete customresourcedefinitions.apiextensions.k8s.io/scaledobjects.keda.k8s.io
kubectl delete customresourcedefinitions.apiextensions.k8s.io/triggerauthentications.keda.k8s.io
