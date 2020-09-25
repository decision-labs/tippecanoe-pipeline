import json
import urllib.parse
import boto3
import os

print('Loading function')

s3 = boto3.client('s3')
REGION = 'us-west-2'  # region to launch instance.
AMI = 'ami-0a07be880014c7b8e'
# matching region/setup amazon linux ami, as per:
# https://aws.amazon.com/amazon-linux-ami/
INSTANCE_TYPE = 't2.medium'  # instance type to launch.
EC2 = boto3.client('ec2', region_name=REGION)

# used for UserData
INIT_SCRIPT_TEMPLATE = """
#cloud-boothook
#!/bin/bash

# Setup the file to load create the initial worker script
touch /init_script.sh && chmod +x /init_script.sh

# Write out the worker script dynamically
# make sure to use hard quotes for 'EOT' so the bash variables are not interpolated while writing the script
cat > /init_script.sh <<'EOT'
#!/bin/bash

# TODO: more to unprivileged user later
# For now running as root user
WORKDIR=/
# Logfile
logfile=$WORKDIR/scriptout.log
whoami >> $logfile

echo "======== starting script" >> $logfile
mkdir -p $WORKDIR/input $WORKDIR/output

echo "======== instal and start docker service" >> $logfile
sudo yum update -y
sudo yum -y install docker 
sudo service docker start

# su ec2-user # FIXME: careful this is a blocking command
# sudo usermod -a -G docker ec2-user
# sudo chkconfig docker on

echo "======== pulling image" >> $logfile
# newgrp docker 
docker pull sabman/tippecanoe:latest

echo "======== configuring aws credentials" >> $logfile
aws configure set aws_access_key_id {AWS_ACCESS_KEY_ID_LAMBDA}
aws configure set aws_secret_access_key {AWS_SECRET_ACCESS_KEY_LAMBDA}

cd $WORKDIR/ && aws s3 cp s3://{bucket}/{key} ./input

echo "======== running docker container" >> $logfile

docker run -p 3000:3000 -e MAPBOX_ACCESS_TOKEN=123 \
  -v $WORKDIR/input:/opt/input \
  -v $WORKDIR/output:/opt/output sabman/tippecanoe:latest \
  /bin/bash -c "/opt/run_tippecanoe.sh /opt/input/$(basename {key}) /opt/output"

echo $? >> $logfile
docker ps -a >> $logfile

data_file_basename=`basename {key} .gdb.zip`

echo "======== copy output to s3 bucket" >> $logfile
aws s3 cp $WORKDIR/output/$data_file_basename.mbtiles s3://{bucket}/
# sendmail
# shutdown -h now
EOT

$WORKDIR/init_script.sh >> $WORKDIR/init_script.log 2>&1

"""

# INIT_SCRIPT_TEMPLATE = """
# touch /root/init_script.sh
# """


def lambda_handler(event, context):
    print("Received event: " + json.dumps(event, indent=2))

    # Get the object from the event and show its content type
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(
        event['Records'][0]['s3']['object']['key'], encoding='utf-8')

    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        print(bucket, key)
        print("CONTENT TYPE: " + response['ContentType'])
        print('Running script:')
        init_script = INIT_SCRIPT_TEMPLATE.format(AWS_ACCESS_KEY_ID_LAMBDA=os.environ['AWS_ACCESS_KEY_ID_LAMBDA'],
                                                  AWS_SECRET_ACCESS_KEY_LAMBDA=os.environ[
                                                      'AWS_SECRET_ACCESS_KEY_LAMBDA'],
                                                  bucket=bucket,
                                                  key=key)
        print(init_script)

        instance = EC2.run_instances(
            ImageId=AMI,
            InstanceType=INSTANCE_TYPE,
            MinCount=1,  # required by boto, even though it's kinda obvious.
            MaxCount=1,
            # make shutdown in script terminate ec2
            InstanceInitiatedShutdownBehavior='terminate',
            UserData=init_script,  # file to run on instance init.
            # KeyName='geodb-ssh' # optionally add ssh keys if you need to debug worker instance
        )

        print("New instance created.")
        instance_id = instance['Instances'][0]['InstanceId']
        print(instance_id)

        return instance_id

    except Exception as e:
        print(e)
        # print('Error getting object {} from bucket {}. Make sure they exist and your bucket is in the same region as this function.'.format(key, bucket))
        raise e
