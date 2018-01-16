data "aws_ami_ids" "ubuntu" {
  owners = [
    "099720109477"
  ]
  filter {
    name   = "name"
    values = [
      "ubuntu/images/hvm-ssd/${var.image}-amd64-server-*"
    ]
  }
}

resource "aws_cloudformation_stack" "algo" {
  name              = "${var.algo_name}"
  disable_rollback  = true
  tags {
    Environment     = "Algo"
  }
  template_body     = <<STACK
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Algo VPN stack'
Resources:

  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 172.16.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true
      InstanceTenancy: default
      Tags:
        - Key: Name
          Value: Algo
        - Key: Environment
          Value: Algo

  VPCIPv6:
    Type: AWS::EC2::VPCCidrBlock
    Properties:
      AmazonProvidedIpv6CidrBlock: true
      VpcId: !Ref VPC

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Environment
          Value: Algo
        - Key: Name
          Value: Algo

  Subnet:
    Type: AWS::EC2::Subnet
    Properties:
      CidrBlock: 172.16.254.0/23
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Environment
          Value: Algo
        - Key: Name
          Value: Algo
      VpcId: !Ref VPC

  VPCGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  RouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Environment
          Value: Algo
        - Key: Name
          Value: Algo

  Route:
    Type: AWS::EC2::Route
    DependsOn:
      - InternetGateway
      - RouteTable
      - VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref RouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  RouteIPv6:
    Type: AWS::EC2::Route
    DependsOn:
      - InternetGateway
      - RouteTable
      - VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref RouteTable
      DestinationIpv6CidrBlock: "::/0"
      GatewayId: !Ref InternetGateway

  SubnetIPv6:
    Type: AWS::EC2::SubnetCidrBlock
    DependsOn:
      - RouteIPv6
      - VPC
      - VPCIPv6
    Properties:
      Ipv6CidrBlock:
        "Fn::Join":
            - ""
            - - !Select [0, !Split [ "::", !Select [0, !GetAtt VPC.Ipv6CidrBlocks] ]]
              - "::dead:beef/64"
      SubnetId: !Ref Subnet

  RouteSubnet:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    DependsOn:
      - RouteTable
      - Subnet
      - Route
    Properties:
      RouteTableId: !Ref RouteTable
      SubnetId: !Ref Subnet

  InstanceSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    DependsOn:
      - Subnet
    Properties:
      VpcId: !Ref VPC
      GroupDescription: Enable SSH and IPsec
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: '22'
          ToPort: '22'
          CidrIp: 0.0.0.0/0
        - IpProtocol: udp
          FromPort: '500'
          ToPort: '500'
          CidrIp: 0.0.0.0/0
        - IpProtocol: udp
          FromPort: '4500'
          ToPort: '4500'
          CidrIp: 0.0.0.0/0
      Tags:
        - Key: Name
          Value: Algo
        - Key: Environment
          Value: Algo

  EC2Instance:
    Type: AWS::EC2::Instance
    DependsOn:
      - SubnetIPv6
      - Subnet
      - InstanceSecurityGroup
    Metadata:
      AWS::CloudFormation::Init:
        config:
          users:
            ubuntu:
              groups:
                - "sudo"
              homeDir: "/home/ubuntu/"
          files:
            /home/ubuntu/.ssh/authorized_keys:
              content: ${var.public_key_openssh}
              mode: "000644"
              owner: "ubuntu"
              group: "ubuntu"
    Properties:
      InstanceType: ${var.size}
      InstanceInitiatedShutdownBehavior: terminate
      SecurityGroupIds:
        - Ref: InstanceSecurityGroup
      ImageId: ${data.aws_ami_ids.ubuntu.ids[0]}
      SubnetId: !Ref Subnet
      Ipv6AddressCount: 1
      UserData:
        "Fn::Base64":
          !Sub |
            #!/bin/bash -xe
            # http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/vpc-migrate-ipv6.html
            # https://bugs.launchpad.net/ubuntu/+source/ifupdown/+bug/1013597
            cat <<EOF > /etc/network/interfaces.d/60-default-with-ipv6.cfg
            iface eth0 inet6 dhcp
                up sysctl net.ipv6.conf.\$IFACE.accept_ra=2
                pre-down ip link set dev \$IFACE up
            EOF
            ifdown eth0; ifup eth0
            dhclient -6
            apt-get update
            apt-get -y install python-setuptools
            easy_install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz
            cfn-init -v --stack ${var.algo_name} --resource EC2Instance --region ${var.region}
            cfn-signal -e $? --stack ${var.algo_name} --resource EC2Instance --region ${var.region}
      Tags:
        - Key: Name
          Value: Algo
        - Key: Environment
          Value: Algo

  ElasticIP:
    Type: AWS::EC2::EIP
    Properties:
      Domain: vpc
      InstanceId: !Ref EC2Instance
    DependsOn:
      - EC2Instance
      - VPCGatewayAttachment

Outputs:
  ElasticIP:
    Value: !Ref ElasticIP
STACK
}
