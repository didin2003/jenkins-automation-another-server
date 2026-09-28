terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

resource "null_resource" "jenkins_install" {
  triggers = {
    install_script = filesha256("${path.module}/../scripts/install-jenkins.sh")
    plugins        = filesha256("${path.module}/../jenkins/plugins.txt")
    casc           = filesha256("${path.module}/../jenkins/casc/jenkins.yaml")
    jenkins_host   = var.jenkins_server_host
  }

  connection {
    type        = "ssh"
    host        = var.jenkins_server_host
    user        = var.jenkins_server_user
    private_key = file(var.jenkins_server_ssh_key)
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/install-jenkins.sh"
    destination = "/tmp/install-jenkins.sh"
  }

  provisioner "file" {
    source      = "${path.module}/../jenkins/plugins.txt"
    destination = "/tmp/plugins.txt"
  }

  provisioner "file" {
    source      = "${path.module}/../jenkins/casc/jenkins.yaml"
    destination = "/tmp/jenkins.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/jenkins-automation/jenkins/casc",
      "cp /tmp/plugins.txt /tmp/jenkins-automation/jenkins/plugins.txt",
      "cp /tmp/jenkins.yaml /tmp/jenkins-automation/jenkins/casc/jenkins.yaml",
      "chmod +x /tmp/install-jenkins.sh",
      "export JENKINS_URL='${var.jenkins_url}'; export JENKINS_ADMIN_USERNAME='${var.jenkins_admin_username}'; export JENKINS_ADMIN_PASSWORD='${var.jenkins_admin_password}'; export JENKINS_ADMIN_NAME='${var.jenkins_admin_name}'; export JENKINS_ADMIN_EMAIL='${var.jenkins_admin_email}'; /tmp/install-jenkins.sh"
    ]
  }
}
