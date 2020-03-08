#!/bin/bash


OCP_RELEASE_PATH=ocp
OCP_SUBRELEASE=4.3.1

RHCOS_RELEASE=4.3
RHCOS_IMAGE_BASE=4.3.1-x86_64

### PULL SECRET - cloud.openshift.com ###
RHEL_PULLSECRET='redhat-registry-pullsecret.json'

#### EXTRA CONFs ###
AIRGAP_REPO='ocp4/openshift4'
AIRGAP_SECRET_JSON='pull-secret.json'


usage() {
    echo " ---- Script Descrtipion ---- "
    echo "  "
    echo " This script configures the bastion host that is meant to serve as local registry and core installation components of Red Hat Openshift 4"
    echo " "
    echo " Pre-requisites: "
    echo " "
    echo " 1 - Update the installation variables at the beginning of this script"
    echo " 2 - Download the OCP installation secret in https://cloud.redhat.com/openshift/install/pull-secret and create a file called 'redhat-registry-pullsecret.json' in the $HOME directory"
    echo " "

    echo " "
    echo " Options:  "
    echo " "
    echo " * registry create <server.domain> : Create and Configures the local registry"
    echo "   	Example:  oc stc4 registry create registry.example.com"
    echo " "
    echo " * registry status : Check if the local registry is running"
    echo "   	Example:  oc stc4 registry status"
    echo " "
    echo " * mirror ocp <version> : mirrors the core registry container images for installation locally"
    echo "   	Example:  oc stc4 mirror ocp 4.3.1"
    echo " "
    echo "  "
    echo -e " Usage: oc stc4 [ repository | mirror ] "
    echo "  "
    echo " ---- Ends Descrtipion ---- "
    echo "  "
exit 0
}

check_deps (){
    if [[ ! $(rpm -qa wget git bind-utils lvm2 lvm2-libs net-utils firewalld | wc -l) -ge 7 ]] ;
    then
        install_tools
    fi    
}

get_images() {
    cd ~/
    test -d images || mkdir images ; cd images 
    test -f openshift-client-linux-${OCP_SUBRELEASE}.tar.gz  || curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/clients/${OCP_RELEASE_PATH}/${OCP_SUBRELEASE}/openshift-client-linux-${OCP_SUBRELEASE}.tar.gz 
    cd ..
    prep_images
    prep_installer
}

install_tools() {
    #RHEL8
    if grep -q -i "release 8" /etc/redhat-release; then   
        dnf -y install libguestfs-tools podman skopeo bind-utils firewalld jq
        echo -e "\e[1;32m Packages - Dependencies installed\e[0m"
    fi

    #RHEL7
    if grep -q -i "release 7" /etc/redhat-release; then
        #subscription-manager repos --enable rhel-7-server-extras-rpms
        yum -y install libguestfs-tools podman skopeo httpd haproxy bind-utils net-tools nfs-utils rpcbind wget tree git lvm2.x86_64 lvm2-libs firewalld || echo "Please - Enable rhel7-server-extras-rpms repo" && echo -e "\e[1;32m Packages - Dependencies installed\e[0m"
    fi
}

mirror_ocp () {
    cd ~/
    echo "Mirroring from Quay into Local Registry"
    test -f /opt/registry/certs/domain.crt && AIRGAP_REG=$(openssl x509 -noout -subject -in /opt/registry/certs/domain.crt | awk '{print $3}') || echo "Local registry not found"
    LOCAL_REGISTRY="${AIRGAP_REG}:5000"
    LOCAL_REPOSITORY="${AIRGAP_REPO}"
    PRODUCT_REPO='openshift-release-dev'
    LOCAL_SECRET_JSON="${AIRGAP_SECRET_JSON}"
    RELEASE_NAME="ocp-release"
    OCP_RELEASE="${RHCOS_IMAGE_BASE}"
    test -f mirror-registry-pullsecret.json || echo "Enter the ADMIN password for local registry:"
    test -f mirror-registry-pullsecret.json || podman login -u admin --authfile mirror-registry-pullsecret.json "${AIRGAP_REG}:5000"

    if [ -f ${RHEL_PULLSECRET} ]
    then
        command -v jq 1>/dev/null 2>/dev/null || { echo >&2 "jq is require but it's not installed.  Aborting."; exit 1; }
        jq -s '{"auths": ( .[0].auths + .[1].auths ) }' mirror-registry-pullsecret.json ${RHEL_PULLSECRET} > ${AIRGAP_SECRET_JSON}

        command -v oc 1>/dev/null 2>/dev/null || { echo >&2 "oc is require but it's not installed.  Aborting."; exit 1; }
        oc adm -a ${LOCAL_SECRET_JSON} release mirror \
        --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
        --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
        --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}
    else
        echo "ERROR: ${RHEL_PULLSECRET} not found."
    fi
}

extract_ocp_installer () {
    cd ~/
    LOCAL_REGISTRY="${AIRGAP_REG}:5000"
    LOCAL_REPOSITORY="${AIRGAP_REPO}"
    PRODUCT_REPO='openshift-release-dev'
    LOCAL_SECRET_JSON="${AIRGAP_SECRET_JSON}"
    RELEASE_NAME="ocp-release"
    OCP_RELEASE="${RHCOS_IMAGE_BASE}"
    podman login -u admin --authfile mirror-registry-pullsecret.json "${AIRGAP_REG}:5000"
    command -v oc 2>/dev/null || { echo >&2 "oc is require but it's not installed.  Aborting."; exit 1; }
    echo "Retrieving 'openshift-install' from local container repository"
    oc adm release extract -a ${AIRGAP_SECRET_JSON} --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}"
    mv openshift-install bin/openshift-install
    echo "Retrieving 'openshift-install' Version"
    openshift-install version
}

prep_installer () {
    cd ~/
    echo "Uncompressing installer and client binaries"
    test -d ~/bin/ || mkdir ~/bin/
    tar -xzf ./images/openshift-client-linux-${OCP_SUBRELEASE}.tar.gz  -C ~/bin 
}

prep_registry (){
    cd ~/
    fqdn=$(dig +short ${AIRGAP_REG})
    if [ ! -z ${fqdn} ]
    then
        test -d /opt/registry/ || mkdir -p /opt/registry/{auth,certs,data}
        if [ ! -f /opt/registry/certs/domain.crt ]
        then
            openssl req -newkey rsa:4096 -nodes -sha256 -keyout /opt/registry/certs/domain.key -x509 -days 365 -subj "/CN=${AIRGAP_REG}" -out /opt/registry/certs/domain.crt
            cp -rf /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
            update-ca-trust
            cert_update=true
        fi
        if [ ! -f /opt/registry/auth/htpasswd ]
            then
                echo "Please enter admin user password"
                htpasswd -Bc /opt/registry/auth/htpasswd admin
        fi

    test -f /etc/systemd/system/mirror-registry.service || cat > /etc/systemd/system/mirror-registry.service << EOF
[Unit]
Description=Mirror registry ${AIRGAP_REG} 
After=network.target

[Service]
Type=simple
TimeoutStartSec=5m

ExecStartPre=-/usr/bin/podman rm "mirror-registry"
ExecStartPre=/usr/bin/podman pull quay.io/redhat-emea-ssa-team/registry:2
ExecStart=/usr/bin/podman run --name mirror-registry --net host \
  -v /opt/registry/data:/var/lib/registry:z \
  -v /opt/registry/auth:/auth:z \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=registry-realm" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  -v /opt/registry/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  quay.io/redhat-emea-ssa-team/registry:2

ExecReload=-/usr/bin/podman stop "mirror-registry"
ExecReload=-/usr/bin/podman rm "mirror-registry"
ExecStop=-/usr/bin/podman stop "mirror-registry"
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    /usr/bin/podman pull quay.io/redhat-emea-ssa-team/registry:2 -q 1>/dev/null
    systemctl enable mirror-registry -q
    systemctl start mirror-registry -q
    if [[ ${cert_update} = true ]]
        then
            systemctl restart mirror-registry -q
    fi
    firewall-cmd --permanent --add-port=5000/tcp -q
    firewall-cmd --permanent --add-port=5000/udp -q
    firewall-cmd --reload -q
    echo -e "\e[1;32m Registry - Container Registry Configuration: DONE \e[0m"
else
    echo -e "$AIRGAP_REG \e[1;31m FAIL - DNS Record not found! \e[0m"
fi
}

key="$1"
sub_key="$2"
last_key="$3"

case $key in
    mirror)
	case $sub_key in
	  ocp)
		[ -z "$last_key" ] || RHCOS_IMAGE_BASE="${last_key}-x86_64"
        	mirror_ocp
		;;
      samples)
        	echo "samples"
		;;
      operators)
        	echo "operators"
		;;
	esac
        ;;
    registry)
	case $sub_key in
	   create)
		[ -z "$last_key" ] && usage || AIRGAP_REG=$last_key
        	prep_registry
		;;
	   status)
		systemctl is-active --quiet mirror-registry && echo Service Mirror-Registry is running || echo Service Mirror-Registry is NOT running
		;;
	   *)
		usage
		;;
	esac
	;;
    *)
        usage
        ;;
esac

##############################################################
# END OF FILE
##############################################################
