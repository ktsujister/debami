# debami
Is a script on top of packer (https://packer.io/) for generating AWS Ubuntu AMI's from a collection of debian packages.
The script requires that both *packer* and *dpkg-scanpackages* be available from $PATH for it to run successfully.

## Usage

```bash
$ ./debami.sh \
  --ami-name ami-name-here \
  --builder-name name-of-build-instance \
  --deb-path /path/to/my/packages \
  --instance-type 't1.micro' \
  --package 'var-aws awslogs-agent' \
  --source-ami ami-bf868e8f \
  --tag-name 'debami test tag' \
  --username-ssh ubuntu
```

_--deb-path_ should indicate a directory containing one or more packages, while _--package_ should list those that should be installed.


## Note
Various parameters can be set as environmental variables, which the debami.sh will then use as default values.
* EC2_REGION
* AWS_ACCESS_KEY
* AWS_SECRET_KEY
* AMI_NAME
* BUILDER_NAME
* DEB_PATH
* HVM
* INSTANCE_TYPE
* INSTALL_PACKAGE
* SOURCE_AMI
* SUBNET_ID
* TAG_NAME
* USERNAME_SSH
* VPC_ID

#### Any required parameters not provided, will be requested for during run time at the command line.

## Packer
Packer can easily be install via the following,
https://packer.io/docs/installation.html

## dpkg-scanpackages
Can be found in the debian package *dpkg-dev*, and installed via the following command,
```bash
$ sudo apt-get install dpkg-dev
```
