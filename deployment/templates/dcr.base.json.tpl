{
  "location": "eastus2",
  "properties": {
    "dataSources": {
      "performanceCounters": [
        {
          "name": "cloudTeamCoreCounters",
          "streams": [
            "Microsoft-InsightsMetrics",
            "Microsoft-Perf"
          ],
          "samplingFrequencyInSeconds": 15,
          "counterSpecifiers": [
            "\\Processor(_Total)\\% Processor Time",
            "\\LogicalDisk(_Total)\\Free Megabytes",
            "\\PhysicalDisk(_Total)\\Avg. Disk Queue Length",
            "\\Memory\\% Committed Bytes In Use",
            "\\Memory\\Committed Bytes",
            "\\Memory\\Available Bytes",
            "\\Memory\\Page Faults/sec",
            "\\Memory(*)\\Available MBytes Memory",
            "\\Memory(*)\\% Available Memory",
            "\\Memory(*)\\Used Memory MBytes",
            "\\Memory(*)\\% Used Memory",
            "\\Memory(*)\\Available MBytes Swap",
            "\\Memory(*)\\% Available Swap Space",
            "\\Memory(*)\\Used MBytes Swap Space",
            "\\Memory(*)\\% Used Swap Space",
            "\\Network Interface(*)\\Bytes Total/sec",
            "\\Network Interface(*)\\Bytes Received/sec",
            "\\Network Interface(*)\\Bytes Sent/sec"
          ]
        },
        {
          "name": "appTeamExtraCounters",
          "streams": [
            "Microsoft-Perf"
          ],
          "samplingFrequencyInSeconds": 30,
          "counterSpecifiers": [
            "\\Process(_Total)\\Thread Count"
          ]
        }
      ],
      "windowsEventLogs": [
        {
          "name": "cloudSecurityTeamEvents",
          "streams": [
            "Microsoft-WindowsEvent"
          ],
          "xPathQueries": [
            "Security!"
          ]
        },
        {
          "name": "appTeam1AppEvents",
          "streams": [
            "Microsoft-WindowsEvent"
          ],
          "xPathQueries": [
            "System![System[(Level = 1 or Level = 2 or Level = 3)]]",
            "Application!*[System[(Level = 1 or Level = 2 or Level = 3)]]"
          ]
        }
      ],
      "syslog": [
        {
          "name": "cronSyslog",
          "streams": [
            "Microsoft-Syslog"
          ],
          "facilityNames": [
            "cron",
            "daemon",
            "auth"
          ],
          "logLevels": [
            "Debug",
            "Critical",
            "Emergency"
          ]
        },
        {
          "name": "syslogBase",
          "streams": [
            "Microsoft-Syslog"
          ],
          "facilityNames": [
            "syslog"
          ],
          "logLevels": [
            "Alert",
            "Critical",
            "Emergency"
          ]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "${log_analytics_workspace_id}",
          "name": "${log_analytics_workspace_name}"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": [
          "Microsoft-Perf",
          "Microsoft-Syslog",
          "Microsoft-Event",
          "Microsoft-WindowsEvent"
        ],
        "destinations": [
          "${destination_name}"
        ]
      }
    ]
  }
}