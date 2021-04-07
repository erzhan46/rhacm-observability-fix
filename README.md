# rhacm-observability-fix
RHACM observability addon fix for certificate issue

The script can both apply the fix and restore multiclusterobservability operator back to active state.

If multiclusterobservability operator is in active state (mco_pause annotation is absent or set to 'false') then it will overwrite any changes made to manifestwork.
At the same time when new cluster is added to MCM - multiclusterobservability operator should be active to deploy all required CRD's. 
Because of that
