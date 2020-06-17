provider "aws" {
  	region 	= "ap-south-1"
}

resource "tls_private_key" "this" {
  	algorithm = "RSA"
}

resource "local_file" "private_key" {
    content         =   tls_private_key.this.private_key_pem
    filename        =   "mykey.pem"
}

resource "aws_key_pair" "mykey" {
  	key_name   = "mykey_new"
  	public_key = tls_private_key.this.public_key_openssh
}

resource "aws_security_group" "allow_traffic" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-97e5f8ff"

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
     description = "SSH from VPC"
     from_port   = 22
     to_port     = 22
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "myfirewall"
  }
}

resource "aws_instance" "myOS" {
  ami          	= "ami-0447a12f28fddb066"
  instance_type 	= "t2.micro"
	key_name 	= aws_key_pair.mykey.key_name
	security_groups  = [aws_security_group.allow_traffic.name]
  root_block_device {
        volume_type     = "gp2"
        volume_size     = 8
        delete_on_termination   = true
    }

		connection {
    		type     = "ssh"
    		user     = "ec2-user"
    		private_key = tls_private_key.this.private_key_pem
    		host     = aws_instance.myOS.public_ip
  }

  	provisioner "remote-exec" {
    		inline = [
      		"sudo yum install httpd  php  -y",
      		"sudo systemctl restart httpd",
      		"sudo systemctl enable httpd",
		      "sudo yum install git -y"
    ]
  }
  	tags = {
   		Name = "myterraOS"
  	}
}

resource "aws_ebs_volume" "myebs_vol" {
  	availability_zone = aws_instance.myOS.availability_zone
  	size              = 1
    type = "gp2"
  	tags = {
    		Name = "myVol"
  	}
}

resource "aws_volume_attachment" "ebs_attach" {
    device_name = "/dev/sdf"
    volume_id   = aws_ebs_volume.myebs_vol.id
    instance_id = aws_instance.myOS.id
    force_detach = true
 }

resource "null_resource" "nullremote"  {

    depends_on = [
       aws_volume_attachment.ebs_attach,
   ]

    connection {
     		type     = "ssh"
     		user     = "ec2-user"
     		private_key = tls_private_key.this.private_key_pem
        port    = 22
     		host     = aws_instance.myOS.public_ip
   }

 	provisioner "remote-exec" {
     	inline = [
      		"sudo mkfs.ext4  /dev/xvdf",
       		"sudo mount  /dev/xvdf  /var/www/html",
      		"sudo rm -rf /var/www/html/*",
       		"sudo git clone https://github.com/anshika-2000/webpage.git /var/www/html/"
     ]
   }
 }

 resource "aws_s3_bucket" "my_image_bucket123" {
     bucket  = "anshikaimages"
     acl     = "public-read"

 }

 resource "aws_s3_bucket_object" "upload" {
      bucket = aws_s3_bucket.my_image_bucket123.bucket
      key    = "matter.jpg"
      source = "D:/image/matter.jpg"
      acl 	 = "public-read"
  }
#  resource "aws_s3_bucket" "my_image_bucket123" {
#      bucket  = "anshikaimages"
#      acl     = "public-read"

#      provisioner "local-exec" {
#      command = "git clone https://github.com/anshika-2000/image.git"
#       }

#  provisioner "local-exec" {
#         when = destroy
#         command = "rm -rf my-images"
#        }


#  }

#  resource "aws_s3_bucket_object" "upload" {
#       bucket = aws_s3_bucket.my_image_bucket123.bucket
#       key    = "matter.jpg"
#       source = "D:/image/matter.jpg"
#       acl 	 = "public-read"
#  }

 

 locals {
   s3_origin_id = "S3-${aws_s3_bucket.my_image_bucket123.bucket}"
 }


resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my_image_bucket123.bucket_domain_name
   origin_id   = local.s3_origin_id
  }

  enabled     = true
 
 default_cache_behavior {    
     allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

     forwarded_values {
       query_string = false

       cookies {
         forward = "none"
       }
     }

     viewer_protocol_policy = "allow-all"
    
   }
  

   restrictions {
     geo_restriction {
       restriction_type = "none"
      
     }
    }

   viewer_certificate {
     cloudfront_default_certificate = true
  }
  connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.myOS.public_ip
        port    = 22
        private_key = tls_private_key.this.private_key_pem
    }
provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.upload.key}'>\" >> /var/www/html/terrapage.html",
            "EOF"
        ]
    }
}