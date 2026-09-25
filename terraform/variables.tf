variable "jenkins_server_host" {
  description = "IP address or hostname of the Jenkins server"
  type        = string
}

variable "jenkins_server_user" {
  description = "SSH user on the Jenkins server"
  type        = string
}

variable "jenkins_server_ssh_key" {
  description = "Path to the SSH private key on the Terraform server"
  type        = string
}

variable "jenkins_url" {
  description = "Jenkins URL"
  type        = string
}

variable "jenkins_admin_username" {
  description = "Jenkins administrator username"
  type        = string
}

variable "jenkins_admin_password" {
  description = "Jenkins administrator password"
  type        = string
  sensitive   = true
}

variable "jenkins_admin_name" {
  description = "Jenkins administrator name"
  type        = string
}

variable "jenkins_admin_email" {
  description = "Jenkins administrator email"
  type        = string
}
