# debami
Simple script on top of packer (https://packer.io/) for generating AWS Ubuntu AMI's from a collection of debian packages.

## Usage
```bash
$ EC2_REGION=us-west-2 ./debami.sh \
  --ami-name ami-name-here \
  --builder-name name-of-build-instance \
  --deb-path /path/my-packages \
  --instance-type 't1.micro' \
  --package 'var-aws awslogs-agent' \
  --source-ami ami-bf868e8f \
  --tag-name 'debami test tag' \
  --username-ssh ubuntu
```