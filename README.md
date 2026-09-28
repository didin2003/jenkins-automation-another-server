# Remote Jenkins Installation with Terraform

## 1. Overview

This project uses Terraform on one Ubuntu server to install and
configure Jenkins on a separate Ubuntu server over SSH.

-   **Terraform server:** `seria` --- `192.168.0.134` --- user `ubuntu`
-   **Jenkins server:** `ubuntu` --- `192.168.0.135` --- user `ubuntu`
-   **Jenkins port:** `8080`

Terraform does not create the virtual machines. It orchestrates the
installation on the existing Jenkins server by copying the installation
script, plugin list, and Jenkins Configuration as Code (JCasC) YAML
file, then executing the script remotely.

The installation script installs prerequisites and Jenkins, installs
plugins listed in `jenkins/plugins.txt`, places the JCasC file,
configures the Jenkins service, and starts Jenkins.

> **Important:** The current Terraform resource has a destroy
> provisioner that purges Jenkins and deletes `/var/lib/jenkins` and
> `/var/cache/jenkins`. Replacing or destroying this resource can delete
> Jenkins data. Review the plan and back up data before applying a
> replacement. The current design is an installation workflow, not yet a
> safe routine upgrade/rollback workflow.

## 2. Project structure

``` text
jenkins-automation-another-server/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── .terraform.lock.hcl
│   └── terraform.tfstate
├── jenkins/
│   ├── plugins.txt
│   └── casc/
│       └── jenkins.yaml
└── scripts/
    └── install-jenkins.sh
```

-   `main.tf`: Terraform resource, SSH file transfers, remote execution,
    and destroy behavior.
-   `variables.tf`: declarations for Terraform input variables.
-   `terraform.tfvars`: environment-specific values, including server
    connection details and administrator settings.
-   `.terraform.lock.hcl`: provider version selections.
-   `terraform.tfstate`: Terraform state; keep it private and do not
    commit it publicly.
-   `plugins.txt`: plugin IDs and optionally pinned versions.
-   `jenkins.yaml`: Jenkins Configuration as Code.
-   `install-jenkins.sh`: installation and configuration commands run on
    the Jenkins server.

Keep this remote-server project separate from the same-server project
and use separate Terraform state.

## 3. Install Terraform on the Terraform server

Run these commands on `seria` (`192.168.0.134`).

### 3.1 Install prerequisites

``` bash
sudo apt-get update
sudo apt-get install -y ca-certificates gnupg curl wget
```

### 3.2 Add the HashiCorp apt repository

``` bash
wget -O- https://apt.releases.hashicorp.com/gpg   | gpg --dearmor   | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
```

``` bash
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main"   | sudo tee /etc/apt/sources.list.d/hashicorp.list
```

### 3.3 Install and verify

``` bash
sudo apt-get update
sudo apt-get install -y terraform
terraform version
```

`terraform version` should display the installed version.

## 4. Set up SSH access to the Jenkins server

Terraform uses SSH to copy files and execute commands on the Jenkins
server. The private key stays on the Terraform server; its matching
public key must be authorized for the remote user.

### 4.1 Generate a dedicated key pair

On the Terraform server:

``` bash
ssh-keygen -t ed25519 -f ~/.ssh/jenkins_automation -C "terraform-jenkins-automation"
```

This creates: - Private key: `~/.ssh/jenkins_automation` - Public key:
`~/.ssh/jenkins_automation.pub`

Protect the private key and never commit or share it. If you already
have a suitable key pair, you can use that instead.

Terraform must be able to read the key non-interactively. If you protect
it with a passphrase, configure an SSH agent or another supported way to
unlock it.

### 4.2 Install the public key on the Jenkins server

From the Terraform server:

``` bash
ssh-copy-id -i ~/.ssh/jenkins_automation.pub ubuntu@192.168.0.135
```

Enter the remote user's password if prompted. This adds the public key
to the remote user's `~/.ssh/authorized_keys`.

If you add the key manually on the Jenkins server, ensure the remote
user's SSH directory and authorized keys have correct ownership and
permissions:

``` bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### 4.3 Set private-key permissions

On the Terraform server:

``` bash
chmod 600 ~/.ssh/jenkins_automation
```

### 4.4 Test SSH

``` bash
ssh -i ~/.ssh/jenkins_automation ubuntu@192.168.0.135
```

After connecting, run:

``` bash
hostname
whoami
```

In this example, both should identify the remote Jenkins server and user
as expected. Exit:

``` bash
exit
```

### 4.5 Configure non-interactive sudo on the Jenkins server

The installation script uses `sudo` to install packages and modify
system files. Terraform's remote execution is non-interactive, so the
remote user must be able to run the required commands without a
password.

On the Jenkins server, open a sudoers drop-in using `visudo`:

``` bash
sudo visudo -f /etc/sudoers.d/jenkins-automation
```

Add:

``` text
ubuntu ALL=(ALL) NOPASSWD:ALL
```

Save and exit, then validate:

``` bash
sudo visudo -c
```

From the Terraform server, test non-interactive sudo:

``` bash
ssh -i ~/.ssh/jenkins_automation ubuntu@192.168.0.135 'sudo -n true'
echo $?
```

Exit code `0` means the test succeeded. `NOPASSWD:ALL` grants broad
administrative access; use narrower permissions where practical and
protect this account and key.

## 5. Configure Terraform inputs

On the Terraform server:

``` bash
cd ~/jenkins-automation-another-server/terraform
```

Review `variables.tf` to ensure every variable referenced in `main.tf`
is declared.

Example `terraform.tfvars` values:

``` hcl
jenkins_server_host    = "192.168.0.135"
jenkins_server_user    = "ubuntu"
jenkins_server_ssh_key = "/home/ubuntu/.ssh/jenkins_automation"

jenkins_url            = "http://192.168.0.135:8080"
jenkins_admin_username = "admin"
jenkins_admin_password = "REPLACE_WITH_A_SECRET"
jenkins_admin_name     = "Jenkins Administrator"
jenkins_admin_email    = "admin@example.com"

jenkins_version        = "2.568.3"
```

This is an example. Keep only variables that are actually declared and
used by the current Terraform configuration. If version pinning is
implemented, confirm that the exact Jenkins package version exists in
the configured apt repository.

Protect the file because it may contain credentials:

``` bash
chmod 600 terraform.tfvars
```

Do not commit `terraform.tfvars` or Terraform state to a public
repository. For shared or production use, prefer a secret-management
solution over plain-text passwords.

## 6. Review the Jenkins files

### 6.1 Plugin list

Edit the plugin list:

``` bash
nano ~/jenkins-automation-another-server/jenkins/plugins.txt
```

Current plugin IDs:

``` text
configuration-as-code
git
workflow-aggregator
credentials
credentials-binding
ssh-agent
pipeline-stage-view
```

A plugin can be pinned to a version using the plugin manager's supported
format, for example:

``` text
git:5.7.0
```

Choose versions compatible with the Jenkins core version. Verify plugin
IDs and compatibility before changing the list.

### 6.2 JCasC configuration

Edit:

``` bash
nano ~/jenkins-automation-another-server/jenkins/casc/jenkins.yaml
```

This YAML contains Jenkins settings managed by the Configuration as Code
plugin. Keep it valid and avoid embedding secrets directly unless they
are handled securely.

### 6.3 Installation script

Review:

``` bash
nano ~/jenkins-automation-another-server/scripts/install-jenkins.sh
```

The script runs on the Jenkins server. It installs prerequisites and
Jenkins, installs plugins, copies the JCasC configuration, configures
the systemd service, and starts Jenkins.

If Jenkins version pinning is configured, the script must read
`JENKINS_VERSION` and use it in the package installation command.
Passing a Terraform variable alone does not change the installed version
unless the script uses it.

## 7. Initialize and validate Terraform

On the Terraform server:

``` bash
cd ~/jenkins-automation-another-server/terraform
terraform init
terraform fmt -recursive
terraform validate
```

-   `terraform init` downloads the required provider.
-   `terraform fmt -recursive` formats Terraform files.
-   `terraform validate` checks Terraform configuration syntax and
    consistency. It does not test SSH access or prove Jenkins will
    install successfully.

Test SSH independently using the commands in Section 4.

## 8. Plan and apply

Inspect the proposed actions first:

``` bash
terraform plan
```

Review every action. Proceed only when you understand the impact and
have confirmed that Jenkins data will not be unexpectedly deleted.

``` bash
terraform apply
```

Terraform asks for confirmation. Review the plan and type `yes` only
when you are ready.

Do not use `terraform apply -auto-approve` while troubleshooting or
while the destroy provisioner can delete Jenkins data.

## 9. Verify the installation

Run these commands on the Jenkins server:

``` bash
sudo systemctl status jenkins --no-pager
```

``` bash
curl -I --max-time 10 http://127.0.0.1:8080/login
```

Check the installed package version:

``` bash
dpkg-query -W -f='${Version}\n' jenkins
```

Check plugin files:

``` bash
sudo ls -lah /var/lib/jenkins/plugins/
```

Check the installation log:

``` bash
sudo tail -n 100 /tmp/jenkins-install.log
```

A running service and HTTP response show that Jenkins is responding.
Also sign in and verify the administrator, expected plugins, and
configuration.

## 10. Updating plugins

To change a plugin version:

1.  Edit `jenkins/plugins.txt`.
2.  Confirm the plugin version is compatible with the installed Jenkins
    core.
3.  Run `terraform plan`.
4.  Review whether Terraform will replace the resource.
5.  Apply only after confirming that the operation is safe.

The Terraform resource uses file hashes in `triggers`. A change to
`plugins.txt` therefore causes the `null_resource` to be replaced.

**Caution:** With the current destroy provisioner, replacement can purge
Jenkins and delete `/var/lib/jenkins`. This is not a safe routine
plugin-upgrade method. For an existing Jenkins instance, use a
non-destructive plugin update process and take a backup first.

## 11. Updating or reverting Jenkins versions

If version pinning has been implemented in Terraform and the
installation script, change `jenkins_version` in `terraform.tfvars`.
Confirm that the target package version is available and review the
plan.

Before upgrading:

1.  Back up `/var/lib/jenkins`.
2.  Record the current Jenkins and plugin versions.
3.  Confirm that the target package version is available.
4.  Ensure the Terraform operation will not unexpectedly delete Jenkins
    data.
5.  Perform the upgrade through a non-destructive process.

For rollback, restore the previous Jenkins package version **and** a
backup of `JENKINS_HOME` from before the upgrade. Installing an older
package against data already modified by a newer release may fail.

The current destroy provisioner is for teardown, not routine upgrades.
Separate installation, upgrade, and destroy workflows before using this
project for ongoing production version management.

## 12. Terraform state and destroy behavior

Terraform state tracks the `null_resource` and its trigger values. Keep
it private and back it up. Do not copy state between the same-server and
remote-server projects; each should have its own state.

The current `when = destroy` remote-exec provisioner: - Stops and
disables Jenkins. - Purges the Jenkins apt package. - Deletes
`/var/lib/jenkins`. - Deletes `/var/cache/jenkins`. - Removes the
Jenkins systemd drop-in. - Reloads systemd.

Therefore, `terraform destroy` is destructive to Jenkins and its data. A
tainted resource also requires replacement, so inspect the plan
carefully before applying.

## 13. Troubleshooting

### SSH connection fails

From the Terraform server:

``` bash
ssh -i ~/.ssh/jenkins_automation ubuntu@192.168.0.135
```

Check the IP address, SSH service, key path, key permissions, and remote
`authorized_keys`.

### Sudo asks for a password

Test from the Terraform server:

``` bash
ssh -i ~/.ssh/jenkins_automation ubuntu@192.168.0.135 'sudo -n true'
```

If it fails, validate sudoers on the Jenkins server:

``` bash
sudo visudo -c
```

### Jenkins service is not running

On the Jenkins server:

``` bash
sudo systemctl status jenkins --no-pager
sudo journalctl -u jenkins -n 100 --no-pager
```

### Terraform timed out or the installation failed

On the Jenkins server:

``` bash
sudo tail -n 200 /tmp/jenkins-install.log
sudo journalctl -u jenkins -n 100 --no-pager
```

A Terraform SSH provisioner timeout alone does not identify the failed
command. Use the installation and service logs to locate the last
completed step.

### Terraform says the resource is tainted

Inspect:

``` bash
terraform plan
```

A tainted resource is scheduled for replacement. Because this project
has a destructive destroy provisioner, do not apply until you have
checked the consequences and protected any Jenkins data you need.

## 14. Typical Terraform command sequence

After the servers, SSH, variables, and configuration files are prepared:

``` bash
cd ~/jenkins-automation-another-server/terraform

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Use this sequence only after reviewing the plan. During troubleshooting,
do not apply a replacement plan without first addressing the destroy
provisioner.

## 15. Summary

Terraform runs on a separate Ubuntu server and connects to the Jenkins
server over SSH. It transfers the installation script, plugin list, and
JCasC configuration, then runs the script remotely. This makes the setup
repeatable and allows the installation files and orchestration to be
maintained together.

The current design automates installation, but it is not yet a safe
ongoing upgrade system. Since the destroy provisioner deletes Jenkins
data, routine plugin or Jenkins version changes must not be applied
until upgrade behavior is made non-destructive and a backup/rollback
process is in place.
