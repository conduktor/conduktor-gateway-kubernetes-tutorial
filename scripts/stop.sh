#!/bin/bash

kubectl delete namespace conduktor
helm uninstall ingress-nginx -n ingress-nginx