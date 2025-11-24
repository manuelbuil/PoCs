# This script duplicates all Ingress resources that currently use 'ingress-nginx',
# assigns the duplicate a new name, changes the ingressClassName to 'traefik',
# and applies the new resource to the cluster.

echo "Starting automated Ingress duplication and reclassification..."

# Use kubectl to get all Ingresses that use the 'ingress-nginx' class.
# Use 'jq' to process the JSON output for modification.
kubectl get ingress --all-namespaces -o json | \
jq -c '.items[] | select(.spec.ingressClassName == "nginx")' | \
while read -r INGRESS; do
    
    # 1. Extract Name and Namespace for logging
    NS=$(echo "$INGRESS" | jq -r '.metadata.namespace')
    NAME=$(echo "$INGRESS" | jq -r '.metadata.name')
    NEW_NAME="${NAME}-traefik"

    echo "Processing Ingress: $NS/$NAME"

    # 2. Modify the Ingress object using jq
    #    - Remove 'status' (read-only field)
    #    - Remove system-generated fields like 'resourceVersion', 'uid', 'creationTimestamp', etc.
    #    - Rename the object by appending '-traefik'
    #    - Change 'ingressClassName' from 'nginx' to 'traefik'
    MODIFIED_INGRESS=$(echo "$INGRESS" | jq \
        'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"], .status, .metadata.managedFields)' | \
        jq --arg NEW_NAME "$NEW_NAME" '.metadata.name = $NEW_NAME | .spec.ingressClassName = "traefik"')

    # 3. Apply the modified (duplicated) Ingress resource
    echo "$MODIFIED_INGRESS" | kubectl apply -f -
    echo "  -> Created duplicate Ingress: $NS/$NEW_NAME"
done

echo "Ingress duplication complete."
