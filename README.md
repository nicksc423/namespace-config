# namespace-config
Repo for basic setup for a namespace in our k8s cluster.


provision_app.sh creates us:
* a namespace
* a Kubeconfig for gitlab runner with deploy only permissions
* a certificate for cert-manager for the namespace

you can run provision_app.sh like this:
`./provision_app.sh app app.staging.company.dev`

then to watch the progress run:
`watch kubectl -n dcp get Certificate`

wait until Ready = true

networkpolicy.yaml creates:
* a default deny networkpolicy
* an allow all networkpolicy for the monitoring namespace (for prometheus)
