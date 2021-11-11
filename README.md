# Introduction

- [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
    - [Azure CLI](#azure-cli)
    - [Section 2. Terraform](#section-2-terraform)
    - [Azure CLI Extensions](#azure-cli-extensions)
    - [Azure Monitor Powershell](#azure-monitor-powershell)
    - [Section 6. CLI Utils](#section-6-cli-utils)
  - [Instructions](#instructions)
    - [Terraform](#terraform)
    - [Data Collection Rule](#data-collection-rule)
    - [SSH to VM](#ssh-to-vm)
    - [Stress test](#stress-test)
    - [View the CPU Spike](#view-the-cpu-spike)
    - [Useful Commands](#useful-commands)
  - [Unknowns](#unknowns)
    - [References](#references)

## Prerequisites

If on Windows 10 it's recommended to use WSL2 + Ubuntu.

### Azure CLI

- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Install Azure CLI ML extension](https://docs.microsoft.com/en-us/azure/machine-learning/how-to-configure-cli) by running `az extension add -n azure-cli-ml`

### Section 2. Terraform

[Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform)

### Azure CLI Extensions

```bash
az extension add --name monitor-control-service
az extension add --name log-analytics
```

### Azure Monitor Powershell

```bash
# In Powershell (type pwsh)
Install-Module Az.Monitor
```

### Section 6. CLI Utils

- [Install jq](https://stedolan.github.io/jq/download/)
  - WSL: `sudo apt-get install jq`
  - OSX: `brew install jq`

## Instructions

### Terraform

```text
cd deployment
touch dev.tfvars
terraform init
terraform plan --var-file dev.tfvars
terraform apply --auto-approve --var-file dev.tfvars
```

Once applied terraform will output three commands, see the [deployment/output.tf](deployment/outputs.tf) for reference.  Copy and paste each of these commands to the terminal.

Note that the [deployment/variables.tf](deployment/variables.tf) contains defaults for each required variable.  You still need a [deployment/dev.tfvars](./deployment/dev.tfvars) however it can be empty unless you want to override the defaults.

### Data Collection Rule

As of 11/2021 the `az monitor data-collection rule create` does not support using a file to configure the DCR.  It can be done with this cli command but it's very lengthy and unweildy, so I recommend using powershell for this, even if you are on MacOS or Linux, it works just as well.

The `terraform apply` output will contain four powershell commands.  Two `New-*` commands for adding a rule and association, and two `Remove-*` for removing those, promarily for testing purposes.

```bash
DESTINATION_NAME="log-analytics-log-destination" \
WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace list -g ama_test | jq -r '.[0].id') \
jq '.properties.destinations.logAnalytics[0].workspaceResourceId |= env.WORKSPACE_RESOURCE_ID | .properties.destinations.logAnalytics[0].name = env.DESTINATION_NAME | .properties.dataFlows[0].destinations |= [ env.DESTINATION_NAME ]' templates/dcr.base.json > templates/dcr.test.json
```

Copy and paste the `New-AzDataCollectionRule ...` then the `New-AzDataCollectionRuleAssociation ...` from the previous terraform output.  If you lost the context in your terminal execute `terraform output`.

Note that the `DESTINATION_NAME="log-analytics-log-destination"` is static, but you could change it to be whatever you want, just ensure it matches the default value in [deployment/locals.tf](deployment/locals.tf).

### SSH to VM

```bash
# Replace vmIp with the public IP of the VM
ssh -i ~/.ssh/id_rsa adminuser@vmIp
```

To get the ip of the VM use: `az vm list-ip-addresses --name vmName --resource-group ama_test --out table`

### Stress test

```bash
stress --cpu 2 --timeout 60
```

### View the CPU Spike

First let's verify we can execute a query against the workspace:

```bash
az monitor log-analytics query -w "$(az monitor log-analytics workspace list -g ama_test | jq -r '.[0].customerId')" --analytics-query "Heartbeat | where TimeGenerated > ago(1h) | summarize count() by Computer"
```

You should see something like:

```text
[
  {
    "Computer": "samuel-linux-1",
    "TableName": "PrimaryResult",
    "count_": "57"
  }
]
```

Now let's look at the CPU spike we produced earlier.

```bash
az monitor log-analytics query -w "$(az monitor log-analytics workspace list -g ama_test | jq -r '.[0].customerId')" --analytics-query " Perf | where CounterName == \"% Processor Time\" | where ObjectName == \"Processor\" | summarize avg(CounterValue) by bin(TimeGenerated, 5min), Computer, _ResourceId | render timechart"
```

This will return quite a bit of data, so it's generally recommended to run this in the Azure Portal in the Log Analytics Workspace.  When doing that you'll see:

![cpu_spike](./images/cpu_spike.png)

### Useful Commands

```bash
# Show public key for server
az vm show -g ama_test --name samuel-linux-1 --query "osProfile.linuxConfiguration.ssh.publicKeys[0].keyData"

# Reset public key
az vm user update -g ama_test --name samuel-linux-1 --username azureuser --ssh-key-value ~/.ssh/id_rsa.pub

# See Azure Monitor versions
az vm extension image list --location eastus2 -o table | grep AzureMonitorLinuxAgent
```

## Unknowns

In the [templates/dcr.test.json](./templates/dcr.test.json) an error is thrown "Operation returned an invalid status code 'BadRequest'" if I include the following in the `performanceCOunters.streams`:

```text
  "Microsoft-Syslog",
  "Microsoft-Event",
```

### References

- [https://docs.microsoft.com/en-us/azure/azure-monitor/agents/data-collection-rule-overview#create-a-dcr]
- [https://github.com/Azure/azure-cli-extensions/blob/main/src/monitor-control-service/README.md]