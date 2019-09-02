  
# Deploy FWB with two services (mgmt and traffic)

kubectl apply -f - <<EOF  
apiVersion: v1  
kind: Service  
metadata:
  name: fwb-mgmt 
  labels:  
    app: fwb 
spec:  
  ports:  
  - name: http  
    port: 8000  
    targetPort: 8  
  selector:  
    app: fwb  
--- 
apiVersion: v1  
kind: Service  
metadata:
  name: fwb-traffic 
  labels:  
    app: fwb  
spec:  
  ports:  
  - name: http  
    port: 8080  
    targetPort: 80  
    protocol: TCP
  selector:  
    app: fwb  
--- 
apiVersion: extensions/v1beta1  
kind: Deployment  
metadata:  
  name: fwb  
spec:  
  replicas: 1  
  template:  
    metadata:  
      labels:  
        app: fwb  
        version: v1  
    spec:  
      containers:  
      - image: fwb-image  
        imagePullPolicy: IfNotPresent  
        name: fwb  
        ports:  
        - containerPort: 8 
        - containerPort: 80 
        - containerPort: 22 
        resources: 
          limits: 
            memory: "4096Mi" 
          requests: 
            memory: "4096Mi" 
        securityContext: 
          privileged: true 
          allowPrivilegeEscalation: true 
          capabilities: 
            add: 
              - NET_ADMIN 
              - NET_RAW 
              - SYS_PTRACE               
EOF
   
# Deploy Ingress gateway from Istio for FWB
  
kubectl apply -f - <<EOF  
apiVersion: networking.istio.io/v1alpha3  
kind: Gateway  
metadata:  
  name: fwb-gateway  
spec:  
  selector:  
    istio: ingressgateway # use Istio default gateway implementation  
  servers:  
  - port:  
      number: 80  
      name: http  
      protocol: HTTP  
    hosts:  
    - "fwb.example.com"  
EOF
  
# Deploy a VirtualService to route traffic properly

kubectl apply -f - <<EOF 
apiVersion: networking.istio.io/v1alpha3  
kind: VirtualService  
metadata:  
  name: fwb  
spec:  
  hosts:  
  - "fwb.example.com"  
  gateways:  
  - fwb-gateway  
  http:
  - match:
    - uri:
        prefix: /login  
    route: 
    - destination: 
        port:
          number: 8000  
        host: fwb-mgmt 
  - route: 
    - destination: 
        port: 
          number: 8080 
        host: fwb-traffic 
EOF
 

# Use these host/port to access Istio Ingress
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}') 
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}') 
export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}') 

# Access FWB (mgmt) using the service (as ClusterIP)
curl -I 10.111.198.90:8000/login 

# Access FWB (mgmt) Using Istio Ingress
curl -I -HHost:fwb.example.com ${INGRESS_HOST}:${INGRESS_PORT}/login 

# Access FWB (traffic) Using Istio Ingress
curl -I -HHost:fwb.example.com ${INGRESS_HOST}:${INGRESS_PORT}/productpage 

# Check ingress logs
kubectl logs -f istio-ingressgateway-75ddf64567-xb8vf -n istio-system 

# Port forward for mgmt HTTP and SSH
kubectl port-forward --address 0.0.0.0 deploy/fwb 2008:8 2022:22 