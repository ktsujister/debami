#!/bin/bash
#
# DEBAMI
#
# Script to build an Ubuntu AWS AMI via packer (https://packer.io)
# based on a collection of local debian packages.

set -e # Halt of first error
# set -x # Enable for debugging


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Define script parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
LOCAL_DEB_REPO_PATH="/usr/local/debami"
APT_LIST_FILENAME="debami.list"
TARBALL_NAME="debami.tar.gz"
JSON_FILENAME="debami.json"
DEBAMI_LOGFILE="`pwd`/debami.log"
HVM_JSON=""
IAM_ROLE_JSON=""

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Ensure we have the correct AWS end point and URL set
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
if [ -z "$EC2_REGION" ]; then
    read -p "EC2_REGION= " EC2_REGION
    export EC2_REGION=${EC2_REGION}
fi


# # # # # # # # # # # # # # # # # # # # # # # # # #
# If AWS credentials aren't provided, ask for them
# # # # # # # # # # # # # # # # # # # # # # # # # #
if [ -z "$AWS_ACCESS_KEY" ]; then
    read -p "AWS_ACCESS_KEY= " AWS_ACCESS_KEY
    export AWS_ACCESS_KEY=$AWS_ACCESS_KEY
fi
if [ -z "$AWS_SECRET_KEY" ]; then
    read -p "AWS_SECRET_KEY= " AWS_SECRET_KEY
    export AWS_SECRET_KEY=$AWS_SECRET_KEY
fi


# # # # # # # # # # # # # # # # # # # # # # # # # #
# Check to see if all tools are availabel in PATH
# # # # # # # # # # # # # # # # # # # # # # # # # #
hash packer 2>/dev/null || \
    { echo >&2 "debami.sh requires 'packer' but it's not available via PATH.  Aborting."; exit 1; }
hash dpkg-scanpackages 2>/dev/null || \
    { echo >&2 "debami.sh requires 'dpkg-scanpackages' but it's not available via PATH.  Aborting."; exit 1; }


# # # # # # # # # # # # # # # # # # # # # # # # # #
# Handle arguments
# # # # # # # # # # # # # # # # # # # # # # # # # #

# Default values
BUILDER_NAME="debami builder"
TAG_NAME="$BUILDER_NAME"
INSTANCE_TYPE="t1.micro"
# SSH_USERNAME="ubuntu"

# Handle command line arguments
while [[ $# > 1 ]]
do
    key="$1"

    case $key in
	-a|--ami-name)
	    AMI_NAME="$2"
	    shift # past argument
	    ;;
	-b|--builder-name)
	    BUILDER_NAME="$2"
	    shift # past argument
	    ;;
	-d|--deb-path)
	    DEB_PATH="$2"
	    shift # past argument
	    ;;
	-h|--hvm)
	    HVM_FLAG="TRUE"
	    ;;
	-i|--instance-type)
	    INSTANCE_TYPE="$2"
	    shift # past argument
	    ;;
	-p|--package)
	    INSTALL_PACKAGE="$2"
	    shift # past argument
	    ;;
	-s|--source-ami)
	    SOURCE_AMI="$2"
	    shift # past argument
	    ;;
	--subnet-id)
	    SUBNET_ID="$2"
	    shift # past argument
	    ;;
	-t|--tag-name)
	    TAG_NAME="$2"
	    shift # past argument
	    ;;
	-u|--username-ssh)
	    SSH_USERNAME="$2"
	    shift # past argument
	    ;;
	--vpc-id)
	    VPC_ID="$2"
	    shift # past argument
	    ;;
	--iam-role)
	    IAM_ROLE="$2"
	    shift
	    ;;
	--private-key-file)
	    PRIVATE_KEY_FILE="$2"
	    shift
	    ;;
	--keypair)
	    KEYPAIR="$2"
	    shift
	    ;;
	--security-group-id)
	    SG_ID="$2"
	    shift
	    ;;
	--token)
	    TOKEN="$2"
	    shift
	    ;;
	*) # Unknown option
	    echo >&2 "'$key' is an unknown option";
	    exit 1;
	    ;;
    esac
    shift # past argument or value
done

# If not already defined, ask the user
if [ -z "$AMI_NAME" ]; then
    read -p "AMI_NAME= " AMI_NAME
fi

if [ -z "$DEB_PATH" ]; then
    read -p "DEB_PATH= " DEB_PATH
fi

if [ -z "$SOURCE_AMI" ]; then
    read -p "SOURCE_AMI= " SOURCE_AMI
fi

if [ -z "$INSTALL_PACKAGE" ]; then
    read -p "INSTALL_PACKAGE= " INSTALL_PACKAGE
fi

if [ -z "$SSH_USERNAME" ]; then
    read -p "USERNAME_SSH= " SSH_USERNAME
fi

if [ -z "$HVM_FLAG" ]; then
    HVM_JSON=""
else
    if [ -z "$VPC_ID" ]; then
	read -p "VPC_ID= " VPC_ID
    fi
    if [ -z "$SUBNET_ID" ]; then
	read -p "SUBNET_ID= " SUBNET_ID
    fi

    HVM_JSON="\"ami_virtualization_type\": \"hvm\", \"vpc_id\": \"${VPC_ID}\", \"subnet_id\": \"${SUBNET_ID}\","
fi

if [ -z "${IAM_ROLE}" ]; then
    IAM_ROLE_JSON=""
else
    IAM_ROLE_JSON="\"iam_instance_profile\": \"${IAM_ROLE}\","
fi

if [ -z "${KEYPAIR}" ]; then
    KEYPAIR_JSON=""
else
    KEYPAIR_JSON="\"ssh_keypair_name\": \"${KEYPAIR}\", \"ssh_private_key_file\": \"${PRIVATE_KEY_FILE}\","
fi

if [ -z "${SG_ID}" ]; then
    SG_ID_JSON=""
else
    SG_ID_JSON="\"security_group_id\": \"${SG_ID}\","
fi

if [ -z "${TOKEN}" ]; then
    TOKEN_JSON=""
else
    TOKEN_JSON="\"token\": \"${TOKEN}\","
fi

# # # # # # # # # # # # # # # # # # # # # # # # # #
# Generate local repo files and tarball
# # # # # # # # # # # # # # # # # # # # # # # # # #

touch $DEBAMI_LOGFILE
echo "Starting build process," >> $DEBAMI_LOGFILE

# Create temporary directory
TMPDIR=`mktemp -d`
echo "Working directory: $TMPDIR" >> $DEBAMI_LOGFILE

# Create install path for packages
DEB_INSTALL_PATH="${TMPDIR}${LOCAL_DEB_REPO_PATH}"
mkdir -p $DEB_INSTALL_PATH && cd $DEB_INSTALL_PATH

# Copy input .deb files into location
cp $DEB_PATH/*.deb $DEB_INSTALL_PATH
echo "cp $DEB_PATH/*.deb $DEB_INSTALL_PATH" >> $DEBAMI_LOGFILE

# Create repo manifest file
echo "dpkg-scanpackages @ $DEB_INSTALL_PATH" >> $DEBAMI_LOGFILE
dpkg-scanpackages . /dev/null 2>> $DEBAMI_LOGFILE | gzip -9c > Packages.gz

# Create install path for sources.list
DEB_SOURCES_PATH="/etc/apt/sources.list.d"
DEB_LIST_PATH="${TMPDIR}${DEB_SOURCES_PATH}"
mkdir -p $DEB_LIST_PATH && cd $DEB_LIST_PATH
cat > $APT_LIST_FILENAME <<EOF
deb file:$LOCAL_DEB_REPO_PATH ./
EOF

# Create tarball to copy
cd $TMPDIR
echo "Creating $TMPDIR/$TARBALL_NAME" >> $DEBAMI_LOGFILE
tar -cvzf $TARBALL_NAME usr etc >> $DEBAMI_LOGFILE


# # # # # # # # # # # # # # # # # # # # # # # # # #
# Generate packer json
# # # # # # # # # # # # # # # # # # # # # # # # # #

JSON_FULLPATH="${TMPDIR}/${JSON_FILENAME}"
echo "Writing  $JSON_FULLPATH" >> $DEBAMI_LOGFILE
cat > $JSON_FULLPATH <<EOF
{
    "variables": {
	"aws_access_key": "{{env \`AWS_ACCESS_KEY\`}}",
	"aws_secret_key": "{{env \`AWS_SECRET_KEY\`}}"
    },
    "builders": [{
	"type": "amazon-ebs",
	"name": "$BUILDER_NAME",
	"access_key": "{{user \`aws_access_key\`}}",
	"secret_key": "{{user \`aws_secret_key\`}}",
	${TOKEN_JSON}
	"region": "$EC2_REGION",
	"source_ami": "$SOURCE_AMI",
        "associate_public_ip_address": "true",
        ${HVM_JSON}
	${IAM_ROLE_JSON}
	${KEYPAIR_JSON}
	${SG_ID_JSON}
	"instance_type": "$INSTANCE_TYPE",
	"ssh_username": "$SSH_USERNAME",
	"tags": {
	    "Name": "$TAG_NAME"
	},
	"ami_name": "$AMI_NAME"
    }],
    "provisioners": [
	{
	    "type": "file",
	    "source": "$TARBALL_NAME",
	    "destination": "/tmp/$TARBALL_NAME"
	},
	{
	    "type": "shell",
	    "inline": [
		"sleep 30",
                "cd /",
                "sudo tar -xvzf /tmp/$TARBALL_NAME",
		"sudo apt-get update",
		"sudo apt-get install --allow-unauthenticated -y $INSTALL_PACKAGE"
	    ]
	}
    ]
}
EOF

# ^ ^ ^ ^ ^ ^ ^ ^
# NOTES ON ABOVE
# ^ ^ ^ ^ ^ ^ ^ ^
# - 'apt-get update' may take exceptionally long on AWS
# - 'apt-get install --allow-unauthenticated' is required as the
#   local packages can't be authenticated.


# # # # # # # # # # # # # # # # # # # # # # # # # #
# Execute packer
# # # # # # # # # # # # # # # # # # # # # # # # # #
echo "Executing 'packer build $JSON_FULLPATH';;" >> $DEBAMI_LOGFILE
packer build $JSON_FULLPATH >> $DEBAMI_LOGFILE

# # # # # # # # # # # # # # # # # # # # # # # # # #
# Clean up
# # # # # # # # # # # # # # # # # # # # # # # # # #
echo "Cleaning up" >> $DEBAMI_LOGFILE

# Nuke temp directory and all it contains
rm -rf $TMPDIR

echo "Success;"
tail -2 $DEBAMI_LOGFILE | head -1
