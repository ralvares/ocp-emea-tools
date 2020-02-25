# Openshift Container Platform v4.x DNS checker

A proper DNS configuration ensures the OpenShift Container Platform software is deployed successfully.

###### PS: I'm not a professional developer, so you might find bugs, there is a lot to improve. 

I developed this tool to validate the DNS configuration hence to deploy a OCP cluster without problems :) 

## How to install

```
git clone https://github.com/ralvares/ocp-emea-tools
cd ocp-emea-tools
mkdir $HOME/bin
cp -rf oc-check-dns $HOME/bin
chmod +x $HOME/bin/oc-check-dns
```

##### If you have oc installed you can run it as a plugin.

You can run it as per following example:

oc check dns -domain=ocp.example.com -etcd -api -nodes=master-0,master-1,master-2,worker-0,worker-1,worker-2 -apps

##### Or you can run it as a standalone binary

oc-check-dns -domain=ocp.example.com -etcd -api -nodes=master-0,master-1,master-2,worker-0,worker-1,worker-2 -apps

```
shell$ oc-check-dns -domain=ocp.example.com -etcd -api -nodes=master-0,master-1,master-2,worker-0,worker-1,worker-2 -apps


######################################################
###     OCP EMEA TOOLKIT - DNS Checking            ###
######################################################

Domain: ocp.example.com

Checking A and PTR for node:...master-0 OK
Checking A and PTR for node:...master-1 OK
Checking A and PTR for node:...master-2 OK
Checking A and PTR for node:...worker-0 OK
Checking A and PTR for node:...worker-1 FAIL
Checking A and PTR for node:...worker-2 OK

Checking SRV Records: _etcd-server-ssl._tcp.ocp.example.com.

etcd-0.ocp.example.com. OK

Checking API and API-INT:...

api.ocp.example.com - 192.168.150.10: OK
api-int.ocp.example.com - 192.168.150.10: OK

Checking *.APPS:...

*.apps.ocp.example.com: OK

######################################################
```
