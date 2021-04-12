# rhacm-observability-fix
RHACM observability addon fix for certificate issue

This script is created to address issue reported in https://bugzilla.redhat.com/show_bug.cgi?id=1906542<br>
Workaroud proposed in the bug has the following issues:
- Multicluster observability operator should be kept in disabled state (mco_pause: true). Otherwise all changes in manifestwork will be immediately overwritten.
- When adding new managed cluster - multicluster observability operator should be enabled to deploy observability components on the new cluster. Once observability components are deployed - multicluster observability operator can be disabled again, but all changes to manifestworks will have to be reapplied.
- In Managed IBM Cloud Openshift environment (ROKS) - workaround steps need to be amended to take into account the fact that API endpoints are not managed via API server cluster operator.
  
This script is created to help automate all steps required to apply workaround and manage RHACM:
- Apply workaround for a specific managed cluster while disabling multicluster observability operator.
- Retrieve API certificate directly from API URL (not from apiserver CRD) - as a workaround for ROKS configuration
- Enable multicluster observability operator when new managed cluster needs to be added.
  - Once new cluster is added - script needsto be re-run for all managed clusters including the new one. This step can be set-up as a separate shell script

## Details
### Enabling multicluster observability operator
To enable multicluster observability operator - script modifies observability instance of multiclusterobservability CRD by setting mco-pause annotation to 'false'.
As a result multicluster observability operator will restore all manifestworks and secrets back to the original state. It will also configre and deploy observability components for all newly added managed clusters.

To enable multicluster observability operator run the script as follows:
```
./rhacm-observability-fix.sh restore -m <MCM_API> -n <MCM_NS> -u <MCM_USER> -p <MCM_PWD>
```
or
```
./rhacm-observability-fix.sh restore -m <MCM_API> -n <MCM_NS> -t <MCM_TOKEN>
```
Where:
- MCM_API - API URI of MCM Cluster, e.g.: https://c101-e.us-east.containers.cloud.ibm.com:30000
- MCM_NS - namespace for endpoint-observability-work manifestwork
- MCM_USER - username to access MCM Cluster - should be cluster admin to be able to make required changes or have specific permissions to modify RHACM CRD's
- MCM_PWD - password
- MCM_TOKEN - authentication token (can be used instead of username / password)

### Applying the workaround for a specific managed cluster
Applying workaround for a specific managed cluster is done by executing the following steps:
- Disable multicluster observability operator by modifying observability instance of multiclusterobservability CRD by setting mco-pause annotation to 'true'.
- Retrieve API Server certificate directly from MCM API URI (using openssl)
- Retrieve endpoint-observability-work instance of manifestwork CRD in a MCM cluster namespace corresponding to a managed cluster.
- Retrieve kubeadmin content from the endpoint-observability-work instance of manifestwork
- Add API Server certificate to a kubeadmin certificate chain
- Update endpoint-observability-work instance of manifestwork CRD by replacing kubeadmin
- Delete hub-kube-config secret in open-cluster-management-addon-observability namespace on a managed cluster
- Delete endpoint-observability-operator pods in open-cluster-management-addon-observability namespace on a managed cluster


To apply the workaround - run the script as follows:
```
./rhacm-observability-fix.sh fix -m <MCM_API> -n <MCM_NS> -u <MCM_USER> -p <MCM_PWD> -c <MGD_API> -d <MGD_NS> -e <MGD_USER> -f <MGD_PWD>
```
or
```
./rhacm-observability-fix.sh fix -m <MCM_API> -n <MCM_NS> -t <MCM_TOKEN> -c <MGD_API> -d <MGD_NS> -g <MGD_TOKEN>
```
Where:
- MCM_API - API URI of MCM Cluster, e.g.: https://c101-e.us-east.containers.cloud.ibm.com:30000
- MCM_NS - namespace for endpoint-observability-work manifestwork (E.g. 'local-cluster' or 'dev-cluster')
- MCM_USER - username to access MCM Cluster - should be cluster admin to be able to make required changes or have specific permissions to modify RHACM CRD's
- MCM_PWD - password
- MCM_TOKEN - authentication token (can be used instead of username / password)
- MGD_API - API URI of a Managed Cluster, e.g.: https://c101-e.us-east.containers.cloud.ibm.com:30001
- MGD_NS - namespace for observability components deployed on a managed cluster (Usually open-cluster-management-addon-observability)
- MGD_USER - username to access Managed Cluster - should be cluster admin to be able to make required changes or have specific permissions to modify components in MGD_NS namespace
- MGD_PWD - password
- MGD_TOKEN - authentication token (can be used instead of username / password)

