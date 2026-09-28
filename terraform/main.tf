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
    jenkins_user   = var.jenkins_server_user
    ssh_key        = var.jenkins_server_ssh_key
    jenkins_version = var.jenkins_version
  }

  # Copy installation script
  provisioner "file" {
    source      = "${path.module}/../scripts/install-jenkins.sh"
    destination = "/tmp/install-jenkins.sh"

    connection {
      type        = "ssh"
      host        = var.jenkins_server_host
      user        = var.jenkins_server_user
      private_key = file(var.jenkins_server_ssh_key)
    }
  }

  # Copy plugin list
  provisioner "file" {
    source      = "${path.module}/../jenkins/plugins.txt"
    destination = "/tmp/plugins.txt"

    connection {
      type        = "ssh"
      host        = var.jenkins_server_host
      user        = var.jenkins_server_user
      private_key = file(var.jenkins_server_ssh_key)
    }
  }

  # Copy JCasC configuration
  provisioner "file" {
    source      = "${path.module}/../jenkins/casc/jenkins.yaml"
    destination = "/tmp/jenkins.yaml"

    connection {
      type        = "ssh"
      host        = var.jenkins_server_host
      user        = var.jenkins_server_user
      private_key = file(var.jenkins_server_ssh_key)
    }
  }

  # Install and configure Jenkins
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/jenkins-automation/jenkins/casc",
      "cp /tmp/plugins.txt /tmp/jenkins-automation/jenkins/plugins.txt",
      "cp /tmp/jenkins.yaml /tmp/jenkins-automation/jenkins/casc/jenkins.yaml",
      "chmod +x /tmp/install-jenkins.sh",
      "export JENKINS_URL='${var.jenkins_url}'; export JENKINS_ADMIN_USERNAME='${var.jenkins_admin_username}'; export JENKINS_ADMIN_PASSWORD='${var.jenkins_admin_password}'; export JENKINS_ADMIN_NAME='${var.jenkins_admin_name}'; export JENKINS_ADMIN_EMAIL='${var.jenkins_admin_email}'; export JENKINS_VERSION='${var.jenkins_version}'; /tmp/install-jenkins.sh"
    ]

    connection {
      type        = "ssh"
      host        = var.jenkins_server_host
      user        = var.jenkins_server_user
      private_key = file(var.jenkins_server_ssh_key)
    }
  }

  # Uninstall Jenkins during terraform destroy
  provisioner "remote-exec" {
    when = destroy

    connection {
      type        = "ssh"
      host        = self.triggers["jenkins_host"]
      user        = self.triggers["jenkins_user"]
      private_key = file(self.triggers["ssh_key"])
    }

    inline = [
      "sudo systemctl stop jenkins || true",
      "sudo systemctl disable jenkins || true",
      "sudo apt-get purge -y jenkins",
      "sudo rm -rf /var/lib/jenkins",
      "sudo rm -rf /var/cache/jenkins",
      "sudo rm -rf /etc/systemd/system/jenkins.service.d",
      "sudo systemctl daemon-reload"
    ]
  }
}
